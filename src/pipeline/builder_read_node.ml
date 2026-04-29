(* src/pipeline/builder_read_node.ml *)
open Ast
open Builder_utils
open Builder_logs

let parse_node_warnings path =
  if Sys.file_exists path then
    match Serialization.read_json path with
    | Ok (VList items) ->
        List.filter_map (fun (_, v) ->
          match v with
          | VString msg ->
              Some {
                nw_kind = "Generic";
                nw_fn = "unknown";
                nw_na_count = 0;
                nw_na_indices = [];
                nw_message = msg;
                nw_source = WarningOwn;
              }
          | VDict d ->
              let get_s k = match List.assoc_opt k d with Some (VString s) -> s | _ -> "" in
              let get_i k = match List.assoc_opt k d with Some (VInt i) -> i | _ -> 0 in
              Some {
                nw_kind = get_s "kind" |> (fun s -> if s = "" then "Generic" else s);
                nw_fn = get_s "fn" |> (fun s -> if s = "" then "unknown" else s);
                nw_na_count = get_i "na_count";
                nw_na_indices = (match List.assoc_opt "na_indices" d with Some (VList l) -> List.filter_map (fun (_, v) -> match v with VInt i -> Some i | _ -> None) l | _ -> []);
                nw_message = get_s "message";
                nw_source = WarningOwn;
              }
          | _ -> None
        ) items
    | _ -> []
  else []

let is_error_class = function
  | "VError" | "Error" -> true
  | _ -> false

let generic_logged_node_error name cn =
  {
    ne_kind = cn.cn_class;
    ne_fn = "unknown";
    ne_message = Printf.sprintf "Node `%s` failed during pipeline build." name;
    ne_na_count = 0;
  }

let node_error_of_logged_value name cn value =
  if is_error_class cn.cn_class then
    match value with
    | VError e ->
        Some {
          ne_kind = Utils.error_code_to_string e.code;
          ne_fn = "unknown";
          ne_message = e.message;
          ne_na_count = e.na_count;
        }
    | _ -> Some (generic_logged_node_error name cn)
  else
    None

let logged_node_diagnostics ?value name cn =
  let node_dir = Filename.dirname cn.cn_path in
  let warnings_path = Filename.concat node_dir "warnings" in
  let warnings = parse_node_warnings warnings_path in
  let error =
    match value with
    | Some value -> node_error_of_logged_value name cn value
    | None ->
        if is_error_class cn.cn_class then
          match Serialization.read_verror_json cn.cn_path with
          | Ok value -> node_error_of_logged_value name cn value
          | Error _ -> Some (generic_logged_node_error name cn)
        else
          None
  in
  {
    nd_warnings = warnings;
    nd_error = error;
    nd_warnings_suppressed = false;
    nd_recovered = false;
    nd_upstream_errors = [];
  }

let wrap_with_diagnostics name cn v =
  VNodeResult { v; node_name = name; diagnostics = logged_node_diagnostics ~value:v name cn }

(* Add node_name to the error context unless it is already present. *)
let add_node_name_context name context =
  if List.exists (fun (k, _) -> k = "node_name") context then context
  else ("node_name", VString name) :: context

let is_visual_metadata_class = function
  | "ggplot" | "matplotlib" | "plotnine" | "seaborn" | "plotly" | "altair" -> true
  | _ -> false

let read_standard_node_value cn =
  if cn.cn_serializer = "json" then
    match Serialization.read_json cn.cn_path with
    | Ok v -> v
    | Error _ -> VComputedNode cn
  else if cn.cn_serializer = "arrow" then
    match Arrow_io.read_ipc cn.cn_path with
    | Ok v -> VDataFrame { arrow_table = v; group_keys = [] }
    | Error _ -> VComputedNode cn
  else if cn.cn_serializer = "csv" then
    (try
       let ch = open_in cn.cn_path in
       let content = really_input_string ch (in_channel_length ch) in
       close_in ch;
       T_read_csv.parse_csv_string content
     with _ ->
       VComputedNode cn)
  else if cn.cn_serializer = "pmml" then
    match Pmml_utils.read_pmml cn.cn_path with
    | Ok v -> Pmml_utils.attach_source_path cn.cn_path v
    | Error _ -> VComputedNode cn
  else
    VComputedNode cn

