open Ast

let register env =
  let env = Env.add "list_files"
    (make_builtin ~name:"list_files" ~variadic:true 0 (fun args _env ->
      let dir = match args with
        | [VString d] -> d
        | [] -> "."
        | _ -> "."
      in
      try
        let files = Sys.readdir dir in
        VList (Array.to_list files |> List.map (fun f -> (None, VString f)))
      with e ->
        Error.make_error FileError (Printf.sprintf "Failed to list files in `%s`: %s" dir (Printexc.to_string e))
    ))
    env
  in
  let env = Env.add "file_exists"
    (make_builtin ~name:"file_exists" 1 (fun args _env ->
      match args with
      | [VString path] -> VBool (Sys.file_exists path)
      | _ -> Error.type_error "Function `file_exists` expects a string."
    ))
    env
  in
  env
