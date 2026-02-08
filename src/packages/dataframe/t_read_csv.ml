open Ast

let register ~parse_csv_string env =
  Env.add "read_csv"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VString path] ->
          (try
            let ch = open_in path in
            let content = really_input_string ch (in_channel_length ch) in
            close_in ch;
            parse_csv_string content
          with
          | Sys_error msg -> make_error FileError ("File Error: " ^ msg))
      | [VNA _] -> make_error TypeError "read_csv() expects a String path, got NA"
      | [_] -> make_error TypeError "read_csv() expects a String path"
      | _ -> make_error ArityError "read_csv() takes exactly 1 argument"
    ))
    env
