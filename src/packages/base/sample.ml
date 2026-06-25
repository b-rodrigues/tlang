open Ast

let sample_vector arr k replace =
  match Rng.sample_indices ~total:(Array.length arr) ~k ~replace with
  | None ->
      Error.value_error
        (Printf.sprintf "Function `sample` cannot sample %d items from a population of size %d without replacement."
           k (Array.length arr))
  | Some indices ->
      VVector (Array.of_list (List.map (fun i -> arr.(i)) indices))

let sample_list items k replace =
  let total = List.length items in
  let arr = Array.of_list items in
  match Rng.sample_indices ~total ~k ~replace with
  | None ->
      Error.value_error
        (Printf.sprintf "Function `sample` cannot sample %d items from a population of size %d without replacement."
           k total)
  | Some indices ->
      let selected = List.map (fun i -> let (name, v) = arr.(i) in (name, v)) indices in
      VList selected

(*
--# Random sample from a vector or list
--#
--# Draws a random sample of size n from a vector or list, with or without
--# replacement.
--#
--# @name sample
--# @param x :: Vector | List The input data.
--# @param n :: Int = 1 Sample size.
--# @param replace :: Bool = false Sample with replacement.
--# @return :: Vector | List The random sample.
--# @example
--#   sample([1, 2, 3, 4, 5], n = 3)
--#   sample([1, 2, 3], n = 5, replace = true)
--# @family base
--# @seealso set_seed, slice_sample
--# @export
*)
let register env =
  Env.add "sample"
    (make_builtin_named ~name:"sample" ~variadic:true 1 (fun named_args _env ->
      let args = Math_common.positional_args_without ["n"; "replace"] named_args in
      match Math_common.get_bool_flag "replace" false named_args with
      | Error e -> e
      | Ok replace ->
          (match Math_common.optional_named_arg "n" named_args with
           | Some (VInt n) when n >= 0 ->
               let k = n in
               (match args with
                | [VVector arr] -> sample_vector arr k replace
                | [VList items] -> sample_list items k replace
                | [VNA _] -> Error.type_error "Function `sample` expects a Vector or List, got NA."
                | [_] -> Error.type_error "Function `sample` expects a Vector or List."
                | _ -> Error.arity_error_named "sample" 1 (List.length args))
           | Some (VInt n) ->
               Error.value_error (Printf.sprintf "Function `sample` expects `n` to be non-negative, got %d." n)
           | Some v ->
               Error.type_error (Printf.sprintf "Function `sample` expects `n` to be an Int, got %s." (Utils.type_name v))
           | None ->
               let k = 1 in
               (match args with
                | [VVector arr] -> sample_vector arr k replace
                | [VList items] -> sample_list items k replace
                | [VNA _] -> Error.type_error "Function `sample` expects a Vector or List, got NA."
                | [_] -> Error.type_error "Function `sample` expects a Vector or List."
                | _ -> Error.arity_error_named "sample" 1 (List.length args)))
    ))
    env
