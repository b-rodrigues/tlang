(* src/packages/pipeline/pipeline_set_ops.ml *)
(* Phase 3 — Set operations for Pipelines *)
(* union, intersect, difference, and patch *)

open Ast

let filter_node_set keep_set p =
  VPipeline {
    p_nodes        = List.filter (fun (n, _) -> keep_set n) p.p_nodes;
    p_exprs        = List.filter (fun (n, _) -> keep_set n) p.p_exprs;
    p_deps         = List.map (fun (n, ds) -> (n, List.filter keep_set ds)) (List.filter (fun (n, _) -> keep_set n) p.p_deps);
    p_imports      = p.p_imports;
    p_runtimes     = List.filter (fun (n, _) -> keep_set n) p.p_runtimes;
    p_serializers  = List.filter (fun (n, _) -> keep_set n) p.p_serializers;
    p_deserializers = List.filter (fun (n, _) -> keep_set n) p.p_deserializers;
    p_env_vars     = List.filter (fun (n, _) -> keep_set n) p.p_env_vars;
    p_args         = List.filter (fun (n, _) -> keep_set n) p.p_args;
    p_shells       = List.filter (fun (n, _) -> keep_set n) p.p_shells;
    p_shell_args   = List.filter (fun (n, _) -> keep_set n) p.p_shell_args;
    p_functions    = List.filter (fun (n, _) -> keep_set n) p.p_functions;
    p_includes     = List.filter (fun (n, _) -> keep_set n) p.p_includes;
    p_noops        = List.filter (fun (n, _) -> keep_set n) p.p_noops;
    p_scripts      = List.filter (fun (n, _) -> keep_set n) p.p_scripts;
    p_explicit_deps = List.filter (fun (n, _) -> keep_set n) p.p_explicit_deps;
    p_node_diagnostics = List.filter (fun (n, _) -> keep_set n) p.p_node_diagnostics;
  }

let union p1 p2 =
  let p1_nodes = List.map fst p1.p_nodes in
  let p2_nodes = List.map fst p2.p_nodes in
  let collisions = List.filter (fun n -> List.mem n p1_nodes) p2_nodes in
  if collisions <> [] then
    let msg = Printf.sprintf "Function `union`: name collision(s) detected: %s. Use `rename_node` to resolve." (String.concat ", " collisions) in
    Error (Error.make_error ValueError msg)
  else
    Ok (VPipeline {
      p_nodes        = p1.p_nodes @ p2.p_nodes;
      p_exprs        = p1.p_exprs @ p2.p_exprs;
      p_deps         = p1.p_deps @ p2.p_deps;
      p_imports      = p1.p_imports @ p2.p_imports;
      p_runtimes     = p1.p_runtimes @ p2.p_runtimes;
      p_serializers  = p1.p_serializers @ p2.p_serializers;
      p_deserializers = p1.p_deserializers @ p2.p_deserializers;
      p_env_vars     = p1.p_env_vars @ p2.p_env_vars;
      p_args         = p1.p_args @ p2.p_args;
      p_shells       = p1.p_shells @ p2.p_shells;
      p_shell_args   = p1.p_shell_args @ p2.p_shell_args;
      p_functions    = p1.p_functions @ p2.p_functions;
      p_includes     = p1.p_includes @ p2.p_includes;
      p_noops        = p1.p_noops @ p2.p_noops;
      p_scripts      = p1.p_scripts @ p2.p_scripts;
      p_explicit_deps = p1.p_explicit_deps @ p2.p_explicit_deps;
      p_node_diagnostics = p1.p_node_diagnostics @ p2.p_node_diagnostics;
    })

let intersect p1 p2 =
  let p2_names = List.map fst p2.p_nodes in
  let keep_set n = List.mem n p2_names in
  filter_node_set keep_set p1

let difference p1 p2 =
  let p2_names = List.map fst p2.p_nodes in
  let keep_set n = not (List.mem n p2_names) in
  filter_node_set keep_set p1

