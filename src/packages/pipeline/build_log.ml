open Ast

let clean_and_truncate_message msg =
  let lines = String.split_on_char '\n' msg 
              |> List.map String.trim 
              |> List.filter (fun s -> s <> "") in
  let msg_line =
    match List.rev lines with
    | [] -> ""
    | last :: _ -> last
  in
  if String.length msg_line > 100 then
    String.sub msg_line 0 97 ^ "..."
  else
    msg_line

let find_latest_matching_log_path (p : Ast.pipeline_result) =
  let logs = Builder.get_logs () in
  let try_log log_file =
    let full_path = Filename.concat Builder.pipeline_dir log_file in
    match Builder.read_log full_path with
    | Ok entries when Builder_read_node.pipeline_matches_logged_entries p entries -> Some full_path
    | _ -> None
  in
  List.find_map try_log logs

let find_all_matching_log_paths (p : Ast.pipeline_result) =
  let logs = Builder.get_logs () in
  List.filter_map (fun log_file ->
    let full_path = Filename.concat Builder.pipeline_dir log_file in
    match Builder.read_log full_path with
    | Ok entries when Builder_read_node.pipeline_matches_logged_entries p entries -> Some full_path
    | _ -> None
  ) logs

(*
--# Retrieve Build Log for Pipeline
--#
--# Returns the `BuildLog` of the latest Nix build for the given pipeline.
--# Includes node-level status records, total duration, failed node names, and `out_path`.
--# Use `which_log` to read from a specific historical build ("time travel").
--#
--# @name build_log
--# @param pipeline :: Pipeline The pipeline to retrieve logs for.
--# @param which_log :: String (Optional) A regex pattern to match a specific build log filename.
--# @return :: BuildLog
--# @family pipeline
--# @export
*)
let build_log_fn named_args _env =
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> (true, v)
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
        else (false, default)
  in
  let named_keys = List.filter_map (fun (k, _) -> k) named_args in
  let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
  match List.find_opt (fun k -> not (List.mem k ["p"; "which_log"])) named_keys with
  | Some k -> Error.type_error (Printf.sprintf "build_log: unknown argument '%s'" k)
  | None when positional_count > 2 ->
      Error.make_error ArityError
        (Printf.sprintf "Function `build_log` accepts at most 2 positional arguments but received %d." positional_count)
  | None ->
    match get_arg "p" 1 (VNA NAGeneric) named_args with
    | (_, VPipeline p) ->
        let (_, which_log_val) = get_arg "which_log" 2 (VNA NAGeneric) named_args in
        let log_path_opt =
          match which_log_val with
          | VString pattern ->
              (try
                 let re = Str.regexp pattern in
                 let all_matches = find_all_matching_log_paths p in
                 List.find_map (fun path ->
                   let log_file = Filename.basename path in
                   try
                     let _ = Str.search_forward re log_file 0 in
                     Some path
                   with Not_found -> None
                 ) all_matches
               with Failure _ -> None)
          | VNA _ -> find_latest_matching_log_path p
          | _ -> None
        in
        if which_log_val <> VNA NAGeneric && log_path_opt = None then
          Error.make_error ValueError "Function `build_log` could not find any matching build log for the specified `which_log` regex pattern."
        else (
          match log_path_opt with
          | Some log_path -> Builder.parse_json_log_to_vbuildlog log_path
          | None -> Error.make_error FileError "No matching build log found for the pipeline. Run build_pipeline(p) first."
        )
    | _ -> Error.type_error "Function `build_log` expects a Pipeline."

