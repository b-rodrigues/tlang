open Ast

(*
--# Count distinct values
--#
--# Returns the number of distinct values in a vector or list.
--# Inside `summarize()`, this acts as an aggregation expression.
--#
--# @name n_distinct
--# @param x :: Vector | List The input values.
--# @param na_rm :: Bool = false Exclude NA values from the count.
--# @return :: Int The number of distinct values.
--# @example
--#   summarize(df, $unique_species = n_distinct($species))
--# @family colcraft
--# @seealso summarize, distinct
--# @export
*)
let count_distinct_in_array ?(na_rm=false) values =
  let seen = Value_hash.ValueHash.create (max 1 (min 64 (Array.length values))) in
  Array.iter (fun value ->
    match value with
    | VNA _ when na_rm -> ()
    | _ -> Value_hash.ValueHash.replace seen value ()
  ) values;
  Value_hash.ValueHash.length seen

let register env =
  Env.add "n_distinct"
    (make_builtin_named ~name:"n_distinct" ~variadic:true 1 (fun named_args _env ->
      match Math_common.get_bool_flag "na_rm" false named_args with
      | Error e -> e
      | Ok na_rm ->
      let args = Math_common.positional_args_without ["na_rm"] named_args in
      match args with
      | [VVector values] -> VInt (count_distinct_in_array ~na_rm values)
      | [VList values] ->
          let arr = Array.of_list (List.map snd values) in
          VInt (count_distinct_in_array ~na_rm arr)
      | [VNA _] -> Error.type_error "Function `n_distinct` expects a vector or list, got NA."
      | [_] -> Error.type_error "Function `n_distinct` expects a vector or list."
      | _ -> Error.arity_error_named "n_distinct" 1 (List.length args)
    ))
    env
