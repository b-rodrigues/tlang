open Ast

let slice_impl args env =
  match args with
  | [VDataFrame df; indices_val] ->
      let n = Arrow_table.num_rows df.arrow_table in
      let idx_list_raw = match indices_val with
        | VVector arr -> Array.to_list arr
        | VList l -> List.map snd l
        | _ -> []
      in
      if idx_list_raw = [] && indices_val <> VList [] && indices_val <> VVector [||] then
        Error.type_error "Function `slice` expects a Vector or List of integer indices."
      else
        let int_indices = List.filter_map (function VInt i -> Some i | _ -> None) idx_list_raw in
        let has_out_of_bounds = List.exists (fun i -> i < 0 || i >= n) int_indices in
        if has_out_of_bounds then
          Error.make_error ValueError "Function `slice` index out of range (indices must be 0-based and within [0, nrow-1])."
        else
          let sub_table = Arrow_table.take_rows df.arrow_table int_indices in
          VDataFrame { df with arrow_table = sub_table }
  | [VString _; VInt _; VInt _] ->
      String_ops.substring_impl args env
  | _ when List.length args = 3 -> 
       Error.arity_error_named "slice" 2 3
  | _ -> Error.make_error ArityError "Function `slice` requires a DataFrame and an index vector, or a String and start/end indices."

let register env =
  Env.add "slice" (make_builtin ~name:"slice" ~variadic:true 2 slice_impl) env
