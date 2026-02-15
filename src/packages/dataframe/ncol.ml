open Ast

(*
--# Number of columns
--#
--# Returns the number of columns in a DataFrame.
--#
--# @name ncol
--# @param df :: DataFrame The input DataFrame.
--# @return :: Int The number of columns.
--# @example
--#   ncol(mtcars)
--# @family dataframe
--# @seealso nrow, colnames
--# @export
*)
let register env =
  Env.add "ncol"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] -> VInt (Arrow_table.num_columns arrow_table)
      | [VNA _] -> Error.type_error "Function `ncol` expects a DataFrame, got NA."
      | [_] -> Error.type_error "Function `ncol` expects a DataFrame."
      | _ -> Error.arity_error_named "ncol" ~expected:1 ~received:(List.length args)
    ))
    env
