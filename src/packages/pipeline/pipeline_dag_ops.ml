open Ast

(* ── DAG traversal helpers ──────────────────────────────────────── *)

(** Compute the set of all ancestors (transitively) of a node.
    Returns names of node + all nodes it (transitively) depends on. *)
let ancestors (start : string) (p_deps : (string * string list) list) : string list =
  let visited = Hashtbl.create 16 in
  let rec visit name =
    if not (Hashtbl.mem visited name) then begin
      Hashtbl.add visited name ();
      let deps = match List.assoc_opt name p_deps with Some d -> d | None -> [] in
      List.iter visit deps
    end
  in
  visit start;
  Hashtbl.fold (fun k () acc -> k :: acc) visited []

(** Compute the set of all descendants (transitively) of a node.
    Returns names of node + all nodes that (transitively) depend on it. *)
let descendants (start : string) (p_deps : (string * string list) list) : string list =
  (* Build reverse dep map: for each node, who depends on it *)
  let reverse = Hashtbl.create 16 in
  List.iter (fun (name, deps) ->
    List.iter (fun dep ->
      let cur = match Hashtbl.find_opt reverse dep with Some l -> l | None -> [] in
      Hashtbl.replace reverse dep (name :: cur)
    ) deps
  ) p_deps;
  let visited = Hashtbl.create 16 in
  let rec visit name =
    if not (Hashtbl.mem visited name) then begin
      Hashtbl.add visited name ();
      let dependents = match Hashtbl.find_opt reverse name with Some l -> l | None -> [] in
      List.iter visit dependents
    end
  in
  visit start;
  Hashtbl.fold (fun k () acc -> k :: acc) visited []

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
    p_args         = List.filter (fun (n, _) -> keep n) p.p_args;
    p_shells       = List.filter (fun (n, _) -> keep n) p.p_shells;
    p_shell_args   = List.filter (fun (n, _) -> keep n) p.p_shell_args;
    p_functions    = List.filter (fun (n, _) -> keep n) p.p_functions;
    p_includes     = List.filter (fun (n, _) -> keep n) p.p_includes;
    p_noops        = List.filter (fun (n, _) -> keep n) p.p_noops;
    p_scripts      = List.filter (fun (n, _) -> keep n) p.p_scripts;
  }

let register env =

(*
--# Swap a Pipeline Node Implementation
--#
--# Replaces a node's implementation with a new node value. The dependency
--# edges of the replaced node are preserved — this operation only changes
--# the node's command and metadata. Use `rewire` to change dependencies.
--#
--# @name swap
--# @param p :: Pipeline The pipeline.
--# @param name :: String The name of the node to replace.
--# @param new_node :: Node The new node implementation.
--# @return :: Pipeline A new pipeline with the node replaced.
--# @example
--#   p |> swap("model_r", node(command = <{ lm(y ~ x, data) }>, runtime = R))
--# @family pipeline
--# @seealso rewire, rename_node, patch
--# @export
*)
  let env = Env.add "swap"
    (make_builtin ~name:"swap" 3 (fun args _env ->
      match args with
      | [VPipeline p; VString name; VNode un] ->
          if not (List.mem_assoc name p.p_exprs) then
            Error.make_error KeyError
              (Printf.sprintf "Node `%s` not found in Pipeline." name)
          else
            let replace_at lst v =
              List.map (fun (k, old) -> if k = name then (k, v) else (k, old)) lst
            in
            VPipeline {
              p with
              p_exprs        = replace_at p.p_exprs un.un_command;
              p_runtimes     = replace_at p.p_runtimes un.un_runtime;
              p_serializers  = replace_at p.p_serializers un.un_serializer;
              p_deserializers = replace_at p.p_deserializers un.un_deserializer;
              p_env_vars     = replace_at p.p_env_vars un.un_env_vars;
              p_args         = replace_at p.p_args un.un_args;
              p_shells       = replace_at p.p_shells un.un_shell;
              p_shell_args   = replace_at p.p_shell_args un.un_shell_args;
              p_functions    = replace_at p.p_functions un.un_functions;
              p_includes     = replace_at p.p_includes un.un_includes;
              p_noops        = replace_at p.p_noops un.un_noop;
              p_scripts      = replace_at p.p_scripts un.un_script;
              (* p_nodes and p_deps are deliberately preserved *)
            }
      | [VPipeline _; VString _; _] ->
          Error.type_error "Function `swap` expects a Node as the third argument."
      | [VPipeline _; _; _] ->
          Error.type_error "Function `swap` expects a String node name as the second argument."
      | [_; _; _] ->
          Error.type_error "Function `swap` expects a Pipeline as first argument."
      | _ -> Error.arity_error_named "swap" 3 (List.length args)
    ))
    env
  in

