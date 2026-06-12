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

(** Create a fresh ID allocator for Mermaid node names.
    Sanitises names (replacing . and - with _) and ensures uniqueness. *)
let make_id_allocator () =
  let sanitized_ids = Hashtbl.create 16 in
  let used_ids = Hashtbl.create 16 in
  fun name ->
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

(** Mapped colour for each runtime's node fill. *)
let runtime_fill = function
  | "r" -> "#246ABF"
  | "python" -> "#FFD343"
  | "julia" -> "#9558b2"
  | "quarto" -> "#4F789E"
  | "sh" -> "#6e3b03"
  | _ -> "#859900"

(** Check whether a pipeline node has an error class. *)
let has_error p name =
  match List.assoc_opt name p.p_nodes with
  | Some (VComputedNode cn) ->
      let cn = !Ast.computed_node_resolver cn in
      cn.cn_class = "Error" || cn.cn_class = "VError"
  | Some (VNodeResult { v = VComputedNode cn; _ }) ->
      let cn = !Ast.computed_node_resolver cn in
      cn.cn_class = "Error" || cn.cn_class = "VError"
  | _ -> false

(** Read project name from tproject.toml and build a graph title. *)
let get_project_title () =
  try
    let root = Builder_utils.get_project_root () in
    let path = Filename.concat root "tproject.toml" in
    if Sys.file_exists path then
      let ic = open_in path in
      let content =
        Fun.protect ~finally:(fun () -> close_in_noerr ic)
          (fun () -> really_input_string ic (in_channel_length ic))
      in
      match Toml_parser.parse_tproject_toml content with
      | Ok cfg when String.length cfg.proj_name > 0 ->
          Some (Printf.sprintf "Dependency Graph of Project '%s'" cfg.proj_name)
      | _ -> None
    else None
  with _ -> None

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
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_edges` expects a Pipeline, but got %s."
               (Utils.type_name other))
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
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_roots` expects a Pipeline, but got %s."
               (Utils.type_name other))
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
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_leaves` expects a Pipeline, but got %s."
               (Utils.type_name other))
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
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_depth` expects a Pipeline, but got %s."
               (Utils.type_name other))
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
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_cycles` expects a Pipeline, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "pipeline_cycles" 1 (List.length args)
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
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_validate` expects a Pipeline, but got %s."
               (Utils.type_name other))
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
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_assert` expects a Pipeline, but got %s."
               (Utils.type_name other))
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
--# @seealso pipeline_to_frame
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
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_print` expects a Pipeline, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "pipeline_print" 1 (List.length args)
    ))
    env
  in

