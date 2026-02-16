open Ast

(*
--# Get All Intent Fields
--#
--# Returns all fields of an Intent object as a dictionary.
--#
--# @name intent_fields
--# @param intent :: Intent The intent object.
--# @return :: Dict The intent fields.
--# @family explain
--# @seealso intent_get
--# @export
*)
let register env =
  Env.add "intent_fields"
    (make_builtin ~name:"intent_fields" 1 (fun args _env ->
      match args with
      | [VIntent { intent_fields }] ->
          VDict (List.map (fun (k, v) -> (k, VString v)) intent_fields)
      | [_] -> Error.type_error "Function `intent_fields` expects an Intent value."
      | _ -> Error.arity_error_named "intent_fields" ~expected:1 ~received:(List.length args)
    ))
    env
