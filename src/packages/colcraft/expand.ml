open Ast
open Arrow_table

type expand_input =
  | Single of string * value list
  | Nested of string list * (value list) list

let rec cartesian lists =
  match lists with
  | [] -> [[]]
  | h :: t ->
      let t_prod = cartesian t in
      List.concat (List.map (fun elm -> List.map (fun t_line -> elm :: t_line) t_prod) h)

let value_compare v1 v2 =
  match v1, v2 with
  | VInt i1, VInt i2 -> compare i1 i2
  | VFloat f1, VFloat f2 -> compare f1 f2
  | VString s1, VString s2 -> compare s1 s2
  | VBool b1, VBool b2 -> compare b1 b2
  | VNA _, VNA _ -> 0
  | VNA _, _ -> -1
  | _, VNA _ -> 1
  | _ -> compare v1 v2

let unique_sorted vals =
  List.sort_uniq value_compare vals

let get_col_vals df col_name =
  match Arrow_table.get_column df.arrow_table col_name with
  | Some (IntColumn a) -> Array.to_list a |> List.map (function Some i -> VInt i | None -> VNA NAGeneric) |> unique_sorted
  | Some (FloatColumn a) -> Array.to_list a |> List.map (function Some f -> VFloat f | None -> VNA NAGeneric) |> unique_sorted
  | Some (StringColumn a) -> Array.to_list a |> List.map (function Some s -> VString s | None -> VNA NAGeneric) |> unique_sorted
  | Some (BoolColumn a) -> Array.to_list a |> List.map (function Some b -> VBool b | None -> VNA NAGeneric) |> unique_sorted
  | _ -> [VNA NAGeneric]

let get_nested_vals df col_names =
  let nrows = Arrow_table.num_rows df.arrow_table in
  let rec get_row i names =
    match names with
    | [] -> []
    | n :: ns ->
        let v = match Arrow_table.get_column df.arrow_table n with
          | Some (IntColumn a) -> (match a.(i) with Some x -> VInt x | None -> VNA NAGeneric)
          | Some (FloatColumn a) -> (match a.(i) with Some x -> VFloat x | None -> VNA NAGeneric)
          | Some (StringColumn a) -> (match a.(i) with Some x -> VString x | None -> VNA NAGeneric)
          | Some (BoolColumn a) -> (match a.(i) with Some x -> VBool x | None -> VNA NAGeneric)
          | _ -> VNA NAGeneric
        in v :: get_row i ns
  in
  let all_combos = ref [] in
  for i = 0 to nrows - 1 do
    all_combos := get_row i col_names :: !all_combos
  done;
  List.sort_uniq (fun l1 l2 ->
    let rec cmp_lists a b = match a, b with
      | [], [] -> 0
      | h1::t1, h2::t2 -> let c = value_compare h1 h2 in if c <> 0 then c else cmp_lists t1 t2
      | _ -> 0
    in cmp_lists l1 l2
  ) !all_combos

(*
--# Create all combinations of values
--#
--# Generates all unique combinations of the provided columns or expressions.
--# Supports nesting() to only include combinations present in the data.
--#
--# @name expand
--# @param df :: DataFrame The DataFrame.
--# @param ... :: Symbol | Vector | Call Specification of columns to expand.
--# @return :: DataFrame A DataFrame with all combinations.
--# @example
--#   expand(df, $type, $size)
--#   expand(df, nesting($type, $size))
--#   expand(df, $type, 2010:2012)
--# @family colcraft
--# @export
*)
let expand_impl named_args _env =
  let df_arg = match named_args with
    | (_, VDataFrame df) :: _ -> Some df
    | _ -> None
  in
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in
  let rest_args = match positional with _::tail -> tail | [] -> [] in
  
  match df_arg with
  | None -> Error.type_error "Function `expand` expects a DataFrame as first argument."
  | Some df ->
      let inputs = List.filter_map (fun v ->
        match v with
        | VSymbol s -> 
            let col = match Utils.extract_column_name v with Some n -> n | None -> s in
            Some (Single (col, get_col_vals df col))
        | VDict d when List.mem_assoc "__nesting__" d ->
            let cols = match List.assoc_opt "cols" d with Some (VList l) -> List.filter_map (fun (_, sv) -> Utils.extract_column_name sv) l | _ -> [] in
            Some (Nested (cols, get_nested_vals df cols))
        | VVector a -> Some (Single ("vector", Array.to_list a |> unique_sorted))
        | VList l -> Some (Single ("list", List.map snd l |> unique_sorted))
        | _ -> None
      ) rest_args in
      
      if inputs = [] then VDataFrame { df with arrow_table = Arrow_table.create [] 0 } else
      
      let column_names = List.concat_map (function Single (n, _) -> [n] | Nested (ns, _) -> ns) inputs in
      
      let combo_lists = List.map (function
        | Single (_, vals) -> List.map (fun v -> [v]) vals
        | Nested (_, combos) -> combos
      ) inputs in
      
      let final_combos = cartesian combo_lists |> List.map List.flatten in
      let nrows = List.length final_combos in
      let combos_arr = Array.of_list final_combos in
      
      let columns = List.mapi (fun i name ->
        let data = Array.init nrows (fun row_idx ->
          match List.nth_opt combos_arr.(row_idx) i with
          | Some (VInt x) -> Some (Ast.VInt x)
          | Some (VFloat x) -> Some (Ast.VFloat x)
          | Some (VString x) -> Some (Ast.VString x)
          | Some (VBool x) -> Some (Ast.VBool x)
          | _ -> None
        ) in
        (* Inference for output column type *)
        let first_v = if nrows > 0 then List.nth combos_arr.(0) i else VNA NAGeneric in
        let col = match first_v with
          | VInt _ -> IntColumn (Array.map (function Some (VInt x) -> Some x | _ -> None) data)
          | VFloat _ -> FloatColumn (Array.map (function Some (VFloat x) -> Some x | Some (VInt x) -> Some (float_of_int x) | _ -> None) data)
          | VString _ -> StringColumn (Array.map (function Some (VString x) -> Some x | _ -> None) data)
          | VBool _ -> BoolColumn (Array.map (function Some (VBool x) -> Some x | _ -> None) data)
          | _ -> NullColumn nrows
        in
        (name, col)
      ) column_names in
      
      let schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) columns in
      VDataFrame { arrow_table = { schema; columns; nrows; native_handle = None } |> Arrow_table.materialize; group_keys = [] }

