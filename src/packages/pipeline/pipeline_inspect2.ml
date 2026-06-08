open Ast

(** Detect cycles in a directed graph using DFS with three-color marking.
    Returns a list of node names involved in cycles.
    White=0 (unvisited), Gray=1 (in-progress), Black=2 (done). *)
let detect_cycles (p_deps : (string * string list) list) : string list =
  let all_names = List.map fst p_deps in
  let color = Hashtbl.create 16 in
  List.iter (fun n -> Hashtbl.add color n 0) all_names;
  let cycle_nodes = ref [] in
  let rec visit name =
    let c = match Hashtbl.find_opt color name with Some x -> x | None -> 0 in
    if c = 1 then begin
      (* Back-edge found: cycle *)
      if not (List.mem name !cycle_nodes) then
        cycle_nodes := name :: !cycle_nodes
    end else if c = 0 then begin
      Hashtbl.replace color name 1;
      let deps = match List.assoc_opt name p_deps with Some d -> d | None -> [] in
      List.iter visit deps;
      Hashtbl.replace color name 2
    end
  in
  List.iter visit all_names;
  !cycle_nodes

(** Find all nodes not referenced in any dep list — nodes with no dependents. *)
let leaf_nodes (p_deps : (string * string list) list) : string list =
  let all_deps = List.concat_map snd p_deps in
  List.filter_map (fun (name, _) ->
    if List.mem name all_deps then None else Some name
  ) p_deps

(** Find all nodes with no dependencies — root nodes. *)
let root_nodes (p_deps : (string * string list) list) : string list =
  List.filter_map (fun (name, deps) ->
    if deps = [] then Some name else None
  ) p_deps

let register env =

(*
--# Pipeline Dependency Edges
--#
--# Returns a list of dependency pairs, each as a two-element list
--# `[from, to]` representing an edge from a dependency to a dependent node.
--#
--# @name pipeline_edges
--# @param p :: Pipeline The pipeline.
--# @return :: List[List[String]] A list of [dependency, dependent] pairs.
--# @example
--#   pipeline_edges(p)
--# @family pipeline
--# @seealso pipeline_nodes, pipeline_deps, pipeline_roots, pipeline_leaves
--# @export
*)
  let env = Env.add "pipeline_edges"
    (make_builtin ~name:"pipeline_edges" 1 (fun args _env ->
      match args with
      | [VPipeline { p_deps; _ }] ->
          let edges = List.concat_map (fun (name, deps) ->
            List.map (fun dep ->
              (None, VList [(None, VString dep); (None, VString name)])
            ) deps
          ) p_deps in
          VList edges
      | [_] -> Error.type_error "Function `pipeline_edges` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_edges" 1 (List.length args)
    ))
    env
  in

(*
--# Pipeline Root Nodes
--#
--# Returns the names of all root nodes — nodes that have no dependencies.
--#
--# @name pipeline_roots
--# @param p :: Pipeline The pipeline.
--# @return :: List[String] Names of root nodes.
--# @example
--#   pipeline_roots(p)
--# @family pipeline
--# @seealso pipeline_leaves, pipeline_nodes
--# @export
*)
  let env = Env.add "pipeline_roots"
    (make_builtin ~name:"pipeline_roots" 1 (fun args _env ->
      match args with
      | [VPipeline { p_deps; _ }] ->
          let roots = root_nodes p_deps in
          VList (List.map (fun n -> (None, VString n)) roots)
      | [_] -> Error.type_error "Function `pipeline_roots` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_roots" 1 (List.length args)
    ))
    env
  in

(*
--# Pipeline Leaf Nodes
--#
--# Returns the names of all leaf nodes — nodes that no other node depends on.
--#
--# @name pipeline_leaves
--# @param p :: Pipeline The pipeline.
--# @return :: List[String] Names of leaf nodes.
--# @example
--#   pipeline_leaves(p)
--# @family pipeline
--# @seealso pipeline_roots, pipeline_nodes
--# @export
*)
  let env = Env.add "pipeline_leaves"
    (make_builtin ~name:"pipeline_leaves" 1 (fun args _env ->
      match args with
      | [VPipeline { p_deps; _ }] ->
          let leaves = leaf_nodes p_deps in
          VList (List.map (fun n -> (None, VString n)) leaves)
      | [_] -> Error.type_error "Function `pipeline_leaves` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_leaves" 1 (List.length args)
    ))
    env
  in

