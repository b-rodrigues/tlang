open Ast

let compute_depths = Pipeline_to_frame.compute_depths

let get_arg name pos default named_args =
  match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
  | Some v -> (true, v)
  | None ->
      let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
      if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
      else (false, default)

let timestamp_string () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec

let timestamp_file_suffix () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d%02d%02d_%02d%02d%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec

let escape_markdown_table s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '\n' -> Buffer.add_char buf ' '
    | '|' -> Buffer.add_string buf "\\|"
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let generate_mermaid p =
  let sanitized_ids = Hashtbl.create 16 in
  let used_ids = Hashtbl.create 16 in
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
  let buf = Buffer.create 256 in
  Buffer.add_string buf "graph LR\n";
  List.iter (fun (name, _) ->
    let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
    let id = get_id name in
    Buffer.add_string buf (Printf.sprintf "  %s[\"%s [%s]\"]\n" id name runtime)
  ) p.p_exprs;
  List.iter (fun (name, deps) ->
    let name_id = get_id name in
    List.iter (fun dep ->
      let dep_id = get_id dep in
      Buffer.add_string buf (Printf.sprintf "  %s --> %s\n" dep_id name_id)
    ) deps
  ) p.p_deps;
  Buffer.contents buf

let read_build_log_entries log_path =
  let open Yojson.Safe.Util in
  try
    let json = Yojson.Safe.from_file log_path in
    let nodes = json |> member "nodes" |> to_list in
    let entries = List.map (fun node_json ->
      let name = node_json |> member "node" |> to_string in
      let status = match node_json |> member "status" with `String s -> s | _ -> "Unknown" in
      let path = match node_json |> member "path" with `String s -> s | _ -> "" in
      let has_warnings = match node_json |> member "warnings" with
        | `Bool b -> b | `String s -> String.lowercase_ascii s = "true" | _ -> false in
      let error_msg = match node_json |> member "error_message" with
        | `String s -> Some s | _ -> None in
      let error_code = match node_json |> member "error_code" with
        | `String s -> Some s | _ -> None in
      let node_duration = match node_json |> member "duration" with
        | `Float f -> f | `Int i -> float_of_int i | _ -> 0.0 in
      (name, (status, path, has_warnings, error_msg, error_code, node_duration))
    ) nodes in
    let duration = match json |> member "duration" with
      | `Float f -> f | `Int i -> float_of_int i | _ -> 0.0 in
    (Some (duration, entries), None)
  with
  | Sys_error msg -> (None, Some (Printf.sprintf "Cannot read build log `%s`: %s" log_path msg))
  | Yojson.Json_error msg -> (None, Some (Printf.sprintf "Invalid JSON in build log `%s`: %s" log_path msg))
  | e -> (None, Some (Printf.sprintf "Unexpected error reading build log `%s`: %s" log_path (Printexc.to_string e)))

let find_matching_log_path p which_log =
  let logs = Builder.get_logs () in
  let matches, pattern_error = match which_log with
    | None -> (logs, None)
    | Some pattern ->
        (match try Some (Str.regexp pattern) with Failure _ -> None with
         | Some re ->
             let filtered = List.filter (fun f ->
               try let _ = Str.search_forward re f 0 in true
               with Not_found -> false) logs in
             (filtered, None)
         | None -> (logs, Some (Printf.sprintf "Invalid regex pattern `%s`; using all available logs." pattern)))
  in
  let try_log log_file =
    let full_path = Filename.concat Builder.pipeline_dir log_file in
    match Builder.read_log full_path with
    | Ok entries when Builder_read_node.pipeline_matches_logged_entries p entries -> Some full_path
    | Ok _ -> None
    | Error _ ->
        None
  in
  match matches with
  | [] ->
      let msg = match pattern_error with
        | Some msg -> msg
        | None ->
            match which_log with
            | Some pat -> Printf.sprintf "No build logs matched pattern `%s` in `_pipeline/`." pat
            | None -> "No build logs found in `_pipeline/`."
      in
      (None, Some msg)
  | first :: rest when which_log <> None ->
      (match try_log first with
       | Some _ as hit -> (hit, pattern_error)
       | None ->
           (match List.find_map try_log rest with
            | Some _ as hit -> (hit, pattern_error)
             | None -> (None, Some (Printf.sprintf "No build log matching pattern `%s` matches this pipeline's structure."
                                      (match which_log with Some pat -> pat | None -> "")))))
  | first :: rest ->
      (match try_log first with
       | Some _ as hit -> (hit, None)
       | None ->
           (match List.find_map try_log rest with
            | Some _ as hit -> (hit, None)
            | None -> (None, Some (Printf.sprintf "None of the %d build logs in `_pipeline/` match this pipeline's structure."
                                     (List.length matches)))))

