open Ast

(*
--# Arrange Pipeline Nodes
--#
--# Returns a new pipeline with nodes sorted by a metadata field. Execution
--# order is always determined by the DAG — this affects only the order in
--# which nodes appear when printing or serializing the pipeline.
--#
--# @name arrange_node
--# @param p :: Pipeline The pipeline to sort.
--# @param field :: Symbol The metadata field to sort by (e.g. `$depth`, `$name`).
--# @param direction :: String (Optional) `"asc"` (default) or `"desc"`.
--# @return :: Pipeline A new pipeline with nodes reordered.
--# @example
--#   p |> arrange_node($depth)
--#   p |> arrange_node($name, "asc")
--#   p |> arrange_node($depth, "desc")
--# @family pipeline
--# @seealso filter_node, select_node
--# @export
*)
let register env =
  Env.add "arrange_node"
    (make_builtin ~name:"arrange_node" ~variadic:true 2 (fun args _env ->
      let do_arrange p field_name ascending =
        let depths = Pipeline_to_frame.compute_depths p.p_deps in
        let node_names = List.map fst p.p_exprs in
        (* Build value list for the sort key *)
        let key_of name =
          let meta = Pipeline_to_frame.node_metadata_dict name p depths in
          match List.assoc_opt field_name meta with
          | Some v -> v
          | None -> (VNA NAGeneric)
        in
        let compare_values a b =
          match (a, b) with
          | (VInt x,    VInt y)    -> compare x y
          | (VFloat x,  VFloat y)  -> compare x y
          | (VString x, VString y) -> String.compare x y
          | (VBool x,   VBool y)   -> compare x y
          | ((VNA NAGeneric), _)             -> 1
          | (_, (VNA NAGeneric))             -> -1
          | _                      -> 0
        in
        let sorted_names =
          List.sort (fun a b ->
            let c = compare_values (key_of a) (key_of b) in
            if ascending then c else -c
          ) node_names
        in
        (* Reorder every association list in the pipeline according to sorted_names *)
        let reorder lst =
          List.filter_map (fun n -> match List.assoc_opt n lst with Some v -> Some (n, v) | None -> None) sorted_names
        in
        VPipeline {
          p_nodes        = reorder p.p_nodes;
          p_exprs        = reorder p.p_exprs;
          p_deps         = reorder p.p_deps;
          p_imports      = p.p_imports;
          p_runtimes     = reorder p.p_runtimes;
          p_serializers  = reorder p.p_serializers;
          p_deserializers = reorder p.p_deserializers;
          p_env_vars     = reorder p.p_env_vars;
          p_args         = reorder p.p_args;
          p_shells       = reorder p.p_shells;
          p_shell_args   = reorder p.p_shell_args;
          p_functions    = reorder p.p_functions;
          p_includes     = reorder p.p_includes;
          p_noops        = reorder p.p_noops;
          p_scripts      = reorder p.p_scripts;
          p_explicit_deps = reorder p.p_explicit_deps;
          p_node_diagnostics = reorder p.p_node_diagnostics;
        }
      in
      match args with
      | [VPipeline p; col_val] | [VPipeline p; col_val; VString "asc"] ->
          (match Utils.extract_column_name col_val with
           | None -> Error.type_error "Function `arrange_node` expects a `$field` reference."
           | Some field_name -> do_arrange p field_name true)
      | [VPipeline p; col_val; VString "desc"] ->
          (match Utils.extract_column_name col_val with
           | None -> Error.type_error "Function `arrange_node` expects a `$field` reference."
           | Some field_name -> do_arrange p field_name false)
      | [VPipeline _; _; VString dir] ->
          Error.value_error
            (Printf.sprintf "Function `arrange_node` direction must be \"asc\" or \"desc\", got \"%s\"." dir)
      | [VPipeline _; _; _] ->
          Error.type_error "Function `arrange_node` expects a `$field` reference."
      | [_; _] | [_; _; _] ->
          Error.type_error "Function `arrange_node` expects a Pipeline as first argument."
      | _ -> Error.make_error ArityError "Function `arrange_node` takes 2 or 3 arguments."
    ))
    env
