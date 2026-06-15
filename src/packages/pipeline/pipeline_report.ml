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

let truncate_message msg =
  let max_len = 100 in
  let cleaned = String.trim msg in
  if String.length cleaned > max_len then
    String.sub cleaned 0 max_len ^ "..."
  else
    cleaned

let escape_markdown_table s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '\n' -> Buffer.add_char buf ' '
    | '|' -> Buffer.add_string buf "\\|"
    | c -> Buffer.add_char buf c
  ) s;
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
  | Some _ -> Built
  | None -> Unbuilt

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

let log_entry_error_message name log_entries_map =
  match log_entries_map with
  | Some entries ->
      (match List.assoc_opt name entries with
       | Some (_, _, _, err_msg_opt, err_code_opt, _) ->
           (match err_msg_opt, err_code_opt with
            | Some msg, Some code when code <> "" -> Some (code ^ ": " ^ msg)
            | Some msg, _ -> Some msg
            | None, Some code when code <> "" -> Some code
            | _ -> None)
       | None -> None)
  | None -> None

let node_error_message name p log_entries_map =
  let err_opt =
    match List.assoc_opt name p.p_node_diagnostics with
    | Some d -> d.nd_error
    | None -> None
  in
  match err_opt with
  | Some e -> Some (e.ne_kind ^ ": " ^ e.ne_message)
  | None -> log_entry_error_message name log_entries_map

let node_warning_messages name p =
  match List.assoc_opt name p.p_node_diagnostics with
  | Some d -> List.map (fun w -> w.nw_message) d.nd_warnings
  | None -> []

let node_warning_entries name p log_entries_map =
  match List.assoc_opt name p.p_node_diagnostics with
  | Some d when d.nd_warnings <> [] ->
      List.map (fun w -> (w.nw_kind, w.nw_message)) d.nd_warnings
  | _ ->
      match log_entries_map with
      | Some entries ->
          (match List.assoc_opt name entries with
           | Some (_, path, has_warnings, _, _, _) when has_warnings && path <> "" ->
               let warnings_path = Filename.concat (Filename.dirname path) "warnings" in
               let warns = Builder_read_node.parse_node_warnings warnings_path in
               List.map (fun w -> (w.nw_kind, w.nw_message)) warns
           | _ -> [])
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

let generate_dag_table p depths =
  let buf = Buffer.create 512 in
  Buffer.add_string buf "| Node | Runtime | Depth | Dependencies |\n";
  Buffer.add_string buf "|------|---------|-------|-------------|\n";
  let sorted = List.sort (fun (n1, _) (n2, _) ->
    let d1 = node_depth n1 depths in
    let d2 = node_depth n2 depths in
    Stdlib.compare d1 d2
  ) p.p_exprs in
  List.iter (fun (name, _) ->
    let rt = node_runtime name p in
    let d = node_depth name depths in
    let deps = match List.assoc_opt name p.p_deps with
      | Some ds -> String.concat ", " ds
      | None -> "—"
    in
    Buffer.add_string buf (Printf.sprintf "| %s | %s | %d | %s |\n"
      (escape_markdown_table name) (escape_markdown_table rt) d (escape_markdown_table deps))
  ) sorted;
  Buffer.contents buf

