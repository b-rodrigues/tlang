open Ast

(*
--# Explain Value as JSON
--#
--# Returns a JSON string representation of the explain output.
--#
--# @name explain_json
--# @param x :: Any The value to explain.
--# @return :: String The JSON description.
--# @family explain
--# @seealso explain
--# @export
*)
let register ~eval_call env =
  Env.add "explain_json"
    (make_builtin 1 (fun args env ->
      match args with
      | [v] ->
          (match Env.find_opt "explain" env with
           | Some explain_fn ->
               let explain_result = eval_call env explain_fn [(None, Value v)] in
               (match explain_result with
                | VError _ -> explain_result
                | _ -> VString (Utils.value_to_string explain_result))
           | None -> Error.make_error GenericError "Function `explain_json`: explain function not found in environment.")
      | _ -> Error.arity_error_named "explain_json" ~expected:1 ~received:(List.length args)
    ))
    env
