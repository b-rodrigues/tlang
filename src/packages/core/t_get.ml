open Ast

(*
--# Get variable or element
--#
--# If called with one argument, retrieves a variable's value from the environment 
--# by name (String or Symbol). Matches R's `get()` semantics for variable lookup.
--#
--# If called with two arguments, retrieves an element from a List, Vector, or 
--# NDArray at the specified index (0-based).
--#
--# @name get
--# @param x :: String | Symbol | List | Vector | NDArray The variable name or collection.
--# @param index :: Int (Optional) The index to retrieve if `x` is a collection.
--# @return :: Any The variable value or collection element.
--# @example
--#   salary = 50000
--#   get("salary")
--#   -- Returns = 50000
--#
--#   col_name = "salary"
--#   get(sym(col_name))
--#   -- Returns = 50000
--#
--#   get([10, 20, 30], 1)
--#   -- Returns = 20
--# @family core
--# @export
*)
let register ~eval_call env =
  let apply_lens lens data _env_ref =
    let rec get_lens l d =
      match l with
      | ColLens col_name ->
          (match d with
           | VDataFrame df -> 
               (match Arrow_table.get_column df.arrow_table col_name with
                | Some col -> VVector (Arrow_bridge.column_to_values col)
                | None -> (VNA NAGeneric))
           | VDict items -> (match List.assoc_opt col_name items with Some v -> v | None -> (VNA NAGeneric))
           | VVector arr -> VVector (Array.map (fun v -> get_lens l v) arr)
           | VList items -> VList (List.map (fun (n, v) -> (n, get_lens l v)) items)
           | _ -> Error.type_error (Printf.sprintf "Lens get('%s') cannot be applied to %s" col_name (Utils.type_name d)))
      | IdxLens i ->
          (match d with
           | VList items ->
               let len = List.length items in
               if i < 0 || i >= len then Error.index_error i len
               else let (_, v) = List.nth items i in v
           | VVector arr ->
               let len = Array.length arr in
               if i < 0 || i >= len then Error.index_error i len
               else arr.(i)
           | _ -> Error.type_error (Printf.sprintf "idx_lens get expects a List or Vector, got %s" (Utils.type_name d)))
      | RowLens i ->
          (match d with
           | VDataFrame df ->
               let nrows = Arrow_table.num_rows df.arrow_table in
               if i < 0 || i >= nrows then Error.index_error i nrows
               else VDict (Arrow_bridge.row_to_dict df.arrow_table i)
           | _ -> Error.type_error (Printf.sprintf "row_lens get expects a DataFrame, got %s" (Utils.type_name d)))
      | NodeLens name ->
          (match d with
           | VPipeline p ->
               (match List.assoc_opt name p.p_nodes with
                | Some v -> v
                | None -> (VNA NAGeneric))
           | _ -> Error.type_error "node_lens get expects a Pipeline")
      | EnvVarLens (node, var) ->
          (match d with
           | VPipeline p ->
               (match List.assoc_opt node p.p_env_vars with
                | Some vars -> (match List.assoc_opt var vars with Some v -> v | None -> (VNA NAGeneric))
                | None -> (VNA NAGeneric))
           | _ -> Error.type_error "env_var_lens get expects a Pipeline")
      | CompositeLens (l1, l2) ->
          let inner = get_lens l1 d in
          (match inner with
           | VError _ as e -> e
           | _ -> get_lens l2 inner)
    in
    get_lens lens data
  in

  Env.add "get"
    (make_builtin ~name:"get" ~variadic:true 1 (fun args env ->
      let args_vals = args in
      match args_vals with
      (* Variable Lookup Case (1 arg) *)
      | [VString name] | [VSymbol name] ->
          (match Env.find_opt name env with
           | Some v -> v
           | None -> Error.name_error name)

      (* Pipeline Node Lookup (2 args: Pipeline, String/Symbol) *)
      | [VPipeline p; VString node_name] | [VPipeline p; VSymbol node_name] ->
          (match List.assoc_opt node_name p.p_nodes with
           | Some v -> v
           | None -> (VNA NAGeneric))

      (* Lens Case (2 args: Data, Lens) *)
      | [data; VLens l] ->
          apply_lens l data (ref env)

      (* Collection Indexing Case (2 args: Collection, Int) *)
      | [VList items; VInt i] ->
          let len = List.length items in
          if i < 0 || i >= len then Error.index_error i len
          else let (_, v) = List.nth items i in v
      | [VVector arr; VInt i] ->
          let len = Array.length arr in
          if i < 0 || i >= len then Error.index_error i len
          else arr.(i)
      | [VNDArray arr; VInt i] ->
          let len = Array.length arr.data in
          if i < 0 || i >= len then Error.index_error i len
          else VFloat arr.data.(i)

      (* Fallback: legacy VDict lens support? *)
      | [data; VDict items] ->
          (match List.assoc_opt "get" items with
           | Some get_fn -> eval_call env get_fn [(None, mk_expr (Value data))]
           | None -> Error.type_error "Function `get`: Data and Dict provided, but Dict is not a valid lens.")

      | [v] -> Error.type_error (Printf.sprintf "Function `get` (1 arg) expects a String or Symbol, got %s." (Utils.type_name v))
      | [_ ; other] -> Error.type_error (Printf.sprintf "Function `get` (2 args) expects (Pipeline, String), (Collection, Int), or (Data, Lens). Got %s as second argument." (Utils.type_name other))
      | _ -> Error.arity_error_named "get" 1 (List.length args)
    ))
    env
