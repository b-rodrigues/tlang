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
  let named_keys = List.filter_map (fun (k, _) -> k) named_args in
  let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
  match List.find_opt (fun k -> not (List.mem k ["p"; "which_log"])) named_keys with
  | Some k -> Error.type_error (Printf.sprintf "build_log: unknown argument '%s'" k)
  | None when positional_count > 2 ->
      Error.make_error ArityError
        (Printf.sprintf "Function `build_log` accepts at most 2 positional arguments but received %d." positional_count)
  | None ->
    match Pipeline_args.get_arg "p" 1 (VNA NAGeneric) named_args with
    | (_, VPipeline p) ->
        let (_, which_log_val) = Pipeline_args.get_arg "which_log" 2 (VNA NAGeneric) named_args in
        let get_log_path () =
          match which_log_val with
          | VString pattern ->
              (try
                 let re = Str.regexp pattern in
                 let all_matches = find_all_matching_log_paths p in
                 let matched_path =
                   List.find_map (fun path ->
                     let log_file = Filename.basename path in
                     try
                       let _ = Str.search_forward re log_file 0 in
                       Some path
                     with Not_found -> None
                   ) all_matches
                 in
                 (match matched_path with
                  | Some path -> Ok (Some path)
                  | None -> Error (Error.make_error ValueError "Function `build_log` could not find any matching build log for the specified `which_log` regex pattern."))
               with Failure msg ->
                 Error (Error.make_error ValueError (Printf.sprintf "Function `build_log` received an invalid regex pattern '%s': %s" pattern msg)))
          | VNA _ ->
              (match find_latest_matching_log_path p with
               | Some path -> Ok (Some path)
               | None -> Ok None)
          | _ ->
              Error (Error.type_error "Function `build_log` expects `which_log` to be a String or NA.")
        in
        (match get_log_path () with
         | Error err -> err
         | Ok (Some log_path) -> Builder.parse_json_log_to_vbuildlog log_path
         | Ok None -> Error.make_error FileError "No matching build log found for the pipeline. Run build_pipeline(p) first.")
    | (_, other) ->
        Error.type_error
          (Printf.sprintf "Function `build_log` expects a Pipeline, but got %s."
             (Utils.type_name other))

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
  | [other] ->
      Error.type_error
        (Printf.sprintf "Function `build_log_to_frame` expects a BuildLog, but got %s. Use `build_log(p)` to obtain a BuildLog from a pipeline."
           (Utils.type_name other))
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
                 let runtime =
                   match node_json |> member "runtime" with
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
                     let read_res =
                       if runtime = "T" then
                         Serialization.deserialize_from_file path
                       else
                         Serialization.read_verror_json path
                     in
                     match read_res with
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
  | [other] ->
      Error.type_error
        (Printf.sprintf "Function `collect_exceptions` expects a Pipeline, but got %s."
           (Utils.type_name other))
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
  let named_keys = List.filter_map (fun (k, _) -> k) named_args in
  let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
  match List.find_opt (fun k -> not (List.mem k ["p"; "n"; "pattern"])) named_keys with
  | Some k -> Error.type_error (Printf.sprintf "build_log_history: unknown argument '%s'" k)
  | None when positional_count > 3 ->
      Error.make_error ArityError
        (Printf.sprintf "Function `build_log_history` accepts at most 3 positional arguments but received %d." positional_count)
  | None ->
    match Pipeline_args.get_arg "p" 1 (VNA NAGeneric) named_args with
    | (_, VPipeline p) ->
        let (n_provided, n_val) = Pipeline_args.get_arg "n" 2 (VNA NAGeneric) named_args in
        let limit_opt =
          match n_val with
          | VInt limit when limit > 0 -> Some limit
          | VNA _ -> None
          | _ -> None
        in
        let (pattern_provided, pattern_val) = Pipeline_args.get_arg "pattern" 3 (VNA NAGeneric) named_args in
        let filter_by_pattern_result =
          match pattern_val with
          | VString pat ->
              (try Ok (Some (Str.regexp pat))
               with Failure msg ->
                 Error (Error.make_error ValueError
                          (Printf.sprintf "Function `build_log_history` received an invalid regex pattern '%s': %s" pat msg)))
          | VNA _ -> Ok None
          | _ when pattern_provided ->
              Error (Error.type_error "Function `build_log_history` expects argument `pattern` to be a String or NA.")
          | _ -> Ok None
        in
        if n_provided && limit_opt = None && n_val <> VNA NAGeneric then
          Error.type_error "Function `build_log_history` expects argument `n` to be a positive Int."
        else (
          match filter_by_pattern_result with
          | Error err -> err
          | Ok filter_by_pattern_opt ->
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
    | (_, other) ->
        Error.type_error
          (Printf.sprintf "Function `build_log_history` expects a Pipeline, but got %s."
             (Utils.type_name other))

(*
--# Compare Node Outputs Across Builds
--#
--# Compares the artifact produced by a named node across two historical builds
--# of the same pipeline.  Returns a structured VDiff dictionary with a
--# consistent envelope (kind, node_a, node_b, log_a, log_b, value_type,
--# identical, summary, detail, hunks).
--#
--# Dispatches to a type-appropriate comparison:
--#   - DataFrame → row-/column-level diff with optional key-based alignment
--#   - Model (PMML) → coefficient deltas and fit-stat comparison
--#   - Scalar → before/after with numeric delta
--#   - Python-native objects → unified_diff-based structural comparison
--#   - Julia-native objects → DeepDiffs-based structural comparison
--#   - R-native objects → diffobj-based structural comparison
--#   - Generic → structural comparison over string representations
--#
--# Runtime-native object diffs are preserved only for runtime artifacts using
--# the standard `default`/`tobj` serializers. Custom serializer names follow
--# the normal artifact-loading path; use the companion helper packages directly
--# when you need a custom deserializer for native objects.
--#
--# @name node_diff
--# @param node_a :: ComputedNode  The "before" node.
--# @param node_b :: ComputedNode  The "after" node.
--# @param log_a  :: String | Int  Build log selector for node_a (default "latest"). Accepts a timestamp prefix, regex, or 1-indexed integer.
--# @param log_b  :: String | Int  Build log selector for node_b (default "latest"). Same format as log_a.
--# @param key    :: List[Symbol]  For DataFrames: natural key column(s) for row alignment (default []).
--# @param context :: Int  Number of unchanged rows shown around each hunk (default 3).
--# @return :: Dict  A VDiff envelope dictionary.
--# @family pipeline
--# @export
*)
let node_diff_fn named_args _env =
  let named_keys = List.filter_map (fun (k, _) -> k) named_args in
  let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in

  (* Form: node_diff(node_a :: ComputedNode, node_b :: ComputedNode, ...) *)
  let (_, first_arg) = Pipeline_args.get_arg "node_a" 1 (VNA NAGeneric) named_args in
  let (_, second_arg) = Pipeline_args.get_arg "node_b" 2 (VNA NAGeneric) named_args in
  let preserve_native_object cn =
    let runtime = String.lowercase_ascii cn.cn_runtime in
    let serializer = String.lowercase_ascii cn.cn_serializer in
    (runtime = "python" || runtime = "julia" || runtime = "r")
    && (serializer = "default" || serializer = "tobj")
  in

  match first_arg, second_arg with
  (* ---- New form: two ComputedNode values ---- *)
  | VComputedNode cn_a, VComputedNode cn_b ->
      let valid_keys = ["node_a"; "node_b"; "log_a"; "log_b"; "key"; "context"] in
      (match List.find_opt (fun k -> not (List.mem k valid_keys)) named_keys with
       | Some k -> Error.type_error (Printf.sprintf "node_diff: unknown argument '%s'" k)
       | None when positional_count > 6 ->
           Error.make_error ArityError
             (Printf.sprintf "Function `node_diff` accepts at most 6 positional arguments but received %d." positional_count)
       | None ->
           let (_, log_a_val) = Pipeline_args.get_arg "log_a" 3 (VString "latest") named_args in
           let (_, log_b_val) = Pipeline_args.get_arg "log_b" 4 (VString "latest") named_args in
           let (_, key_val)   = Pipeline_args.get_arg "key"   5 (VList []) named_args in
           let (_, ctx_val)   = Pipeline_args.get_arg "context" 6 (VInt 3) named_args in
           let key = match key_val with
             | VList items -> List.filter_map (fun (_, v) -> match v with VString s -> Some s | VSymbol s -> Some s | _ -> None) items
             | _ -> []
           in
           let context = match ctx_val with VInt n -> n | _ -> 3 in
           (* Load artifacts *)
           let load_artifact cn log_val arg_name =
             let resolve_from_logs cn selector_val =
                 let logs = Builder_logs.get_logs () in
                 let all_matches = List.filter_map (fun log_file ->
                   let full_path = Filename.concat Builder_utils.pipeline_dir log_file in
                   match Builder_logs.read_log full_path with
                   | Ok entries ->
                       (match List.assoc_opt cn.cn_name entries with
                        | Some _ -> Some full_path
                        | None -> None)
                   | _ -> None
                 ) logs in
                 let num_builds = List.length all_matches in
                 let resolve = function
                   | VString "latest" ->
                       if num_builds = 0 then
                         Error (Error.make_error FileError (Printf.sprintf "No historical builds found for node '%s'." cn.cn_name))
                       else Ok (List.hd all_matches)
                   | VInt idx ->
                       if idx <= 0 then
                         Error (Error.make_error ValueError (Printf.sprintf "Function `node_diff` expects `%s` to be a positive 1-indexed integer." arg_name))
                       else if idx > num_builds then
                         Error (Error.make_error ValueError (Printf.sprintf "%s index %d is out of range. Only %d historical builds found." arg_name idx num_builds))
                       else Ok (List.nth all_matches (idx - 1))
                   | VString pattern ->
                       (try
                          let re = Str.regexp pattern in
                          let matched = List.find_opt (fun path ->
                            let f = Filename.basename path in
                            try let _ = Str.search_forward re f 0 in true
                            with Not_found -> false
                          ) all_matches in
                          match matched with
                          | None -> Error (Error.make_error ValueError (Printf.sprintf "No build logs matched '%s' for `%s`." pattern arg_name))
                          | Some p -> Ok p
                        with Failure _ ->
                          Error (Error.make_error ValueError (Printf.sprintf "Invalid regex '%s' for `%s`." pattern arg_name)))
                   | _ -> Error (Error.type_error (Printf.sprintf "Function `node_diff` expects `%s` to be a String or Int." arg_name))
                 in
                 match resolve selector_val with
                 | Error e -> Error e
                 | Ok log_path ->
                     match Builder_logs.read_log log_path with
                     | Error msg -> Error (Error.make_error FileError (Printf.sprintf "Failed to read build log: %s" msg))
                     | Ok entries ->
                         match List.assoc_opt cn.cn_name entries with
                         | None -> Error (Error.make_error NameError (Printf.sprintf "Node '%s' not found in log '%s'." cn.cn_name (Filename.basename log_path)))
                         | Some logged_cn ->
                             if logged_cn.cn_path = "" || not (Sys.file_exists logged_cn.cn_path) then
                               Error (Error.make_error FileError (Printf.sprintf "Artifact for node '%s' is no longer present at: %s" cn.cn_name logged_cn.cn_path))
                             else
                               Ok
                                 ( Filename.basename log_path,
                                   if preserve_native_object logged_cn
                                   then VComputedNode logged_cn
                                   else Builder_read_node.read_standard_node_value logged_cn )
             in
             match log_val with
             | VString "latest" when cn.cn_path <> "" && cn.cn_path <> "<unbuilt>" && Sys.file_exists cn.cn_path ->
                 Ok
                   ( "latest",
                     if preserve_native_object cn
                     then VComputedNode cn
                     else Builder_read_node.read_standard_node_value cn )
             | _ ->
                 resolve_from_logs cn log_val
           in
           match load_artifact cn_a log_a_val "log_a", load_artifact cn_b log_b_val "log_b" with
           | Error e, _ | _, Error e -> e
           | Ok (resolved_a, val_a), Ok (resolved_b, val_b) ->
               (try
                  Diff.node_diff_values
                    ~va:val_a ~vb:val_b
                    ~node_a_name:cn_a.cn_name ~node_b_name:cn_b.cn_name
                    ~log_a:resolved_a ~log_b:resolved_b
                    ~key ~context
                with Invalid_argument msg ->
                  Error.make_error ValueError msg))

  | first, second ->
      Error.type_error
        (Printf.sprintf "Function `node_diff` expects two ComputedNodes as its first two arguments, but got %s and %s."
           (Utils.type_name first) (Utils.type_name second))

let register env =
  let make_builtin_named ?name ?(variadic=false) arity func =
    VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
               b_func = (fun named_args env_ref -> func (List.map (fun (n, v) -> (n, !Ast.meta_pipeline_flatten_resolver (Ast.Utils.unwrap_value v))) named_args) !env_ref) }
  in
  let env = Env.add "build_log" (make_builtin_named ~name:"build_log" ~variadic:true 1 build_log_fn) env in
  let env = Env.add "build_log_to_frame" (make_builtin ~name:"build_log_to_frame" 1 build_log_to_frame_fn) env in
  let env = Env.add "collect_exceptions" (make_builtin ~name:"collect_exceptions" 1 collect_exceptions_fn) env in
  let env = Env.add "build_log_history" (make_builtin_named ~name:"build_log_history" ~variadic:true 1 build_log_history_fn) env in
  let env = Env.add "node_diff" (make_builtin_named ~name:"node_diff" ~variadic:true 2 node_diff_fn) env in
  env
