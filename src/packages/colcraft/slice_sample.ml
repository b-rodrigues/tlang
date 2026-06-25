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
          if List.exists (fun (k, _) -> k = None) rest then
            let n_args = 1 + List.length (List.filter (fun (k, _) -> k = None) rest) in
            Error.arity_error_named "slice_sample" 1 n_args
          else
            (match Math_common.get_bool_flag "replace" false rest with
             | Error e -> e
             | Ok replace ->
                 let k_res =
                   match Math_common.optional_named_arg "n" rest with
                   | Some (VInt n) when n >= 0 -> Ok n
                   | Some (VInt n) ->
                       Error (Error.value_error (Printf.sprintf "Function `slice_sample` expects `n` to be non-negative, got %d." n))
                   | Some v ->
                       Error (Error.type_error (Printf.sprintf "Function `slice_sample` expects `n` to be an Int, got %s." (Utils.type_name v)))
                   | None -> Ok 1
                 in
                 (match k_res with
                  | Error e -> e
                  | Ok k ->
                      let total = Arrow_table.num_rows df.arrow_table in
                      (match Rng.sample_indices ~total ~k ~replace with
                       | None ->
                           if total = 0 && k > 0 then
                             Error.value_error "Function `slice_sample` cannot sample from an empty DataFrame."
                           else
                             Error.value_error
                               (Printf.sprintf "Function `slice_sample` cannot sample %d rows from a DataFrame with %d rows without replacement."
                                  k total)
                       | Some indices ->
                           let sub_table = Arrow_table.take_rows df.arrow_table indices in
                           VDataFrame { df with arrow_table = sub_table })))
      | _ -> Error.type_error "Function `slice_sample` expects a DataFrame as first argument."
    ))
    env
