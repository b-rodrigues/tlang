open Ast

let starts_with_function args =
  match args with
  | [VString prefix] -> StartsWith prefix
  | _ -> VError "starts_with expects a string argument"

(* Registration during environment setup *)
let () =
  Hashtbl.replace global_env "starts_with" (VBuiltin starts_with_function)