let generate_mermaid_web p errored_names warned_names built_names =
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
  let buf = Buffer.create 512 in
  Buffer.add_string buf "graph LR\n";
  Buffer.add_string buf "  classDef errored fill:#fdd,stroke:#c00,color:#c00;\n";
  Buffer.add_string buf "  classDef warned fill:#ffe,stroke:#f90,color:#960;\n";
  Buffer.add_string buf "  classDef built fill:#dfd,stroke:#090,color:#090;\n";
  List.iter (fun (name, _) ->
    let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
    let id = get_id name in
    let cls = if List.mem name errored_names then ":::errored"
              else if List.mem name warned_names then ":::warned"
              else if List.mem name built_names then ":::built"
              else ""
    in
    Buffer.add_string buf (Printf.sprintf "  %s[\"%s [%s]\"]%s\n" id name runtime cls)
  ) p.p_exprs;
  List.iter (fun (name, deps) ->
    let name_id = get_id name in
    List.iter (fun dep ->
      let dep_id = get_id dep in
      Buffer.add_string buf (Printf.sprintf "  %s --> %s\n" dep_id name_id)
    ) deps
  ) p.p_deps;
  List.iter (fun (name, _) ->
    let id = get_id name in
    let prefix = if List.mem name errored_names then "errored"
                 else if List.mem name built_names then "built"
                 else "unbuilt"
    in
    Buffer.add_string buf (Printf.sprintf "  click %s href \"#%s-%s\" _self\n" id prefix name)
  ) p.p_exprs;
  Buffer.contents buf