(*
--# Maximum Topological Depth
--#
--# Returns the maximum topological depth of any node in the pipeline.
--# Root nodes have depth 0.
--#
--# @name pipeline_depth
--# @param p :: Pipeline The pipeline.
--# @return :: Int The maximum depth.
--# @example
--#   pipeline_depth(p)
--# @family pipeline
--# @seealso pipeline_roots, pipeline_to_frame
--# @export
*)
  let env = Env.add "pipeline_depth"
    (make_builtin ~name:"pipeline_depth" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          let depths = Pipeline_to_frame.compute_depths p.p_deps in
          let max_d = List.fold_left (fun acc (_, d) -> max acc d) 0 depths in
          VInt max_d
      | [_] -> Error.type_error "Function `pipeline_depth` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_depth" 1 (List.length args)
    ))
    env
  in

(*
--# Detect Pipeline Cycles
--#
--# Returns a list of node names involved in dependency cycles. A well-formed
--# pipeline should always return an empty list.
--#
--# @name pipeline_cycles
--# @param p :: Pipeline The pipeline.
--# @return :: List[String] Names of nodes in cycles (empty if DAG is valid).
--# @example
--#   pipeline_cycles(p)
--# @family pipeline
--# @seealso pipeline_validate, pipeline_assert
--# @export
*)
  let env = Env.add "pipeline_cycles"
    (make_builtin ~name:"pipeline_cycles" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          let cycles = detect_cycles p.p_deps in
          VList (List.map (fun n -> (None, VString n)) cycles)
      | [_] -> Error.type_error "Function `pipeline_cycles` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_cycles" 1 (List.length args)
    ))
    env
  in

(*
--# Pipeline Summary
--#
--# Returns a DataFrame with full metadata for every node in the pipeline.
--# This is a convenience wrapper around `pipeline_to_frame`.
--#
--# @name pipeline_summary
--# @param p :: Pipeline The pipeline.
--# @return :: DataFrame A DataFrame with one row per node and all metadata columns.
--# @example
--#   pipeline_summary(p)
--# @family pipeline
--# @seealso pipeline_to_frame, select_node
--# @export
*)
  let env = Env.add "pipeline_summary"
    (make_builtin ~name:"pipeline_summary" 1 (fun args runtime_env ->
      match args with
      | [VPipeline _ as p_val] ->
          (* Delegate to pipeline_to_frame via the runtime env *)
          (match Env.find_opt "pipeline_to_frame" runtime_env with
           | Some fn -> (match fn with
               | VBuiltin { b_func; _ } ->
                   b_func [(None, p_val)] (ref runtime_env)
               | _ -> Error.type_error "pipeline_summary: pipeline_to_frame not a builtin.")
           | None -> Error.name_error "pipeline_to_frame")
      | [_] -> Error.type_error "Function `pipeline_summary` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_summary" 1 (List.length args)
    ))
    env
  in

(*
--# Validate a Pipeline
--#
--# Checks a pipeline for structural errors without throwing. Returns a list
--# of error messages. An empty list means the pipeline is valid.
--#
--# Checks performed:
--# - No dependency cycles
--# - All referenced dependencies exist as nodes in the pipeline
--#
--# @name pipeline_validate
--# @param p :: Pipeline The pipeline to validate.
--# @return :: List[String] A list of validation error messages (empty = valid).
--# @example
--#   pipeline_validate(p)
--# @family pipeline
--# @seealso pipeline_assert, pipeline_cycles
--# @export
*)
  let env = Env.add "pipeline_validate"
    (make_builtin ~name:"pipeline_validate" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          let errors = ref [] in
          let all_names = List.map fst p.p_exprs in
          (* Check: all deps reference existing nodes *)
          List.iter (fun (name, deps) ->
            List.iter (fun dep ->
              if not (List.mem dep all_names) then
                errors := Printf.sprintf
                  "Node `%s` depends on `%s` which does not exist in the pipeline."
                  name dep :: !errors
            ) deps
          ) p.p_deps;
          (* Check: no cycles *)
          let cycles = detect_cycles p.p_deps in
          if cycles <> [] then
            errors := Printf.sprintf
              "Pipeline has dependency cycle(s) involving: %s."
              (String.concat ", " cycles) :: !errors;
          VList (List.map (fun msg -> (None, VString msg)) (List.rev !errors))
      | [_] -> Error.type_error "Function `pipeline_validate` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_validate" 1 (List.length args)
    ))
    env
  in

