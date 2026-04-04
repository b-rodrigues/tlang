open Ast

(*
--# Write text to a file
--#
--# Writes a string to a file at the specified path.
--#
--# @name write_text
--# @param path :: String The file path.
--# @param content :: String The content to write.
--# @return :: Null
--# @family core
--# @export
*)
let register env =
  Env.add "write_text"
    (make_builtin ~name:"write_text" 2 (fun args _env ->
      match args with
      | [VString path; VString content] ->
          (try
            let oc = open_out path in
            output_string oc content;
            close_out oc;
            (VNA NAGeneric)
          with e ->
            Error.make_error FileError (Printf.sprintf "Failed to write to file `%s`: %s" path (Printexc.to_string e)))
      | [VString _; _] -> Error.type_error "Function `write_text` expects a string as second argument."
      | [_; _] -> Error.type_error "Function `write_text` expects a string as first argument."
      | _ -> Error.arity_error_named "write_text" 2 (List.length args)
    ))
    env