let patch p1 p2 =
  let p1_names = List.map fst p1.p_nodes in
  let p2_names = List.map fst p2.p_nodes in
  let keep_from_p1 n = not (List.mem n p2_names) in
  let keep_from_p2 n = List.mem n p1_names in
  let p1_filtered = (match filter_node_set keep_from_p1 p1 with VPipeline p -> p | _ -> failwith "unreachable") in
  let p2_filtered = (match filter_node_set keep_from_p2 p2 with VPipeline p -> p | _ -> failwith "unreachable") in
  VPipeline {
    p_nodes        = p1_filtered.p_nodes @ p2_filtered.p_nodes;
    p_exprs        = p1_filtered.p_exprs @ p2_filtered.p_exprs;
    p_deps         = p1_filtered.p_deps @ p2_filtered.p_deps;
    p_imports      = p1_filtered.p_imports @ p2_filtered.p_imports;
    p_runtimes     = p1_filtered.p_runtimes @ p2_filtered.p_runtimes;
    p_serializers  = p1_filtered.p_serializers @ p2_filtered.p_serializers;
    p_deserializers = p1_filtered.p_deserializers @ p2_filtered.p_deserializers;
    p_env_vars     = p1_filtered.p_env_vars @ p2_filtered.p_env_vars;
    p_args         = p1_filtered.p_args @ p2_filtered.p_args;
    p_shells       = p1_filtered.p_shells @ p2_filtered.p_shells;
    p_shell_args   = p1_filtered.p_shell_args @ p2_filtered.p_shell_args;
    p_functions    = p1_filtered.p_functions @ p2_filtered.p_functions;
    p_includes     = p1_filtered.p_includes @ p2_filtered.p_includes;
    p_noops        = p1_filtered.p_noops @ p2_filtered.p_noops;
    p_scripts      = p1_filtered.p_scripts @ p2_filtered.p_scripts;
    p_explicit_deps = p1_filtered.p_explicit_deps @ p2_filtered.p_explicit_deps;
    p_node_diagnostics = p1_filtered.p_node_diagnostics @ p2_filtered.p_node_diagnostics;
  }

(*
--# Combine two pipelines
--#
--# Returns a pipeline containing nodes from both inputs and errors on name collisions.
--#
--# @name union
--# @family pipeline
--# @export
*)
(*
--# Subtract one pipeline from another
--#
--# Returns the nodes that appear in the first pipeline but not the second.
--#
--# @name difference
--# @family pipeline
--# @export
*)
(*
--# Keep shared pipeline nodes
--#
--# Returns the nodes from the first pipeline whose names also appear in the second.
--#
--# @name intersect
--# @family pipeline
--# @export
*)
(*
--# Overlay one pipeline onto another
--#
--# Replaces matching nodes in one pipeline with definitions from another pipeline.
--#
--# @name patch
--# @family pipeline
--# @export
*)
let register ~rerun_pipeline env =
  let env = Env.add "union" (make_builtin ~name:"union" 2 (fun args env ->
    match args with
    | [VPipeline p1; VPipeline p2] -> 
        (match union p1 p2 with
        | Ok (VPipeline p) -> rerun_pipeline ?strict:None env p
        | Ok _ -> failwith "unreachable"
        | Error e -> e)
    | _ -> Error.type_error "Function `union` expects two Pipeline arguments."
  )) env in
  let env = Env.add "difference" (make_builtin ~name:"difference" 2 (fun args _ ->
    match args with
    | [VPipeline p1; VPipeline p2] -> difference p1 p2
    | _ -> Error.type_error "Function `difference` expects two Pipeline arguments."
  )) env in
  let env = Env.add "intersect" (make_builtin ~name:"intersect" 2 (fun args _ ->
    match args with
    | [VPipeline p1; VPipeline p2] -> intersect p1 p2
    | _ -> Error.type_error "Function `intersect` expects two Pipeline arguments."
  )) env in
  let env = Env.add "patch" (make_builtin ~name:"patch" 2 (fun args env ->
    match args with
    | [VPipeline p1; VPipeline p2] -> 
        (match patch p1 p2 with 
        | VPipeline p -> rerun_pipeline ?strict:None env p
        | _ -> failwith "unreachable")
    | _ -> Error.type_error "Function `patch` expects two Pipeline arguments."
  )) env in
  env