(*
--# Create a data frame from all combinations of inputs
--#
--# crossing() generates all unique combinations of its inputs.
--# Unlike expand_grid(), it de-duplicates and sorts its inputs.
--#
--# @name crossing
--# @param ... :: Vector | List Named or unnamed inputs to combine.
--# @return :: DataFrame A DataFrame with all unique combinations.
--# @example
--#   crossing(x = 1:3, y = ["a", "b"])
--# @family colcraft
--# @export
*)
let crossing_impl named_args _env =
  let inputs = List.mapi (fun i (name, v) ->
    let col_name = match name with Some s -> s | None -> "col" ^ string_of_int (i + 1) in
    let vals = match v with
      | VVector a -> Array.to_list a |> unique_sorted
      | VList l -> List.map snd l |> unique_sorted
      | _ -> [v] |> unique_sorted
    in
    (col_name, vals)
  ) named_args in
  
  if inputs = [] then VDataFrame { arrow_table = Arrow_table.create [] 0; group_keys = [] } else
  
  (* Handle the case where any input has zero values: return empty DataFrame *)
  if List.exists (fun (_, vals) -> vals = []) inputs then begin
    let columns = List.map (fun (name, vals) ->
      (* Infer type from first element if available; empty inputs fall through to NullColumn *)
      let col = match vals with
        | (VInt _) :: _ -> IntColumn (Array.make 0 None)
        | (VFloat _) :: _ -> FloatColumn (Array.make 0 None)
        | (VString _) :: _ -> StringColumn (Array.make 0 None)
        | (VBool _) :: _ -> BoolColumn (Array.make 0 None)
        | _ -> NullColumn 0  (* empty list or unrecognised type *)
      in (name, col)
    ) inputs in
    let schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) columns in
    VDataFrame { arrow_table = { schema; columns; nrows = 0; native_handle = None } |> Arrow_table.materialize; group_keys = [] }
  end else begin
    let combo_lists = List.map (fun (_, vals) -> List.map (fun v -> [v]) vals) inputs in
    let final_combos = cartesian combo_lists |> List.map List.flatten in
    let nrows = List.length final_combos in
    let combos_arr = Array.of_list final_combos in
    
    let columns = List.mapi (fun i (name, _) ->
      let data = Array.init nrows (fun row_idx -> match List.nth_opt combos_arr.(row_idx) i with Some v -> v | None -> VNA NAGeneric) in
      let col = match data.(0) with
        | VInt _ -> IntColumn (Array.map (function VInt x -> Some x | _ -> None) data)
        | VFloat _ -> FloatColumn (Array.map (function VFloat x -> Some x | VInt x -> Some (float_of_int x) | _ -> None) data)
        | VString _ -> StringColumn (Array.map (function VString x -> Some x | _ -> None) data)
        | VBool _ -> BoolColumn (Array.map (function VBool x -> Some x | _ -> None) data)
        | _ -> NullColumn nrows
      in (name, col)
    ) inputs in
    
    let schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) columns in
    VDataFrame { arrow_table = { schema; columns; nrows; native_handle = None } |> Arrow_table.materialize; group_keys = [] }
  end

(*
--# Helper to find combinations present in data
--#
--# nesting() is used inside expand() or complete() to only use combinations
--# that already appear in the data.
--#
--# @name nesting
--# @param ... :: Symbol The columns to nest (use $col syntax).
--# @return :: Dict A special marker for expand/complete.
--# @example
--#   expand(df, nesting($year, $month))
--# @family colcraft
--# @export
*)
let nesting_impl args _env =
  let col_args = List.map snd args in
  VDict [("__nesting__", VBool true); ("cols", VList (List.map (fun v -> (None, v)) col_args))]

let register env =
  let env = Env.add "expand" (make_builtin_named ~name:"expand" ~variadic:true 1 expand_impl) env in
  let env = Env.add "crossing" (make_builtin_named ~name:"crossing" ~variadic:true 0 crossing_impl) env in
  let env = Env.add "nesting" (make_builtin_named ~name:"nesting" ~variadic:true 0 nesting_impl) env in
  env
