(* src/packages/pipeline/pipeline_metrics.ml *)

open Ast

(*
--# Cross-Runtime Model Metrics Leaderboard
--#
--# Collects build-time `foreign_meta` sidecars from model nodes across R,
--# Python, and Julia into a single comparison DataFrame. Includes every
--# built node whose `meta` sidecar reports `kind = "model"` or non-empty
--# `metrics`. Base columns (`name`, `runtime`, `kind`, `task`, `method`,
--# `n_obs`, `n_features`, `status`) are followed by one Float column per
--# metric key found across the selected nodes (sorted alphabetically, NA
--# where a node does not report that metric). Metric keys that collide with
--# a base column name are prefixed with `metric_`. Non-finite metrics
--# (NaN/Inf) are recorded as NA, and nodes with missing or unreadable `meta`
--# sidecars are skipped.
--#
--# @name pipeline_metrics
--# @param pipeline :: Pipeline The pipeline to compare.
--# @param task :: String = NA Optional task filter (e.g. "regression", "classification", "time_series").
--# @param sort_by :: String = NA Optional column to sort by (any metric column, "n_obs", "n_features", or "name").
--# @param descending :: Bool = false Sort descending when true (default false, lowest metric first).
--# @return :: DataFrame One row per model node with aligned metric columns.
--# @example
--#   pipeline_metrics(p)
--#   pipeline_metrics(p, task = "time_series", sort_by = "aic")
--#   pipeline_metrics(p, sort_by = "r2", descending = true)
--# @family pipeline
--# @seealso pipeline_metrics_markdown, pipeline_overview, explain
--# @export
*)

(*
--# Markdown Model Metrics Leaderboard
--#
--# Renders model metadata and metrics (`name`, `runtime`, `kind`, `task`,
--# `method`, `n_obs`, `status`, plus all metric columns) as a Markdown table
--# for reports and workflow summaries.
--#
--# @name pipeline_metrics_markdown
--# @param pipeline :: Pipeline The pipeline to compare.
--# @param task :: String = NA Optional task filter.
--# @param sort_by :: String = NA Optional column to sort by.
--# @param descending :: Bool = false Sort descending when true.
--# @return :: String Markdown table of model metadata and metrics.
--# @example
--#   pipeline_metrics_markdown(p)
--#   pipeline_metrics_markdown(p, sort_by = "aic")
--# @family pipeline
--# @seealso pipeline_metrics, pipeline_overview_markdown, pipeline_report
--# @export
*)

type model_row = {
  mr_name : string;
  mr_runtime : string;
  mr_kind : string option;
  mr_task : string option;
  mr_method : string option;
  mr_n_obs : int option;
  mr_n_features : int option;
  mr_status : string option;
  mr_metrics : (string * float) list;
}

let base_column_names =
  ["name"; "runtime"; "kind"; "task"; "method"; "n_obs"; "n_features"; "status"]

let safe_metric_col_name key =
  if List.mem key base_column_names then "metric_" ^ key else key

let assoc_int key pairs =
  match List.assoc_opt key pairs with
  | Some v -> Artifact_meta.json_to_int v
  | None -> None

