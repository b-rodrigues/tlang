(* src/pipeline/builder_read_node.ml *)
open Builder_utils
open Builder_logs

let read_node ?which_log name =
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
      Error.type_error (Printf.sprintf "read_node: invalid regex pattern for 'which_log': %s" msg)
  | Ok None ->
      let suffix = match which_log with
        | Some pat -> " matching \"" ^ pat ^ "\""
        | None -> ""
      in
      Error.make_error FileError
        (Printf.sprintf "No build logs found in `_pipeline/`%s. Run `populate_pipeline(p, build=true)` first." suffix)
  | Ok (Some f) ->
      match read_log (Filename.concat pipeline_dir f) with
      | Error msg -> Error.make_error FileError (Printf.sprintf "Failed to read log `%s`: %s" f msg)
      | Ok entries ->
          (match List.assoc_opt name entries with
          | None -> Error.make_error KeyError (Printf.sprintf "Node `%s` not found in build log `%s`." name f)
          | Some path ->
              (match Serialization.deserialize_from_file path with
              | Ok v -> v
              | Error msg -> Error.make_error FileError (Printf.sprintf "Failed to read node `%s` from `%s`: %s" name path msg)))
