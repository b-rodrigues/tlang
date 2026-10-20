open Ast

(*
--# Unified pipeline overview table
--#
--# One call joins pipeline structure with the latest build log into a
--# single per-node table. It replaces three separate calls
--# (`pipeline_to_frame`, `pipeline_status`, `pipeline_config_to_frame`)
--# when you need both static config and live build state. Column names
--# match the source frames so filters copy over unchanged. Failed nodes
--# sort first so the root cause is visible without extra calls.
--#
--# Columns:
--# - `name` — node name (String)
--# - `runtime` — e.g. "T", "R", "Python" (String)
--# - `serializer` — e.g. "default", "^csv" (String)
--# - `deserializer` — e.g. "default", "^csv" (String)
--# - `noop` — whether the node is a no-op (Bool)
--# - `deps` — names of nodes this node depends on (String, comma-separated)
--# - `depth` — topological depth in the DAG (Int); roots are depth 0
--# - `command_type` — one of "command" or "script" (String)
--# - `status` — build status from the latest matching log, or NA
--# - `duration` — node build duration in seconds (Float), or NA
--# - `path` — Nix store path of the node output, or NA
--# - `error` — `code: message` for failed nodes, or NA
--#
--# @name pipeline_overview
--# @param pipeline :: Pipeline The pipeline to summarize.
--# @return :: DataFrame One row per node, failed nodes first.
--# @example
--#   pipeline_overview(p)
--#   pipeline_overview(p) |> filter($status == "Errored")
--# @family pipeline
--# @seealso pipeline_to_frame, pipeline_status, pipeline_config_to_frame
--# @export
*)

let register env =
  Env.add "pipeline_overview"
    (make_builtin ~name:"pipeline_overview" 1 (fun args _env ->
       match args with
       | [VPipeline p] ->
           let node_names = List.map fst p.p_exprs in
           let depths = Pipeline_to_frame.compute_depths p.p_deps in
           let health = Pipeline_status.health_of_latest_log p in
           let health_of name =
             match List.assoc_opt name health with
             | Some h -> h
             | None -> Pipeline_status.empty_health
           in
           (* Failed nodes first, stable within each group. *)
           let failed, ok =
             List.partition (fun name -> Pipeline_status.is_failed (health_of name).Pipeline_status.h_status) node_names
           in
           let ordered = failed @ ok in
           let nrows = List.length ordered in
           let str_of f = Array.of_list (List.map (fun n -> f n) ordered) in
           let runtime_of n =
             Some (match List.assoc_opt n p.p_runtimes with Some r -> r | None -> "T") in
           let ser_of field n =
             let tbl = if field = "ser" then p.p_serializers else p.p_deserializers in
             let e = match List.assoc_opt n tbl with Some s -> s | None -> Ast.mk_expr (Var "default") in
             Some (Nix_unparse.expr_to_string e) in
           let columns = [
             ("name", Arrow_table.StringColumn
               (Array.of_list (List.map (fun n -> Some n) ordered)));
             ("runtime", Arrow_table.StringColumn (str_of runtime_of));
             ("serializer", Arrow_table.StringColumn (str_of (ser_of "ser")));
             ("deserializer", Arrow_table.StringColumn (str_of (ser_of "des")));
             ("noop", Arrow_table.BoolColumn
               (str_of (fun n -> Some (match List.assoc_opt n p.p_noops with Some b -> b | None -> false))));
             ("deps", Arrow_table.StringColumn
               (str_of (fun n ->
                 let deps = match List.assoc_opt n p.p_deps with Some d -> d | None -> [] in
                 Some (String.concat ", " deps))));
             ("depth", Arrow_table.IntColumn
               (str_of (fun n -> Some (match List.assoc_opt n depths with Some d -> d | None -> 0))));
             ("command_type", Arrow_table.StringColumn
               (str_of (fun n ->
                 Some (match List.assoc_opt n p.p_scripts with Some (Some _) -> "script" | _ -> "command"))));
             ("status", Arrow_table.StringColumn
               (str_of (fun n -> (health_of n).Pipeline_status.h_status)));
             ("duration", Arrow_table.FloatColumn
               (str_of (fun n -> (health_of n).Pipeline_status.h_duration)));
             ("path", Arrow_table.StringColumn
               (str_of (fun n -> (health_of n).Pipeline_status.h_path)));
             ("error", Arrow_table.StringColumn
               (str_of (fun n -> (health_of n).Pipeline_status.h_error)));
           ] in
           let arrow_table = Arrow_table.create columns nrows in
           VDataFrame { arrow_table; group_keys = [] }
       | [other] ->
           Error.type_error
             (Printf.sprintf "Function `pipeline_overview` expects a Pipeline, but got %s."
                (Utils.type_name other))
       | _ -> Error.arity_error_named "pipeline_overview" 1 (List.length args)
     ))
    env
