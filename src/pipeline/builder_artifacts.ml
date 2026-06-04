open Ast
open Builder_utils

type artifact_error = {
  code : Ast.error_code;
  message : string;
}

let error code message = Error { code; message }

let close_noerr fd =
  try Unix.close fd with
  | Unix.Unix_error _ -> ()

let error_of_value = function
  | VError err -> { code = err.code; message = err.message }
  | other -> { code = RuntimeError; message = Ast.Utils.value_to_string other }

let read_all_fd fd =
  let buffer = Buffer.create 1024 in
  let chunk = Bytes.create 4096 in
  let rec loop () =
    try
      match Unix.read fd chunk 0 (Bytes.length chunk) with
      | 0 -> ()
      | n ->
          Buffer.add_subbytes buffer chunk 0 n;
          loop ()
    with
    | Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
  in
  loop ();
  Buffer.contents buffer

let run_process_redirected (argv : string array) ~stdin_fd ~stdout_fd :
    (unit, artifact_error) result =
  if Array.length argv = 0 then
    error RuntimeError "Artifact command requires a non-empty argument vector."
  else
    let stderr_read, stderr_write = Unix.pipe () in
    try
      let pid =
        Unix.create_process_env argv.(0) argv (Unix.environment ()) stdin_fd stdout_fd stderr_write
      in
      Unix.close stderr_write;
      let stderr_output =
        Fun.protect
          ~finally:(fun () -> Unix.close stderr_read)
          (fun () -> read_all_fd stderr_read |> String.trim)
      in
      let _, status = Unix.waitpid [] pid in
      match status with
      | Unix.WEXITED 0 -> Ok ()
      | Unix.WEXITED code ->
          let cmd_display = String.concat " " (Array.to_list argv) in
          let msg =
            if stderr_output <> "" then
              Printf.sprintf "Command `%s` failed (exit %d): %s" cmd_display code stderr_output
            else
              Printf.sprintf "Command `%s` failed with exit code %d" cmd_display code
          in
          error RuntimeError msg
      | Unix.WSIGNALED signal ->
          error RuntimeError
            (Printf.sprintf "Command `%s` was terminated by signal %d."
               (String.concat " " (Array.to_list argv)) signal)
      | Unix.WSTOPPED signal ->
          error RuntimeError
            (Printf.sprintf "Command `%s` was stopped by signal %d."
               (String.concat " " (Array.to_list argv)) signal)
    with
    | exn ->
        close_noerr stderr_read;
        close_noerr stderr_write;
        error RuntimeError (Printexc.to_string exn)

let ensure_archive_path archive_path =
  if String.trim archive_path = "" then
    error FileError "Archive path must not be empty."
  else
    Ok ()

let split_non_empty_lines text =
  text
  |> String.split_on_char '\n'
  |> List.map String.trim
  |> List.filter (fun line -> line <> "")

let dedupe_preserve_order items =
  let rec loop seen acc = function
    | [] -> List.rev acc
    | item :: rest when List.mem item seen -> loop seen acc rest
    | item :: rest -> loop (item :: seen) (item :: acc) rest
  in
  loop [] [] items

let pipeline_store_paths (p : Ast.pipeline_result) =
  match Builder.populate_pipeline ~build:false p with
  | Error msg -> error StructuralError msg
  | Ok _ ->
      let rec collect acc = function
        | [] -> Ok (List.rev acc)
        | (name, _) :: rest ->
            (match eval_node_store_path name with
             | Ok store_path -> collect ((name, store_path) :: acc) rest
             | Error err -> Error (error_of_value err))
      in
      collect [] p.p_nodes

let invalid_store_paths node_paths =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | (name, store_path) :: rest ->
        (match run_command_argv_exit [| "nix-store"; "--verify-path"; store_path |] with
         | Ok 0 -> loop acc rest
         | Ok _ -> loop (name :: acc) rest
         | Error msg ->
             error RuntimeError
               (Printf.sprintf "Failed to query cache status for node `%s`: %s" name msg))
  in
  loop [] node_paths

let export_closure_paths node_paths =
  let argv =
    Array.of_list
      ("nix-store" :: "--query" :: "--requisites" :: List.map snd node_paths)
  in
  match run_command_argv_capture argv with
  | Ok output -> Ok (split_non_empty_lines output |> dedupe_preserve_order)
  | Error msg -> error RuntimeError ("Failed to compute artifact closure: " ^ msg)

let concat_map f lst = List.concat (List.map f lst)

