open Ast

let extract_string_list = function
  | VList items ->
      let rec go acc = function
        | [] -> Some (List.rev acc)
        | (_, VString s) :: rest -> go (s :: acc) rest
        | (_, _) :: _ -> None
      in
      go [] items
  | VVector arr ->
      let rec go i acc =
        if i >= Array.length arr then Some (List.rev acc)
        else match arr.(i) with
          | VString s -> go (i + 1) (s :: acc)
          | _ -> None
      in
      go 0 []
  | VString s -> Some [s]
  | _ -> None

let get_pipeline_node_names env p =
  let base_names = List.map fst p.p_nodes in
  let branch_names = Pipeline_nodes.compute_branch_names env p in
  base_names @ branch_names

let rec depends_on p target current visited =
  if current = target then true
  else if List.mem current visited then false
  else
    match List.assoc_opt current p.p_deps with
    | None -> false
    | Some deps ->
        List.exists (fun d -> depends_on p target d (current :: visited)) deps

let match_serializer_deserializer expr expected =
  let canonical_str = Nix_unparse.expr_to_string expr in
  match expected with
  | VString s | VSymbol s -> s = canonical_str
  | _ -> false

(*
--# Pipeline assertion
--#
--# Passes if `x` is a Pipeline value.
--#
--# @name expect_pipeline
--# @param x :: Any The value to check.
--# @return :: Expect `Expect_pass` if a Pipeline; `Expect_stop` otherwise.
--# @example
--#   assert(expect_pipeline(p))
--# @family testcraft
--# @export
*)

(*
--# Pipeline nodes assertion
--#
--# Passes if a pipeline contains exactly the expected node names (including dynamic branch nodes).
--#
--# @name expect_nodes
--# @param p :: Pipeline The pipeline to check.
--# @param expected_names :: List | Vector Expected node names.
--# @return :: Expect `Expect_pass` if match; `Expect_stop` otherwise.
--# @example
--#   assert(expect_nodes(p, ["load", "clean", "model"]))
--# @family testcraft
--# @export
*)

(*
--# Node dependency assertion
--#
--# Passes if `to_node` directly or transitively depends on `from_node` in the pipeline DAG.
--#
--# @name expect_dependency
--# @param p :: Pipeline The pipeline.
--# @param from_node :: String The upstream node name.
--# @param to_node :: String The downstream node name.
--# @return :: Expect `Expect_pass` if dependency exists; `Expect_stop` otherwise.
--# @example
--#   assert(expect_dependency(p, "load", "model"))
--# @family testcraft
--# @export
*)

(*
--# Node dynamic branching pattern assertion
--#
--# Passes if `node_name` is defined with a dynamic branching pattern (e.g. mapping or crossing).
--#
--# @name expect_has_pattern
--# @param p :: Pipeline The pipeline.
--# @param node_name :: String The node name to inspect.
--# @return :: Expect `Expect_pass` if pattern exists; `Expect_stop` otherwise.
--# @example
--#   assert(expect_has_pattern(p, "train_model"))
--# @family testcraft
--# @export
*)

(*
--# Node runtime assertion
--#
--# Passes if `node_name` runtime matches the expected runtime.
--#
--# @name expect_runtime
--# @param p :: Pipeline The pipeline.
--# @param node_name :: String The node name.
--# @param expected :: String The expected runtime name (e.g. "R", "Python").
--# @return :: Expect `Expect_pass` if matches; `Expect_stop` otherwise.
--# @example
--#   assert(expect_runtime(p, "model", "Python"))
--# @family testcraft
--# @export
*)

(*
--# Node serializer assertion
--#
--# Passes if `node_name` serializer matches the expected serializer.
--#
--# @name expect_serializer
--# @param p :: Pipeline The pipeline.
--# @param node_name :: String The node name.
--# @param expected :: String | Symbol The expected serializer.
--# @return :: Expect `Expect_pass` if matches; `Expect_stop` otherwise.
--# @example
--#   assert(expect_serializer(p, "data", ^csv))
--# @family testcraft
--# @export
*)

