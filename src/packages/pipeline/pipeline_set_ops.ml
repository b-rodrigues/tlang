open Ast

(* ── Shared helpers ─────────────────────────────────────────────── *)

(** Filter all assoc-lists in a pipeline to keep only the given names. *)
let filter_pipeline (names : string list) (p : pipeline_result) : pipeline_result =
  let keep n = List.mem n names in
  {
    p_nodes        = List.filter (fun (n, _) -> keep n) p.p_nodes;
    p_exprs        = List.filter (fun (n, _) -> keep n) p.p_exprs;
    p_deps         = List.filter (fun (n, _) -> keep n) p.p_deps;
    p_imports      = p.p_imports;
    p_runtimes     = List.filter (fun (n, _) -> keep n) p.p_runtimes;
    p_serializers  = List.filter (fun (n, _) -> keep n) p.p_serializers;
    p_deserializers = List.filter (fun (n, _) -> keep n) p.p_deserializers;
    p_env_vars     = List.filter (fun (n, _) -> keep n) p.p_env_vars;
    p_functions    = List.filter (fun (n, _) -> keep n) p.p_functions;
    p_includes     = List.filter (fun (n, _) -> keep n) p.p_includes;
    p_noops        = List.filter (fun (n, _) -> keep n) p.p_noops;
    p_scripts      = List.filter (fun (n, _) -> keep n) p.p_scripts;
  }

(** Merge: lst1 entries first, then lst2 entries whose keys are new to lst1. *)
let merge_new lst1 lst2 =
  let keys1 = List.map fst lst1 in
  lst1 @ List.filter (fun (k, _) -> not (List.mem k keys1)) lst2

(** Patch merge: lst1 entries, but replace from lst2 where key matches;
    does not add new keys from lst2. *)
let merge_patch lst1 lst2 =
  List.map (fun (k, v) ->
    match List.assoc_opt k lst2 with
    | Some v2 -> (k, v2)
    | None    -> (k, v)
  ) lst1

let register env =

(*
--# Union of Two Pipelines
--#
--# Merges two pipelines into one. All nodes from both pipelines are
--# included. Errors immediately if any node name exists in both pipelines.
--# Use `rename_node` to resolve collisions before calling `union`.
--#
--# @name union
--# @param p1 :: Pipeline The first pipeline.
--# @param p2 :: Pipeline The second pipeline.
--# @return :: Pipeline A new pipeline containing all nodes from both.
--# @example
--#   p_etl |> union(p_model)
--# @family pipeline
--# @seealso difference, intersect, patch, rename_node
--# @export
*)
  let env = Env.add "union"
    (make_builtin ~name:"union" 2 (fun args _env ->
      match args with
      | [VPipeline p1; VPipeline p2] ->
          let names1 = List.map fst p1.p_exprs in
          let names2 = List.map fst p2.p_exprs in
          let collisions = List.filter (fun n -> List.mem n names2) names1 in
          if collisions <> [] then
            Error.make_error ValueError
              (Printf.sprintf
                 "Function `union`: name collision(s) detected: %s. Use `rename_node` to resolve."
                 (String.concat ", " collisions))
          else
            VPipeline {
              p_nodes        = merge_new p1.p_nodes p2.p_nodes;
              p_exprs        = merge_new p1.p_exprs p2.p_exprs;
              p_deps         = merge_new p1.p_deps p2.p_deps;
              p_imports      = p1.p_imports @ p2.p_imports;
              p_runtimes     = merge_new p1.p_runtimes p2.p_runtimes;
              p_serializers  = merge_new p1.p_serializers p2.p_serializers;
              p_deserializers = merge_new p1.p_deserializers p2.p_deserializers;
              p_env_vars     = merge_new p1.p_env_vars p2.p_env_vars;
              p_functions    = merge_new p1.p_functions p2.p_functions;
              p_includes     = merge_new p1.p_includes p2.p_includes;
              p_noops        = merge_new p1.p_noops p2.p_noops;
              p_scripts      = merge_new p1.p_scripts p2.p_scripts;
            }
      | [_; _] -> Error.type_error "Function `union` expects two Pipeline arguments."
      | _ -> Error.arity_error_named "union" ~expected:2 ~received:(List.length args)
    ))
    env
  in

