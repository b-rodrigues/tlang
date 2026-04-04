open Ast

let slice_generic ~desc (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
      let n_limit = match List.assoc_opt (Some "n") rest with Some (VInt i) -> i | _ -> 1 in
      let order_by_val = match List.assoc_opt (Some "order_by") rest with Some v -> v | None -> 
        (match List.filter (fun (k, _) -> k = None) rest with [(_, v)] -> v | _ -> (VNA NAGeneric)) in
      
      (match Utils.extract_column_name order_by_val with
       | None -> Error.type_error "slice_max/min expects `order_by = $column`."
       | Some col_name ->
           match Arrow_table.get_column df.arrow_table col_name with
           | None -> Error.make_error KeyError (Printf.sprintf "Column `%s` not found." col_name)
           | Some col ->
               let values = Arrow_bridge.column_to_values col in
               let indexed = Array.mapi (fun i v -> (i, v)) values in
               
               let compare_v (_, v1) (_, v2) =
                 let c = match v1, v2 with
                   | VInt x, VInt y -> compare x y
                   | VFloat x, VFloat y -> compare x y
                   | VInt x, VFloat y -> compare (float_of_int x) y
                   | VFloat x, VInt y -> compare x (float_of_int y)
                   | VString x, VString y -> String.compare x y
                   | VNA _, VNA _ -> 0
                   | VNA _, _ -> -1
                   | _, VNA _ -> 1
                   | _ -> 0
                 in
                 if desc then -c else c
               in
               
               Array.sort compare_v indexed;
               
               let top_n = ref [] in
               for i = 0 to min n_limit (Array.length indexed) - 1 do
                 top_n := (fst indexed.(i)) :: !top_n
               done;
               
               let sub_table = Arrow_compute.take_rows df.arrow_table (List.rev !top_n) in
               VDataFrame { df with arrow_table = sub_table })
  | _ :: _ -> Error.type_error "Function expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function requires a DataFrame."

let slice_max_impl = slice_generic ~desc:true
let slice_min_impl = slice_generic ~desc:false

(*
--# Keep rows with the largest values
--#
--# Returns the rows with the highest values in an ordering column.
--#
--# @name slice_max
--# @family colcraft
--# @export
*)
(*
--# Keep rows with the smallest values
--#
--# Returns the rows with the lowest values in an ordering column.
--#
--# @name slice_min
--# @family colcraft
--# @export
*)
let register env =
  let env = Env.add "slice_max" (make_builtin_named ~name:"slice_max" ~variadic:true 1 slice_max_impl) env in
  let env = Env.add "slice_min" (make_builtin_named ~name:"slice_min" ~variadic:true 1 slice_min_impl) env in
  env
