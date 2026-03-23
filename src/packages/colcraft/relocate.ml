open Ast

let relocate_impl (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
      let all_names = Arrow_table.column_names df.arrow_table in
      
      (* Separate positional and named arguments *)
      let positional = List.filter (fun (k, _) -> k = None) rest |> List.map snd in
      let before = match List.assoc_opt (Some ".before") rest with Some v -> Utils.extract_column_name v | None -> None in
      let after = match List.assoc_opt (Some ".after") rest with Some v -> Utils.extract_column_name v | None -> None in

      (* 1. Identify which columns to move *)
      let to_move = List.filter_map Utils.extract_column_name positional in
      
      if to_move = [] then VDataFrame df
      else
        (* 2. Construct new column order *)
        let others = List.filter (fun n -> not (List.mem n to_move)) all_names in
        let new_names = 
          match before, after with
          | Some b, _ when List.mem b others ->
              let rec insert i acc = function
                | [] -> List.rev acc
                | h :: t -> if h = b then List.rev acc @ to_move @ (h :: t) else insert (i + 1) (h :: acc) t
              in insert 0 [] others
          | _, Some a when List.mem a others ->
              let rec insert i acc = function
                | [] -> List.rev acc
                | h :: t -> if h = a then List.rev acc @ (h :: to_move) @ t else insert (i + 1) (h :: acc) t
              in insert 0 [] others
          | _ -> (* Default to beginning *)
              to_move @ others
        in
        
        let new_table = Arrow_compute.project df.arrow_table new_names in
        VDataFrame { df with arrow_table = new_table }
  | _ :: _ -> Error.type_error "Function `relocate` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `relocate` requires a DataFrame and columns to move."

(*
--# Move columns to a new position
--#
--# Reorders DataFrame columns by moving selected columns before or after another column.
--#
--# @name relocate
--# @family colcraft
--# @export
*)
let register env =
  Env.add "relocate" (make_builtin_named ~name:"relocate" ~variadic:true 1 relocate_impl) env
