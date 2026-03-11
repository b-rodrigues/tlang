open Ast

(*
--# Group size aggregation
--#
--# Returns the number of rows in the current aggregation context.
--# Use this inside `summarize()` to count rows per group.
--#
--# @name n
--# @return :: Int The row count.
--# @example
--#   df |> group_by($species) |> summarize($rows = n())
--# @family colcraft
--# @seealso summarize, count
--# @export
*)
let register env =
  Env.add "n"
    (make_builtin ~name:"n" ~variadic:true 0 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] -> VInt (Arrow_table.num_rows arrow_table)
      | [VVector values] -> VInt (Array.length values)
      | [VList values] -> VInt (List.length values)
      | [] -> Error.value_error "Function `n` is only valid inside `summarize()`."
      | [_] -> Error.type_error "Function `n` expects a DataFrame, vector, or list aggregation context."
      | _ -> Error.arity_error_named "n" ~expected:1 ~received:(List.length args)
    ))
    env