let read_logged_node_value name cn =
  if cn.Ast.cn_runtime = "T"
     && (cn.Ast.cn_serializer = "default" || cn.Ast.cn_serializer = "serialize")
  then
    (match Serialization.deserialize_from_file cn.Ast.cn_path with
     | Ok v -> v
     | Error msg -> Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read node `%s` from `%s`: %s" name cn.Ast.cn_path msg))
  else if cn.Ast.cn_serializer = "json" then
    (match Serialization.read_json cn.Ast.cn_path with
     | Ok v -> v
     | Error msg -> Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read JSON node `%s` from `%s`: %s" name cn.Ast.cn_path msg))
  else if cn.Ast.cn_serializer = "arrow" then
    (match Arrow_io.read_ipc cn.Ast.cn_path with
     | Ok v -> VDataFrame { arrow_table = v; group_keys = [] }
     | Error msg -> Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read Arrow node `%s` from `%s`: %s" name cn.Ast.cn_path msg))
  else if cn.Ast.cn_serializer = "csv" then
    (try
       let ch = open_in cn.Ast.cn_path in
       let content = really_input_string ch (in_channel_length ch) in
       close_in ch;
       T_read_csv.parse_csv_string content
     with exn ->
       Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read CSV node `%s` from `%s`: %s" name cn.Ast.cn_path (Printexc.to_string exn)))
  else if cn.Ast.cn_serializer = "pmml" then
    (match Pmml_utils.read_pmml cn.Ast.cn_path with
     | Ok v -> Pmml_utils.attach_source_path cn.Ast.cn_path v
     | Error msg -> Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read PMML node `%s` from `%s`: %s" name cn.Ast.cn_path msg))
  else
    VComputedNode cn

(* Best-effort deserialization for nodes exposed through T_NODE_<name> in the
   Nix sandbox: recover structured VError artifacts when possible and otherwise
   fall back to the computed node handle. *)
let read_env_node_value name cn =
  if is_error_class cn.cn_class then
    match Serialization.read_verror_json cn.cn_path with
    | Ok (VError e) -> VError { e with context = add_node_name_context name e.context }
    | Ok v -> v
    | Error _ -> VComputedNode cn
  else if is_visual_metadata_class cn.cn_class then
    let viz_path = Filename.concat (Filename.dirname cn.cn_path) "viz" in
    if Sys.file_exists viz_path then
      match Serialization.read_json viz_path with
      | Ok v -> v
      | Error _ -> VComputedNode cn
    else
      read_standard_node_value cn
  else
    read_standard_node_value cn

let candidate_logs ?which_log () =
  match which_log with
  | Some _ -> get_all_logs ()
  | None -> get_logs ()

let logged_node_value name cn =
  if is_error_class cn.Ast.cn_class then
    (match Serialization.read_verror_json cn.Ast.cn_path with
     | Ok (VError e) ->
          VError { e with context = add_node_name_context name e.context }
     | Ok v -> v
     | Error msg ->
         Error.make_error
           ~context:[("runtime", VString cn.Ast.cn_runtime)]
           FileError
           (Printf.sprintf
              "Failed to read Error node `%s` from `%s`: %s"
              name
              cn.Ast.cn_path
              msg))
  else if is_visual_metadata_class cn.cn_class then
    let viz_path = Filename.concat (Filename.dirname cn.cn_path) "viz" in
    if Sys.file_exists viz_path then
      (match Serialization.read_json viz_path with
       | Ok v -> v
       | Error msg ->
           Error.make_error
             ~context:[("runtime", VString cn.cn_runtime)]
             FileError
             (Printf.sprintf
                "Failed to read plot metadata node `%s` from `%s`: %s"
                name
                viz_path
                msg))
    else
      read_logged_node_value name cn
  else
    read_logged_node_value name cn

let pipeline_matches_logged_entries (p : Ast.pipeline_result) entries =
  let pipeline_node_names = List.map fst p.p_nodes in
  let runtimes = p.p_runtimes in
  let runtime_matches_logged_entry (name, cn) =
    match List.assoc_opt name runtimes with
    | Some runtime -> runtime = cn.cn_runtime
    | None -> true
  in
  let expected = List.sort String.compare pipeline_node_names in
  let actual = entries |> List.map fst |> List.sort String.compare in
  expected = actual
  && List.for_all runtime_matches_logged_entry entries

let matching_pipeline_log_entries ?which_log (p : Ast.pipeline_result) =
  let logs = candidate_logs ?which_log () in
  let try_log log_file =
    match read_log (Filename.concat pipeline_dir log_file) with
    | Ok entries when pipeline_matches_logged_entries p entries -> Some entries
    | _ -> None
  in
  match which_log with
  | None ->
      (* Fast path: in the common case the most recent log is the correct
         match. Try it first to avoid parsing every log in the directory. *)
      (match logs with
       | [] -> None
       | newest :: rest ->
           (match try_log newest with
            | Some _ as hit -> hit
            | None -> List.find_map try_log rest))
  | Some pattern ->
      let candidate_log_files =
        try
          let re = Str.regexp pattern in
          Some
            (List.filter
               (fun log ->
                 try
                   let _ = Str.search_forward re log 0 in
                   true
                 with Not_found -> false)
               logs)
        with Failure _ ->
          None
      in
      (match candidate_log_files with
       | Some log_files -> List.find_map try_log log_files
       | None -> None)

let merge_pipeline_nodes_with_latest_log ?which_log (p : Ast.pipeline_result) =
  let should_overlay_value = function
    | VComputedNode cn -> cn.cn_path = "<unbuilt>" || cn.cn_path = ""
    | _ -> false
  in
  match matching_pipeline_log_entries ?which_log p with
  | Some entries ->
      List.map
        (fun (name, value) ->
          match value, List.assoc_opt name entries with
          | _, None -> (name, value)
          | value, Some cn when should_overlay_value value ->
              (name, logged_node_value name cn)
          | _ -> (name, value))
        p.p_nodes
  | None ->
      p.p_nodes

let read_node ?which_log name =
  let env_name = "T_NODE_" ^ name in
  match Sys.getenv_opt env_name with
  | Some path when which_log = None ->
      let artifact_path = Filename.concat path "artifact" in
      let class_path = Filename.concat path "class" in
      if Sys.file_exists artifact_path && Sys.file_exists class_path then
        let ch = open_in class_path in
        let cls = try input_line ch |> String.trim with _ -> "unknown" in
        close_in ch;
        
        let cn = {
          cn_name = name;
          cn_runtime = "unknown";
          cn_path = artifact_path;
          cn_serializer = (
            match cls with
            | "ArrowDataFrame" | "data.frame" | "DataFrame" | "Table" -> "arrow"
            | "JSON" | "VDict" | "VList" | "list" | "dict" -> "json"
            | "PMML" | "pmml" -> "pmml"
            | _ -> "default"
           );
          cn_class = cls;
          cn_dependencies = [];
        } in
        
        let v = read_env_node_value name cn in
        wrap_with_diagnostics name cn v
      else
        Error.make_error FileError (Printf.sprintf "read_node: node `%s` found in environment as %s, but artifact is missing." name path)
  | _ ->
      let logs = candidate_logs ?which_log () in
  let log_file_result =
    match which_log with
    | None -> Ok (match logs with [] -> None | l :: _ -> Some l)
    | Some pattern ->
        (try
          Ok (List.find_opt (fun l ->
            try let _ = Str.search_forward (Str.regexp pattern) l 0 in true
            with Not_found -> false
          ) logs)
        with Failure msg ->
          Error msg)
  in
  match log_file_result with
  | Error msg ->
      Error.type_error (Printf.sprintf "read_node: invalid regex pattern for 'which_log': %s" msg)
  | Ok None ->
      let suffix = match which_log with
        | Some pat -> " matching \"" ^ pat ^ "\""
        | None -> ""
      in
      Error.make_error FileError
        (Printf.sprintf "No build logs found in `_pipeline/`%s. Run `populate_pipeline(p, build=true)` first." suffix)
  | Ok (Some f) ->
      match read_log (Filename.concat pipeline_dir f) with
       | Error msg -> Error.make_error FileError (Printf.sprintf "Failed to read log `%s`: %s" f msg)
       | Ok entries ->
           (match List.assoc_opt name entries with
           | None -> Error.make_error KeyError (Printf.sprintf "Node `%s` not found in build log `%s`." name f)
           | Some cn ->
               let v = logged_node_value name cn in
               wrap_with_diagnostics name cn v)

let merge_pipeline_node_diagnostics_with_latest_log ?which_log (p : Ast.pipeline_result) =
  let merge_diagnostics base overlay =
    {
      nd_warnings =
        if base.nd_warnings <> [] then base.nd_warnings else overlay.nd_warnings;
      nd_error =
        (match base.nd_error with
         | Some _ -> base.nd_error
         | None -> overlay.nd_error);
      nd_warnings_suppressed = base.nd_warnings_suppressed;
      nd_recovered = base.nd_recovered;
      nd_upstream_errors = base.nd_upstream_errors;
    }
  in
  match matching_pipeline_log_entries ?which_log p with
  | Some entries ->
      List.map
        (fun name ->
          let base =
            match List.assoc_opt name p.p_node_diagnostics with
            | Some diagnostics -> diagnostics
            | None -> Ast.Utils.empty_node_diagnostics
          in
          match List.assoc_opt name entries with
          | Some cn ->
              let overlay = logged_node_diagnostics name cn in
              (name, merge_diagnostics base overlay)
          | None ->
              (name, base))
        (List.map fst p.p_nodes)
  | None ->
      p.p_node_diagnostics