let rec collect_paths_from_value (v : Ast.value) : (string * string) list =
  match v with
  | VPipeline p ->
      let node_names = List.map fst p.p_nodes in
      List.filter_map (fun name ->
        match eval_node_store_path name with
        | Ok store_path -> Some (name, store_path)
        | Error _ -> None
      ) node_names
  | VMetaPipeline mp ->
      concat_map (fun (_, sub_v) -> collect_paths_from_value sub_v) mp.mp_pipelines
  | VComputedNode cn ->
      [(cn.cn_name, cn.cn_path)]
  | VString s ->
      if String.length s >= 11 && String.sub s 0 11 = "/nix/store/" then
        let basename = Filename.basename s in
        let name =
          if String.length basename > 33 && basename.[32] = '-' then
            String.sub basename 33 (String.length basename - 33)
          else basename
        in
        [(name, s)]
      else
        (match eval_node_store_path s with
         | Ok store_path -> [(s, store_path)]
         | Error _ -> [])
  | VList items ->
      concat_map (fun (_, elem) -> collect_paths_from_value elem) items
  | VVector arr ->
      concat_map collect_paths_from_value (Array.to_list arr)
  | VDict pairs ->
      concat_map (fun (_, elem) -> collect_paths_from_value elem) pairs
  | _ -> []

let export_artifacts (target : Ast.value) archive_path =
  match target with
  | VInt _ | VFloat _ | VBool _ | VNA _ | VDate _ | VDatetime _ | VSymbol _ | VFactor _ | VPeriod _ | VDuration _ | VInterval _ ->
      error TypeError "Function `export_artifacts` expects a Pipeline, MetaPipeline, Node, or collection of pipelines/nodes as first argument."
  | _ ->
      match ensure_archive_path archive_path with
      | Error _ as err -> err
      | Ok () ->
          let node_paths = dedupe_preserve_order (collect_paths_from_value target) in
          if node_paths = [] then
            error RuntimeError "No valid pipeline/node artifacts were found to export."
          else
            (match invalid_store_paths node_paths with
             | Error _ as err -> err
             | Ok (_ :: _ as missing_nodes) ->
                 error RuntimeError
                   (Printf.sprintf
                      "Cannot export artifacts because these pipeline nodes are not cached: %s. Build the pipeline first."
                      (String.concat ", " missing_nodes))
             | Ok [] ->
                 (match export_closure_paths node_paths with
                  | Error _ as err -> err
                  | Ok [] ->
                      error RuntimeError "No pipeline artifacts were found to export."
                  | Ok closure_paths ->
                      let archive_fd =
                        try Ok (Unix.openfile archive_path [Unix.O_CREAT; Unix.O_TRUNC; Unix.O_WRONLY] 0o644)
                        with Unix.Unix_error (err, _, _) ->
                          error FileError
                            (Printf.sprintf "Could not open archive path `%s`: %s"
                               archive_path (Unix.error_message err))
                      in
                      (match archive_fd with
                       | Error _ as err -> err
                       | Ok archive_fd ->
                           let result =
                             Fun.protect
                               ~finally:(fun () -> close_noerr archive_fd)
                               (fun () ->
                                 let devnull_fd = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
                                 Fun.protect
                                   ~finally:(fun () -> close_noerr devnull_fd)
                                   (fun () ->
                                     run_process_redirected
                                       (Array.of_list ("nix-store" :: "--export" :: closure_paths))
                                       ~stdin_fd:devnull_fd
                                       ~stdout_fd:archive_fd))
                           in
                           (match result with
                            | Ok () ->
                                Ok
                                  (Printf.sprintf "Exported %d pipeline artifact(s) to `%s`."
                                     (List.length node_paths) archive_path)
                            | Error _ as err ->
                                (try Sys.remove archive_path with _ -> ());
                                err))))

let import_artifacts_no_verify archive_path =
  match ensure_archive_path archive_path with
  | Error _ as err -> err
  | Ok () when not (Sys.file_exists archive_path) ->
      error FileError (Printf.sprintf "Archive not found: %s" archive_path)
  | Ok () when Sys.is_directory archive_path ->
      error FileError (Printf.sprintf "Expected an archive file but received a directory: %s" archive_path)
  | Ok () ->
      let archive_fd =
        try Ok (Unix.openfile archive_path [Unix.O_RDONLY] 0)
        with Unix.Unix_error (err, _, _) ->
          error FileError
            (Printf.sprintf "Could not open archive path `%s`: %s"
               archive_path (Unix.error_message err))
      in
      (match archive_fd with
       | Error _ as err -> err
       | Ok archive_fd ->
           let import_result =
             Fun.protect
               ~finally:(fun () -> close_noerr archive_fd)
               (fun () ->
                 let devnull_fd = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
                 Fun.protect
                   ~finally:(fun () -> close_noerr devnull_fd)
                   (fun () ->
                     run_process_redirected
                       [| "nix-store"; "--import" |]
                       ~stdin_fd:archive_fd
                       ~stdout_fd:devnull_fd))
           in
           (match import_result with
            | Error _ as err -> err
            | Ok () ->
                Ok (Printf.sprintf "Imported pipeline artifacts from `%s`." archive_path)))

let import_artifacts (target : Ast.value) archive_path =
  match target with
  | VInt _ | VFloat _ | VBool _ | VNA _ | VDate _ | VDatetime _ | VSymbol _ | VFactor _ | VPeriod _ | VDuration _ | VInterval _ ->
      error TypeError "Function `import_artifacts` expects a Pipeline, MetaPipeline, Node, or collection of pipelines/nodes as first argument."
  | _ ->
      match import_artifacts_no_verify archive_path with
      | Error _ as err -> err
      | Ok msg ->
          let node_paths = dedupe_preserve_order (collect_paths_from_value target) in
          if node_paths = [] then Ok msg
          else
            (match invalid_store_paths node_paths with
             | Error _ as err -> err
             | Ok [] -> Ok msg
             | Ok missing_nodes ->
                 error RuntimeError
                   (Printf.sprintf
                      "Artifact archive `%s` was imported, but these pipeline nodes are still missing from the local store: %s"
                      archive_path (String.concat ", " missing_nodes)))

