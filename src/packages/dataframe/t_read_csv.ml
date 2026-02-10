open Ast

let register ~parse_csv_string env =
  Env.add "read_csv"
    (make_builtin_named ~variadic:true 1 (fun named_args _env ->
      (* Extract named arguments *)
      let sep = List.fold_left (fun acc (name, v) ->
        match name, v with
        | Some "sep", VString s when String.length s = 1 -> s.[0]
        | Some "sep", VString _ -> acc  (* ignore multi-char sep, keep default *)
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
      (* Extract positional arguments *)
      let args = List.filter (fun (name, _) ->
        name <> Some "sep" && name <> Some "skip_header" && name <> Some "skip_lines"
      ) named_args |> List.map snd in
      match args with
      | [VString path] ->
          (try
            let ch = open_in path in
            let content = really_input_string ch (in_channel_length ch) in
            close_in ch;
            parse_csv_string ~sep ~skip_header ~skip_lines content
          with
          | Sys_error msg -> make_error FileError ("File Error: " ^ msg))
      | [VNA _] -> make_error TypeError "read_csv() expects a String path, got NA"
      | [_] -> make_error TypeError "read_csv() expects a String path"
      | _ -> make_error ArityError "read_csv() takes exactly 1 positional argument (path)"
    ))
    env
