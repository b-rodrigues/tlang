open Ast

(*
--# Convert Pipeline to DataFrame
--#
--# Converts a Pipeline to a DataFrame where each row represents a node and each
--# column represents a metadata field. This is a key inspection utility for
--# understanding and debugging pipeline structure.
--#
--# The columns returned are:
--# - `name` — the node name (String)
--# - `runtime` — one of "T", "R", "Python" (String)
--# - `serializer` — e.g. "default", "pmml" (String)
--# - `deserializer` — e.g. "default", "pmml" (String)
--# - `noop` — whether the node is a no-op (Bool)
--# - `deps` — names of nodes this node depends on (String, comma-separated)
--# - `depth` — topological depth in the DAG (Int); roots are depth 0
--# - `command_type` — one of "command" or "script" (String)
--#
--# @name pipeline_to_frame
--# @param p :: Pipeline The pipeline to convert.
--# @return :: DataFrame A DataFrame with one row per node.
--# @example
--#   pipeline_to_frame(p)
--# @family pipeline
--# @seealso select_node, pipeline_nodes
--# @export
*)

(** Compute the topological depth of every node in a pipeline.
    Roots (nodes with no dependencies) have depth 0.
    Each node's depth is one greater than the maximum depth of its
    dependencies. *)
let compute_depths (p_deps : (string * string list) list) : (string * int) list =
  (* Memoised depth via a simple recursive lookup. We protect against
     infinite loops by assuming the pipeline is acyclic (DAG validity is
     checked elsewhere). *)
  let cache : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let rec depth_of name =
    match Hashtbl.find_opt cache name with
    | Some d -> d
    | None ->
        let deps = match List.assoc_opt name p_deps with Some d -> d | None -> [] in
        let d =
          if deps = [] then 0
          else 1 + List.fold_left (fun acc dep -> max acc (depth_of dep)) 0 deps
        in
        Hashtbl.add cache name d;
        d
  in
  List.map (fun (name, _) -> (name, depth_of name)) p_deps

(** Build a metadata dict for a single node, suitable for NSE predicate
    evaluation.  The dict keys mirror the column names returned by
    [pipeline_to_frame] so that the same predicate expressions work in
    both [filter_node] and [select_node]. *)
let node_metadata_dict
      (name : string)
      (p : pipeline_result)
      (depths : (string * int) list) : (string * value) list =
  let runtime      = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
  let ser_expr     = match List.assoc_opt name p.p_serializers with Some s -> s | None -> Ast.mk_expr (Var "default") in
  let des_expr     = match List.assoc_opt name p.p_deserializers with Some s -> s | None -> Ast.mk_expr (Var "default") in
  let serializer   = Nix_unparse.expr_to_string ser_expr in
  let deserializer = Nix_unparse.expr_to_string des_expr in
  let noop         = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
  let deps         = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
  let depth        = match List.assoc_opt name depths with Some d -> d | None -> 0 in
  let cmd_type     = match List.assoc_opt name p.p_scripts with
    | Some (Some _) -> "script"
    | _ -> "command"
  in
  [
    ("name",         VString name);
    ("runtime",      VString runtime);
    ("serializer",   VString serializer);
    ("deserializer", VString deserializer);
    ("noop",         VBool noop);
    ("deps",         VList (List.map (fun d -> (None, VString d)) deps));
    ("depth",        VInt depth);
    ("command_type", VString cmd_type);
  ]

let register env =
  Env.add "pipeline_to_frame"
    (make_builtin ~name:"pipeline_to_frame" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          let node_names = List.map fst p.p_exprs in
          let depths = compute_depths p.p_deps in
          let nrows = List.length node_names in
          let arr_name        = Array.init nrows (fun i -> Some (List.nth node_names i)) in
          let arr_runtime     = Array.init nrows (fun i ->
            let n = List.nth node_names i in
            Some (match List.assoc_opt n p.p_runtimes with Some r -> r | None -> "T")) in
          let arr_serializer  = Array.init nrows (fun i ->
            let n = List.nth node_names i in
            let e = match List.assoc_opt n p.p_serializers with Some s -> s | None -> Ast.mk_expr (Var "default") in
            Some (Nix_unparse.expr_to_string e)) in
          let arr_deserializer = Array.init nrows (fun i ->
            let n = List.nth node_names i in
            let e = match List.assoc_opt n p.p_deserializers with Some s -> s | None -> Ast.mk_expr (Var "default") in
            Some (Nix_unparse.expr_to_string e)) in
          let arr_noop        = Array.init nrows (fun i ->
            let n = List.nth node_names i in
            Some (match List.assoc_opt n p.p_noops with Some b -> b | None -> false)) in
          let arr_deps        = Array.init nrows (fun i ->
            let n = List.nth node_names i in
            let deps = match List.assoc_opt n p.p_deps with Some d -> d | None -> [] in
            Some (String.concat ", " deps)) in
          let arr_depth       = Array.init nrows (fun i ->
            let n = List.nth node_names i in
            Some (match List.assoc_opt n depths with Some d -> d | None -> 0)) in
          let arr_cmd_type    = Array.init nrows (fun i ->
            let n = List.nth node_names i in
            Some (match List.assoc_opt n p.p_scripts with Some (Some _) -> "script" | _ -> "command")) in
          let columns = [
            ("name",         Arrow_table.StringColumn arr_name);
            ("runtime",      Arrow_table.StringColumn arr_runtime);
            ("serializer",   Arrow_table.StringColumn arr_serializer);
            ("deserializer", Arrow_table.StringColumn arr_deserializer);
            ("noop",         Arrow_table.BoolColumn arr_noop);
            ("deps",         Arrow_table.StringColumn arr_deps);
            ("depth",        Arrow_table.IntColumn arr_depth);
            ("command_type", Arrow_table.StringColumn arr_cmd_type);
          ] in
          let arrow_table = Arrow_table.create columns nrows in
          VDataFrame { arrow_table; group_keys = [] }
      | [_] -> Error.type_error "Function `pipeline_to_frame` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_to_frame" 1 (List.length args)
    ))
    env