(*
--# Node deserializer assertion
--#
--# Passes if `node_name` deserializer matches the expected deserializer.
--#
--# @name expect_deserializer
--# @param p :: Pipeline The pipeline.
--# @param node_name :: String The node name.
--# @param expected :: String | Symbol The expected deserializer.
--# @return :: Expect `Expect_pass` if matches; `Expect_stop` otherwise.
--# @example
--#   assert(expect_deserializer(p, "model", ^onnx))
--# @family testcraft
--# @export
*)

(*
--# Node noop assertion
--#
--# Passes if `node_name` noop flag matches the expected value.
--#
--# @name expect_noop
--# @param p :: Pipeline The pipeline.
--# @param node_name :: String The node name.
--# @param expected :: Bool Expected noop value.
--# @return :: Expect `Expect_pass` if matches; `Expect_stop` otherwise.
--# @example
--#   assert(expect_noop(p, "heavy_job", true))
--# @family testcraft
--# @export
*)

(*
--# Computed node assertion
--#
--# Passes if the node is computed and has a finished value.
--#
--# @name expect_computed
--# @param node :: ComputedNode | NodeResult The node to check.
--# @return :: Expect `Expect_pass` if computed; `Expect_stop` otherwise.
--# @example
--#   assert(expect_computed(res.heavy_job))
--# @family testcraft
--# @export
*)

