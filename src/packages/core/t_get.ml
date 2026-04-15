open Ast

(*
--# Unified Data Retrieval (get)
--#
--# Retrieves values from environments, collections, or pipelines using names, 
--# indices, or lenses. 
--#
--# This is a polymorphic primitive that unifies several retrieval modes:
--#
--# 1. **Variable Lookup**: `get("var_name")` retrieves a variable from the environment.
--# 2. **Collection Indexing**: `get(collection, index)` retrieves an element (0-based).
--# 3. **Pipeline Access**: `get(pipeline, "node_name")` retrieves a specific node result.
--# 4. **Lens Focus**: `get(data, lens)` applies a Lens to focus on a subset of data.
--#
--# @name get
--# @param target :: Any The environment name (String/Symbol), Collection, Pipeline, or Data.
--# @param selector :: Any (Optional) The index (Int), Node name (String/Symbol), or Lens.
--# @return :: Any The retrieved value or focused data subset.
--# @example
--#   salary = 50000
--#   get("salary")                -- 50000 (Lookup)
--#
--#   lst = [10, 20, 30]
--#   get(lst, 1)                  -- 20 (Indexing)
--#
--#   p = pipeline { a = 1 }
--#   get(p, "a")                  -- 1 (Pipeline Access)
--#
--#   l = col_lens("mpg")
--#   get(mtcars, l)               -- Vector of 'mpg' column (Lens)
--#
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
          let get_node_from_env name =
            let env_name = "T_NODE_" ^ name in
            match Sys.getenv_opt env_name with
            | Some path ->
                let artifact_path = Filename.concat path "artifact" in
                if Sys.file_exists artifact_path then
                  (match Serialization.deserialize_from_file artifact_path with
                   | Ok v -> Some v
                   | Error _ -> None)
                else None
            | None -> None
          in
          (match d with
           | VPipeline p ->
               (match List.assoc_opt name p.p_nodes with
                | Some v -> v
                | None -> (VNA NAGeneric))
           | _ -> 
               (match get_node_from_env name with
                | Some v -> v
                | None -> Error.type_error "node_lens get expects a Pipeline or available T_NODE_<name> environment variable."))
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

      (* Lens/Node Fallback Case (1 arg: Lens) *)
      | [VLens (NodeLens name)] ->
          (match get_node_from_env name with
           | Some v -> v
           | None -> Error.type_error (Printf.sprintf "node_lens get('%s') failed: T_NODE_%s environment variable not found." name name))
      | [VLens l] ->
          Error.type_error "Single-argument get() with a lens requires a node_lens to perform environment-based retrieval."

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
