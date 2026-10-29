open Ast

(*
--# Unified pipeline overview table
--#
--# One call joins pipeline structure with the latest build log into a
--# single per-node table: the columns of `pipeline_to_frame` plus the live
--# build state of `pipeline_status`.
--#
--# It is not a superset of the other frames. `pipeline_config_to_frame` also
--# reports `shell`, `flake`, the `prov_*` provenance columns and the `n_*`
--# count columns. None of these are repeated here; call that function when
--# you need them. Node diagnostics live in `pipeline_node_options` (and as
--# `$diagnostics` in `filter_node` predicates), not in this table nor in
--# `pipeline_to_frame`.
--#
--# Column names match the source frames so filters copy over unchanged.
--# Failed nodes sort first so the root cause is visible without extra calls.
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
--# @param only :: String = NA Filter rows: failed, built, unbuilt, or all. Default shows all, failed first.
--# @return :: DataFrame One row per node, failed nodes first.
--# @example
--#   pipeline_overview(p)
--#   pipeline_overview(p, only = "failed")
--#   pipeline_overview(p) |> filter($status == "Errored")
--# @family pipeline
--# @seealso pipeline_to_frame, pipeline_status, pipeline_config_to_frame, pipeline_overview_markdown
--# @export
--#
--# Markdown overview table
--#
--# Same rows as pipeline_overview, rendered as a Markdown table
--# for reports and workflow summaries.
--#
--# @name pipeline_overview_markdown
--# @param pipeline :: Pipeline The pipeline to summarize.
--# @param only :: String = NA Same filter as pipeline_overview.
--# @return :: String Markdown table with name, runtime, status, depth, error.
--# @example
--#   pipeline_overview_markdown(p)
--#   pipeline_overview_markdown(p, only = "failed")
--# @family pipeline
--# @seealso pipeline_overview, pipeline_report
--# @export
*)

(* Failed nodes first, stable within each group. *)
let order_failed_first ~is_failed names =
  let failed, ok = List.partition is_failed names in
  failed @ ok

let status_of_health h =
  match h.Pipeline_status.h_status with
  | Some s -> s
  | None -> "NA"

let matches_only only status =
  match only with
  | None -> true
  | Some f ->
      let want = String.lowercase_ascii f in
      if want = "all" then true
      else begin
        let got = String.lowercase_ascii status in
        if want = "failed" || want = "errored" then
          got = "errored" || got = "softfailed"
        else if want = "built" || want = "completed" then
          got = "completed" || got = "built" || got = "cached"
        else if want = "unbuilt" || want = "pending" then
          got = "na" || got = "---" || got = "pending" || got = "unbuilt"
          || got = "skipped"
        else got = want
      end

let allowed_only =
  ["failed"; "errored"; "built"; "completed"; "unbuilt"; "pending"; "all"]

(* Read `only` from the named or positional argument, validate its type (a
   non-String is an error, not a silent no-op), and reject unknown named
   arguments so a misspelled filter does not silently return every row. *)
let read_only fn_name named_args =
  let unknown_named =
    List.find_map (fun (k, _) -> match k with
      | Some n when n <> "only" -> Some n
      | _ -> None) named_args
  in
  match unknown_named with
  | Some name ->
      Error (Error.type_error
        (Printf.sprintf "Function `%s` got an unknown argument `%s`. The only supported argument is `only`."
           fn_name name))
  | None ->
      let named =
        List.find_map (fun (k, v) -> match k with
          | Some "only" -> Some v
          | _ -> None) named_args
      in
      let positional =
        List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args
      in
      let value = match named with
        | Some v -> Some v
        | None -> List.nth_opt positional 1
      in
      (match value with
       | None -> Ok None
       | Some (VNA _) -> Ok None
       | Some (VString s) -> Ok (Some s)
       | Some (VSymbol s) -> Ok (Some s)
       | Some v ->
           Error (Error.type_error
             (Printf.sprintf "Function `%s` argument `only` must be a String, but got %s."
                fn_name (Utils.type_name v))))

let validate_only fn_name = function
  | None -> Ok None
  | Some s ->
      let w = String.lowercase_ascii s in
      if List.mem w allowed_only then Ok (Some s)
      else
        Error (Error.value_error
          (Printf.sprintf
             "Function `%s` argument `only` must be failed, built, unbuilt, or all, but got \"%s\"."
             fn_name s))

