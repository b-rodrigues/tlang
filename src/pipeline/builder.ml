open Ast

let pipeline_dir = "_pipeline"
let pipeline_nix_path = Filename.concat pipeline_dir "pipeline.nix"
let dag_path = Filename.concat pipeline_dir "dag.json"

let write_file path content =
  try
    let oc = open_out path in
    output_string oc content;
    close_out oc;
    Ok ()
  with exn ->
    Error (Printexc.to_string exn)

let command_exists cmd =
  Sys.command (Printf.sprintf "command -v %s >/dev/null 2>&1" cmd) = 0

let run_command_capture cmd =
  try
    let ic = Unix.open_process_in cmd in
    let b = Buffer.create 256 in
    (try
       while true do
         Buffer.add_string b (input_line ic);
         Buffer.add_char b '\n'
       done
     with End_of_file -> ());
    let status = Unix.close_process_in ic in
    Ok (status, String.trim (Buffer.contents b))
  with exn ->
    Error (Printexc.to_string exn)

let ensure_pipeline_dir () =
  if not (Sys.file_exists pipeline_dir) then
    Unix.mkdir pipeline_dir 0o755

let write_dag (p : Ast.pipeline_result) =
  let nodes_json =
    List.map (fun (name, _) ->
      let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
      let entries = [
        ("node_name", "\"" ^ Serialization.json_escape name ^ "\"");
        ("depends", Serialization.json_list deps)
      ] in
      Serialization.json_dict entries
    ) p.p_exprs
  in
  let dag_json = "[\n" ^ (String.concat ",\n" nodes_json) ^ "\n]" in
  write_file dag_path dag_json

let get_timestamp () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d%02d%02d_%02d%02d%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec

let build_pipeline_internal (p : Ast.pipeline_result) =
  if not (command_exists "nix-build") then
    Error "build_pipeline requires `nix-build` to be available."
  else
    match run_command_capture
            (Printf.sprintf "nix-build %s -A pipeline_output --no-out-link --print-out-paths 2>&1" (Filename.quote pipeline_nix_path)) with
    | Ok (Unix.WEXITED 0, output) when output <> "" ->
        (* Filter output lines to find the Nix store path.
           Only lines starting with /nix/store/ are valid store paths. *)
        let lines = String.split_on_char '\n' (String.trim output) in
        let store_paths = List.filter (fun l ->
          String.length l > 11 && String.sub l 0 11 = "/nix/store/"
        ) lines in
        (match store_paths with
        | [] -> Error "nix-build succeeded but did not return a store path."
        | _ ->
            let out_path = List.nth store_paths (List.length store_paths - 1) in
            let timestamp = get_timestamp () in
            let hash = try
              let parts = String.split_on_char '-' (Filename.basename out_path) in
              List.hd parts
            with _ -> "no_hash"
            in
            let log_name = Printf.sprintf "build_log_%s_%s.json" timestamp hash in
            let log_path = Filename.concat pipeline_dir log_name in
            let registry =
              List.map (fun (name, _) ->
                (name, Filename.concat (Filename.concat out_path name) "artifact.tobj")
              ) p.p_exprs
            in
            let log_entries =
              List.map (fun (name, path) ->
                Serialization.json_dict [
                  ("node", "\"" ^ Serialization.json_escape name ^ "\"");
                  ("path", "\"" ^ Serialization.json_escape path ^ "\"");
                  ("success", "true")
                ]
              ) registry
            in
            let log_json = Serialization.json_dict [
              ("timestamp", "\"" ^ timestamp ^ "\"");
              ("hash", "\"" ^ hash ^ "\"");
              ("out_path", "\"" ^ out_path ^ "\"");
              ("nodes", "[\n" ^ (String.concat ",\n" log_entries) ^ "\n]")
            ] in
            (match write_file log_path log_json with
            | Ok () -> Ok out_path
            | Error msg -> Error ("Failed to write build log: " ^ msg)))
    | Ok (Unix.WEXITED 0, _) ->
        Error "nix-build succeeded but did not return an output path."
    | Ok (_, output) ->
        Error (Printf.sprintf "nix-build failed: %s" output)
    | Error msg ->
        Error (Printf.sprintf "Failed to run nix-build: %s" msg)

let env_nix_path = Filename.concat pipeline_dir "env.nix"

(** Extract the Nix store derivation path from a binary path.
    e.g. /nix/store/abc123-t-lang-0.5.0/bin/t -> /nix/store/abc123-t-lang-0.5.0 *)
