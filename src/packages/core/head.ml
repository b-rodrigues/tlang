open Ast

(*
--# Get the first n rows/items
--#
--# Returns the first n items from a List, Vector, or DataFrame.
--# For DataFrames, it returns the top n rows.
--#
--# @name head
--# @param data :: DataFrame | List | Vector The collection to slice.
--# @param n :: Int = 5 Number of items to return.
--# @return :: DataFrame | List | Vector A subset of the input containing the first n items.
--# @example
--#   head([1, 2, 3, 4, 5, 6], n = 3)
--#   -- Returns = [1, 2, 3]
--#
--#   df |> head(n = 10)
--# @family core
--# @export
*)
let register env =
  Env.add "head"
    (make_builtin_named ~name:"head" ~variadic:true 1 (fun named_args _env ->
      (* Extract named arguments *)
      let n_named = List.fold_left (fun acc (name, v) ->
        match name, v with
        | Some "n", VInt n when n >= 0 -> Some n
        | _ -> acc
      ) None named_args in
      (* Extract positional arguments *)
      let args = List.filter (fun (name, _) ->
        name <> Some "n"
      ) named_args |> List.map snd in
      let take_head_df arrow_table group_keys n =
        let nrows = Arrow_table.num_rows arrow_table in
        let take_n = min n nrows in
        let new_table = Arrow_table.slice arrow_table 0 take_n in
        VDataFrame { arrow_table = new_table; group_keys }
      in
      match args with
      | [VDataFrame { arrow_table; group_keys }] ->
          let n = match n_named with Some n -> n | None -> 5 in
          take_head_df arrow_table group_keys n
      | [VDataFrame { arrow_table; group_keys }; VInt n] when n >= 0 ->
          take_head_df arrow_table group_keys n
      | [VList items] ->
          (match n_named with
           | Some n -> VList (Utils.list_take n items)
           | None -> (match items with h :: _ -> snd h | [] -> VNA NAGeneric))
      | [VList items; VInt n] when n >= 0 ->
          VList (Utils.list_take n items)
      | [VVector arr] ->
          let n_opt = n_named in
          (match n_opt with
           | Some n -> 
               let take_n = min n (Array.length arr) in
               VVector (Array.sub arr 0 take_n)
           | None -> 
               if Array.length arr > 0 then arr.(0) else VNA NAGeneric)
      | [VVector arr; VInt n] when n >= 0 ->
          let take_n = min n (Array.length arr) in
          VVector (Array.sub arr 0 take_n)
      | [VNA _] -> Error.type_error "Function `head` cannot be called on NA."
      | [_] -> Error.type_error "Function `head` expects a DataFrame, List, or Vector."
      | _ -> Error.arity_error_named "head" 2 (List.length args)
    ))
    env