let register env =
  (* expect_pipeline *)
  let env =
    Env.add "expect_pipeline"
      (make_builtin ~name:"expect_pipeline" 1 (fun args _env ->
         match args with
         | [VPipeline _] -> VExpect Expect_pass
         | [VNA _] -> VExpect (Expect_hold "`x` is NA")
         | [VError err] -> VExpect (Expect_stop (Printf.sprintf "`x` is an error: %s" err.message))
         | [other] -> VExpect (Expect_stop (Printf.sprintf "Expected a Pipeline, got %s." (Utils.type_name other)))
         | args -> Error.arity_error_named "expect_pipeline" 1 (List.length args)))
      env
  in
  (* expect_nodes *)
  let env =
    Env.add "expect_nodes"
      (make_builtin ~name:"expect_nodes" 2 (fun args env ->
         match args with
         | [VPipeline p; expected_val] ->
             (match extract_string_list expected_val with
              | Some expected_names ->
                  let actual_names = get_pipeline_node_names env p in
                  if actual_names = expected_names then VExpect Expect_pass
                  else
                    let actual_s = "[" ^ String.concat ", " (List.map (fun s -> "\"" ^ s ^ "\"") actual_names) ^ "]" in
                    let expected_s = "[" ^ String.concat ", " (List.map (fun s -> "\"" ^ s ^ "\"") expected_names) ^ "]" in
                    VExpect (Expect_stop (Printf.sprintf "Expected nodes %s, got %s." expected_s actual_s))
              | None -> Error.type_error "Expected a list or vector of strings for the expected names argument.")
         | [VNA _; _] -> VExpect (Expect_hold "`pipeline` is NA")
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`pipeline` is an error: %s" err.message))
         | [other; _] -> Error.type_error (Printf.sprintf "Function `expect_nodes` expects a Pipeline, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_nodes" 2 (List.length args)))
      env
  in
  (* expect_dependency *)
  let env =
    Env.add "expect_dependency"
      (make_builtin ~name:"expect_dependency" 3 (fun args env ->
         match args with
         | [VPipeline p; VString from_node; VString to_node]
         | [VPipeline p; VSymbol from_node; VSymbol to_node] ->
             let all_nodes = get_pipeline_node_names env p in
             if not (List.mem from_node all_nodes) then
               VExpect (Expect_stop (Printf.sprintf "Node '%s' not found in pipeline." from_node))
             else if not (List.mem to_node all_nodes) then
               VExpect (Expect_stop (Printf.sprintf "Node '%s' not found in pipeline." to_node))
             else if depends_on p from_node to_node [] then
               VExpect Expect_pass
             else
               VExpect (Expect_stop (Printf.sprintf "Node '%s' does not depend on '%s'." to_node from_node))
         | [VPipeline _; other; _] when (match other with VString _ | VSymbol _ -> false | _ -> true) ->
             Error.type_error (Printf.sprintf "Function `expect_dependency` expects String or Symbol for node names, got %s." (Utils.type_name other))
         | [VPipeline _; _; other] when (match other with VString _ | VSymbol _ -> false | _ -> true) ->
             Error.type_error (Printf.sprintf "Function `expect_dependency` expects String or Symbol for node names, got %s." (Utils.type_name other))
         | [VNA _; _; _] -> VExpect (Expect_hold "`pipeline` is NA")
         | [VError err; _; _] -> VExpect (Expect_stop (Printf.sprintf "`pipeline` is an error: %s" err.message))
         | [other; _; _] -> Error.type_error (Printf.sprintf "Function `expect_dependency` expects a Pipeline, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_dependency" 3 (List.length args)))
      env
  in
  (* expect_has_pattern *)
  let env =
    Env.add "expect_has_pattern"
      (make_builtin ~name:"expect_has_pattern" 2 (fun args _env ->
         match args with
         | [VPipeline p; VString node_name] | [VPipeline p; VSymbol node_name] ->
             if List.mem_assoc node_name p.p_patterns then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "Node '%s' does not have a dynamic branching pattern." node_name))
         | [VPipeline _; other] when (match other with VString _ | VSymbol _ -> false | _ -> true) ->
             Error.type_error (Printf.sprintf "Function `expect_has_pattern` expects String or Symbol for node name, got %s." (Utils.type_name other))
         | [VNA _; _] -> VExpect (Expect_hold "`pipeline` is NA")
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`pipeline` is an error: %s" err.message))
         | [other; _] -> Error.type_error (Printf.sprintf "Function `expect_has_pattern` expects a Pipeline, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_has_pattern" 2 (List.length args)))
      env
  in
  (* expect_runtime *)
  let env =
    Env.add "expect_runtime"
      (make_builtin ~name:"expect_runtime" 3 (fun args _env ->
         match args with
         | [VPipeline p; (VString node_name | VSymbol node_name); VString expected] ->
             if not (List.mem_assoc node_name p.p_nodes) then
               VExpect (Expect_stop (Printf.sprintf "Node '%s' not found in pipeline." node_name))
             else
               let actual = match List.assoc_opt node_name p.p_runtimes with Some r -> r | None -> "T" in
               if actual = expected then VExpect Expect_pass
               else VExpect (Expect_stop (Printf.sprintf "Expected node '%s' runtime to be '%s', got '%s'." node_name expected actual))
         | [VPipeline _; (VString _ | VSymbol _); other] ->
             Error.type_error (Printf.sprintf "Function `expect_runtime` expects String for expected runtime, got %s." (Utils.type_name other))
         | [VPipeline _; other; _] ->
             Error.type_error (Printf.sprintf "Function `expect_runtime` expects String or Symbol for node name, got %s." (Utils.type_name other))
         | [VNA _; _; _] -> VExpect (Expect_hold "`pipeline` is NA")
         | [VError err; _; _] -> VExpect (Expect_stop (Printf.sprintf "`pipeline` is an error: %s" err.message))
         | [other; _; _] -> Error.type_error (Printf.sprintf "Function `expect_runtime` expects a Pipeline, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_runtime" 3 (List.length args)))
      env
  in
  (* expect_serializer *)
  let env =
    Env.add "expect_serializer"
      (make_builtin ~name:"expect_serializer" 3 (fun args _env ->
         match args with
         | [VPipeline p; (VString node_name | VSymbol node_name); expected] ->
             if not (List.mem_assoc node_name p.p_nodes) then
               VExpect (Expect_stop (Printf.sprintf "Node '%s' not found in pipeline." node_name))
             else
               let expr = match List.assoc_opt node_name p.p_serializers with Some e -> e | None -> mk_expr (Var "default") in
               if match_serializer_deserializer expr expected then VExpect Expect_pass
               else
                 let actual = Nix_unparse.expr_to_string expr in
                 let expected_str = match expected with VString s | VSymbol s -> s | other -> Utils.value_to_string other in
                 VExpect (Expect_stop (Printf.sprintf "Expected node '%s' serializer to be '%s', got '%s'." node_name expected_str actual))
         | [VNA _; _; _] -> VExpect (Expect_hold "`pipeline` is NA")
         | [VError err; _; _] -> VExpect (Expect_stop (Printf.sprintf "`pipeline` is an error: %s" err.message))
         | [other; _; _] -> Error.type_error (Printf.sprintf "Function `expect_serializer` expects a Pipeline, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_serializer" 3 (List.length args)))
      env
  in
  (* expect_deserializer *)
  let env =
    Env.add "expect_deserializer"
      (make_builtin ~name:"expect_deserializer" 3 (fun args _env ->
         match args with
         | [VPipeline p; (VString node_name | VSymbol node_name); expected] ->
             if not (List.mem_assoc node_name p.p_nodes) then
               VExpect (Expect_stop (Printf.sprintf "Node '%s' not found in pipeline." node_name))
             else
               let expr = match List.assoc_opt node_name p.p_deserializers with Some e -> e | None -> mk_expr (Var "default") in
               if match_serializer_deserializer expr expected then VExpect Expect_pass
               else
                 let actual = Nix_unparse.expr_to_string expr in
                 let expected_str = match expected with VString s | VSymbol s -> s | other -> Utils.value_to_string other in
                 VExpect (Expect_stop (Printf.sprintf "Expected node '%s' deserializer to be '%s', got '%s'." node_name expected_str actual))
         | [VNA _; _; _] -> VExpect (Expect_hold "`pipeline` is NA")
         | [VError err; _; _] -> VExpect (Expect_stop (Printf.sprintf "`pipeline` is an error: %s" err.message))
         | [other; _; _] -> Error.type_error (Printf.sprintf "Function `expect_deserializer` expects a Pipeline, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_deserializer" 3 (List.length args)))
      env
  in
  (* expect_noop *)
  let env =
    Env.add "expect_noop"
      (make_builtin ~name:"expect_noop" 3 (fun args _env ->
         match args with
         | [VPipeline p; (VString node_name | VSymbol node_name); VBool expected] ->
             if not (List.mem_assoc node_name p.p_nodes) then
               VExpect (Expect_stop (Printf.sprintf "Node '%s' not found in pipeline." node_name))
             else
               let actual = match List.assoc_opt node_name p.p_noops with Some b -> b | None -> false in
               if actual = expected then VExpect Expect_pass
               else VExpect (Expect_stop (Printf.sprintf "Expected node '%s' noop flag to be %b, got %b." node_name expected actual))
         | [VPipeline _; (VString _ | VSymbol _); other] ->
             Error.type_error (Printf.sprintf "Function `expect_noop` expects Bool for expected noop value, got %s." (Utils.type_name other))
         | [VPipeline _; other; _] ->
             Error.type_error (Printf.sprintf "Function `expect_noop` expects String or Symbol for node name, got %s." (Utils.type_name other))
         | [VNA _; _; _] -> VExpect (Expect_hold "`pipeline` is NA")
         | [VError err; _; _] -> VExpect (Expect_stop (Printf.sprintf "`pipeline` is an error: %s" err.message))
         | [other; _; _] -> Error.type_error (Printf.sprintf "Function `expect_noop` expects a Pipeline, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_noop" 3 (List.length args)))
      env
  in
  (* expect_computed *)
  let env =
    Env.add "expect_computed"
      (make_builtin ~name:"expect_computed" ~unwrap:false 1 (fun args _env ->
         match args with
         | [VNodeResult _] -> VExpect Expect_pass
         | [VComputedNode cn] ->
             (match get_in_memory_node_value_for_cn cn with
              | Some (VNodeResult _) -> VExpect Expect_pass
              | _ -> VExpect (Expect_stop "Expected node to be computed, but it has not been evaluated."))
         | [VNA _] -> VExpect (Expect_stop "Expected node to be computed, but got NA.")
         | [VError err] -> VExpect (Expect_stop (Printf.sprintf "`node` is an error: %s" err.message))
         | [other] -> Error.type_error (Printf.sprintf "Function `expect_computed` expects a ComputedNode or NodeResult, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_computed" 1 (List.length args)))
      env
  in
  env