type node_kind = Built | Unbuilt | Errored

let rec classify_node name p log_entries_map =
  let diag_error = match List.assoc_opt name p.p_node_diagnostics with
    | Some d when d.nd_error <> None -> true
    | _ -> false
  in
  if diag_error then Errored
  else
    match log_entries_map with
    | Some entries ->
        (match List.assoc_opt name entries with
         | Some (status_str, path, _, _, _, _) ->
             let sl = String.lowercase_ascii status_str in
             if path <> "" && (sl = "completed" || sl = "completed with warning") then Built
             else if sl = "errored" || sl = "softfailed" then Errored
             else if sl = "completed" && path = "" then Unbuilt
             else if sl = "skipped" || sl = "pending" || sl = "building" then Unbuilt
             else Built
         | None -> classify_node_by_value name p)
    | None -> classify_node_by_value name p

and classify_node_by_value name p =
  match List.assoc_opt name p.p_nodes with
  | Some (VComputedNode cn) when cn.cn_path <> "" && cn.cn_path <> "<unbuilt>" -> Built
  | Some (VComputedNode _) -> Unbuilt
  | Some (VNode _) -> Unbuilt
  | Some (VError _) -> Errored
  | _ -> Unbuilt

let node_depth name depths =
  match List.assoc_opt name depths with Some d -> d | None -> 0

let node_runtime name p =
  match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T"

let node_has_warnings name p log_entries_map =
  let diag_warnings = match List.assoc_opt name p.p_node_diagnostics with
    | Some d -> List.length d.nd_warnings > 0
    | None -> false
  in
  if diag_warnings then true
  else
    match log_entries_map with
    | Some entries ->
        (match List.assoc_opt name entries with
         | Some (_, _, hw, _, _, _) -> hw
         | None -> false)
    | None -> false

let node_error_message name p log_entries_map =
  match List.assoc_opt name p.p_node_diagnostics with
  | Some d ->
      (match d.nd_error with
       | Some e -> Some (e.ne_kind ^ ": " ^ e.ne_message)
       | None -> None)
  | None ->
      match log_entries_map with
      | Some entries ->
          (match List.assoc_opt name entries with
           | Some (_, _, _, err_msg_opt, err_code_opt, _) ->
               (match err_msg_opt, err_code_opt with
                | Some msg, Some code when code <> "" -> Some (code ^ ": " ^ msg)
                | Some msg, _ -> Some msg
                | None, Some code -> Some code
                | None, None -> None)
           | None -> None)
      | None -> None

let node_warning_messages name p =
  match List.assoc_opt name p.p_node_diagnostics with
  | Some d -> List.map (fun w -> w.nw_message) d.nd_warnings
  | None -> []

let get_node_status_str name log_entries_map =
  match log_entries_map with
  | Some entries ->
      (match List.assoc_opt name entries with
       | Some (status_str, _, _, _, _, _) ->
           let sl = String.lowercase_ascii status_str in
           if sl = "completed" then "Completed"
           else if sl = "completed with warning" then "Completed (warnings)"
           else if sl = "errored" then "Errored"
           else if sl = "softfailed" then "Completed (errors)"
           else if sl = "skipped" then "Skipped"
           else if sl = "building" then "Building"
           else if sl = "pending" then "Pending"
           else status_str
       | None -> "---")
  | None -> "---"