(*
--# Assert Pipeline Validity
--#
--# Validates the pipeline and returns it unchanged if valid. Throws the first
--# validation error found if the pipeline is invalid.
--#
--# @name pipeline_assert
--# @param p :: Pipeline The pipeline to validate.
--# @return :: Pipeline The same pipeline if valid.
--# @example
--#   p |> pipeline_assert
--# @family pipeline
--# @seealso pipeline_validate, pipeline_cycles
--# @export
*)
  let env = Env.add "pipeline_assert"
    (make_builtin ~name:"pipeline_assert" 1 (fun args _env ->
      match args with
      | [VPipeline p as v] ->
          let all_names = List.map fst p.p_exprs in
          (* Check: missing deps *)
          let first_missing = List.find_map (fun (name, deps) ->
            List.find_map (fun dep ->
              if not (List.mem dep all_names) then
                Some (Printf.sprintf
                  "Node `%s` depends on `%s` which does not exist in the pipeline."
                  name dep)
              else None
            ) deps
          ) p.p_deps in
          (match first_missing with
           | Some msg -> Error.make_error ValueError msg
           | None ->
               let cycles = detect_cycles p.p_deps in
               if cycles <> [] then
                 Error.make_error ValueError
                   (Printf.sprintf "Pipeline has dependency cycle(s) involving: %s."
                      (String.concat ", " cycles))
               else v)
      | [_] -> Error.type_error "Function `pipeline_assert` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_assert" 1 (List.length args)
    ))
    env
  in

(*
--# Pretty-Print a Pipeline
--#
--# Prints a human-readable summary of the pipeline nodes to stdout, showing
--# each node's name, runtime, depth, noop status, and dependencies.
--#
--# @name pipeline_print
--# @param p :: Pipeline The pipeline to print.
--# @return :: Null
--# @example
--#   pipeline_print(p)
--# @family pipeline
--# @seealso pipeline_summary, pipeline_dot
--# @export
*)
  let env = Env.add "pipeline_print"
    (make_builtin ~name:"pipeline_print" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          let depths = Pipeline_to_frame.compute_depths p.p_deps in
          let node_names = List.map fst p.p_exprs in
          let n = List.length node_names in
          Printf.printf "Pipeline (%d nodes):\n" n;
          List.iter (fun name ->
            let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
            let depth   = match List.assoc_opt name depths with Some d -> d | None -> 0 in
            let noop    = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
            let deps    = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
            Printf.printf "  %-20s  runtime=%-8s  depth=%d  noop=%-5b  deps=[%s]\n"
              name runtime depth noop (String.concat ", " deps)
          ) node_names;
          (VNA NAGeneric)
      | [_] -> Error.type_error "Function `pipeline_print` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_print" 1 (List.length args)
    ))
    env
  in

(*
--# Export Pipeline as DOT Graph
--#
--# Returns a string containing a Graphviz DOT representation of the pipeline's
--# dependency graph, suitable for visualization.
--#
--# @name pipeline_dot
--# @param p :: Pipeline The pipeline.
--# @return :: String A DOT graph string.
--# @example
--#   pipeline_dot(p)
--# @family pipeline
--# @seealso pipeline_print, pipeline_edges
--# @export
*)
  let env = Env.add "pipeline_dot"
    (make_builtin ~name:"pipeline_dot" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          let buf = Buffer.create 256 in
          Buffer.add_string buf "digraph pipeline {\n";
          Buffer.add_string buf "  rankdir=LR;\n";
          Buffer.add_string buf "  node [shape=box];\n";
          (* Nodes with attributes *)
          List.iter (fun (name, _) ->
            let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
            let noop    = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
            let label =
              if noop then Printf.sprintf "%s\\n[%s, noop]" name runtime
              else          Printf.sprintf "%s\\n[%s]" name runtime
            in
            Buffer.add_string buf
              (Printf.sprintf "  \"%s\" [label=\"%s\"];\n" name label)
          ) p.p_exprs;
          (* Edges: dep -> name *)
          List.iter (fun (name, deps) ->
            List.iter (fun dep ->
              Buffer.add_string buf
                (Printf.sprintf "  \"%s\" -> \"%s\";\n" dep name)
            ) deps
          ) p.p_deps;
          Buffer.add_string buf "}\n";
          VString (Buffer.contents buf)
      | [_] -> Error.type_error "Function `pipeline_dot` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_dot" 1 (List.length args)
    ))
    env
  in
  
(*
--# Export Pipeline/MetaPipeline as DOT Graph
--#
--# Returns a string containing a Graphviz DOT representation of the pipeline or metapipeline
--# dependency graph, including node names and language runtimes.
--#
--# @name pipeline_to_dot
--# @param p :: Pipeline|MetaPipeline The pipeline or metapipeline.
--# @return :: String A DOT graph string.
--# @example
--#   pipeline_to_dot(p)
--# @family pipeline
--# @seealso pipeline_to_mermaid, pipeline_dot
--# @export
*)
  let env = Env.add "pipeline_to_dot"
    (make_builtin ~name:"pipeline_to_dot" 1 (fun args _env ->
      let render p =
        let buf = Buffer.create 256 in
        Buffer.add_string buf "digraph pipeline {\n";
        Buffer.add_string buf "  rankdir=LR;\n";
        Buffer.add_string buf "  node [shape=box];\n";
        List.iter (fun (name, _) ->
          let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
          let noop    = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
          let label =
            if noop then Printf.sprintf "%s\\n[%s, noop]" name runtime
            else          Printf.sprintf "%s\\n[%s]" name runtime
          in
          Buffer.add_string buf
            (Printf.sprintf "  \"%s\" [label=\"%s\"];\n" name label)
        ) p.p_exprs;
        List.iter (fun (name, deps) ->
          List.iter (fun dep ->
            Buffer.add_string buf
              (Printf.sprintf "  \"%s\" -> \"%s\";\n" dep name)
          ) deps
        ) p.p_deps;
        Buffer.add_string buf "}\n";
        VString (Buffer.contents buf)
      in
      match args with
      | [VPipeline p] -> render p
      | [VMetaPipeline _ as v] ->
          (match Pipeline_composition.flatten_meta v with
           | VPipeline p -> render p
           | e -> e)
      | [_] -> Error.type_error "Function `pipeline_to_dot` expects a Pipeline or MetaPipeline."
      | _ -> Error.arity_error_named "pipeline_to_dot" 1 (List.length args)
    ))
    env
  in