let extract_metrics_assoc pairs =
  match List.assoc_opt "metrics" pairs with
  | Some (`Assoc m) ->
      List.filter_map (fun (k, v) ->
        match Artifact_meta.json_to_float v with
        | Some f -> Some (safe_metric_col_name k, f)
        | None -> None
      ) m
  | _ -> []

let model_row_of_meta ~name ~runtime ~status pairs =
  let kind = Artifact_meta.assoc_str "kind" pairs in
  let metrics = extract_metrics_assoc pairs in
  let is_model =
    (match kind with Some "model" -> true | _ -> false)
    || metrics <> []
  in
  if not is_model then None
  else
    Some {
      mr_name = name;
      mr_runtime = runtime;
      mr_kind = kind;
      mr_task = Artifact_meta.assoc_str "task" pairs;
      mr_method = Artifact_meta.assoc_str "method" pairs;
      mr_n_obs = assoc_int "n_obs" pairs;
      mr_n_features = assoc_int "n_features" pairs;
      mr_status = status;
      mr_metrics = metrics;
    }

let collect_model_rows (p : pipeline_result) =
  let node_names = List.map fst p.p_exprs in
  let health = Pipeline_status.health_of_latest_log p in
  List.filter_map (fun name ->
    let runtime =
      match List.assoc_opt name p.p_runtimes with
      | Some r -> r
      | None -> "T"
    in
    match List.assoc_opt name health with
    | None -> None
    | Some h ->
        (match h.Pipeline_status.h_path with
         | None -> None
         | Some art_path ->
             (match Artifact_meta.read_meta_assoc_of_artifact art_path with
              | None -> None
              | Some pairs ->
                  model_row_of_meta ~name ~runtime
                    ~status:h.Pipeline_status.h_status pairs))
  ) node_names

let metric_keys_of_rows rows =
  let tbl = Hashtbl.create 16 in
  List.iter (fun r ->
    List.iter (fun (k, _) -> Hashtbl.replace tbl k ()) r.mr_metrics
  ) rows;
  Hashtbl.fold (fun k () acc -> k :: acc) tbl []
  |> List.sort String.compare

let filter_by_task task_opt rows =
  match task_opt with
  | None -> rows
  | Some want ->
      let want_lc = String.lowercase_ascii (String.trim want) in
      List.filter (fun r ->
        match r.mr_task with
        | Some t -> String.lowercase_ascii t = want_lc
        | None -> false
      ) rows

let compare_opt cmp ~descending a b =
  match a, b with
  | None, None -> 0
  | None, Some _ -> 1
  | Some _, None -> -1
  | Some x, Some y ->
      let c = cmp x y in
      if descending then -c else c

let sort_rows ~metric_keys ?(all_metric_keys=metric_keys) ~sort_by ~descending rows =
  match sort_by with
  | None -> Ok rows
  | Some _ when rows = [] -> Ok []
  | Some col ->
      let valid_base = ["name"; "n_obs"; "n_features"] in
      let lookup_col = safe_metric_col_name col in
      if not (List.mem col valid_base || List.mem col all_metric_keys || List.mem lookup_col all_metric_keys) then
        let available = valid_base @ all_metric_keys in
        Error (Error.value_error
          (Printf.sprintf
             "Unknown `sort_by` column \"%s\". Available columns: %s."
             col (String.concat ", " available)))
      else
        let cmp r1 r2 =
          match col with
          | "name" ->
              let c = String.compare r1.mr_name r2.mr_name in
              if descending then -c else c
          | "n_obs" ->
              compare_opt Int.compare ~descending r1.mr_n_obs r2.mr_n_obs
          | "n_features" ->
              compare_opt Int.compare ~descending r1.mr_n_features r2.mr_n_features
          | m ->
              let key = if List.mem m all_metric_keys then m else safe_metric_col_name m in
              compare_opt Float.compare ~descending
                (List.assoc_opt key r1.mr_metrics)
                (List.assoc_opt key r2.mr_metrics)
        in
        Ok (List.stable_sort cmp rows)

let build_dataframe_of_rows ~metric_keys rows =
  let nrows = List.length rows in
  let map_arr f = Array.of_list (List.map f rows) in
  let base_cols = [
    ("name", Arrow_table.StringColumn (map_arr (fun r -> Some r.mr_name)));
    ("runtime", Arrow_table.StringColumn (map_arr (fun r -> Some r.mr_runtime)));
    ("kind", Arrow_table.StringColumn (map_arr (fun r -> r.mr_kind)));
    ("task", Arrow_table.StringColumn (map_arr (fun r -> r.mr_task)));
    ("method", Arrow_table.StringColumn (map_arr (fun r -> r.mr_method)));
    ("n_obs", Arrow_table.IntColumn (map_arr (fun r -> r.mr_n_obs)));
    ("n_features", Arrow_table.IntColumn (map_arr (fun r -> r.mr_n_features)));
    ("status", Arrow_table.StringColumn (map_arr (fun r -> r.mr_status)));
  ] in
  let metric_cols =
    List.map (fun k ->
      (k, Arrow_table.FloatColumn (map_arr (fun r -> List.assoc_opt k r.mr_metrics)))
    ) metric_keys
  in
  let arrow_table = Arrow_table.create (base_cols @ metric_cols) nrows in
  VDataFrame { arrow_table; group_keys = [] }

let escape_md s =
  let b = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '|' -> Buffer.add_string b "\\|"
    | '\n' | '\r' -> Buffer.add_char b ' '
    | c -> Buffer.add_char b c
  ) s;
  Buffer.contents b

let format_float_md f = Printf.sprintf "%.4g" f

let render_markdown_of_rows ~metric_keys rows =
  let headers =
    ["name"; "runtime"; "kind"; "task"; "method"; "n_obs"; "status"]
    @ List.map escape_md metric_keys
  in
  let buf = Buffer.create 512 in
  Buffer.add_string buf ("| " ^ String.concat " | " headers ^ " |\n");
  Buffer.add_string buf
    ("|" ^ String.concat "|" (List.map (fun _ -> "------") headers) ^ "|\n");
  List.iter (fun r ->
    let opt_s = function Some s -> escape_md s | None -> "NA" in
    let opt_i = function Some i -> string_of_int i | None -> "NA" in
    let base_vals = [
      escape_md r.mr_name;
      escape_md r.mr_runtime;
      opt_s r.mr_kind;
      opt_s r.mr_task;
      opt_s r.mr_method;
      opt_i r.mr_n_obs;
      opt_s r.mr_status;
    ] in
    let metric_vals =
      List.map (fun k ->
        match List.assoc_opt k r.mr_metrics with
        | Some f -> format_float_md f
        | None -> "NA"
      ) metric_keys
    in
    Buffer.add_string buf
      ("| " ^ String.concat " | " (base_vals @ metric_vals) ^ " |\n")
  ) rows;
  Buffer.contents buf

let allowed_named_args = ["pipeline"; "task"; "sort_by"; "descending"]

let parse_options fn_name named_args =
  let positional_count =
    List.fold_left (fun acc (k, _) -> match k with None -> acc + 1 | Some _ -> acc) 0 named_args
  in
  if positional_count > 1 then
    Error (Error.type_error
      (Printf.sprintf
         "Function `%s` accepts only 1 positional argument (pipeline). Pass optional arguments by name: task = ..., sort_by = ..., descending = ...."
         fn_name))
  else
    let unknown =
      List.find_map (fun (k, _) ->
        match k with
        | Some n when not (List.mem n allowed_named_args) -> Some n
        | _ -> None
      ) named_args
    in
    match unknown with
    | Some name ->
        Error (Error.type_error
          (Printf.sprintf
             "Function `%s` got an unknown argument `%s`. Supported arguments: pipeline, task, sort_by, descending."
             fn_name name))
    | None ->
        let find_opt_str key =
          match List.find_map (fun (k, v) -> if k = Some key then Some v else None) named_args with
          | None | Some (VNA _) -> Ok None
          | Some (VString s) -> Ok (Some s)
          | Some (VSymbol s) -> Ok (Some s)
          | Some v ->
              Error (Error.type_error
                (Printf.sprintf "Function `%s` argument `%s` must be a String, but got %s."
                   fn_name key (Utils.type_name v)))
        in
        let find_bool key default =
          match List.find_map (fun (k, v) -> if k = Some key then Some v else None) named_args with
          | None | Some (VNA _) -> Ok default
          | Some (VBool b) -> Ok b
          | Some v ->
              Error (Error.type_error
                (Printf.sprintf "Function `%s` argument `%s` must be a Bool, but got %s."
                   fn_name key (Utils.type_name v)))
        in
        (match find_opt_str "task" with
         | Error e -> Error e
         | Ok task ->
             (match find_opt_str "sort_by" with
              | Error e -> Error e
              | Ok sort_by ->
                  (match find_bool "descending" false with
                   | Error e -> Error e
                   | Ok descending -> Ok (task, sort_by, descending))))

let eval_metrics fn_name ~as_markdown named_args _env =
  match Pipeline_args.get_arg "pipeline" 1 (VNA NAGeneric) named_args with
  | (_, VPipeline p) ->
      (match parse_options fn_name named_args with
       | Error e -> e
       | Ok (task, sort_by, descending) ->
           let all_rows = collect_model_rows p in
           let all_metric_keys = metric_keys_of_rows all_rows in
           let rows = filter_by_task task all_rows in
           let metric_keys = metric_keys_of_rows rows in
           (match sort_rows ~metric_keys ~all_metric_keys ~sort_by ~descending rows with
            | Error e -> e
            | Ok sorted ->
                if as_markdown then
                  VString (render_markdown_of_rows ~metric_keys sorted)
                else
                  build_dataframe_of_rows ~metric_keys sorted))
  | (_, other) ->
      Error.type_error
        (Printf.sprintf "Function `%s` expects a Pipeline, but got %s."
           fn_name (Utils.type_name other))

let register env =
  env
  |> Env.add "pipeline_metrics"
       (make_builtin_named ~name:"pipeline_metrics" ~variadic:true 1
          (eval_metrics "pipeline_metrics" ~as_markdown:false))
  |> Env.add "pipeline_metrics_markdown"
       (make_builtin_named ~name:"pipeline_metrics_markdown" ~variadic:true 1
          (eval_metrics "pipeline_metrics_markdown" ~as_markdown:true))