let inspect_artifacts archive_path =
  match ensure_archive_path archive_path with
  | Error _ as err -> err
  | Ok () when not (Sys.file_exists archive_path) ->
      error FileError (Printf.sprintf "Archive not found: %s" archive_path)
  | Ok () when Sys.is_directory archive_path ->
      error FileError (Printf.sprintf "Expected an archive file but received a directory: %s" archive_path)
  | Ok () ->
      let temp_store_dir =
        let pid = Unix.getpid () in
        let () = Random.self_init () in
        let rand = Random.int 100000000 in
        Filename.concat (Sys.getcwd ()) (Printf.sprintf ".t_inspect_%d_%d" pid rand)
      in
      let cleanup () =
        if Sys.file_exists temp_store_dir then (
          let _ = run_command_argv_exit [| "chmod"; "-R"; "+w"; temp_store_dir |] in
          let _ = run_command_argv_exit [| "rm"; "-rf"; temp_store_dir |] in
          ()
        )
      in
      (try Unix.mkdir temp_store_dir 0o755 with _ -> ());
      let archive_fd =
        try Ok (Unix.openfile archive_path [Unix.O_RDONLY] 0)
        with Unix.Unix_error (err, _, _) ->
          cleanup ();
          error FileError
            (Printf.sprintf "Could not open archive path `%s`: %s"
               archive_path (Unix.error_message err))
      in
      match archive_fd with
      | Error _ as err -> err
      | Ok archive_fd ->
          let stdout_read, stdout_write = Unix.pipe () in
          let stderr_read, stderr_write = Unix.pipe () in
          let import_res =
            try
              let pid =
                Unix.create_process_env "nix-store"
                  [| "nix-store"; "--import"; "--store"; temp_store_dir |]
                  (Unix.environment ())
                  archive_fd stdout_write stderr_write
              in
              Unix.close stdout_write;
              Unix.close stderr_write;
              let stdout_output =
                Fun.protect
                  ~finally:(fun () -> Unix.close stdout_read)
                  (fun () -> read_all_fd stdout_read)
              in
              let stderr_output =
                Fun.protect
                  ~finally:(fun () -> Unix.close stderr_read)
                  (fun () -> read_all_fd stderr_read |> String.trim)
              in
              let _, status = Unix.waitpid [] pid in
              match status with
              | Unix.WEXITED 0 -> Ok (split_non_empty_lines stdout_output)
              | Unix.WEXITED code ->
                  let msg =
                    if stderr_output <> "" then
                      Printf.sprintf "nix-store --import failed (exit %d): %s" code stderr_output
                    else
                      Printf.sprintf "nix-store --import failed with exit code %d" code
                  in
                  Error msg
              | _ -> Error "nix-store --import failed unexpectedly"
            with exn ->
              close_noerr stdout_write;
              close_noerr stderr_write;
              close_noerr stdout_read;
              close_noerr stderr_read;
              Error (Printexc.to_string exn)
          in
          close_noerr archive_fd;
          match import_res with
          | Error msg ->
              cleanup ();
              error RuntimeError msg
          | Ok [] ->
              cleanup ();
              Ok []
          | Ok imported_paths ->
              let info_argv = Array.of_list ("nix" :: "path-info" :: "--json" :: "--store" :: temp_store_dir :: imported_paths) in
              let results_res =
                match run_command_argv_capture info_argv with
                | Error msg -> Error msg
                | Ok json_str ->
                    try
                      let json = Yojson.Safe.from_string json_str in
                      let open Yojson.Safe.Util in
                      match json with
                      | `Assoc kvs ->
                          let res =
                            List.map (fun (store_path, details) ->
                              let basename = Filename.basename store_path in
                              let hash = if String.length basename >= 32 then String.sub basename 0 32 else "" in
                              let name =
                                if String.length basename > 33 && basename.[32] = '-' then
                                  String.sub basename 33 (String.length basename - 33)
                                else basename
                              in
                              let size =
                                match member "narSize" details with
                                | `Int sz -> sz
                                | _ -> 0
                              in
                              let refs =
                                match member "references" details with
                                | `List refs_list ->
                                    let ref_paths = List.filter_map (function `String s -> Some (Filename.basename s) | _ -> None) refs_list in
                                    String.concat ", " ref_paths
                                | _ -> ""
                              in
                              (name, store_path, hash, size, refs)
                            ) kvs
                          in
                          Ok res
                      | _ -> Error "nix path-info output was not a JSON object"
                    with exn ->
                      Error (Printexc.to_string exn)
              in
              cleanup ();
              (match results_res with
               | Ok res -> Ok res
               | Error msg -> error RuntimeError msg)
