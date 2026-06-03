open Ast
open Builder_utils

(*
--# Build Pipeline Internally
--#
--# Calls `nix-build` on the generated `pipeline.nix` file. Extracts the store
--# path of the result and saves a build log with an exact mapping of node names
--# to artifact paths in the Nix store.
--#
--# @name build_pipeline_internal
--# @param p :: PipelineResult The pipeline AST structure.
--# @return :: Result[Value] The output Nix store path or the dry-run DataFrame.
--# @family pipeline
--# @export
*)
let nix_build_args = ref []
let default_nix_build_verbose = ref 0

let nix_verbosity_args verbose =
  if verbose <= 0 then []
  else List.init (max 0 (verbose - 1)) (fun _ -> "--verbose")

(*
--# Print Failed Node Logs
--#
--# Prints stderr log sections for each failed node by resolving its
--# derivation path through `nix log`.
--#
--# @param drv_paths :: Hashtbl Captured derivation paths keyed by node name.
--# @param errored :: List[String] Node names that failed during the build.
--# @family pipeline
*)
let print_failed_node_logs drv_paths errored =
  List.iter
    (fun name ->
      match Hashtbl.find_opt drv_paths name with
      | Some drv_path ->
          Printf.eprintf "\n--- Logs for failed node `%s` ---\n%!" name;
          let argv = [| "nix"; "log"; drv_path |] in
          (match run_command_argv_capture argv with
           | Ok output ->
               let output = String.trim output in
               if output = "" then
                 Printf.eprintf "(No log output returned for `%s`).\n%!" name
               else
                 Printf.eprintf "%s\n%!" output
           | Error msg ->
               Printf.eprintf "Failed to fetch logs for `%s`: %s\n%!" name msg)
      | None ->
          Printf.eprintf "\n--- Logs for failed node `%s` ---\nNo derivation path was captured for this node.\n%!" name)
    errored

let get_failed_node_error_info drv_path =
  let argv = [| "nix"; "log"; drv_path |] in
  match run_command_argv_capture argv with
  | Ok output ->
      let output = String.trim output in
      if output = "" then
        ("NixError", "No log output returned from nix log.")
      else
        let lines = String.split_on_char '\n' output |> List.map String.trim |> List.filter (fun s -> s <> "") in
        let last_lines =
          let len = List.length lines in
          if len > 3 then
            List.filteri (fun i _ -> i >= len - 3) lines
          else
            lines
        in
        let error_msg = String.concat "\n" last_lines in
        let error_code =
          match List.rev last_lines with
          | last :: _ ->
              (match String.split_on_char ':' last with
               | first :: _ ->
                   let parts = String.split_on_char '.' first in
                   let last_part = List.nth parts (List.length parts - 1) |> String.trim in
                   if last_part = "" then "NixError" else last_part
               | _ -> "NixError")
          | [] -> "NixError"
        in
        (error_code, error_msg)
  | Error msg ->
      ("NixError", "Failed to run nix log: " ^ msg)

