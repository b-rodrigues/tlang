open Ast

(*
--# Remove grouping
--#
--# Removes the grouping structure from a DataFrame.
--#
--# @name ungroup
--# @param df :: DataFrame The input DataFrame.
--# @return :: DataFrame An ungrouped DataFrame.
--# @example
--#   ungroup(df)
--# @family colcraft
--# @seealso group_by
--# @export
*)
let register env =
  Env.add "ungroup"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame df] ->
          VDataFrame { df with group_keys = [] }
      | [_] -> Error.type_error "Function `ungroup` expects a DataFrame as first argument."
      | _ -> Error.make_error ArityError "Function `ungroup` takes exactly 1 argument."
    ))
    env