(*
--# Export Pipeline/MetaPipeline as DOT Graph
--#
--# Returns a string containing a Graphviz DOT representation of the pipeline or metapipeline
--# dependency graph, including node names and language runtimes.
--#
--# For MetaPipelines, sub-pipelines are rendered as DOT subgraph clusters by default,
--# providing visual grouping of related nodes. Set flatten = true to get a flat diagram.
--#
--# @name pipeline_to_dot
--# @param p :: Pipeline|MetaPipeline The pipeline or metapipeline.
--# @param flatten :: Bool = false Flatten meta-pipeline subgraphs into a single level.
--# @param title :: Str = None Optional graph title. Auto-detected from tproject.toml when omitted.
--# @return :: String A DOT graph string.
--# @example
--#   pipeline_to_dot(p)
--#   pipeline_to_dot(meta, flatten = true)
--#   pipeline_to_dot(p, title = "My Graph")
--# @family pipeline
--# @seealso pipeline_to_mermaid
--# @export
*)
  let env = Env.add "pipeline_to_dot"
    (VBuiltin { b_name = Some "pipeline_to_dot"; b_arity = 1; b_variadic = true;
      b_func = (fun named_args _env_ref ->
        let named_args = List.map (fun (n, v) -> (n, Ast.Utils.unwrap_value v)) named_args in
      match Math_common.get_bool_flag "flatten" false named_args with
      | Error e -> e
      | Ok flatten ->
      let title =
        match Math_common.optional_named_arg "title" named_args with
        | Some (VString t) when String.length t > 0 -> Some t
        | _ -> get_project_title ()
      in
      let args = Math_common.positional_args_without ["flatten"; "title"] named_args in
      (* DOT output intentionally omits runtime-colour fills and error-node
         styling (unlike Mermaid) because Graphviz users typically apply
         their own stylesheet or theme. *)
      let emit_flat_diagram p =
        let buf = Buffer.create 256 in
        Buffer.add_string buf "digraph pipeline {\n";
        (match title with
         | Some t -> Buffer.add_string buf (Printf.sprintf "  label=\"%s\";\n" t)
         | None -> ());
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
      let emit_subgraph_diagram p sub_names =
        let buf = Buffer.create 256 in
        Buffer.add_string buf "digraph pipeline {\n";
        (match title with
         | Some t -> Buffer.add_string buf (Printf.sprintf "  label=\"%s\";\n" t)
         | None -> ());
        Buffer.add_string buf "  rankdir=LR;\n";
        Buffer.add_string buf "  node [shape=box];\n";
        let subgraph_of name =
          List.find_map (fun sub ->
            let prefix = sub ^ "." in
            let plen = String.length prefix in
            if String.length name > plen && String.sub name 0 plen = prefix then
              Some sub
            else None
          ) sub_names
        in
        let subgraph_nodes = Hashtbl.create (List.length sub_names) in
        List.iter (fun ((name, _) as entry) ->
          match subgraph_of name with
          | Some sub ->
              let group = match Hashtbl.find_opt subgraph_nodes sub with
                | Some l -> l | None -> [] in
              Hashtbl.replace subgraph_nodes sub (entry :: group)
          | None -> ()
        ) p.p_exprs;
        (* Defensive: sub-pipeline names should be unique already, but sort_uniq is safe. *)
        let sorted_subs = List.sort_uniq compare sub_names in
        List.iter (fun sub ->
          match Hashtbl.find_opt subgraph_nodes sub with
          | Some nodes ->
              let nodes = List.rev nodes in
              let prefix_len = String.length sub + 1 in
              Buffer.add_string buf (Printf.sprintf "  subgraph cluster_%s {\n" sub);
              Buffer.add_string buf (Printf.sprintf "    label=\"%s\";\n" sub);
              List.iter (fun (name, _) ->
                let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
                let noop    = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
                let short_name = String.sub name prefix_len (String.length name - prefix_len) in
                let label =
                  if noop then Printf.sprintf "%s\\n[%s, noop]" short_name runtime
                  else          Printf.sprintf "%s\\n[%s]" short_name runtime
                in
                Buffer.add_string buf
                  (Printf.sprintf "    \"%s\" [label=\"%s\"];\n" name label)
              ) nodes;
              List.iter (fun (dependent, deps) ->
                match subgraph_of dependent with
                | Some s when s = sub ->
                    List.iter (fun dep ->
                      if subgraph_of dep = Some sub then
                        Buffer.add_string buf
                          (Printf.sprintf "    \"%s\" -> \"%s\";\n" dep dependent)
                    ) deps
                | _ -> ()
              ) p.p_deps;
              Buffer.add_string buf "  }\n"
          | None -> ()
        ) sorted_subs;
        List.iter (fun (dependent, deps) ->
          match subgraph_of dependent with
          | Some ds ->
              List.iter (fun dep ->
                match subgraph_of dep with
                | Some ss when ss <> ds ->
                    Buffer.add_string buf
                      (Printf.sprintf "  \"%s\" -> \"%s\";\n" dep dependent)
                | _ -> ()
              ) deps
          | None ->
              List.iter (fun dep ->
                Buffer.add_string buf
                  (Printf.sprintf "  \"%s\" -> \"%s\";\n" dep dependent)
              ) deps
        ) p.p_deps;
        Buffer.add_string buf "}\n";
        VString (Buffer.contents buf)
      in
      match args with
      | [VPipeline p] -> emit_flat_diagram p
      | [VMetaPipeline _ as v] when flatten ->
          (match Pipeline_composition.flatten_meta v with
           | VPipeline p -> emit_flat_diagram p
           | e -> e)
      | [VMetaPipeline mp] ->
          (match Pipeline_composition.flatten_meta (VMetaPipeline mp) with
           | VPipeline p -> emit_subgraph_diagram p (List.map fst mp.mp_pipelines)
           | e -> e)
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_to_dot` expects a Pipeline or MetaPipeline, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "pipeline_to_dot" 1 (List.length args)
      ) })
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
--# For MetaPipelines, sub-pipelines are rendered as Mermaid subgraph blocks by default,
--# providing visual grouping of related nodes. Set flatten = true to get a flat diagram.
--#
--# @name pipeline_to_mermaid
--# @param p :: Pipeline|MetaPipeline The pipeline or metapipeline.
--# @param flatten :: Bool = false Flatten meta-pipeline subgraphs into a single level.
--# @param title :: Str = None Optional graph title. Auto-detected from tproject.toml when omitted.
--# @return :: String A Mermaid flowchart string.
--# @example
--#   pipeline_to_mermaid(p)
--#   pipeline_to_mermaid(meta, flatten = true)
--#   pipeline_to_mermaid(p, title = "My Graph")
--# @family pipeline
--# @seealso pipeline_to_dot
--# @export
*)
  let env = Env.add "pipeline_to_mermaid"
    (VBuiltin { b_name = Some "pipeline_to_mermaid"; b_arity = 1; b_variadic = true;
      b_func = (fun named_args _env_ref ->
        let named_args = List.map (fun (n, v) -> (n, Ast.Utils.unwrap_value v)) named_args in
      match Math_common.get_bool_flag "flatten" false named_args with
      | Error e -> e
      | Ok flatten ->
      let title =
        match Math_common.optional_named_arg "title" named_args with
        | Some (VString t) when String.length t > 0 -> Some t
        | _ -> get_project_title ()
      in
      let args = Math_common.positional_args_without ["flatten"; "title"] named_args in
      let emit_flat_diagram p =
        let buf = Buffer.create 256 in
        (match title with
         | Some t ->
             Buffer.add_string buf "---\n";
             Buffer.add_string buf (Printf.sprintf "tlang-title: %s\n" t);
             Buffer.add_string buf "---\n"
         | None -> ());
        Buffer.add_string buf "graph LR\n";
        let get_id = make_id_allocator () in
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
        List.iter (fun (name, _) ->
          let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
          let id = get_id name in
          let fill = runtime_fill (String.lowercase_ascii runtime) in
          let stroke = if has_error p name then "#ff0000" else "#333" in
          let stroke_width = if has_error p name then 3 else 1 in
          Buffer.add_string buf
            (Printf.sprintf "  style %s fill:%s,color:#000000,stroke:%s,stroke-width:%dpx\n"
               id fill stroke stroke_width)
        ) p.p_exprs;
        VString (Buffer.contents buf)
      in
      let emit_subgraph_diagram p sub_names =
        let buf = Buffer.create 256 in
        (match title with
         | Some t ->
             Buffer.add_string buf "---\n";
             Buffer.add_string buf (Printf.sprintf "tlang-title: %s\n" t);
             Buffer.add_string buf "---\n"
         | None -> ());
        Buffer.add_string buf "graph LR\n";
        let get_id = make_id_allocator () in
        let subgraph_of name =
          List.find_map (fun sub ->
            let prefix = sub ^ "." in
            let plen = String.length prefix in
            if String.length name > plen && String.sub name 0 plen = prefix then
              Some sub
            else None
          ) sub_names
        in
        let subgraph_nodes = Hashtbl.create (List.length sub_names) in
        List.iter (fun ((name, _) as entry) ->
          match subgraph_of name with
          | Some sub ->
              let group = match Hashtbl.find_opt subgraph_nodes sub with
                | Some l -> l | None -> [] in
              Hashtbl.replace subgraph_nodes sub (entry :: group)
          | None -> ()
        ) p.p_exprs;
        (* Defensive: sub-pipeline names should be unique already, but sort_uniq is safe. *)
        let sorted_subs = List.sort_uniq compare sub_names in
        List.iter (fun sub ->
          match Hashtbl.find_opt subgraph_nodes sub with
          | Some nodes ->
              let nodes = List.rev nodes in
              let prefix_len = String.length sub + 1 in
              Buffer.add_string buf (Printf.sprintf "  subgraph %s\n" sub);
              List.iter (fun (name, _) ->
                let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
                let noop    = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
                let short_name = String.sub name prefix_len (String.length name - prefix_len) in
                let label =
                  if noop then Printf.sprintf "%s [%s, noop]" short_name runtime
                  else          Printf.sprintf "%s [%s]" short_name runtime
                in
                let id = get_id name in
                Buffer.add_string buf
                  (Printf.sprintf "    %s[\"%s\"];\n" id label)
              ) nodes;
              List.iter (fun (dependent, deps) ->
                match subgraph_of dependent with
                | Some s when s = sub ->
                    let dep_id = get_id dependent in
                    List.iter (fun dep ->
                      if subgraph_of dep = Some sub then
                        let src_id = get_id dep in
                        Buffer.add_string buf
                          (Printf.sprintf "    %s --> %s;\n" src_id dep_id)
                    ) deps
                | _ -> ()
              ) p.p_deps;
              Buffer.add_string buf "  end\n"
          | None -> ()
        ) sorted_subs;
        List.iter (fun (dependent, deps) ->
          match subgraph_of dependent with
          | Some ds ->
              let dep_id = get_id dependent in
              List.iter (fun dep ->
                match subgraph_of dep with
                | Some ss when ss <> ds ->
                    let src_id = get_id dep in
                    Buffer.add_string buf
                      (Printf.sprintf "  %s --> %s;\n" src_id dep_id)
                | _ -> ()
              ) deps
          | None ->
              let dep_id = get_id dependent in
              List.iter (fun dep ->
                let src_id = get_id dep in
                Buffer.add_string buf
                  (Printf.sprintf "  %s --> %s;\n" src_id dep_id)
              ) deps
        ) p.p_deps;
        List.iter (fun (name, _) ->
          let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
          let id = get_id name in
          let fill = runtime_fill (String.lowercase_ascii runtime) in
          let stroke = if has_error p name then "#ff0000" else "#333" in
          let stroke_width = if has_error p name then 3 else 1 in
          Buffer.add_string buf
            (Printf.sprintf "  style %s fill:%s,color:#000000,stroke:%s,stroke-width:%dpx\n"
               id fill stroke stroke_width)
        ) p.p_exprs;
        VString (Buffer.contents buf)
      in
      match args with
      | [VPipeline p] -> emit_flat_diagram p
      | [VMetaPipeline _ as v] when flatten ->
          (match Pipeline_composition.flatten_meta v with
           | VPipeline p -> emit_flat_diagram p
           | e -> e)
      | [VMetaPipeline mp] ->
          (match Pipeline_composition.flatten_meta (VMetaPipeline mp) with
           | VPipeline p -> emit_subgraph_diagram p (List.map fst mp.mp_pipelines)
           | e -> e)
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_to_mermaid` expects a Pipeline or MetaPipeline, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "pipeline_to_mermaid" 1 (List.length args)
      ) })
    env
  in

  env