(*
--# Rewire a Node's Dependencies
--#
--# Reroutes a node's declared dependencies. The `replace` argument is a
--# named list (or Dict) mapping old dependency names to new ones. Only
--# the named node's dependency list is updated.
--#
--# @name rewire
--# @param p :: Pipeline The pipeline.
--# @param name :: String The name of the node whose deps should change.
--# @param replace :: List[String] A named list mapping old dep names to new ones.
--# @return :: Pipeline A new pipeline with updated dependency edges.
--# @example
--#   p |> rewire("model_py", replace = list(data = "data_v2"))
--# @family pipeline
--# @seealso swap, rename_node
--# @export
*)
  let env = Env.add "rewire"
    (make_builtin_named ~name:"rewire" ~variadic:true 2 (fun named_args _env ->
      let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
      let named      = List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args in
      match positionals with
      | [VPipeline p; VString name] ->
          if not (List.mem_assoc name p.p_exprs) then
            Error.make_error KeyError
              (Printf.sprintf "Node `%s` not found in Pipeline." name)
          else begin
            let replace_map = match List.assoc_opt "replace" named with
              | Some (VList items) ->
                  List.filter_map (fun (key, v) ->
                    match key, v with
                    | Some k, VString v -> Some (k, v)
                    | _ -> None
                  ) items
              | Some (VDict pairs) ->
                  List.filter_map (fun (k, v) ->
                    match v with VString s -> Some (k, s) | _ -> None
                  ) pairs
              | _ -> []
            in
            let new_deps = match List.assoc_opt name p.p_deps with
              | None -> []
              | Some deps ->
                  List.map (fun d ->
                    match List.assoc_opt d replace_map with
                    | Some new_d -> new_d
                    | None       -> d
                  ) deps
            in
            let new_p_deps = List.map (fun (k, v) ->
              if k = name then (k, new_deps) else (k, v)
            ) p.p_deps in
            VPipeline { p with p_deps = new_p_deps }
          end
      | [_; _] ->
          Error.type_error "Function `rewire` expects a Pipeline and a node name String."
      | _ ->
          Error.arity_error_named "rewire" 2 (List.length positionals)
    ))
    env
  in

(*
--# Prune Pipeline Leaf Nodes
--#
--# Removes all leaf nodes — nodes that have no downstream dependents
--# (nothing depends on them). This is useful for cleaning up intermediate
--# pipelines after `filter_node` or `difference` operations.
--#
--# @name prune
--# @param p :: Pipeline The pipeline to prune.
--# @return :: Pipeline A new pipeline with leaf nodes removed.
--# @example
--#   p |> difference(p_remove) |> prune
--# @family pipeline
--# @seealso filter_node, difference
--# @export
*)
  let env = Env.add "prune"
    (make_builtin ~name:"prune" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          (* A node is a leaf if it appears in no other node's dep list *)
          let all_deps = List.concat_map snd p.p_deps in
          let is_leaf name = not (List.mem name all_deps) in
          let keep = List.filter_map (fun (n, _) ->
            if is_leaf n then None else Some n
          ) p.p_exprs in
          VPipeline (filter_pipeline keep p)
      | [_] -> Error.type_error "Function `prune` expects a Pipeline."
      | _ -> Error.arity_error_named "prune" 1 (List.length args)
    ))
    env
  in

