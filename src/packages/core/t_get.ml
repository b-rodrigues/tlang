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
--# 5. **Cross-Node Access (Sandbox)**: `get(node_lens("name"))` retrieves a sibling node's artifact from the sandbox environment.
--#
--# @name get
--# @param target :: Any The environment name (String/Symbol), Collection, Pipeline, Data, or NodeLens.
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
--#   -- Sandbox access (within a Nix-built node):
--#   get(node_lens("node_a"))      -- Deserializes T_NODE_node_a artifact
--#
--# @family core
--# @export
*)
let register ~eval_call env =
  let get_node_from_env name =
    let env_name = "T_NODE_" ^ name in
    match Sys.getenv_opt env_name with
    | Some path ->
        let artifact_path = Filename.concat path "artifact" in
        if Sys.file_exists artifact_path then
          (match Serialization.deserialize_from_file artifact_path with
           | Ok v -> v
           | Error e ->
               Error.runtime_error
                 (Printf.sprintf
                    "Function `get` failed to deserialize node artifact `%s` from `%s`: %s"
                    name artifact_path e))
        else
          Error.missing_artifact_error
            (Printf.sprintf "Artifact file %s does not exist." artifact_path)
    | None ->
        Error.missing_artifact_error
          (Printf.sprintf "Environment variable %s not found." env_name)
  in

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
            | _ -> get_node_from_env name)
      | NodeMetaLens (name, field) ->
          (match d with
           | VPipeline p ->
               (match field with
                | "runtime" -> (match List.assoc_opt name p.p_runtimes with Some v -> VString v | None -> (VNA NAGeneric))
                | "noop" -> (match List.assoc_opt name p.p_noops with Some v -> VBool v | None -> (VNA NAGeneric))
                | "serializer" -> (match List.assoc_opt name p.p_serializers with Some e -> VExpr e | None -> (VNA NAGeneric))
                | "deserializer" -> (match List.assoc_opt name p.p_deserializers with Some e -> VExpr e | None -> (VNA NAGeneric))
                | _ -> (VNA NAGeneric))
           | _ -> Error.type_error "node_meta_lens get expects a Pipeline")
      | CompositeLens (l1, l2) ->
          let inner = get_lens l1 d in
          (match inner with
           | VError _ as e -> e
           | _ -> get_lens l2 inner)
      | EnvVarLens (node, var) ->
          (match d with
           | VPipeline p ->
               (match List.assoc_opt node p.p_env_vars with
                | Some vars -> (match List.assoc_opt var vars with Some v -> v | None -> (VNA NAGeneric))
                | None -> (VNA NAGeneric))
           | _ -> Error.type_error "env_var_lens get expects a Pipeline")
       | FilterLens p ->
           let eval_pred v =
             match eval_call env p [(None, mk_expr (Value v))] with
             | VBool b -> Ok b
             | VError _ as e -> Error e
             | other ->
                 Error
                   (Error.type_error
                      (Printf.sprintf "filter_lens predicate must return Bool, got %s"
                         (Utils.type_name other)))
           in
           (match d with
            | VList items ->
                let rec aux acc = function
                  | [] -> Ok (List.rev acc)
                  | (name, v) :: rest ->
                      (match eval_pred v with
                       | Ok true -> aux ((name, v) :: acc) rest
                       | Ok false -> aux acc rest
                       | Error e -> Error e)
                in
                (match aux [] items with
                 | Ok filtered -> VList filtered
                 | Error e -> e)
            | VVector arr ->
                let rec aux acc = function
                  | [] -> Ok (List.rev acc)
                  | v :: rest ->
                      (match eval_pred v with
                       | Ok true -> aux (v :: acc) rest
                       | Ok false -> aux acc rest
                       | Error e -> Error e)
                in
                (match aux [] (Array.to_list arr) with
                 | Ok filtered -> VVector (Array.of_list filtered)
                 | Error e -> e)
            | VDataFrame df ->
                let nrows = Arrow_table.num_rows df.arrow_table in
                let keep = Array.make nrows false in
                let rec aux i =
                  if i >= nrows then Ok ()
                  else
                    let row_dict = VDict (Arrow_bridge.row_to_dict df.arrow_table i) in
                    match eval_pred row_dict with
                    | Ok b -> keep.(i) <- b; aux (i + 1)
                    | Error e -> Error e
                in
                (match aux 0 with
                 | Ok () ->
                     VDataFrame
                       { arrow_table = Arrow_compute.filter df.arrow_table keep
                       ; group_keys = df.group_keys
                       }
                 | Error e -> e)
            | VPipeline pipe ->
                let depths = Pipeline_to_frame.compute_depths pipe.p_deps in
                let rec aux acc = function
                  | [] -> Ok (List.rev acc)
                  | (name, v) :: rest ->
                      let meta = VDict (Pipeline_to_frame.node_metadata_dict name pipe depths) in
                      (match eval_pred meta with
                       | Ok true -> aux ((Some name, v) :: acc) rest
                       | Ok false -> aux acc rest
                       | Error e -> Error e)
                in
                (match aux [] pipe.p_nodes with
                 | Ok filtered -> VList filtered
                 | Error e -> e)
            | other ->
                Error.type_error
                  (Printf.sprintf "filter_lens expected collection, got %s"
                     (Utils.type_name other)))
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
           get_node_from_env name
       | [VLens _l] ->
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
