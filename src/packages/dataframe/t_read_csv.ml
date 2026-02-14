open Ast

let is_sep_name = function Some "separator" -> true | _ -> false

let register ~parse_csv_string env =
  Env.add "read_csv"
    (make_builtin_named ~variadic:true 1 (fun named_args _env ->
      (* Validate sep/separator parameter if provided *)
      let bad_sep = List.exists (fun (name, v) ->
        match name, v with
        | n, VString s when is_sep_name n -> String.length s <> 1
        | n, _ when is_sep_name n -> true
        | _ -> false
      ) named_args in
      if bad_sep then
        Error.type_error "Function `read_csv` separator must be a single character string."
      else
      (* Extract named arguments *)
      let sep = List.fold_left (fun acc (name, v) ->
        match name, v with
        | n, VString s when is_sep_name n -> s.[0]
        | _ -> acc
      ) ',' named_args in
      let skip_header = List.exists (fun (name, v) ->
        name = Some "skip_header" && (match v with VBool true -> true | _ -> false)
      ) named_args in
      let skip_lines = List.fold_left (fun acc (name, v) ->
        match name, v with
        | Some "skip_lines", VInt n when n >= 0 -> n
        | _ -> acc
      ) 0 named_args in
      let do_clean = List.exists (fun (name, v) ->
        name = Some "clean_colnames" && (match v with VBool true -> true | _ -> false)
      ) named_args in
      (* Extract positional arguments *)
      let args = List.filter (fun (name, _) ->
        not (is_sep_name name) && name <> Some "skip_header"
        && name <> Some "skip_lines" && name <> Some "clean_colnames"
      ) named_args |> List.map snd in
      match args with
      | [VString path] ->
          (try
            let read_content_from_path p =
              let ch = open_in p in
              let content = really_input_string ch (in_channel_length ch) in
              close_in ch;
              content
            in

            let content = 
              if Arrow_io.is_url path then
                match Arrow_io.download_url path with
                | Ok temp_path ->
                    let c = read_content_from_path temp_path in
                    (try Sys.remove temp_path with _ -> ());
                    c
                | Error msg -> raise (Sys_error msg)
              else
                read_content_from_path path
            in
            parse_csv_string ~sep ~skip_header ~skip_lines ~clean_colnames:do_clean content
          with
          | Sys_error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
      | [VNA _] -> Error.type_error "Function `read_csv` expects a String path, got NA."
      | [_] -> Error.type_error "Function `read_csv` expects a String path."
      | _ -> Error.make_error ArityError "Function `read_csv` takes exactly 1 positional argument (path)."
    ))
    env