let build_overview_frame p only_opt =
  let node_names = List.map fst p.p_exprs in
  let depths = Pipeline_to_frame.compute_depths p.p_deps in
  let health = Pipeline_status.health_of_latest_log p in
  let health_of name =
    match List.assoc_opt name health with
    | Some h -> h
    | None -> Pipeline_status.empty_health
  in
  let ordered =
    order_failed_first
      ~is_failed:(fun name -> Pipeline_status.is_failed (health_of name).Pipeline_status.h_status)
      node_names
  in
  let filtered = List.filter (fun n -> matches_only only_opt (status_of_health (health_of n))) ordered in
  let nrows = List.length filtered in
  let str_of f = Array.of_list (List.map (fun n -> f n) filtered) in
  let runtime_of n =
    Some (match List.assoc_opt n p.p_runtimes with Some r -> r | None -> "T") in
  let ser_of field n =
    let tbl = if field = "ser" then p.p_serializers else p.p_deserializers in
    let e = match List.assoc_opt n tbl with Some s -> s | None -> Ast.mk_expr (Var "default") in
    Some (Nix_unparse.expr_to_string e) in
  let columns = [
    ("name", Arrow_table.StringColumn
      (Array.of_list (List.map (fun n -> Some n) filtered)));
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

let overview_to_markdown p only_opt =
  let node_names = List.map fst p.p_exprs in
  let depths = Pipeline_to_frame.compute_depths p.p_deps in
  let health = Pipeline_status.health_of_latest_log p in
  let health_of name =
    match List.assoc_opt name health with
    | Some h -> h
    | None -> Pipeline_status.empty_health
  in
  let ordered =
    order_failed_first
      ~is_failed:(fun name -> Pipeline_status.is_failed (health_of name).Pipeline_status.h_status)
      node_names
  in
  let filtered = List.filter (fun n -> matches_only only_opt (status_of_health (health_of n))) ordered in
  let buf = Buffer.create 512 in
  Buffer.add_string buf "| name | runtime | status | depth | error |\n";
  Buffer.add_string buf "|------|---------|--------|-------|-------|\n";
  List.iter (fun n ->
    let rt = match List.assoc_opt n p.p_runtimes with Some r -> r | None -> "T" in
    let d = match List.assoc_opt n depths with Some v -> v | None -> 0 in
    let h = health_of n in
    let st = (match h.Pipeline_status.h_status with Some s -> s | None -> "NA") in
    let er = (match h.Pipeline_status.h_error with Some s -> s | None -> "") in
    let esc s =
      let b = Buffer.create (String.length s) in
      String.iter (fun c -> match c with '|' -> Buffer.add_string b "\\|" | '\n' -> Buffer.add_char b ' ' | c -> Buffer.add_char b c) s;
      Buffer.contents b
    in
    Buffer.add_string buf (Printf.sprintf "| %s | %s | %s | %d | %s |\n" (esc n) (esc rt) (esc st) d (esc er))
  ) filtered;
  Buffer.contents buf

let register env =
  let overview_fn named_args _env =
    match Pipeline_args.get_arg "pipeline" 1 (VNA NAGeneric) named_args with
    | (_, VPipeline p) ->
        (match read_only "pipeline_overview" named_args with
         | Error e -> e
         | Ok only_opt ->
             (match validate_only "pipeline_overview" only_opt with
              | Error e -> e
              | Ok valid -> build_overview_frame p valid))
    | (_, other) ->
        Error.type_error
          (Printf.sprintf "Function `pipeline_overview` expects a Pipeline, but got %s."
             (Utils.type_name other))
  in
  let markdown_fn named_args _env =
    match Pipeline_args.get_arg "pipeline" 1 (VNA NAGeneric) named_args with
    | (_, VPipeline p) ->
        (match read_only "pipeline_overview_markdown" named_args with
         | Error e -> e
         | Ok only_opt ->
             (match validate_only "pipeline_overview_markdown" only_opt with
              | Error e -> e
              | Ok valid -> VString (overview_to_markdown p valid)))
    | (_, other) ->
        Error.type_error
          (Printf.sprintf "Function `pipeline_overview_markdown` expects a Pipeline, but got %s."
             (Utils.type_name other))
  in
  let env = Env.add "pipeline_overview"
    (make_builtin_named ~name:"pipeline_overview" ~variadic:true 1 overview_fn) env in
  let env = Env.add "pipeline_overview_markdown"
    (make_builtin_named ~name:"pipeline_overview_markdown" ~variadic:true 1 markdown_fn) env in
  env