let html_escape s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '&' -> Buffer.add_string buf "&amp;"
    | '<' -> Buffer.add_string buf "&lt;"
    | '>' -> Buffer.add_string buf "&gt;"
    | '"' -> Buffer.add_string buf "&quot;"
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let generate_html_report ~total ~built_nodes ~unbuilt_nodes ~errored_nodes ~warned_nodes
    ~depths ~p ~log_entries_map ~log_path ~log_search_msg ~log_parse_msg
    ~build_duration ~which_log_opt =
  let b = Buffer.create 4096 in
  let esc = html_escape in

  Buffer.add_string b "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n";
  Buffer.add_string b "<meta charset=\"utf-8\">\n";
  Buffer.add_string b "<title>Pipeline Report</title>\n";
  Buffer.add_string b "<script src=\"https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js\"></script>\n";
  Buffer.add_string b "<style>\n";
  Buffer.add_string b "  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 960px; margin: 0 auto; padding: 20px; background: #fff; color: #333; }\n";
  Buffer.add_string b "  h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 8px; }\n";
  Buffer.add_string b "  h2 { color: #34495e; margin-top: 32px; padding: 4px 8px; border-radius: 4px; }\n";
  Buffer.add_string b "  h2.section-built { background: #e8f5e9; border-left: 4px solid #4caf50; }\n";
  Buffer.add_string b "  h2.section-unbuilt { background: #f5f5f5; border-left: 4px solid #9e9e9e; }\n";
  Buffer.add_string b "  h2.section-errored { background: #ffebee; border-left: 4px solid #f44336; }\n";
  Buffer.add_string b "  h2.section-warned { background: #fff8e1; border-left: 4px solid #ff9800; }\n";
  Buffer.add_string b "  table { border-collapse: collapse; width: 100%; margin: 12px 0; }\n";
  Buffer.add_string b "  th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #ddd; }\n";
  Buffer.add_string b "  th { background: #f8f9fa; font-weight: 600; }\n";
  Buffer.add_string b "  tr.errored { background: #ffebee; }\n";
  Buffer.add_string b "  tr.warned { background: #fff8e1; }\n";
  Buffer.add_string b "  tr.built { background: #f1f8e9; }\n";
  Buffer.add_string b "  .mermaid { text-align: center; margin: 20px 0; }\n";
  Buffer.add_string b "  .note { background: #e3f2fd; border-left: 4px solid #2196f3; padding: 8px 16px; margin: 12px 0; border-radius: 4px; }\n";
  Buffer.add_string b "  .warning-note { background: #fff3e0; border-left: 4px solid #ff9800; padding: 8px 16px; margin: 12px 0; border-radius: 4px; }\n";
  Buffer.add_string b "  @media (prefers-color-scheme: dark) { body { background: #1a1a2e; color: #e0e0e0; } th { background: #2a2a3e; } }\n";
  Buffer.add_string b "</style>\n</head>\n<body>\n";

  Buffer.add_string b "<h1>Pipeline Report</h1>\n";
  Buffer.add_string b (Printf.sprintf "<p><strong>Generated</strong>: %s</p>\n" (timestamp_string ()));

  Buffer.add_string b "<h2>Overview</h2>\n";
  Buffer.add_string b "<table>\n<tr><th>Metric</th><th>Count</th></tr>\n";
  Buffer.add_string b (Printf.sprintf "<tr><td>Total Nodes</td><td>%d</td></tr>\n" total);
  Buffer.add_string b (Printf.sprintf "<tr><td>Built</td><td>%d</td></tr>\n" (List.length built_nodes));
  Buffer.add_string b (Printf.sprintf "<tr><td>Unbuilt</td><td>%d</td></tr>\n" (List.length unbuilt_nodes));
  Buffer.add_string b (Printf.sprintf "<tr class=\"errored\"><td>Errored</td><td>%d</td></tr>\n" (List.length errored_nodes));
  Buffer.add_string b (Printf.sprintf "<tr class=\"warned\"><td>Warnings</td><td>%d</td></tr>\n" (List.length warned_nodes));
  Buffer.add_string b "</table>\n";

  Buffer.add_string b "<h2>Dependency Graph</h2>\n";
  Buffer.add_string b "<div class=\"mermaid\">\n";
  Buffer.add_string b (generate_mermaid_web p errored_nodes warned_nodes built_nodes);
  Buffer.add_string b "</div>\n";

  let emit_section title section_class_id nodes columns ~empty_msg =
    let node_class = match section_class_id with
      | "errored" -> "errored" | "warned" -> "warned" | "built" -> "built" | _ -> ""
    in
    Buffer.add_string b (Printf.sprintf "<h2 class=\"section-%s\" id=\"%s\">%s (%d)</h2>\n"
      section_class_id section_class_id title (List.length nodes));
    if nodes = [] then
      Buffer.add_string b (Printf.sprintf "<p><em>%s</em></p>\n" empty_msg)
    else begin
      Buffer.add_string b "<table>\n";
      Buffer.add_string b "<tr><th>Name</th>";
      if List.mem "runtime" columns then Buffer.add_string b "<th>Runtime</th>";
      if List.mem "depth" columns then Buffer.add_string b "<th>Depth</th>";
      if List.mem "status" columns then Buffer.add_string b "<th>Status</th>";
      if List.mem "error" columns then Buffer.add_string b "<th>Error</th>";
      if List.mem "warning" columns then Buffer.add_string b "<th>Warning</th>";
      Buffer.add_string b "</tr>\n";
      List.iter (fun name ->
        let row_id = Printf.sprintf "%s-%s" section_class_id name in
        Buffer.add_string b (Printf.sprintf "<tr id=\"%s\" class=\"%s\">" row_id node_class);
        Buffer.add_string b (Printf.sprintf "<td>%s</td>" (esc name));
        if List.mem "runtime" columns then
          Buffer.add_string b (Printf.sprintf "<td>%s</td>" (esc (node_runtime name p)));
        if List.mem "depth" columns then
          Buffer.add_string b (Printf.sprintf "<td>%d</td>" (node_depth name depths));
        if List.mem "status" columns then
          Buffer.add_string b (Printf.sprintf "<td>%s</td>" (esc (get_node_status_str name log_entries_map)));
        if List.mem "error" columns then begin
          let msg = match node_error_message name p log_entries_map with
            | Some m -> truncate_message m | None -> "Unknown error" in
          Buffer.add_string b (Printf.sprintf "<td>%s</td>" (esc msg))
        end;
        if List.mem "warning" columns then begin
          let entries = node_warning_entries name p log_entries_map in
          let msg = match entries with
            | [(kind, m)] -> truncate_message (kind ^ ": " ^ m)
            | (kind, m) :: _ -> truncate_message (kind ^ ": " ^ m) ^ " (+" ^ string_of_int (List.length entries - 1) ^ " more)"
            | [] -> "Warning flagged in build log."
          in
          Buffer.add_string b (Printf.sprintf "<td>%s</td>" (esc msg))
        end;
        Buffer.add_string b "</tr>\n"
      ) nodes;
      Buffer.add_string b "</table>\n"
    end
  in

  emit_section "Built Nodes" "built" built_nodes ["runtime"; "depth"; "status"] ~empty_msg:"No nodes built yet.";
  emit_section "Unbuilt Nodes" "unbuilt" unbuilt_nodes ["runtime"; "depth"] ~empty_msg:"All nodes have been built.";
  emit_section "Errored Nodes" "errored" errored_nodes ["error"] ~empty_msg:"No errors.";
  emit_section "Nodes with Warnings" "warned" warned_nodes ["warning"] ~empty_msg:"No warnings.";

  (match log_path with
   | Some path ->
       Buffer.add_string b "<h2>Build Log</h2>\n";
       Buffer.add_string b (Printf.sprintf "<p><strong>Log file</strong>: <code>%s</code></p>\n" (Filename.basename path));
       Buffer.add_string b (Printf.sprintf "<p><strong>Duration</strong>: %.2fs</p>\n" build_duration);
       Buffer.add_string b (Printf.sprintf "<p><strong>Failed nodes</strong>: %d</p>\n" (List.length errored_nodes))
   | None ->
       let msg = match log_search_msg with
         | Some s -> s
         | None ->
             if which_log_opt <> None then "No matching build log found for the given pattern."
             else if total > 0 then "No build log found. Run `build_pipeline(p)` first."
             else ""
       in
       if msg <> "" then
         Buffer.add_string b (Printf.sprintf "<div class=\"note\">%s</div>\n" (esc msg))
  );
  (match log_parse_msg with
   | Some msg -> Buffer.add_string b (Printf.sprintf "<div class=\"warning-note\">%s</div>\n" (esc msg))
   | None -> ()
  );

  Buffer.add_string b "<script>mermaid.initialize({ startOnLoad: true });</script>\n";
  Buffer.add_string b "</body>\n</html>\n";
  Buffer.contents b

