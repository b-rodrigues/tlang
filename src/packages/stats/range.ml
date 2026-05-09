open Ast

(*
--# Range
--#
--# Return min and max as a length-2 vector.
--#
--# @name range
--# @param x :: Vector | List Numeric input.
--# @param na_rm :: Bool = false Remove NA values first.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family stats
--# @export
*)

let register env =
  Env.add "range" (make_builtin_named ~name:"range" ~variadic:true 1 (fun named_args _ ->
    match Math_common.get_bool_flag "na_rm" false named_args with
    | Error e -> e
    | Ok na_rm ->
    let args = Math_common.positional_args_without ["na_rm"] named_args in
    match args with
    | [x] -> 
        (match Math_utils.extract_numeric_array ~label:"range" ~na_rm x with 
         | Error e -> e 
         | Ok [||] -> VNA NAFloat 
         | Ok xs -> VVector [|VFloat (Array.fold_left min infinity xs); VFloat (Array.fold_left max neg_infinity xs)|])
    | args -> Error.arity_error_named "range" 1 (List.length args))) env
