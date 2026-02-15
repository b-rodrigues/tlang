open Ast

(*
--# Map a function over a list
--#
--# Applies a function to each element of a list and returns a new list of results.
--#
--# @name map
--# @param list :: List The input list.
--# @param fn :: Function The function to apply to each element.
--# @return :: List The list of results.
--# @example
--#   map([1, 2, 3], fn(x) -> x * 2)
--#   -- Returns: [2, 4, 6]
--# @family core
--# @export
*)
let register ~eval_call env =
  Env.add "map"
    (make_builtin 2 (fun args env ->
      match args with
      | [VList items; fn] ->
          let mapped = List.map (fun (name, v) ->
            let result = eval_call env fn [(None, Value v)] in
            (name, result)
          ) items in
          VList mapped
      | _ -> Error.type_error "Function `map` expects a List and a Function."
    ))
    env
