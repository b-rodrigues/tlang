open Ast

(*
--# Check for NA
--#
--# Checks if a value is NA (Not Available).
--#
--# @name is_na
--# @param x :: Any The value to check.
--# @return :: Bool True if the value is NA.
--# @example
--#   is_na(na())
--#   is_na(1)
--# @family base
--# @seealso na, is_error
--# @export
*)
let register env =
  Env.add "is_na"
    (make_builtin ~name:"is_na" 1 (fun args _env ->
      match args with
      | [VNA _] -> VBool true
      | [VVector arr] -> VVector (Array.map (function VNA _ -> VBool true | _ -> VBool false) arr)
      | [VList items] -> VList (List.map (fun (n, v) -> (n, match v with VNA _ -> VBool true | _ -> VBool false)) items)
      | [_] -> VBool false
      | _ -> Error.arity_error_named "is_na" 1 (List.length args)
    ))
    env