(*
--# Tabulate Build Log as DataFrame
--#
--# Returns a DataFrame with columns `name`, `status`, and `duration` summarizing the build nodes.
--#
--# @name build_log_to_frame
--# @param log :: BuildLog The build log to tabulate.
--# @return :: DataFrame
--# @family pipeline
--# @export
*)
let build_log_to_frame_fn args _env =
  match args with
  | [VBuildLog bl] ->
      let nrows = List.length bl.bl_nodes in
      let arr_name = Array.make nrows None in
      let arr_status = Array.make nrows None in
      let arr_duration = Array.make nrows None in
      let arr_path = Array.make nrows None in
      List.iteri (fun i item ->
        match item with
        | VDict fields ->
            let name = match List.assoc_opt "name" fields with Some (VString s) -> Some s | _ -> None in
            let status = match List.assoc_opt "status" fields with Some (VString s) -> Some s | _ -> None in
            let duration = match List.assoc_opt "duration" fields with Some (VFloat f) -> Some f | _ -> None in
            let path = match List.assoc_opt "path" fields with Some (VString s) -> Some s | _ -> None in
            arr_name.(i) <- name;
            arr_status.(i) <- status;
            arr_duration.(i) <- duration;
            arr_path.(i) <- path;
        | _ -> ()
      ) bl.bl_nodes;
      let columns = [
        ("name", Arrow_table.StringColumn arr_name);
        ("status", Arrow_table.StringColumn arr_status);
        ("duration", Arrow_table.FloatColumn arr_duration);
        ("path", Arrow_table.StringColumn arr_path);
      ] in
      let arrow_table = Arrow_table.create columns nrows in
      VDataFrame { arrow_table; group_keys = [] }
  | [_] -> Error.type_error "Function `build_log_to_frame` expects a BuildLog."
  | _ -> Error.arity_error_named "build_log_to_frame" 1 (List.length args)

(*
--# Gather Pipeline Node Exceptions and Warnings
--#
--# Gathers all `VError` values and warning diagnostics from computed nodes of a built pipeline
--# and returns them as a structured DataFrame.
--#
--# @name collect_exceptions
--# @param pipeline :: Pipeline The built pipeline to gather exceptions from.
--# @return :: DataFrame A DataFrame with columns `node`, `status`, `code`, and `message`.
--# @family pipeline
--# @export
*)
let collect_exceptions_fn args _env =
  match args with
  | [VPipeline p] ->
      (match find_latest_matching_log_path p with
       | None ->
           let columns = [
             ("node", Arrow_table.StringColumn (Array.make 0 None));
             ("status", Arrow_table.StringColumn (Array.make 0 None));
             ("code", Arrow_table.StringColumn (Array.make 0 None));
             ("message", Arrow_table.StringColumn (Array.make 0 None));
           ] in
           let arrow_table = Arrow_table.create columns 0 in
           VDataFrame { arrow_table; group_keys = [] }
       | Some log_path ->
            let entries = ref [] in
            (try
               let json = Yojson.Safe.from_file log_path in
               let open Yojson.Safe.Util in
               let nodes = json |> member "nodes" |> to_list in
               List.iter (fun node_json ->
                 let name = node_json |> member "node" |> to_string in
                 let status = node_json |> member "status" |> to_string in
                 let path =
                   match node_json |> member "path" with
                   | `String s -> s
                   | _ -> ""
                 in
                 let class_val =
                   match node_json |> member "class" with
                   | `String s -> s
                   | _ -> ""
                 in
                 let has_warnings =
                   match node_json |> member "warnings" with
                   | `Bool b -> b
                   | `String s -> String.lowercase_ascii s = "true"
                   | _ -> false
                 in
                 if status = "Errored" then (
                   let err_code =
                     match node_json |> member "error_code" with
                     | `String s -> s
                     | _ -> "NixError"
                   in
                   let err_message =
                     match node_json |> member "error_message" with
                     | `String s -> s
                     | _ -> "Nix build failed."
                   in
                   let err_message_truncated = clean_and_truncate_message err_message in
                   entries := (name, "Error", err_code, err_message_truncated) :: !entries
                 ) else if status = "SoftFailed" || class_val = "VError" || class_val = "Error" then (
                   if path <> "" && Sys.file_exists path then (
                     match Serialization.read_verror_json path with
                     | Ok (VError e) ->
                         let msg_truncated = clean_and_truncate_message e.message in
                         entries := (name, "Error", Ast.Utils.error_code_to_string e.code, msg_truncated) :: !entries
                     | _ ->
                         entries := (name, "Error", class_val, "Node failed with a soft error.") :: !entries
                   ) else (
                     entries := (name, "Error", class_val, "Node failed with a soft error.") :: !entries
                   )
                 );
                 
                 (* Handle warnings *)
                 if has_warnings && path <> "" then (
                   let warnings_path = Filename.concat (Filename.dirname path) "warnings" in
                   if Sys.file_exists warnings_path then (
                     let warns = Builder_read_node.parse_node_warnings warnings_path in
                     List.iter (fun w ->
                       entries := (name, "Warning", w.nw_kind, w.nw_message) :: !entries
                     ) warns
                   )
                 )
               ) nodes
             with _ -> ());
            let entries = List.rev !entries in
           let nrows = List.length entries in
           let arr_node = Array.make nrows None in
           let arr_status = Array.make nrows None in
           let arr_code = Array.make nrows None in
           let arr_message = Array.make nrows None in
           List.iteri (fun i (node, status, code, message) ->
             arr_node.(i) <- Some node;
             arr_status.(i) <- Some status;
             arr_code.(i) <- Some code;
             arr_message.(i) <- Some message;
           ) entries;
           let columns = [
             ("node", Arrow_table.StringColumn arr_node);
             ("status", Arrow_table.StringColumn arr_status);
             ("code", Arrow_table.StringColumn arr_code);
             ("message", Arrow_table.StringColumn arr_message);
           ] in
           let arrow_table = Arrow_table.create columns nrows in
           VDataFrame { arrow_table; group_keys = [] })
  | [_] -> Error.type_error "Function `collect_exceptions` expects a Pipeline."
  | _ -> Error.arity_error_named "collect_exceptions" 1 (List.length args)