(*
--# Generate Pipeline Report
--#
--# Generates a Markdown report summarizing the pipeline's current status,
--# dependency graph, built nodes, unbuilt nodes, and errored/warned nodes.
--# The report is written to a timestamped file in the `_pipeline/` directory.
--#
--# @name pipeline_report
--# @param p :: Pipeline The pipeline to report on.
--# @param errors :: Bool = false Include full error messages for errored nodes.
--# @param which_log :: String (Optional) Regex to select a specific build log.
--# @param file :: String (Optional) Output file path. Defaults to `_pipeline/pipeline_report_<timestamp>.md`.
--# @return :: String The path to the generated report file.
--# @example
--#   pipeline_report(p)
--#   pipeline_report(p, errors = true)
--#   pipeline_report(p, which_log = "20260615")
--# @family pipeline
--# @export
*)
let register env =
  let report_fn named_args _env =
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["p"; "errors"; "which_log"; "file"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "pipeline_report: unknown argument '%s'" k)
    | None when positional_count > 4 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `pipeline_report` accepts at most 4 positional arguments but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (_, errors_val) = get_arg "errors" 2 (VBool false) named_args in
        let (_, which_log_val) = get_arg "which_log" 3 (VNA NAGeneric) named_args in
        let (_, file_val) = get_arg "file" 4 (VNA NAGeneric) named_args in

        let errors_flag = match errors_val with
          | VBool b -> b
          | _ -> false
        in
        let which_log_opt = match which_log_val with
          | VString s when String.length s > 0 -> Some s
          | VSymbol s when String.length s > 0 -> Some s
          | _ -> None
        in
        let file_path =
          match file_val with
          | VString s when String.length s > 0 ->
              let dir = Filename.dirname s in
              if dir <> "" && dir <> "." then
                (try Builder_utils.ensure_dir dir
                 with e ->
                   let msg = Printf.sprintf "Cannot create directory `%s` for pipeline report: %s"
                     dir (Printexc.to_string e) in
                   raise (Failure msg));
              s
          | _ ->
              Builder_utils.ensure_pipeline_dir ();
              Filename.concat Builder_utils.pipeline_dir
                (Printf.sprintf "pipeline_report_%s.md" (timestamp_file_suffix ()))
        in

        (try
          let depths = compute_depths p.p_deps in
          let node_names = List.map fst p.p_exprs in
          let total = List.length node_names in

          let (log_path, log_search_msg) = find_matching_log_path p which_log_opt in
          let (log_info, log_parse_msg) = match log_path with
            | Some path -> read_build_log_entries path
            | None -> (None, None)
          in
          let log_entries_map = match log_info with
            | Some (_, entries) -> Some entries
            | None -> None
          in
          let build_duration = match log_info with
            | Some (duration, _) -> duration
            | None -> 0.0
          in

          let classify name = classify_node name p log_entries_map in

          let built_nodes = List.filter (fun n -> match classify n with Built -> true | _ -> false) node_names in
          let unbuilt_nodes = List.filter (fun n -> match classify n with Unbuilt -> true | _ -> false) node_names in
          let errored_nodes = List.filter (fun n -> match classify n with Errored -> true | _ -> false) node_names in
          let warned_nodes = List.filter (fun n -> node_has_warnings n p log_entries_map) node_names in

          let buf = Buffer.create 4096 in

          Buffer.add_string buf "# Pipeline Report\n\n";
          Buffer.add_string buf (Printf.sprintf "**Generated**: %s\n\n" (timestamp_string ()));

          Buffer.add_string buf "## Overview\n\n";
          Buffer.add_string buf "| Metric | Count |\n";
          Buffer.add_string buf "|--------|-------|\n";
          Buffer.add_string buf (Printf.sprintf "| Total Nodes | %d |\n" total);
          Buffer.add_string buf (Printf.sprintf "| Built | %d |\n" (List.length built_nodes));
          Buffer.add_string buf (Printf.sprintf "| Unbuilt | %d |\n" (List.length unbuilt_nodes));
          Buffer.add_string buf (Printf.sprintf "| Errored | %d |\n" (List.length errored_nodes));
          Buffer.add_string buf (Printf.sprintf "| Warnings | %d |\n" (List.length warned_nodes));
          Buffer.add_char buf '\n';

          Buffer.add_string buf "## Dependency Graph\n\n";
          Buffer.add_string buf "```mermaid\n";
          Buffer.add_string buf (generate_mermaid p);
          Buffer.add_string buf "```\n\n";

          Buffer.add_string buf (Printf.sprintf "## Built Nodes (%d)\n\n" (List.length built_nodes));
          if built_nodes = [] then
            Buffer.add_string buf "_No nodes built yet._\n\n"
          else begin
            Buffer.add_string buf "| Name | Runtime | Depth | Status |\n";
            Buffer.add_string buf "|------|---------|-------|--------|\n";
            List.iter (fun name ->
              let d = node_depth name depths in
              let rt = node_runtime name p in
              let st = get_node_status_str name log_entries_map in
              Buffer.add_string buf (Printf.sprintf "| %s | %s | %d | %s |\n"
                (escape_markdown_table name) (escape_markdown_table rt) d (escape_markdown_table st))
            ) built_nodes;
            Buffer.add_char buf '\n'
          end;

          Buffer.add_string buf (Printf.sprintf "## Unbuilt Nodes (%d)\n\n" (List.length unbuilt_nodes));
          if unbuilt_nodes = [] then
            Buffer.add_string buf "_All nodes have been built._\n\n"
          else begin
            Buffer.add_string buf "| Name | Runtime | Depth |\n";
            Buffer.add_string buf "|------|---------|-------|\n";
            List.iter (fun name ->
              let d = node_depth name depths in
              let rt = node_runtime name p in
              Buffer.add_string buf (Printf.sprintf "| %s | %s | %d |\n"
                (escape_markdown_table name) (escape_markdown_table rt) d)
            ) unbuilt_nodes;
            Buffer.add_char buf '\n'
          end;

          Buffer.add_string buf (Printf.sprintf "## Errored Nodes (%d)\n\n" (List.length errored_nodes));
          if errored_nodes = [] then
            Buffer.add_string buf "_No errors._\n\n"
          else begin
            if errors_flag then begin
              Buffer.add_string buf "| Name | Error |\n";
              Buffer.add_string buf "|------|-------|\n";
              List.iter (fun name ->
                let msg = match node_error_message name p log_entries_map with
                  | Some m -> m
                  | None -> "Unknown error"
                in
                Buffer.add_string buf (Printf.sprintf "| %s | %s |\n"
                  (escape_markdown_table name) (escape_markdown_table msg))
              ) errored_nodes
            end else begin
              Buffer.add_string buf "| Name |\n";
              Buffer.add_string buf "|------|\n";
              List.iter (fun name ->
                Buffer.add_string buf (Printf.sprintf "| %s |\n" (escape_markdown_table name))
              ) errored_nodes;
              Buffer.add_string buf "\n_Use `pipeline_report(p, errors = true)` to see full error messages._\n"
            end;
            Buffer.add_char buf '\n'
          end;

          Buffer.add_string buf (Printf.sprintf "## Nodes with Warnings (%d)\n\n" (List.length warned_nodes));
          if warned_nodes = [] then
            Buffer.add_string buf "_No warnings._\n\n"
          else begin
            List.iter (fun name ->
              let msgs = node_warning_messages name p in
              Buffer.add_string buf (Printf.sprintf "- **%s**: " name);
              if msgs = [] then
                Buffer.add_string buf "Warning flagged in build log.\n"
              else
                List.iter (fun msg ->
                  Buffer.add_string buf (Printf.sprintf "%s " (escape_markdown_table msg))
                ) msgs;
              Buffer.add_char buf '\n'
            ) warned_nodes;
            Buffer.add_char buf '\n'
          end;

          (match log_path with
           | Some path ->
               Buffer.add_string buf "## Build Log\n\n";
               Buffer.add_string buf (Printf.sprintf "- **Log file**: `%s`\n" (Filename.basename path));
               Buffer.add_string buf (Printf.sprintf "- **Duration**: %.2fs\n" build_duration);
               Buffer.add_string buf (Printf.sprintf "- **Failed nodes**: %d\n" (List.length errored_nodes));
               Buffer.add_char buf '\n'
           | None ->
               let msg = match log_search_msg with
                 | Some s -> s
                 | None ->
                     if which_log_opt <> None then
                       "No matching build log found for the given pattern."
                     else if total > 0 then
                       "No build log found. Run `build_pipeline(p)` first."
                     else ""
               in
               if msg <> "" then
                 Buffer.add_string buf (Printf.sprintf "> **Note**: %s\n\n" msg)
          );

          (match log_parse_msg with
           | Some msg ->
               Buffer.add_string buf (Printf.sprintf "> **Warning**: %s\n\n" msg)
           | None -> ()
          );

          (match Builder_utils.write_file file_path (Buffer.contents buf) with
           | Ok () -> VString file_path
           | Error msg ->
               Error.make_error FileError
                 (Printf.sprintf "Failed to write pipeline report to `%s`: %s" file_path msg))
        with
        | Failure msg ->
            Error.make_error FileError msg
        | e ->
            Error.make_error RuntimeError
              (Printf.sprintf "Unexpected error generating pipeline report: %s" (Printexc.to_string e)))

      | (_, other) ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_report` expects a Pipeline, but got %s."
               (Utils.type_name other))
  in
  Env.add "pipeline_report" (make_builtin_named ~name:"pipeline_report" ~variadic:true 1 report_fn) env