(*
--# Generate Pipeline Report
--#
--# Generates a report summarizing the pipeline's current status,
--# dependency graph, built nodes, unbuilt nodes, and errored/warned nodes.
--# When target is "ssh" (default), writes a Markdown file with plain-text tables.
--# When target is "web", writes a self-contained HTML file with an interactive
--# Mermaid diagram, color-coded sections, and clickable nodes.
--#
--# @name pipeline_report
--# @param p :: Pipeline The pipeline to report on.
--# @param which_log :: String (Optional) Regex to select a specific build log.
--# @param file :: String (Optional) Output file path. Defaults to `_pipeline/pipeline_report_<timestamp>.md` (ssh) or `.html` (web).
--# @param target :: String = "ssh" Output format. "ssh" for Markdown, "web" for HTML.
--# @return :: String The path to the generated report file.
--# @example
--#   pipeline_report(p)
--#   pipeline_report(p, target = "web")
--#   pipeline_report(p, target = "web", file = "report.html")
--#   pipeline_report(p, which_log = "20260615")
--# @family pipeline
--# @export
--*)
let register env =
  let report_fn named_args _env =
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["p"; "which_log"; "file"; "target"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "pipeline_report: unknown argument '%s'" k)
    | None when positional_count > 4 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `pipeline_report` accepts at most 4 positional arguments but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (_, which_log_val) = get_arg "which_log" 2 (VNA NAGeneric) named_args in
        let (_, file_val) = get_arg "file" 3 (VNA NAGeneric) named_args in
        let (_, target_val) = get_arg "target" 4 (VString "ssh") named_args in

        let which_log_opt = match which_log_val with
          | VString s when String.length s > 0 -> Some s
          | VSymbol s when String.length s > 0 -> Some s
          | _ -> None
        in
        let target_res =
          match target_val with
          | VString s when s = "ssh" || s = "web" -> Ok s
          | VString s ->
              Error (Error.value_error
                (Printf.sprintf "Function `pipeline_report` target must be \"ssh\" or \"web\", but got \"%s\". Use `target = \"ssh\"` for plain-text reports or `target = \"web\"` for HTML reports." s))
          | other ->
              Error (Error.type_error
                (Printf.sprintf "Function `pipeline_report` target must be a string: \"ssh\" or \"web\", but got %s." (Utils.type_name other)))
        in
        (match target_res with
         | Error e -> e
         | Ok target ->
            let default_ext = if target = "web" then ".html" else ".md" in
            let file_path_res =
              match file_val with
              | VString s when String.length s > 0 ->
                  let dir = Filename.dirname s in
                  if dir <> "" && dir <> "." then
                    (try
                       Builder_utils.ensure_dir dir;
                       Ok s
                     with e ->
                       Error (Error.make_error FileError
                         (Printf.sprintf "Cannot create directory `%s` for pipeline report: %s"
                            dir (Printexc.to_string e))))
                  else
                    Ok s
              | _ ->
                  (try
                     Builder_utils.ensure_pipeline_dir ();
                     Ok (Filename.concat Builder_utils.pipeline_dir
                       (Printf.sprintf "pipeline_report_%s%s" (timestamp_file_suffix ()) default_ext))
                   with e ->
                     Error (Error.make_error FileError
                       (Printf.sprintf "Cannot create pipeline directory: %s" (Printexc.to_string e))))
            in
            (match file_path_res with
             | Error e -> e
             | Ok file_path ->
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

                  let result = match target with
                  | "web" ->
                      let html = generate_html_report ~total ~built_nodes ~unbuilt_nodes ~errored_nodes ~warned_nodes
                        ~depths ~p ~log_entries_map ~log_path ~log_search_msg ~log_parse_msg
                        ~build_duration ~which_log_opt in
                      (match Builder_utils.write_file file_path html with
                       | Ok () -> VString file_path
                       | Error msg ->
                           Error.make_error FileError
                             (Printf.sprintf "Failed to write pipeline report to `%s`: %s" file_path msg))
                  | _ ->
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
                      Buffer.add_string buf (generate_dag_table p depths);
                      Buffer.add_char buf '\n';

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
                        Buffer.add_string buf "| Name | Error |\n";
                        Buffer.add_string buf "|------|-------|\n";
                        List.iter (fun name ->
                          let msg = match node_error_message name p log_entries_map with
                            | Some m -> truncate_message m
                            | None -> "Unknown error"
                          in
                          Buffer.add_string buf (Printf.sprintf "| %s | %s |\n"
                            (escape_markdown_table name) (escape_markdown_table msg))
                        ) errored_nodes;
                        Buffer.add_char buf '\n'
                      end;

                      Buffer.add_string buf (Printf.sprintf "## Nodes with Warnings (%d)\n\n" (List.length warned_nodes));
                      if warned_nodes = [] then
                        Buffer.add_string buf "_No warnings._\n\n"
                      else begin
                        Buffer.add_string buf "| Name | Warning |\n";
                        Buffer.add_string buf "|------|---------|\n";
                        List.iter (fun name ->
                          let entries = node_warning_entries name p log_entries_map in
                          if entries = [] then
                            Buffer.add_string buf (Printf.sprintf "| %s | Warning flagged in build log. |\n"
                              (escape_markdown_table name))
                          else
                            List.iter (fun (kind, msg) ->
                              let display = truncate_message (kind ^ ": " ^ msg) in
                              Buffer.add_string buf (Printf.sprintf "| %s | %s |\n"
                                (escape_markdown_table name) (escape_markdown_table display))
                            ) entries
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
                  in
                  result
                with e ->
                  Error.make_error RuntimeError
                    (Printf.sprintf "Unexpected error generating pipeline report: %s" (Printexc.to_string e)))))

      | (_, other) ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_report` expects a Pipeline, but got %s."
               (Utils.type_name other))
  in
  Env.add "pipeline_report" (make_builtin_named ~name:"pipeline_report" ~variadic:true 1 report_fn) env