(*
--# Extract Upstream Subgraph
--#
--# Returns a new pipeline containing the named node and all of its transitive
--# dependencies (ancestors in the DAG).
--#
--# @name upstream_of
--# @param p :: Pipeline The pipeline.
--# @param name :: String The name of the target node.
--# @return :: Pipeline A new pipeline with only the node and its ancestors.
--# @example
--#   p |> upstream_of("predictions")
--# @family pipeline
--# @seealso downstream_of, subgraph
--# @export
*)
  let env = Env.add "upstream_of"
    (make_builtin ~name:"upstream_of" 2 (fun args _env ->
      match args with
      | [VPipeline p; VString name] ->
          if not (List.mem_assoc name p.p_exprs) then
            Error.make_error KeyError
              (Printf.sprintf "Node `%s` not found in Pipeline." name)
          else
            let keep = ancestors name p.p_deps in
            VPipeline (filter_pipeline keep p)
      | [VPipeline _; _] ->
          Error.type_error "Function `upstream_of` expects a String node name."
      | [_; _] ->
          Error.type_error "Function `upstream_of` expects a Pipeline as first argument."
      | _ -> Error.arity_error_named "upstream_of" 2 (List.length args)
    ))
    env
  in

(*
--# Extract Downstream Subgraph
--#
--# Returns a new pipeline containing the named node and all nodes that
--# transitively depend on it (descendants in the DAG).
--#
--# @name downstream_of
--# @param p :: Pipeline The pipeline.
--# @param name :: String The name of the target node.
--# @return :: Pipeline A new pipeline with only the node and its descendants.
--# @example
--#   p |> downstream_of("data")
--# @family pipeline
--# @seealso upstream_of, subgraph
--# @export
*)
  let env = Env.add "downstream_of"
    (make_builtin ~name:"downstream_of" 2 (fun args _env ->
      match args with
      | [VPipeline p; VString name] ->
          if not (List.mem_assoc name p.p_exprs) then
            Error.make_error KeyError
              (Printf.sprintf "Node `%s` not found in Pipeline." name)
          else
            let keep = descendants name p.p_deps in
            VPipeline (filter_pipeline keep p)
      | [VPipeline _; _] ->
          Error.type_error "Function `downstream_of` expects a String node name."
      | [_; _] ->
          Error.type_error "Function `downstream_of` expects a Pipeline as first argument."
      | _ -> Error.arity_error_named "downstream_of" 2 (List.length args)
    ))
    env
  in

(*
--# Extract Connected Subgraph
--#
--# Returns a new pipeline containing the named node, all of its ancestors,
--# and all of its descendants — the full connected component reachable from
--# the node in either direction.
--#
--# @name subgraph
--# @param p :: Pipeline The pipeline.
--# @param name :: String The name of the target node.
--# @return :: Pipeline A new pipeline with the full connected component.
--# @example
--#   p |> subgraph("model_r")
--# @family pipeline
--# @seealso upstream_of, downstream_of
--# @export
*)
  let env = Env.add "subgraph"
    (make_builtin ~name:"subgraph" 2 (fun args _env ->
      match args with
      | [VPipeline p; VString name] ->
          if not (List.mem_assoc name p.p_exprs) then
            Error.make_error KeyError
              (Printf.sprintf "Node `%s` not found in Pipeline." name)
          else
            let ups   = ancestors name p.p_deps in
            let downs = descendants name p.p_deps in
            (* Union of both sets: ups already contains `name`; add downs entries not in ups *)
            let keep = ups @ List.filter (fun n -> not (List.mem n ups)) downs in
            VPipeline (filter_pipeline keep p)
      | [VPipeline _; _] ->
          Error.type_error "Function `subgraph` expects a String node name."
      | [_; _] ->
          Error.type_error "Function `subgraph` expects a Pipeline as first argument."
      | _ -> Error.arity_error_named "subgraph" 2 (List.length args)
    ))
    env
  in

  env