let build_pipeline_internal ?verbose ?(nix_options : nix_opts option) (p : Ast.pipeline_result) =
  let verbose =
    match verbose with
    | Some level -> level
    | None -> !default_nix_build_verbose
  in
  let opts =
    match nix_options with
    | Some o -> merge_nix_opts ~specific:o ~fallback:(!global_nix_defaults)
    | None -> !global_nix_defaults
  in
  let targets = opts.targets in
  let force = opts.force in
  let dry_run = Option.value ~default:false opts.dry_run in
  let max_jobs = opts.max_jobs in
  let max_cores = opts.max_cores in
  let cache = opts.cache in
  let builders = opts.builders in
  let keep_env = opts.keep_env in
  let sandbox = opts.sandbox in
  let extract_string_list label = function
    | VString s -> Ok [s]
    | VList items ->
        if List.exists (function (_, VString _) -> false | _ -> true) items then
          Error (Printf.sprintf "Expected `%s` to contain only String values, but found non-string elements." label)
        else
          Ok (List.filter_map (function (_, VString s) -> Some s | _ -> None) items)
    | VVector arr ->
        let lst = Array.to_list arr in
        if List.exists (function VString _ -> false | _ -> true) lst then
          Error (Printf.sprintf "Expected `%s` to contain only String values, but found non-string elements." label)
        else
          Ok (List.filter_map (function VString s -> Some s | _ -> None) lst)
    | _ -> Error (Printf.sprintf "Expected `%s` to be a String, List, or Vector of strings." label)
  in
  let contains_substring line pattern =
    try
      let len_p = String.length pattern in
      let len_l = String.length line in
      let rec loop i =
        if i + len_p > len_l then false
        else if String.sub line i len_p = pattern then true
        else loop (i + 1)
      in
      loop 0
    with _ -> false
  in
  let contains_substring_idx line pattern =
    let len_p = String.length pattern in
    let len_l = String.length line in
    let rec loop i =
      if i + len_p > len_l then -1
      else if String.sub line i len_p = pattern then i
      else loop (i + 1)
    in
    loop 0
  in
  if not (command_exists "nix-build") then
    Error "build_pipeline requires `nix-build` to be available."
  else begin
    let total_start_time = Unix.gettimeofday () in
    let node_names = List.map fst p.p_exprs in
    let sorted_node_names = List.sort (fun a b -> compare (String.length b) (String.length a)) node_names in
    let target_args_result =
      match targets with
      | Some lst ->
          (match extract_string_list "targets" lst with
           | Error msg -> Error msg
           | Ok [] -> Ok ["-A"; "pipeline_output"]
           | Ok strs ->
               let invalid = List.filter (fun t -> not (List.mem t node_names)) strs in
               if invalid <> [] then
                 Error (Printf.sprintf "build_pipeline: target node(s) %s do not exist in the pipeline. Available nodes: %s"
                          (String.concat ", " (List.map (fun s -> "'" ^ s ^ "'") invalid))
                          (String.concat ", " node_names))
               else
                 Ok (List.concat (List.map (fun t -> ["-A"; t]) strs)))
      | None ->
          (* When targets is not provided but force names specific nodes,
             use those node names as the implicit build targets. *)
          (match force with
           | Some (VList _ | VVector _ | VString _ as v) ->
               (match extract_string_list "force" v with
                | Error msg -> Error msg
                | Ok [] -> Ok ["-A"; "pipeline_output"]
                | Ok strs ->
                    let invalid = List.filter (fun t -> not (List.mem t node_names)) strs in
                    if invalid <> [] then
                      Error (Printf.sprintf "build_pipeline: force rebuild node(s) %s do not exist in the pipeline. Available nodes: %s"
                               (String.concat ", " (List.map (fun s -> "'" ^ s ^ "'") invalid))
                               (String.concat ", " node_names))
                    else
                      Ok (List.concat (List.map (fun t -> ["-A"; t]) strs)))
           | _ -> Ok ["-A"; "pipeline_output"])
    in
    let force_check_result =
      match force with
      | Some (VList _ | VVector _ | VString _ as v) ->
          (match extract_string_list "force" v with
           | Error msg -> Error msg
           | Ok strs ->
               let invalid = List.filter (fun t -> not (List.mem t node_names)) strs in
               if invalid <> [] then
                 Error (Printf.sprintf "build_pipeline: force rebuild node(s) %s do not exist in the pipeline. Available nodes: %s"
                          (String.concat ", " (List.map (fun s -> "'" ^ s ^ "'") invalid))
                          (String.concat ", " node_names))
               else Ok ())
      | _ -> Ok ()
    in
    match target_args_result, force_check_result with
    | Error msg, _ | _, Error msg -> Error msg
    | Ok target_args, Ok () ->
    let force_args =
      let force_enabled =
        match force with
        | None -> false
        | Some (VBool b) -> b
        | Some (VList items) -> List.length items > 0
        | Some (VVector arr) -> Array.length arr > 0
        | Some (VString s) -> s <> ""
        | _ -> false
      in
      if force_enabled then ["--check"] else []
    in
    let max_jobs_args =
      match max_jobs with
      | Some (VInt n) when n > 0 -> ["--max-jobs"; string_of_int n]
      | _ -> []
    in
    let max_cores_args =
      match max_cores with
      | Some (VInt n) when n >= 0 -> ["--cores"; string_of_int n]
      | _ -> []
    in
    let cache_args =
      match cache with
      | Some (VString name) when name <> "" ->
          let base = ["--option"; "extra-substituters"; "https://" ^ name ^ ".cachix.org"] in
          if name = "rstats-on-nix" then
            base @ ["--option"; "extra-trusted-public-keys"; "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="]
          else
            base
      | _ -> []
    in
    let builders_args =
      match builders with
      | Some (VString s) when s <> "" -> ["--builders"; s]
      | _ -> []
    in
    let keep_env_args =
      match keep_env with
      | Some v ->
          (match extract_string_list "keep_env" v with
           | Ok [] -> []
           | Ok strs -> ["--option"; "keep-env"; String.concat " " strs]
           | Error _ -> [])
      | _ -> []
    in
    let sandbox_args =
      match sandbox with
      | Some (VBool true) -> ["--option"; "sandbox"; "true"]
      | Some (VBool false) -> ["--option"; "sandbox"; "false"]
      | Some (VString "relaxed") -> ["--option"; "sandbox"; "relaxed"]
      | Some (VString "strict") -> ["--option"; "sandbox"; "true"]
      | Some (VString "none") -> ["--option"; "sandbox"; "false"]
      | _ -> []
    in
    let all_args = !nix_build_args @ (nix_verbosity_args verbose) @ force_args @ max_jobs_args @ max_cores_args @ cache_args @ builders_args @ keep_env_args @ sandbox_args in
    let node_store_paths = Hashtbl.create (List.length node_names) in
    let () =
      if Sys.file_exists pipeline_nix_path then (
        let expr =
          let assignments =
            List.map (fun name -> Printf.sprintf "\"%s\" = toString p.\"%s\";" name name) node_names
            |> String.concat " "
          in
          Printf.sprintf "let p = import ./%s {}; in { %s }" pipeline_nix_path assignments
        in
        let argv_eval = [| "nix-instantiate"; "--impure"; "--eval"; "--strict"; "--expr"; expr |] in
        match run_command_argv_capture argv_eval with
        | Ok output ->
            let re = Str.regexp "\"?\\([a-zA-Z0-9_.-]+\\)\"?[ \t]*=[ \t]*\"\\([^\"]+\\)\"" in
            let pos = ref 0 in
            (try
               while true do
                 let _ = Str.search_forward re output !pos in
                 let name = Str.matched_group 1 output in
                 let path = Str.matched_group 2 output in
                 Hashtbl.replace node_store_paths name path;
                 pos := Str.match_end ()
               done
             with Not_found -> ())
        | Error msg ->
            if verbose > 0 then
              Printf.eprintf "[Debug] nix-instantiate eval failed: %s\n%!" msg
      )
    in
    if dry_run then begin
      let lines = ref [] in
      let callback line =
        lines := line :: !lines
      in
      let dry_args = ["--dry-run"] @ all_args in
      let argv = Array.of_list (["nix-build"; "--impure"; pipeline_nix_path] @ target_args @ ["--no-out-link"] @ dry_args) in
      match run_command_stream_argv argv callback with
      | Ok status ->
          let exit_code =
            match status with
            | Unix.WEXITED n -> n
            | Unix.WSIGNALED n | Unix.WSTOPPED n -> n
          in
          if exit_code <> 0 then
            Error (Printf.sprintf "Dry run failed with exit code %d" exit_code)
          else begin
            let reversed_lines = List.rev !lines in
            let dry_builds = Hashtbl.create (List.length node_names) in
            let dry_fetches = Hashtbl.create (List.length node_names) in
            let dry_paths = Hashtbl.create (List.length node_names) in
            let current_action = ref "build" in
            List.iter (fun line ->
              let trimmed = String.trim line in
              if contains_substring trimmed "will be built:" then
                current_action := "build"
              else if contains_substring trimmed "will be fetched" then
                current_action := "fetch"
              else if String.starts_with ~prefix:"/nix/store/" trimmed then begin
                let path = trimmed in
                match List.find_opt (fun name -> contains_substring path ("-" ^ name ^ ".drv") || contains_substring path ("-" ^ name)) sorted_node_names with
                | Some name ->
                    if !current_action = "build" then Hashtbl.replace dry_builds name true
                    else Hashtbl.replace dry_fetches name true;
                    Hashtbl.replace dry_paths name path
                | None -> ()
              end
            ) reversed_lines;
            let final_nodes = ref [] in
            let final_actions = ref [] in
            let final_paths = ref [] in
            List.iter (fun name ->
              let action =
                if Hashtbl.mem dry_builds name then "build"
                else if Hashtbl.mem dry_fetches name then "fetch"
                else "cached"
              in
              let path =
                match Hashtbl.find_opt dry_paths name with
                | Some p -> p
                | None ->
                    (match Hashtbl.find_opt node_store_paths name with
                     | Some p -> p
                     | None -> "")
              in
              final_nodes := name :: !final_nodes;
              final_actions := action :: !final_actions;
              final_paths := path :: !final_paths
            ) node_names;
            let actions_arr = Array.of_list (List.map (fun s -> Some s) (List.rev !final_actions)) in
            let paths_arr = Array.of_list (List.map (fun s -> Some s) (List.rev !final_paths)) in
            let nodes_arr = Array.of_list (List.map (fun s -> Some s) (List.rev !final_nodes)) in
            let nrows = Array.length actions_arr in
            let columns = [
              ("node", Arrow_table.StringColumn nodes_arr);
              ("action", Arrow_table.StringColumn actions_arr);
              ("path", Arrow_table.StringColumn paths_arr);
            ] in
            let arrow_table = Arrow_table.create columns nrows in
            Ok (VDataFrame { arrow_table; group_keys = [] })
          end
      | Error msg -> Error ("Dry run execution failed: " ^ msg)
    end else begin
      let statuses = Hashtbl.create (List.length node_names) in
      List.iter (fun n -> Hashtbl.add statuses n "Pending") node_names;
      
      let captured_output = Buffer.create 1024 in
      let argv = Array.of_list
        (["nix-build"; "--impure"; pipeline_nix_path] @ target_args @ ["--no-out-link"] @ all_args)
      in
      
      Printf.eprintf "\nStarting pipeline build...\n%!";
      
      let drv_paths = Hashtbl.create (List.length node_names) in
      let node_has_warnings = Hashtbl.create (List.length node_names) in
      let node_start_times = Hashtbl.create (List.length node_names) in
      let node_durations = Hashtbl.create (List.length node_names) in
      
      let callback line =
        Buffer.add_string captured_output line;
        Buffer.add_char captured_output '\n';
        
        let line = String.trim line in
        if String.starts_with ~prefix:"building '/nix/store/" line then (
          match List.find_opt (fun name -> contains_substring line ("-" ^ name ^ ".drv")) sorted_node_names with
          | Some name -> 
              Hashtbl.replace node_start_times name (Unix.gettimeofday ());
              let drv_path = 
                try
                  let start_idx = contains_substring_idx line "/nix/store/" in
                  if start_idx >= 0 then
                    let sub = String.sub line start_idx (String.length line - start_idx) in
                    let end_idx = try String.index sub '\'' with _ ->
                                  try String.index sub ' ' with _ ->
                                  String.length sub in
                    String.sub sub 0 end_idx
                  else ""
                with _ -> ""
              in
              if drv_path <> "" then Hashtbl.replace drv_paths name drv_path;

              if Hashtbl.find statuses name = "Pending" then (
                Hashtbl.replace statuses name "Building";
                Printf.eprintf "  + %s building\n%!" name
              )
          | None -> ()
        )
        else if String.starts_with ~prefix:"/nix/store/" line
             && not (String.ends_with ~suffix:".drv" line) then (
          match List.find_opt (fun name -> contains_substring line ("-" ^ name)) sorted_node_names with
          | Some name ->
              Hashtbl.replace node_store_paths name line;
              if Hashtbl.find statuses name <> "Completed" && 
                 Hashtbl.find statuses name <> "SoftFailed" &&
                 Hashtbl.find statuses name <> "Errored" then (
                let duration =
                  match Hashtbl.find_opt node_start_times name with
                  | Some t -> Unix.gettimeofday () -. t
                  | None -> 0.0
                in
                Hashtbl.replace node_durations name duration;
                Hashtbl.replace statuses name "Completed";
                Printf.eprintf "  ✓ %s built\n%!" name
              )
          | None -> ()
        )
        else (
          if contains_substring line "error:" || contains_substring line "failed" then (
            match List.find_opt (fun name -> contains_substring line ("-" ^ name ^ ".drv")) sorted_node_names with
            | Some name ->
                if Hashtbl.find statuses name <> "Errored" then (
                  let duration =
                    match Hashtbl.find_opt node_start_times name with
                    | Some t -> Unix.gettimeofday () -. t
                    | None -> 0.0
                  in
                  Hashtbl.replace node_durations name duration;
                  Hashtbl.replace statuses name "Errored";
                  let drv_path = 
                    match Hashtbl.find_opt drv_paths name with
                    | Some p -> p
                    | None ->
                      try
                        let start_idx = contains_substring_idx line "/nix/store/" in
                        if start_idx >= 0 then
                          let sub = String.sub line start_idx (String.length line - start_idx) in
                          let end_idx = try String.index sub '\'' with _ ->
                                        try String.index sub ' ' with _ ->
                                        String.length sub in
                          String.sub sub 0 end_idx
                        else "<path>"
                      with _ -> "<path>"
                  in
                  if drv_path <> "" && drv_path <> "<path>" then Hashtbl.replace drv_paths name drv_path;
                  if verbose > 0 then
                    Printf.eprintf "\n  ✖ Node %s failed! For full logs, run: read_log(\"%s\")\n\n%!" name name
                  else
                    Printf.eprintf "  ✖ %s failed\n%!" name
                )
            | None -> ()
          )
        )
      in

      let timestamp = get_timestamp () in

      let save_build_log out_path_opt =
        let total_duration = Unix.gettimeofday () -. total_start_time in
        let hash =
          match out_path_opt with
          | Some path ->
              (try
                 let parts = String.split_on_char '-' (Filename.basename path) in
                 List.hd parts
               with _ -> "no_hash")
          | None -> "no_hash"
        in
        let log_name = Printf.sprintf "build_log_%s_%s.json" timestamp hash in
        let log_path = Filename.concat pipeline_dir log_name in
        
        let log_entries =
          List.map (fun (name, _) ->
            let node_path =
              match Hashtbl.find_opt node_store_paths name with
              | Some p -> p
              | None ->
                  (match out_path_opt with
                   | Some op -> Filename.concat op name
                   | None -> "")
            in
            let artifact_path = if node_path <> "" then Filename.concat node_path "artifact" else "" in
            let class_path = if node_path <> "" then Filename.concat node_path "class" else "" in
            let class_val =
              if class_path <> "" && Sys.file_exists class_path then
                match read_file_first_line class_path with Some c -> c | None -> "Unknown"
              else "Unknown"
            in
            let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
            let serializer_expr = match List.assoc_opt name p.p_serializers with Some s -> s | None -> Ast.mk_expr (Ast.Var "default") in
            let serializer = Nix_unparse.expr_to_string serializer_expr in
            let deps = match List.assoc_opt name p.p_deps with Some d -> d| None -> [] in
            let status =
              let current = Hashtbl.find statuses name in
              if current = "Errored" then "Errored"
              else if class_val = "VError" || class_val = "Error" then "SoftFailed"
              else if class_val <> "Unknown" then "Completed"
              else if current = "Pending" || current = "Building" then "Skipped"
              else current
            in
            let success = if status = "Completed" then "true" else "false" in
            
            (* Reconcile warnings on completed nodes *)
            if node_path <> "" then (
              let warnings_path = Filename.concat node_path "warnings" in
              if Sys.file_exists warnings_path then Hashtbl.replace node_has_warnings name true
            );
            let has_warns = if Hashtbl.find_opt node_has_warnings name = Some true then "true" else "false" in
            let node_dur = match Hashtbl.find_opt node_durations name with Some d -> d | None -> 0.0 in
            
            (* Capture error code and error message for failed nodes *)
            let error_fields =
              if status = "Errored" then
                match Hashtbl.find_opt drv_paths name with
                | Some drv_path ->
                    let (err_code, err_msg) = get_failed_node_error_info drv_path in
                    [
                      ("error_code", "\"" ^ Serialization.json_escape err_code ^ "\"");
                      ("error_message", "\"" ^ Serialization.json_escape err_msg ^ "\"")
                    ]
                | None -> []
              else []
            in
            
            Serialization.json_dict ([
              ("node", "\"" ^ Serialization.json_escape name ^ "\"");
              ("path", "\"" ^ Serialization.json_escape artifact_path ^ "\"");
              ("runtime", "\"" ^ Serialization.json_escape runtime ^ "\"");
              ("serializer", "\"" ^ Serialization.json_escape serializer ^ "\"");
              ("class", "\"" ^ Serialization.json_escape class_val ^ "\"");
              ("dependencies", Serialization.json_list deps);
              ("status", "\"" ^ Serialization.json_escape status ^ "\"");
              ("success", success);
              ("warnings", has_warns);
              ("duration", Printf.sprintf "%.4f" node_dur)
            ] @ error_fields)
          ) p.p_exprs
        in
        let log_json = Serialization.json_dict [
          ("timestamp", "\"" ^ timestamp ^ "\"");
          ("hash", "\"" ^ hash ^ "\"");
          ("out_path", "\"" ^ (match out_path_opt with Some op -> op | None -> "") ^ "\"");
          ("duration", Printf.sprintf "%.4f" total_duration);
          ("nodes", "[\n" ^ (String.concat ",\n" log_entries) ^ "\n]")
        ] ^ "\n" in
        write_file log_path log_json
      in

      match run_command_stream_argv argv callback with
      | Ok status ->
          (* Save drv_paths for later tool use (e.g. read_log) *)
          if Hashtbl.length drv_paths > 0 then (
            let existing_drvs =
              let path = Filename.concat pipeline_dir "last_build_drvs.json" in
              if Sys.file_exists path then
                try
                  let json = Yojson.Safe.from_file path in
                  let open Yojson.Safe.Util in
                  match json with
                  | `Assoc pairs ->
                      List.filter_map (fun (k, v) ->
                        if List.mem k node_names then Some (k, to_string v) else None
                      ) pairs
                  | _ -> []
                with _ -> []
              else []
            in
            let drv_map = Hashtbl.create (List.length node_names + List.length existing_drvs) in
            List.iter (fun (k, v) -> Hashtbl.add drv_map k v) existing_drvs;
            Hashtbl.iter (fun k v -> Hashtbl.replace drv_map k v) drv_paths;

            let drv_entries = Hashtbl.fold (fun k v acc -> 
                (Printf.sprintf "\"%s\": \"%s\"" (Serialization.json_escape k) (Serialization.json_escape v)) :: acc
              ) drv_map [] in
            
            let drv_json = "{\n  " ^ (String.concat ",\n  " drv_entries) ^ "\n}\n" in
            ignore (write_file (Filename.concat pipeline_dir "last_build_drvs.json") drv_json)
          );

          let output = String.trim (Buffer.contents captured_output) in
          (match status with
           | Unix.WEXITED 0 when output <> "" ->
              let lines = String.split_on_char '\n' output in
              let store_paths = List.filter (fun l ->
                String.length l > 11 && String.sub l 0 11 = "/nix/store/"
              ) lines in
              (match store_paths with
              | [] -> Error "nix-build succeeded but did not return a store path."
              | _ ->
                  let out_path = List.nth store_paths (List.length store_paths - 1) in
                  let reconcile_end_time = Unix.gettimeofday () in
                  
                  (* Reconcile statuses: if nix-build succeeded, check which nodes were built (cached or otherwise) *)
                  List.iter (fun name ->
                    let node_path = Filename.concat out_path name in
                    Hashtbl.replace node_store_paths name node_path;
                    if Sys.file_exists node_path then (
                      let class_path = Filename.concat node_path "class" in
                      let warnings_path = Filename.concat node_path "warnings" in
                      if Sys.file_exists warnings_path then Hashtbl.replace node_has_warnings name true;
                      
                      if Hashtbl.find statuses name <> "Completed" && 
                         Hashtbl.find statuses name <> "SoftFailed" &&
                         Hashtbl.find statuses name <> "Errored" then (
                        (match read_file_first_line class_path with
                         | Some "VError" | Some "Error" -> Hashtbl.replace statuses name "SoftFailed"
                         | _ -> Hashtbl.replace statuses name "Completed")
                      ) else if Hashtbl.find statuses name = "Completed" then (
                        if (match read_file_first_line class_path with Some "VError" | Some "Error" -> true | _ -> false) then
                           Hashtbl.replace statuses name "SoftFailed"
                      );

                      (* Reconcile durations: if we have a start time, use it to calculate duration *)
                      (match Hashtbl.find_opt node_start_times name with
                       | Some t ->
                           let dur = reconcile_end_time -. t in
                           Hashtbl.replace node_durations name dur
                       | None -> ())
                    )
                  ) node_names;

                  (* Success Summary *)
                  let completed = List.filter (fun n -> Hashtbl.find statuses n = "Completed") node_names in
                  let soft_failed = List.filter (fun n -> Hashtbl.find statuses n = "SoftFailed") node_names in
                  let with_warnings = List.filter (fun n -> Hashtbl.find_opt node_has_warnings n = Some true) node_names in
                  let total_built = List.length completed + List.length soft_failed in
                   
                  if List.length soft_failed > 0 || List.length with_warnings > 0 then (
                    let msg = if List.length soft_failed > 0 then "\n✖ Pipeline build captured node errors" else "\n✓ Pipeline build completed" in
                    Printf.eprintf "%s [%d succeeded, %d captured errors, %d had warnings]\n%!" 
                      msg (List.length completed) (List.length soft_failed) (List.length with_warnings);
                    List.iter (fun n -> Printf.eprintf "  ! Captured error in node: %s\n%!" n) soft_failed;
                    List.iter (fun n -> Printf.eprintf "  ? Warnings in node: %s\n%!" n) with_warnings
                  ) else
                    Printf.eprintf "\n✓ Pipeline build completed [%d/%d nodes built successfully]\n%!" 
                      total_built (List.length node_names);
                  
                  (match save_build_log (Some out_path) with
                   | Error msg -> Error ("Failed to write build log: " ^ msg)
                   | Ok () -> Ok (VString out_path)))
           | Unix.WEXITED 0 ->
              ignore (save_build_log None);
              Error "nix-build succeeded but did not return an output path."
           | _ ->
              List.iter (fun name ->
                match Hashtbl.find_opt node_store_paths name with
                | Some node_path when node_path <> "" ->
                    if Sys.file_exists node_path then (
                      let class_path = Filename.concat node_path "class" in
                      let warnings_path = Filename.concat node_path "warnings" in
                      if Sys.file_exists warnings_path then Hashtbl.replace node_has_warnings name true;
                      
                      (match read_file_first_line class_path with
                       | Some "VError" | Some "Error" -> Hashtbl.replace statuses name "SoftFailed"
                       | _ -> Hashtbl.replace statuses name "Completed")
                    )
                | _ -> ()
              ) node_names;

              let errored = List.filter (fun n -> Hashtbl.find statuses n = "Errored") node_names in
              let soft_failed = List.filter (fun n -> Hashtbl.find statuses n = "SoftFailed") node_names in
              let with_warnings = List.filter (fun n -> Hashtbl.find_opt node_has_warnings n = Some true) node_names in

              let error_summary =
                if List.length errored > 0 then
                  Printf.sprintf "%d nodes errored: %s" (List.length errored) (String.concat ", " errored)
                else "General Nix build failure (check dependencies or environment)."
              in
              if verbose > 0 then (
                if errored <> [] then
                  print_failed_node_logs drv_paths errored
                else
                  let output = String.trim (Buffer.contents captured_output) in
                  if output <> "" then
                    Printf.eprintf "\n--- nix-build failure output ---\n%s\n%!" output
              );

              if List.length soft_failed > 0 || List.length with_warnings > 0 then (
                let soft_failed_str =
                  if List.length soft_failed > 0 then
                    Printf.sprintf " (%d captured errors)" (List.length soft_failed)
                  else ""
                in
                let warnings_str =
                  if List.length with_warnings > 0 then
                    Printf.sprintf " (%d warnings)" (List.length with_warnings)
                  else ""
                in
                Printf.eprintf "\n✖ Pipeline build failed [%s]%s%s\n%!" error_summary soft_failed_str warnings_str;
                List.iter (fun n -> Printf.eprintf "  ! Captured error in node: %s\n%!" n) soft_failed;
                List.iter (fun n -> Printf.eprintf "  ? Warnings in node: %s\n%!" n) with_warnings
              ) else (
                Printf.eprintf "\n✖ Pipeline build failed [%s]\n%!" error_summary
              );

              let is_failed name =
                match Hashtbl.find_opt statuses name with
                | Some "Completed" -> false
                | _ -> true
              in
              let root_causes =
                List.filter (fun name ->
                  if not (is_failed name) then false
                  else
                    let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
                    not (List.exists is_failed deps)
                ) node_names
              in

              let rec_msg =
                if root_causes <> [] then
                  let lines =
                    List.map (fun n ->
                      Printf.sprintf "  → %s (Run 'error_msg(p.%s)' and share the traceback with an LLM/Copilot for instant help!)" n n
                    ) root_causes
                  in
                  "\n💡 Recommendation: Start diagnosing at independent root failure(s):\n" ^ (String.concat "\n" lines) ^ "\n"
                else ""
              in
              if rec_msg <> "" then Printf.eprintf "%s%!" rec_msg;

              let hint =
                let base_hint =
                  if verbose > 0 then "See logs above."
                  else "Use collect_exceptions(p) and explain() for diagnostics."
                in
                if root_causes <> [] then
                  Printf.sprintf "%s (Root cause: %s. Run 'error_msg(p.%s)' and share the traceback with an LLM for help!)"
                    base_hint
                    (String.concat ", " root_causes)
                    (List.hd root_causes)
                else base_hint
              in
              ignore (save_build_log None);
              Error (Printf.sprintf "nix-build failed: %s %s" error_summary hint))
      | Error msg ->
          Error (Printf.sprintf "Failed to run nix-build: %s" msg)
    end
  end

let update_pipeline_with_build_paths (p : Ast.pipeline_result) out_path =
  let updated_nodes =
    List.map (fun (name, v) ->
      let node_path = Filename.concat out_path name in
      let artifact_path = Filename.concat node_path "artifact" in
      if Sys.file_exists artifact_path then
        let class_path = Filename.concat node_path "class" in
        let cn_class =
          match read_file_first_line class_path with
          | Some c -> c
          | None -> (match v with VComputedNode cn -> cn.cn_class | _ -> "Unknown")
        in
        let cn_runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
        let cn_serializer =
          match List.assoc_opt name p.p_serializers with
          | Some e -> Nix_unparse.expr_to_string e
          | None -> (match v with VComputedNode cn -> cn.cn_serializer | _ -> "default")
        in
        let cn_dependencies = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
        let updated_cn = {
          cn_name = name;
          cn_runtime;
          cn_path = artifact_path;
          cn_serializer;
          cn_class;
          cn_dependencies;
        } in
        (name, VComputedNode updated_cn)
      else
        (name, v)
    ) p.p_nodes
  in
  { p with p_nodes = updated_nodes }
