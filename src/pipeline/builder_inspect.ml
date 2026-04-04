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
  if not (Sys.file_exists drv_path_file) then
    Error.make_error FileError "No derivation paths found. Run `build_pipeline` first."
  else
    try
      let json = Yojson.Safe.from_file drv_path_file in
      let open Yojson.Safe.Util in
      match json |> member node_name |> to_string_option with
      | None ->
          Error.make_error ValueError (Printf.sprintf "Node `%s` not found in the last build attempt." node_name)
      | Some drv ->
          let argv = [| "nix"; "log"; drv |] in
          (match run_command_argv_capture argv with
           | Ok output -> VString output
           | Error msg -> Error.make_error ShellError (Printf.sprintf "Failed to fetch nix log: %s" msg))
    with exn ->
      Error.make_error FileError (Printf.sprintf "Failed to parse `%s`: %s" drv_path_file (Printexc.to_string exn))
