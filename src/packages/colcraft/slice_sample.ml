open Ast

(*
--# Randomly sample rows from a DataFrame
--#
--# Draws a random sample of n rows from a DataFrame, with or without
--# replacement.
--#
--# @name slice_sample
--# @param data :: DataFrame The input DataFrame.
--# @param n :: Int = 1 Number of rows to sample.
--# @param replace :: Bool = false Sample with replacement.
--# @return :: DataFrame A DataFrame containing the sampled rows.
--# @example
--#   mtcars |> slice_sample(n = 5)
--#   mtcars |> slice_sample(n = 100, replace = true)
--# @family colcraft
--# @seealso sample, set_seed, slice, slice_max, slice_min
--# @export
*)
let register env =
  Env.add "slice_sample"
    (make_builtin_named ~name:"slice_sample" ~variadic:true 1 (fun named_args _env ->
      match named_args with
      | (_, VDataFrame df) :: rest ->
          (match Math_common.get_bool_flag "replace" false rest with
           | Error e -> e
           | Ok replace ->
               (match Math_common.optional_named_arg "n" rest with
                | Some (VInt n) when n >= 0 ->
                    let k = n in
                    let total = Arrow_table.num_rows df.arrow_table in
                    (match Rng.sample_indices ~total ~k ~replace with
                     | None ->
                         Error.value_error
                           (Printf.sprintf "Function `slice_sample` cannot sample %d rows from a DataFrame with %d rows without replacement."
                              k total)
                     | Some indices ->
                         let sub_table = Arrow_table.take_rows df.arrow_table indices in
                         VDataFrame { df with arrow_table = sub_table })
                | Some (VInt n) ->
                    Error.value_error (Printf.sprintf "Function `slice_sample` expects `n` to be non-negative, got %d." n)
                | Some v ->
                    Error.type_error (Printf.sprintf "Function `slice_sample` expects `n` to be an Int, got %s." (Utils.type_name v))
                | None ->
                    let k = 1 in
                    let total = Arrow_table.num_rows df.arrow_table in
                    (match Rng.sample_indices ~total ~k ~replace with
                     | None ->
                         Error.value_error
                           (Printf.sprintf "Function `slice_sample` cannot sample %d rows from a DataFrame with %d rows without replacement."
                              k total)
                     | Some indices ->
                         let sub_table = Arrow_table.take_rows df.arrow_table indices in
                         VDataFrame { df with arrow_table = sub_table })))
      | _ -> Error.type_error "Function `slice_sample` expects a DataFrame as first argument."
    ))
    env