let nix_store_path_of_executable () =
  (* Resolve the real path of the running executable *)
  let exe = try Unix.readlink "/proc/self/exe" with _ -> Sys.executable_name in
  if String.length exe > 11 && String.sub exe 0 11 = "/nix/store/" then
    (* Strip everything after the store hash-name, i.e. /nix/store/<hash-name>/... *)
    let rest = String.sub exe 11 (String.length exe - 11) in
    match String.index_opt rest '/' with
    | Some i -> Some (String.sub exe 0 (11 + i))
    | None -> Some exe
  else
    None

let write_env_nix () =
  match nix_store_path_of_executable () with
  | Some store_path ->
      let content = Printf.sprintf {|{ pkgs ? import <nixpkgs> {} }:
let
  t_lang = builtins.storePath "%s";
in
{
  buildInputs = [ t_lang ];
}
|} store_path
      in
      ignore (write_file env_nix_path content)
  | None ->
      (* Not running from a Nix store — write a no-op env.nix *)
      let content = {|{ pkgs ? import <nixpkgs> {} }:
{
  buildInputs = [];
}
|}
      in
      ignore (write_file env_nix_path content)

let populate_pipeline ?(build=false) (p : Ast.pipeline_result) =
  ensure_pipeline_dir ();
  write_env_nix ();
  match write_dag p with
  | Error msg -> Error ("Failed to write dag.json: " ^ msg)
  | Ok () ->
      let nix_content = Nix_emitter.emit_pipeline p in
      match write_file pipeline_nix_path nix_content with
      | Error msg -> Error ("Failed to write pipeline.nix: " ^ msg)
      | Ok () ->
          if build then build_pipeline_internal p
          else Ok (Printf.sprintf "Pipeline populated in `%s`" pipeline_dir)

let list_logs () =
  if not (Sys.file_exists pipeline_dir) then []
  else
    Sys.readdir pipeline_dir
    |> Array.to_list
    |> List.filter (fun f ->
      Filename.check_suffix f ".json"
      && String.starts_with ~prefix:"build_log_" f)
    |> List.sort (fun a b -> compare b a) (* Newest first *)

let inspect_pipeline () =
  let logs = list_logs () in
  VList (List.map (fun f -> (None, VString f)) logs)

let read_log path =
  try
    let ic = open_in path in
    let len = in_channel_length ic in
    let raw = really_input_string ic len in
    close_in ic;
    (* Very basic regex for log items *)
    let re_node = Str.regexp "\"node\": \"\\([^\"]+\\)\"" in
    let re_path = Str.regexp "\"path\": \"\\([^\"]+\\)\"" in
    let rec collect pos acc =
      try
        let _ = Str.search_forward re_node raw pos in
        let node = Str.matched_group 1 raw in
        let next_pos = Str.match_end () in
        let _ = Str.search_forward re_path raw next_pos in
        let path = Str.matched_group 1 raw in
        collect (Str.match_end ()) ((node, path) :: acc)
      with Not_found -> List.rev acc
    in
    Ok (collect 0 [])
  with exn -> Error (Printexc.to_string exn)

let read_node ?which_log name =
  let logs = list_logs () in
  let log_file =
    match which_log with
    | None -> (match logs with [] -> None | l :: _ -> Some l)
    | Some pattern ->
        (try
          List.find_opt (fun l ->
            try let _ = Str.search_forward (Str.regexp pattern) l 0 in true
            with Not_found -> false
          ) logs
        with Failure msg ->
          (* Invalid regex pattern *)
          Some ("__invalid_regex__:" ^ msg))
  in
  match log_file with
  | Some s when String.length s > 18 && String.sub s 0 18 = "__invalid_regex__:" ->
      let msg = String.sub s 18 (String.length s - 18) in
      Error.type_error (Printf.sprintf "read_node: invalid regex pattern for 'which_log': %s" msg)
  | None ->
      let suffix = match which_log with
        | Some pat -> " matching \"" ^ pat ^ "\""
        | None -> ""
      in
      Error.make_error FileError
        (Printf.sprintf "No build logs found in `_pipeline/`%s. Run `populate_pipeline(p, build=true)` first." suffix)
  | Some f ->
      match read_log (Filename.concat pipeline_dir f) with
      | Error msg -> Error.make_error FileError (Printf.sprintf "Failed to read log `%s`: %s" f msg)
      | Ok entries ->
          (match List.assoc_opt name entries with
          | None -> Error.make_error KeyError (Printf.sprintf "Node `%s` not found in build log `%s`." name f)
          | Some path ->
              (match Serialization.deserialize_from_file path with
              | Ok v -> v
              | Error msg -> Error.make_error FileError (Printf.sprintf "Failed to read node `%s` from `%s`: %s" name path msg)))