(*
--# Retrieve Build Log History for Pipeline
--#
--# Returns a summary DataFrame of all historical builds matching the current pipeline's node signature, ordered from most recent to oldest.
--#
--# @name build_log_history
--# @param pipeline :: Pipeline The pipeline to retrieve history for.
--# @param n :: Int (Optional) Limit to last N builds. Defaults to NA (no limit).
--# @param pattern :: String (Optional) A regex pattern to filter log filenames. Defaults to NA.
--# @return :: DataFrame Summary DataFrame of historical builds.
--# @family pipeline
--# @export
*)
let build_log_history_fn named_args _env =
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> (true, v)
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
        else (false, default)
  in
  let named_keys = List.filter_map (fun (k, _) -> k) named_args in
  let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
  match List.find_opt (fun k -> not (List.mem k ["p"; "n"; "pattern"])) named_keys with
  | Some k -> Error.type_error (Printf.sprintf "build_log_history: unknown argument '%s'" k)
  | None when positional_count > 3 ->
      Error.make_error ArityError
        (Printf.sprintf "Function `build_log_history` accepts at most 3 positional arguments but received %d." positional_count)
  | None ->
    match get_arg "p" 1 (VNA NAGeneric) named_args with
    | (_, VPipeline p) ->
        let (n_provided, n_val) = get_arg "n" 2 (VNA NAGeneric) named_args in
        let limit_opt =
          match n_val with
          | VInt limit when limit > 0 -> Some limit
          | VNA _ -> None
          | _ -> None
        in
        let (pattern_provided, pattern_val) = get_arg "pattern" 3 (VNA NAGeneric) named_args in
        let filter_by_pattern_opt =
          match pattern_val with
          | VString pat ->
              (try Some (Str.regexp pat)
               with Failure _ -> None)
          | _ -> None
        in
        if n_provided && limit_opt = None && n_val <> VNA NAGeneric then
          Error.type_error "Function `build_log_history` expects argument `n` to be a positive Int."
        else if pattern_provided && filter_by_pattern_opt = None && pattern_val <> VNA NAGeneric then
          Error.type_error "Function `build_log_history` expects argument `pattern` to be a valid regular expression String."
        else (
          let all_matches = find_all_matching_log_paths p in
          let matched_by_pattern =
            match filter_by_pattern_opt with
            | Some re ->
                List.filter (fun path ->
                  let log_file = Filename.basename path in
                  try
                    let _ = Str.search_forward re log_file 0 in
                    true
                  with Not_found -> false
                ) all_matches
            | None -> all_matches
          in
          let truncated_matches =
            match limit_opt with
            | Some limit ->
                let rec take n lst =
                  if n <= 0 then []
                  else
                    match lst with
                    | [] -> []
                    | x :: xs -> x :: take (n - 1) xs
                in
                take limit matched_by_pattern
            | None -> matched_by_pattern
          in
          let nrows = List.length truncated_matches in
          
          let arr_build_id = Array.make nrows None in
          let arr_timestamp = Array.make nrows None in
          let arr_duration = Array.make nrows None in
          let arr_n_nodes = Array.make nrows None in
          let arr_n_failed = Array.make nrows None in
          let arr_n_warnings = Array.make nrows None in
          let arr_out_path = Array.make nrows None in
          let arr_hash = Array.make nrows None in
          
          let open Yojson.Safe.Util in
          List.iteri (fun i log_path ->
            let build_id = i + 1 in
            arr_build_id.(i) <- Some build_id;
            (try
               let json = Yojson.Safe.from_file log_path in
               let timestamp =
                 match json |> member "timestamp" with
                 | `String s -> s
                 | _ ->
                     (* fallback: parse from filename *)
                     let base = Filename.basename log_path in
                     (try
                        let parts = String.split_on_char '_' base in
                        if List.length parts >= 4 then
                          List.nth parts 2 ^ "_" ^ List.nth parts 3
                        else
                          let stats = Unix.stat log_path in
                          let tm = Unix.localtime stats.Unix.st_mtime in
                          Printf.sprintf "%04d%02d%02d_%02d%02d%02d"
                            (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec
                      with _ -> "")
               in
               let hash =
                 match json |> member "hash" with
                 | `String s -> s
                 | _ -> ""
               in
               let out_path =
                 match json |> member "out_path" with
                 | `String s -> s
                 | _ -> ""
               in
               let duration =
                 match json |> member "duration" with
                 | `Float f -> f
                 | `Int i -> float_of_int i
                 | _ -> 0.0
               in
               let nodes =
                 match json |> member "nodes" with
                 | `List lst -> lst
                 | _ -> []
               in
               let n_nodes = List.length nodes in
               let n_failed =
                 List.fold_left (fun acc node_json ->
                   let status = match node_json |> member "status" with `String s -> s | _ -> "" in
                   if status = "Errored" || status = "SoftFailed" then acc + 1 else acc
                 ) 0 nodes
               in
               let n_warnings =
                 List.fold_left (fun acc node_json ->
                   let has_warnings =
                     match node_json |> member "warnings" with
                     | `Bool b -> b
                     | `String s -> String.lowercase_ascii s = "true"
                     | _ -> false
                   in
                   if has_warnings then acc + 1 else acc
                 ) 0 nodes
               in
               arr_timestamp.(i) <- Some timestamp;
               arr_duration.(i) <- Some duration;
               arr_n_nodes.(i) <- Some n_nodes;
               arr_n_failed.(i) <- Some n_failed;
               arr_n_warnings.(i) <- Some n_warnings;
               arr_out_path.(i) <- Some out_path;
               arr_hash.(i) <- Some hash;
             with _ -> ())
          ) truncated_matches;
          
          let columns = [
            ("build_id",   Arrow_table.IntColumn arr_build_id);
            ("timestamp",  Arrow_table.StringColumn arr_timestamp);
            ("duration",   Arrow_table.FloatColumn arr_duration);
            ("n_nodes",    Arrow_table.IntColumn arr_n_nodes);
            ("n_failed",   Arrow_table.IntColumn arr_n_failed);
            ("n_warnings", Arrow_table.IntColumn arr_n_warnings);
            ("out_path",   Arrow_table.StringColumn arr_out_path);
            ("hash",       Arrow_table.StringColumn arr_hash);
          ] in
          let arrow_table = Arrow_table.create columns nrows in
          VDataFrame { arrow_table; group_keys = [] }
        )
    | _ -> Error.type_error "Function `build_log_history` expects a Pipeline."

let get_cell (t : Arrow_table.t) (name : string) (row : int) : Ast.value =
  match Arrow_table.get_column t name with
  | None -> VNA NAGeneric
  | Some col ->
      (match col with
       | Arrow_table.IntColumn a ->
           if row < Array.length a then
             (match a.(row) with Some i -> VInt i | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.FloatColumn a ->
           if row < Array.length a then
             (match a.(row) with Some f -> VFloat f | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.BoolColumn a ->
           if row < Array.length a then
             (match a.(row) with Some b -> VBool b | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.StringColumn a ->
           if row < Array.length a then
             (match a.(row) with Some s -> VString s | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.DateColumn a ->
           if row < Array.length a then
             (match a.(row) with Some d -> VDate d | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.DatetimeColumn (a, tz) ->
           if row < Array.length a then
             (match a.(row) with Some dt -> VDatetime (dt, tz) | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.DictionaryColumn (indices, levels, _) ->
           if row < Array.length indices then
             (match indices.(row) with
              | Some idx ->
                  (match List.nth_opt levels idx with
                   | Some s -> VString s
                   | None -> VNA NAGeneric)
              | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.NAColumn _ -> VNA NAGeneric
       | Arrow_table.ListColumn _ -> VNA NAGeneric)

(*
--# Compare Node Outputs Across Builds
--#
--# Compares the artifact produced by a named node across two historical builds.
--# Dispatches to a type-appropriate comparison based on the node's serializer.
--#
--# @name node_diff
--# @param pipeline :: Pipeline The pipeline.
--# @param node :: String The node name.
--# @param build_a :: Int (Optional) Most recent build rank index (default 1).
--# @param build_b :: Int (Optional) Second most recent build rank index (default 2).
--# @return :: Dict A structured diff dictionary depending on the node's serializer type.
--# @family pipeline
--# @export
*)
let node_diff_fn named_args _env =
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> (true, v)
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
        else (false, default)
  in
  let resolve_build_path p val_arg arg_name =
    let all_matches = find_all_matching_log_paths p in
    let num_builds = List.length all_matches in
    match val_arg with
    | VInt idx ->
        if idx <= 0 then
          Error (Error.make_error ValueError (Printf.sprintf "Function `node_diff` expects `%s` to be a positive 1-indexed integer." arg_name))
        else if idx > num_builds then
          Error (Error.make_error ValueError (Printf.sprintf "%s index %d is out of range. Only %d historical builds match this pipeline." arg_name idx num_builds))
        else
          Ok (List.nth all_matches (idx - 1), idx)
    | VString pattern ->
        (try
           let re = Str.regexp pattern in
           let matched_indices = List.filter_map (fun (i, path) ->
             let log_file = Filename.basename path in
             try
               let _ = Str.search_forward re log_file 0 in
               Some (path, i + 1)
             with Not_found -> None
           ) (List.mapi (fun i x -> (i, x)) all_matches) in
           match matched_indices with
           | [] ->
               Error (Error.make_error ValueError (Printf.sprintf "No build logs matched the regex pattern '%s' for argument `%s`." pattern arg_name))
           | (path, idx) :: _ ->
               Ok (path, idx)
         with Failure _ ->
           Error (Error.make_error ValueError (Printf.sprintf "Invalid regular expression pattern '%s' for argument `%s`." pattern arg_name)))
    | _ ->
        Error (Error.type_error (Printf.sprintf "Function `node_diff` expects `%s` to be an Integer or a String regex pattern." arg_name))
  in
  let named_keys = List.filter_map (fun (k, _) -> k) named_args in
  let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
  match List.find_opt (fun k -> not (List.mem k ["p"; "node"; "build_a"; "build_b"])) named_keys with
  | Some k -> Error.type_error (Printf.sprintf "node_diff: unknown argument '%s'" k)
  | None when positional_count > 4 ->
      Error.make_error ArityError
        (Printf.sprintf "Function `node_diff` accepts at most 4 positional arguments but received %d." positional_count)
  | None ->
    match get_arg "p" 1 (VNA NAGeneric) named_args, get_arg "node" 2 (VNA NAGeneric) named_args with
    | (_, VPipeline p), (_, VString node_name) ->
        let (_, build_a_val) = get_arg "build_a" 3 (VInt 1) named_args in
        let (_, build_b_val) = get_arg "build_b" 4 (VInt 2) named_args in
        (match resolve_build_path p build_a_val "build_a", resolve_build_path p build_b_val "build_b" with
         | Ok (log_path_a, idx_a), Ok (log_path_b, idx_b) ->
             (match Builder.read_log log_path_a, Builder.read_log log_path_b with
              | Ok entries_a, Ok entries_b ->
                  (match List.assoc_opt node_name entries_a, List.assoc_opt node_name entries_b with
                   | Some cn_a, Some cn_b ->
                       if cn_a.cn_serializer <> cn_b.cn_serializer then
                         Error.make_error TypeError
                           (Printf.sprintf "Serializer mismatch for node '%s': build %d used '%s', but build %d used '%s'."
                              node_name idx_a cn_a.cn_serializer idx_b cn_b.cn_serializer)
                          else if cn_a.cn_path = "" || not (Sys.file_exists cn_a.cn_path) then
                            Error.make_error FileError
                              (Printf.sprintf "Artifact for node '%s' in build %d is no longer present in the Nix store at path: %s"
                                 node_name idx_a cn_a.cn_path)
                          else if cn_b.cn_path = "" || not (Sys.file_exists cn_b.cn_path) then
                            Error.make_error FileError
                              (Printf.sprintf "Artifact for node '%s' in build %d is no longer present in the Nix store at path: %s"
                                 node_name idx_b cn_b.cn_path)
                          else (
                            (* Load both values using standard pipeline reader *)
                            let val_a = Builder_read_node.read_standard_node_value cn_a in
                            let val_b = Builder_read_node.read_standard_node_value cn_b in
                            
                            (* Check serializer to decide on comparison strategy *)
                            if cn_a.cn_serializer = "csv" || cn_a.cn_serializer = "arrow" || cn_a.cn_serializer = "parquet" then (
                              match val_a, val_b with
                              | VDataFrame df_a, VDataFrame df_b ->
                                  (* DataFrame Diff logic *)
                                  let cols_a = Arrow_table.column_names df_a.arrow_table in
                                  let cols_b = Arrow_table.column_names df_b.arrow_table in
                                  let added_cols = List.filter (fun c -> not (List.mem c cols_a)) cols_b in
                                  let removed_cols = List.filter (fun c -> not (List.mem c cols_b)) cols_a in
                                  let schema_changed = added_cols <> [] || removed_cols <> [] in
                                  
                                  let nrows_a = Arrow_table.num_rows df_a.arrow_table in
                                  let nrows_b = Arrow_table.num_rows df_b.arrow_table in
                                  
                                  (* Shared columns comparison *)
                                  let shared_cols = List.filter (fun c -> List.mem c cols_b) cols_a in
                                  let nrows_summaries = List.length shared_cols in
                                  let arr_col_name = Array.make nrows_summaries None in
                                  let arr_col_type = Array.make nrows_summaries None in
                                  let arr_mean_a = Array.make nrows_summaries None in
                                  let arr_mean_b = Array.make nrows_summaries None in
                                  let arr_mean_delta = Array.make nrows_summaries None in
                                  let arr_n_changed = Array.make nrows_summaries None in
                                  
                                  List.iteri (fun i col ->
                                    arr_col_name.(i) <- Some col;
                                    (match Arrow_table.get_column df_a.arrow_table col, Arrow_table.get_column df_b.arrow_table col with
                                     | Some col_a, Some col_b ->
                                         let t_name =
                                           match col_a with
                                           | Arrow_table.IntColumn _ -> "Int"
                                           | Arrow_table.FloatColumn _ -> "Float"
                                           | Arrow_table.BoolColumn _ -> "Bool"
                                           | Arrow_table.StringColumn _ -> "String"
                                           | _ -> "Unknown"
                                         in
                                         arr_col_type.(i) <- Some t_name;
                                         
                                         (* Compute means for numeric types *)
                                         (match col_a, col_b with
                                          | Arrow_table.FloatColumn arr_a, Arrow_table.FloatColumn arr_b ->
                                              let mean xs =
                                                let vals = List.filter_map (fun x -> x) (Array.to_list xs) in
                                                if vals = [] then 0.0
                                                else List.fold_left (+.) 0.0 vals /. float_of_int (List.length vals)
                                              in
                                              let m_a = mean arr_a in
                                              let m_b = mean arr_b in
                                              arr_mean_a.(i) <- Some m_a;
                                              arr_mean_b.(i) <- Some m_b;
                                              arr_mean_delta.(i) <- Some (m_b -. m_a)
                                          | Arrow_table.IntColumn arr_a, Arrow_table.IntColumn arr_b ->
                                              let mean xs =
                                                let vals = List.filter_map (fun x -> x) (Array.to_list xs) |> List.map float_of_int in
                                                if vals = [] then 0.0
                                                else List.fold_left (+.) 0.0 vals /. float_of_int (List.length vals)
                                              in
                                              let m_a = mean arr_a in
                                              let m_b = mean arr_b in
                                              arr_mean_a.(i) <- Some m_a;
                                              arr_mean_b.(i) <- Some m_b;
                                              arr_mean_delta.(i) <- Some (m_b -. m_a)
                                          | _ -> ());
                                          
                                         (* Compute raw differences row by row if row counts are equal *)
                                          if nrows_a = nrows_b then (
                                            let count_changed = ref 0 in
                                            for r = 0 to nrows_a - 1 do
                                              let cell_a = get_cell df_a.arrow_table col r in
                                              let cell_b = get_cell df_b.arrow_table col r in
                                              if cell_a <> cell_b then incr count_changed
                                            done;
                                            arr_n_changed.(i) <- Some !count_changed
                                          )
                                     | _ -> ())
                                  ) shared_cols;
                                  
                                  let col_summaries_columns = [
                                    ("name",       Arrow_table.StringColumn arr_col_name);
                                    ("type",       Arrow_table.StringColumn arr_col_type);
                                    ("mean_a",     Arrow_table.FloatColumn arr_mean_a);
                                    ("mean_b",     Arrow_table.FloatColumn arr_mean_b);
                                    ("mean_delta", Arrow_table.FloatColumn arr_mean_delta);
                                    ("n_changed",  Arrow_table.IntColumn arr_n_changed);
                                  ] in
                                  let col_summaries_table = Arrow_table.create col_summaries_columns nrows_summaries in
                                  let col_summaries = VDataFrame { arrow_table = col_summaries_table; group_keys = [] } in
                                  
                                  VDict [
                                    ("schema_changed",   VBool schema_changed);
                                    ("added_columns",    VList (List.map (fun c -> (None, VString c)) added_cols));
                                    ("removed_columns",  VList (List.map (fun c -> (None, VString c)) removed_cols));
                                    ("nrows_a",          VInt nrows_a);
                                    ("nrows_b",          VInt nrows_b);
                                    ("nrows_added",      VInt (max 0 (nrows_b - nrows_a)));
                                    ("nrows_removed",    VInt (max 0 (nrows_a - nrows_b)));
                                    ("column_summaries", col_summaries);
                                  ]
                              | _ ->
                                  Error.make_error StructuralError "DataFrame diff failed: loaded node values were not DataFrames."
                            )
                            else if cn_a.cn_serializer = "pmml" then (
                              (* PMML Model Diff logic *)
                              match val_a, val_b with
                              | VDict coef_a, VDict coef_b ->
                                  let find_linear_regression coeffs =
                                    let get_str k = match List.assoc_opt k coeffs with Some (VString s) -> s | _ -> "" in
                                    let model_type = get_str "model_type" in
                                    let coefficients =
                                      match List.assoc_opt "coefficients" coeffs with
                                      | Some (VDict pairs) -> pairs
                                      | _ -> []
                                    in
                                    (model_type, coefficients)
                                  in
                                  let mtype_a, coefs_a = find_linear_regression coef_a in
                                  let mtype_b, coefs_b = find_linear_regression coef_b in
                                  
                                  let names_a = List.map fst coefs_a in
                                  let names_b = List.map fst coefs_b in
                                  let all_names = List.sort_uniq String.compare (names_a @ names_b) in
                                  
                                  let nrows = List.length all_names in
                                  let arr_coef_name = Array.make nrows None in
                                  let arr_val_a = Array.make nrows None in
                                  let arr_val_b = Array.make nrows None in
                                  let arr_delta = Array.make nrows None in
                                  
                                  let changed = ref (mtype_a <> mtype_b) in
                                  List.iteri (fun i name ->
                                    arr_coef_name.(i) <- Some name;
                                    let get_float v_opt =
                                      match v_opt with
                                      | Some (VFloat f) -> Some f
                                      | Some (VInt n) -> Some (float_of_int n)
                                      | _ -> None
                                    in
                                    let v_a = get_float (List.assoc_opt name coefs_a) in
                                    let v_b = get_float (List.assoc_opt name coefs_b) in
                                    arr_val_a.(i) <- v_a;
                                    arr_val_b.(i) <- v_b;
                                    (match v_a, v_b with
                                     | Some fa, Some fb ->
                                         arr_delta.(i) <- Some (fb -. fa);
                                         if abs_float (fb -. fa) > 1e-9 then changed := true
                                     | _ -> changed := true)
                                  ) all_names;
                                  
                                  let coef_diff_columns = [
                                    ("name",    Arrow_table.StringColumn arr_coef_name);
                                    ("value_a", Arrow_table.FloatColumn arr_val_a);
                                    ("value_b", Arrow_table.FloatColumn arr_val_b);
                                    ("delta",   Arrow_table.FloatColumn arr_delta);
                                  ] in
                                  let coef_diff_table = Arrow_table.create coef_diff_columns nrows in
                                  let coef_diff = VDataFrame { arrow_table = coef_diff_table; group_keys = [] } in
                                  
                                  VDict [
                                    ("model_type",           VString (if mtype_b <> "" then mtype_b else mtype_a));
                                    ("coefficients_changed", VBool !changed);
                                    ("coef_diff",            coef_diff);
                                  ]
                              | _ ->
                                  (* Simple structural diff fallback *)
                                  let changed = val_a <> val_b in
                                  VDict [
                                    ("model_type",           VString "Generic PMML Model");
                                    ("coefficients_changed", VBool changed);
                                    ("coef_diff",            VNA NAGeneric);
                                  ]
                            )
                            else if cn_a.cn_serializer = "text" then (
                              (* Text Diff using system diff utility *)
                              let path_a = cn_a.cn_path in
                              let path_b = cn_b.cn_path in
                              let cmd = Printf.sprintf "diff -u %s %s" (Filename.quote path_a) (Filename.quote path_b) in
                              match Builder_utils.run_command_capture cmd with
                              | Ok (Unix.WEXITED (0 | 1), diff_out) ->
                                  let diff_str = String.trim diff_out in
                                  let lines = String.split_on_char '\n' diff_str in
                                  let added = ref 0 in
                                  let removed = ref 0 in
                                  List.iter (fun line ->
                                    if String.length line > 0 then (
                                      if line.[0] = '+' && not (String.starts_with ~prefix:"+++" line) then incr added
                                      else if line.[0] = '-' && not (String.starts_with ~prefix:"---" line) then incr removed
                                    )
                                  ) lines;
                                  VDict [
                                    ("changed",       VBool (diff_str <> ""));
                                    ("lines_added",   VInt !added);
                                    ("lines_removed", VInt !removed);
                                    ("diff",          VString diff_str);
                                  ]
                              | _ ->
                                  (* Fallback if diff failed or was empty *)
                                  let changed = val_a <> val_b in
                                  VDict [
                                    ("changed",       VBool changed);
                                    ("lines_added",   VInt (if changed then 1 else 0));
                                    ("lines_removed", VInt (if changed then 1 else 0));
                                    ("diff",          VString (if changed then "Text nodes are different." else ""));
                                  ]
                            )
                            else (
                              (* Scalar or general serializer fallback *)
                              let changed = val_a <> val_b in
                              let delta =
                                match val_a, val_b with
                                | VFloat fa, VFloat fb -> VFloat (fb -. fa)
                                | VInt ia, VInt ib -> VFloat (float_of_int (ib - ia))
                                | _ -> VNA NAGeneric
                              in
                              VDict [
                                ("value_a", val_a);
                                ("value_b", val_b);
                                ("changed", VBool changed);
                                ("delta",   delta);
                              ]
                            )
                          )
                      | _ ->
                          Error.make_error NameError (Printf.sprintf "Node '%s' was not found in one or both of the matching build logs." node_name))
                 | Error msg, _ | _, Error msg ->
                     Error.make_error FileError (Printf.sprintf "Failed to read historical build logs: %s" msg))
         | Error err, _ | _, Error err -> err)
    | _ -> Error.type_error "Function `node_diff` expects a Pipeline and a String node name as its first two arguments."

let register env =
  let make_builtin_named ?name ?(variadic=false) arity func =
    VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
               b_func = (fun named_args env_ref -> func (List.map (fun (n, v) -> (n, Ast.Utils.unwrap_value v)) named_args) !env_ref) }
  in
  let env = Env.add "build_log" (make_builtin_named ~name:"build_log" ~variadic:true 1 build_log_fn) env in
  let env = Env.add "build_log_to_frame" (make_builtin ~name:"build_log_to_frame" 1 build_log_to_frame_fn) env in
  let env = Env.add "collect_exceptions" (make_builtin ~name:"collect_exceptions" 1 collect_exceptions_fn) env in
  let env = Env.add "build_log_history" (make_builtin_named ~name:"build_log_history" ~variadic:true 1 build_log_history_fn) env in
  let env = Env.add "node_diff" (make_builtin_named ~name:"node_diff" ~variadic:true 2 node_diff_fn) env in
  env
