open Ast

(** Merge: lst1 entries first, then lst2 entries whose keys are new to lst1. *)
let merge_new lst1 lst2 =
  let keys1 = List.map fst lst1 in
  lst1 @ List.filter (fun (k, _) -> not (List.mem k keys1)) lst2

let register env =

(*
--# Chain Two Pipelines
--#
--# Connects two pipelines by merging them. The second pipeline can reference
--# node names from the first pipeline as dependencies — these are automatically
--# satisfied. Errors if there are name collisions (other than the intentional
--# inter-pipeline wiring) or if no shared names exist between the two pipelines.
--#
--# @name chain
--# @param p1 :: Pipeline The upstream pipeline (provides outputs).
--# @param p2 :: Pipeline The downstream pipeline (consumes inputs).
--# @return :: Pipeline A merged pipeline with p2's nodes wired to p1's outputs.
--# @example
--#   p_etl |> chain(p_model)
--# @family pipeline
--# @seealso parallel, union
--# @export
*)
  let env = Env.add "chain"
    (make_builtin ~name:"chain" 2 (fun args _env ->
      match args with
      | [VPipeline p1; VPipeline p2] ->
          let names1 = List.map fst p1.p_exprs in
          let names2 = List.map fst p2.p_exprs in
          (* Check for name collisions (same node in both) *)
          let collisions = List.filter (fun n -> List.mem n names2) names1 in
          if collisions <> [] then
            Error.make_error ValueError
              (Printf.sprintf
                 "Function `chain`: name collision(s) detected: %s. Use `rename_node` to resolve."
                 (String.concat ", " collisions))
          else begin
            (* Find shared references: node names from p1 that appear as deps in p2 *)
            let p2_all_deps = List.concat_map snd p2.p_deps in
            let shared = List.filter (fun n -> List.mem n p2_all_deps) names1 in
            if shared = [] then
              Error.make_error ValueError
                "Function `chain`: no shared dependency names found between the two pipelines."
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
          end
      | [_; _] -> Error.type_error "Function `chain` expects two Pipeline arguments."
      | _ -> Error.arity_error_named "chain" ~expected:2 ~received:(List.length args)
    ))
    env
  in

(*
--# Combine Pipelines in Parallel
--#
--# Combines two pipelines that are intended to run independently. Errors
--# immediately if any node name exists in both pipelines. Outputs are not
--# automatically wired.
--#
--# @name parallel
--# @param p1 :: Pipeline The first pipeline.
--# @param p2 :: Pipeline The second pipeline.
--# @return :: Pipeline A merged pipeline with all nodes from both.
--# @example
--#   parallel(p_r_model, p_py_model)
--# @family pipeline
--# @seealso chain, union
--# @export
*)
  let env = Env.add "parallel"
    (make_builtin ~name:"parallel" 2 (fun args _env ->
      match args with
      | [VPipeline p1; VPipeline p2] ->
          let names1 = List.map fst p1.p_exprs in
          let names2 = List.map fst p2.p_exprs in
          let collisions = List.filter (fun n -> List.mem n names2) names1 in
          if collisions <> [] then
            Error.make_error ValueError
              (Printf.sprintf
                 "Function `parallel`: name collision(s) detected: %s. Use `rename_node` to resolve."
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
      | [_; _] -> Error.type_error "Function `parallel` expects two Pipeline arguments."
      | _ -> Error.arity_error_named "parallel" ~expected:2 ~received:(List.length args)
    ))
    env
  in

  env