(*
--# Difference of Two Pipelines
--#
--# Removes from `p1` all nodes whose names appear in `p2`. Nodes in `p2`
--# that are not present in `p1` are silently ignored. No DAG validity check
--# is performed after the removal.
--#
--# @name difference
--# @param p1 :: Pipeline The pipeline to remove nodes from.
--# @param p2 :: Pipeline The pipeline whose node names determine what to remove.
--# @return :: Pipeline A new pipeline with the specified nodes removed.
--# @example
--#   p_full |> difference(p_to_remove)
--# @family pipeline
--# @seealso union, intersect, patch
--# @export
*)
  let env = Env.add "difference"
    (make_builtin ~name:"difference" 2 (fun args _env ->
      match args with
      | [VPipeline p1; VPipeline p2] ->
          let names2 = List.map fst p2.p_exprs in
          let keep = List.filter_map (fun (n, _) ->
            if List.mem n names2 then None else Some n
          ) p1.p_exprs in
          VPipeline (filter_pipeline keep p1)
      | [_; _] -> Error.type_error "Function `difference` expects two Pipeline arguments."
      | _ -> Error.arity_error_named "difference" ~expected:2 ~received:(List.length args)
    ))
    env
  in

(*
--# Intersection of Two Pipelines
--#
--# Returns a new pipeline retaining only the nodes present by name in both
--# pipelines. Definitions are taken from `p1`.
--#
--# @name intersect
--# @param p1 :: Pipeline The pipeline whose definitions are kept.
--# @param p2 :: Pipeline The pipeline used to determine which nodes to retain.
--# @return :: Pipeline A new pipeline with only the shared nodes (p1 definitions).
--# @example
--#   p_full |> intersect(p_subset)
--# @family pipeline
--# @seealso union, difference, patch
--# @export
*)
  let env = Env.add "intersect"
    (make_builtin ~name:"intersect" 2 (fun args _env ->
      match args with
      | [VPipeline p1; VPipeline p2] ->
          let names2 = List.map fst p2.p_exprs in
          let keep = List.filter_map (fun (n, _) ->
            if List.mem n names2 then Some n else None
          ) p1.p_exprs in
          VPipeline (filter_pipeline keep p1)
      | [_; _] -> Error.type_error "Function `intersect` expects two Pipeline arguments."
      | _ -> Error.arity_error_named "intersect" ~expected:2 ~received:(List.length args)
    ))
    env
  in

(*
--# Patch a Pipeline
--#
--# Updates nodes in `p1` with definitions from `p2`, but only for nodes that
--# already exist in `p1`. New nodes from `p2` are not added. Useful for
--# overriding node configurations without accidentally importing stray nodes.
--#
--# @name patch
--# @param p1 :: Pipeline The base pipeline.
--# @param p2 :: Pipeline The pipeline providing updated node definitions.
--# @return :: Pipeline A new pipeline with matching nodes updated from `p2`.
--# @example
--#   p_prod |> patch(p_staging_overrides)
--# @family pipeline
--# @seealso union, difference, intersect
--# @export
*)
  let env = Env.add "patch"
    (make_builtin ~name:"patch" 2 (fun args _env ->
      match args with
      | [VPipeline p1; VPipeline p2] ->
          VPipeline {
            p_nodes        = merge_patch p1.p_nodes p2.p_nodes;
            p_exprs        = merge_patch p1.p_exprs p2.p_exprs;
            p_deps         = merge_patch p1.p_deps p2.p_deps;
            p_imports      = p1.p_imports;
            p_runtimes     = merge_patch p1.p_runtimes p2.p_runtimes;
            p_serializers  = merge_patch p1.p_serializers p2.p_serializers;
            p_deserializers = merge_patch p1.p_deserializers p2.p_deserializers;
            p_env_vars     = merge_patch p1.p_env_vars p2.p_env_vars;
            p_functions    = merge_patch p1.p_functions p2.p_functions;
            p_includes     = merge_patch p1.p_includes p2.p_includes;
            p_noops        = merge_patch p1.p_noops p2.p_noops;
            p_scripts      = merge_patch p1.p_scripts p2.p_scripts;
          }
      | [_; _] -> Error.type_error "Function `patch` expects two Pipeline arguments."
      | _ -> Error.arity_error_named "patch" ~expected:2 ~received:(List.length args)
    ))
    env
  in

  env