(*
--# Export Pipeline/MetaPipeline as Mermaid Graph
--#
--# Returns a string containing a Mermaid JS flowchart representation of the pipeline or metapipeline
--# dependency graph, including node names, language runtimes, and execution error status
--# (errored nodes are highlighted with a red stroke).
--# You can view the diagram in your browser by passing the result to show_plot().
--#
--# @name pipeline_to_mermaid
--# @param p :: Pipeline|MetaPipeline The pipeline or metapipeline.
--# @return :: String A Mermaid flowchart string.
--# @example
--#   pipeline_to_mermaid(p)
--# @family pipeline
--# @seealso pipeline_to_dot
--# @export
*)
  let env = Env.add "pipeline_to_mermaid"
    (make_builtin ~name:"pipeline_to_mermaid" 1 (fun args _env ->
      let render p =
        let buf = Buffer.create 256 in
        Buffer.add_string buf "graph LR\n";
        let sanitized_ids = Hashtbl.create (List.length p.p_exprs) in
        let used_ids = Hashtbl.create (List.length p.p_exprs) in
        let get_id name =
          match Hashtbl.find_opt sanitized_ids name with
          | Some id -> id
          | None ->
              let base = String.map (fun c -> if c = '.' || c = '-' then '_' else c) name in
              let rec find_unique candidate suffix =
                let cand = if suffix = 1 then candidate else Printf.sprintf "%s__%d" candidate suffix in
                if Hashtbl.mem used_ids cand then
                  find_unique candidate (suffix + 1)
                else begin
                  Hashtbl.add used_ids cand true;
                  cand
                end
              in
              let unique_id = find_unique base 1 in
              Hashtbl.add sanitized_ids name unique_id;
              unique_id
        in
        List.iter (fun (name, _) ->
          let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
          let noop    = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
          let label =
            if noop then Printf.sprintf "%s [%s, noop]" name runtime
            else          Printf.sprintf "%s [%s]" name runtime
          in
          let id = get_id name in
          Buffer.add_string buf
            (Printf.sprintf "  %s[\"%s\"];\n" id label)
        ) p.p_exprs;
        List.iter (fun (name, deps) ->
          let name_id = get_id name in
          List.iter (fun dep ->
            let dep_id = get_id dep in
            Buffer.add_string buf
              (Printf.sprintf "  %s --> %s;\n" dep_id name_id)
          ) deps
        ) p.p_deps;
        let runtime_fill = function
          | "r" -> "#246ABF"
          | "python" -> "#FFD343"
          | "julia" -> "#9558b2"
          | "quarto" -> "#4F789E"
          | "sh" -> "#6e3b03"
          | _ -> "#ffced0"
        in
        let has_error name =
          match List.assoc_opt name p.p_node_diagnostics with
          | Some d when d.nd_error <> None -> true
          | _ -> false
        in
        List.iter (fun (name, _) ->
          let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
          let id = get_id name in
          let fill = runtime_fill (String.lowercase_ascii runtime) in
          let stroke = if has_error name then "#ff0000" else "#333" in
          let stroke_width = if has_error name then 3 else 1 in
          Buffer.add_string buf
            (Printf.sprintf "  style %s fill:%s,color:#000000,stroke:%s,stroke-width:%dpx\n"
               id fill stroke stroke_width)
        ) p.p_exprs;

        VString (Buffer.contents buf)
      in
      match args with
      | [VPipeline p] -> render p
      | [VMetaPipeline _ as v] ->
          (match Pipeline_composition.flatten_meta v with
           | VPipeline p -> render p
           | e -> e)
      | [_] -> Error.type_error "Function `pipeline_to_mermaid` expects a Pipeline or MetaPipeline."
      | _ -> Error.arity_error_named "pipeline_to_mermaid" 1 (List.length args)
    ))
    env
  in

  env
