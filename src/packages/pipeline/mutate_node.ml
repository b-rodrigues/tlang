open Ast

(*
--# Mutate Pipeline Node Metadata
--#
--# Modifies metadata fields on pipeline nodes. Supports a `where` named
--# argument to scope changes to a subset of nodes. Without `where`, all
--# nodes are affected.
--#
--# Mutable metadata fields: `noop` (Bool), `serializer` (String),
--# `deserializer` (String), `runtime` (String).
--#
--# The `where` clause uses NSE (`$field`) just like `filter_node`.
--#
--# @name mutate_node
--# @param p :: Pipeline The pipeline to modify.
--# @param ... :: KeywordArgs Metadata assignments as `$field = value` pairs.
--# @param where :: Function (Optional) Predicate scoping which nodes are updated.
--# @return :: Pipeline A new pipeline with updated node metadata.
--# @example
--#   p |> mutate_node($noop = true)
--#   p |> mutate_node($serializer = "pmml", where = $runtime == "R")
--# @family pipeline
--# @seealso filter_node, rename_node
--# @export
*)
let register ~eval_call env =
  Env.add "mutate_node"
    (make_builtin_named ~name:"mutate_node" ~variadic:true 1 (fun named_args env ->
      match named_args with
      | [] -> Error.arity_error_named "mutate_node" ~expected:1 ~received:0
      | (_, VPipeline p) :: rest ->
          (* Separate the optional `where` predicate from field assignments.
             Named args arrive as (string option * value) pairs. *)
          let where_pred_opt = List.assoc_opt (Some "where") rest in
          let mutations = List.filter (fun (name, _) -> name <> Some "where") rest in
          let depths = Pipeline_to_frame.compute_depths p.p_deps in
          (* Determine whether a node matches the optional where predicate *)
          let matches name =
            match where_pred_opt with
            | None -> true
            | Some pred ->
                let row_dict = VDict (Pipeline_to_frame.node_metadata_dict name p depths) in
                (match eval_call env pred [(None, Value row_dict)] with
                 | VBool b -> b
                 | _ -> false)
          in
          (* Apply all mutations to the appropriate pipeline fields *)
          let new_runtimes =
            match List.assoc_opt (Some "runtime") mutations with
            | None -> p.p_runtimes
            | Some (VString v) ->
                List.map (fun (n, old) -> if matches n then (n, v) else (n, old)) p.p_runtimes
            | Some _ ->
                p.p_runtimes  (* ignore bad value; keep existing *)
          in
          let new_noops =
            match List.assoc_opt (Some "noop") mutations with
            | None -> p.p_noops
            | Some (VBool v) ->
                List.map (fun (n, old) -> if matches n then (n, v) else (n, old)) p.p_noops
            | Some _ -> p.p_noops
          in
          let new_serializers =
            match List.assoc_opt (Some "serializer") mutations with
            | None -> p.p_serializers
            | Some (VString v) ->
                List.map (fun (n, _old) ->
                  if matches n then (n, Ast.Value (Ast.VString v)) else (n, _old)
                ) p.p_serializers
            | Some _ -> p.p_serializers
          in
          let new_deserializers =
            match List.assoc_opt (Some "deserializer") mutations with
            | None -> p.p_deserializers
            | Some (VString v) ->
                List.map (fun (n, _old) ->
                  if matches n then (n, Ast.Value (Ast.VString v)) else (n, _old)
                ) p.p_deserializers
            | Some _ -> p.p_deserializers
          in
          VPipeline {
            p with
            p_runtimes     = new_runtimes;
            p_noops        = new_noops;
            p_serializers  = new_serializers;
            p_deserializers = new_deserializers;
          }
      | (_, _) :: _ -> Error.type_error "Function `mutate_node` expects a Pipeline as first argument."
    ))
    env
