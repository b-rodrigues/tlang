open Ast
open Arrow_table

let uncount_impl (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
      let weights_col = match List.filter (fun (k, _) -> k = None) rest with
        | [(_, v)] -> Utils.extract_column_name v
        | _ -> (match List.assoc_opt (Some "weights") rest with Some v -> Utils.extract_column_name v | _ -> None)
      in
      let remove = match List.assoc_opt (Some ".remove") rest with Some (VBool b) -> b | _ -> true in

      (match weights_col with
       | None -> Error.make_error ArityError "uncount expects a weights column ($col)."
       | Some col_name ->
           match Arrow_table.get_column df.arrow_table col_name with
           | Some col ->
               let weights = Arrow_bridge.column_to_values col in
               let len = Array.length weights in
               let weight_ints = Array.make len 0 in
               let error = ref None in
               Array.iteri
                 (fun i v ->
                   match (!error, v) with
                   | (Some _, _) -> ()
                   | (None, VInt n) ->
                       if n < 0 then
                         error := Some (Error.make_error ValueError "Function `uncount` expects non-negative weights.")
                       else
                         weight_ints.(i) <- n
                   | (None, VFloat f) ->
                       if f < 0. then
                         error := Some (Error.make_error ValueError "Function `uncount` expects non-negative weights.")
                       else
                         let rounded = floor f in
                         if rounded <> f then
                           error := Some (Error.make_error ValueError "Function `uncount` expects integer weights (whole numbers) when provided as floats.")
                         else
                           weight_ints.(i) <- int_of_float f
                   | (None, _) ->
                       error := Some (Error.type_error "Function `uncount` expects a numeric weights column.")
                 )
                 weights;
               (match !error with
                | Some e -> e
                | None ->
                    let final_nrows = Array.fold_left (+) 0 weight_ints in
                    let expansion_indices = Array.make final_nrows 0 in
                    let curr = ref 0 in
                    Array.iteri (fun i w ->
                      for _ = 1 to w do
                        expansion_indices.(!curr) <- i;
                        incr curr
                      done
                    ) weight_ints;

                    let base_names = if remove then
                      List.filter (fun n -> n <> col_name) (Arrow_table.column_names df.arrow_table)
                    else
                      Arrow_table.column_names df.arrow_table
                    in

                    let new_columns = List.map (fun name ->
                      match Arrow_table.get_column df.arrow_table name with
                      | Some c -> (name, Arrow_table.take_col c expansion_indices final_nrows)
                      | None -> (name, Arrow_table.NullColumn final_nrows)
                    ) base_names in

                    let new_schema = List.filter_map (fun (n, t) ->
                      if remove && n = col_name then None else Some (n, t)
                    ) df.arrow_table.schema in

                    VDataFrame { df with arrow_table = {
                      schema = new_schema;
                      columns = new_columns;
                      nrows = final_nrows;
                      native_handle = None
                    } })
           | None -> Error.make_error KeyError (Printf.sprintf "Column `%s` not found." col_name))
  | _ :: _ -> Error.type_error "Function `uncount` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `uncount` requires a DataFrame."

(*
--# Expand rows by weight
--#
--# Repeats each row according to a count column or weight expression.
--#
--# @name uncount
--# @family colcraft
--# @export
*)
let register env =
  Env.add "uncount" (make_builtin_named ~name:"uncount" ~variadic:true 1 uncount_impl) env
