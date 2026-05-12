open Ast
open Builder_utils
open Builder_logs

let inspect_pipeline ?which_log () =
  let logs = get_logs () in
  let log_file_result =
    match which_log with
    | None -> Ok (match logs with [] -> None | l :: _ -> Some l)
    | Some pattern ->
        (try
          Ok (List.find_opt (fun l ->
            try let _ = Str.search_forward (Str.regexp pattern) l 0 in true
            with Not_found -> false
          ) logs)
        with Failure msg ->
          Error msg)
  in
  match log_file_result with
  | Error msg ->
      Error.type_error (Printf.sprintf "inspect_pipeline: invalid regex pattern for 'which_log': %s" msg)
  | Ok None ->
      Error.make_error FileError "No build logs found in `_pipeline/`."
  | Ok (Some f) ->
      match read_log (Filename.concat pipeline_dir f) with
      | Error msg -> Error.make_error FileError (Printf.sprintf "Failed to read log `%s`: %s" f msg)
      | Ok entries ->
          let nrows = List.length entries in
          let arr_derivations = Array.init nrows (fun i -> let (n,_) = List.nth entries i in Some n) in
          let arr_success = Array.init nrows (fun _ -> Some true) in
          let arr_path = Array.init nrows (fun i -> let (_,cn) = List.nth entries i in Some cn.cn_path) in
          let arr_runtime = Array.init nrows (fun i -> let (_,cn) = List.nth entries i in Some cn.cn_runtime) in
          let arr_class = Array.init nrows (fun i -> let (_,cn) = List.nth entries i in Some cn.cn_class) in
          let arr_output = Array.init nrows (fun i -> let (n,_) = List.nth entries i in Some n) in
          let columns = [
            ("derivation", Arrow_table.StringColumn arr_derivations);
            ("build_success", Arrow_table.BoolColumn arr_success);
            ("runtime", Arrow_table.StringColumn arr_runtime);
            ("class", Arrow_table.StringColumn arr_class);
            ("path", Arrow_table.StringColumn arr_path);
            ("output", Arrow_table.StringColumn arr_output);
          ] in
          let arrow_table = Arrow_table.create columns nrows in
          Ast.VDataFrame { arrow_table; group_keys = [] }

let read_node_log node_name =
  let drv_path_file = Filename.concat pipeline_dir "last_build_drvs.json" in
  let json_opt = 
    if Sys.file_exists drv_path_file then
      try 
        let json = Yojson.Safe.from_file drv_path_file in
        let open Yojson.Safe.Util in
        json |> member node_name |> to_string_option
      with _ -> None
    else None
  in
  match json_opt with
  | Some drv ->
      let argv = [| "nix"; "log"; drv |] in
      (match run_command_argv_capture argv with
       | Ok output -> VString output
       | Error msg -> Error.make_error ShellError (Printf.sprintf "Failed to fetch nix log: %s" msg))
  | None ->
      (* Fallback: try to instantiate the derivation path from pipeline.nix *)
      if Sys.file_exists pipeline_nix_path then
        let argv = [| "nix-instantiate"; "--impure"; pipeline_nix_path; "-A"; node_name |] in
        (match run_command_argv_capture argv with
         | Ok output ->
             let drv = String.trim output in
             if drv <> "" && String.ends_with ~suffix:".drv" drv then
               let argv_log = [| "nix"; "log"; drv |] in
               (match run_command_argv_capture argv_log with
                | Ok log_output -> VString log_output
                | Error msg -> Error.make_error ShellError (Printf.sprintf "Failed to fetch nix log: %s" msg))
             else
               Error.make_error ValueError (Printf.sprintf "Node `%s` not found in last build attempt and could not be instantiated from `%s`." node_name pipeline_nix_path)
         | Error msg ->
             Error.make_error ValueError (Printf.sprintf "Node `%s` not found in last build attempt and instantiation failed: %s" node_name msg))
      else
        Error.make_error FileError (Printf.sprintf "Node `%s` not found in last build attempt and `%s` is missing. Run `build_pipeline` first." node_name pipeline_nix_path)
