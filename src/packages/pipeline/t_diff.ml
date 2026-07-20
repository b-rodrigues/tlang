(* src/packages/pipeline/t_diff.ml *)
(* REPL-callable version of `t diff` — compares two builds of a pipeline
   using per-node Nix content hashes. *)

open Ast

(*
--# Compare Two Builds of a Pipeline
--#
--# Compares two builds of a pipeline and returns a summary of which nodes
--# changed, were added, or were removed. Uses per-node Nix content hashes.
--#
--# @name t_diff
--# @param file :: String The path to the .t file to diff.
--# @param json :: Bool = false Output diff as JSON.
--# @param log_a :: Int = 2 Rank of the first (older) build log.
--# @param log_b :: Int = 1 Rank of the second (newer) build log.
--# @return :: String The formatted diff (text or JSON).
--# @family pipeline
--# @export
*)

let format_diff_result (r : Builder_diff.diff_result) =
  let buf = Buffer.create 256 in
  Buffer.add_string buf (Printf.sprintf "\nBuild A: %s (%s)\n" r.dr_build_a.Builder_diff.bi_log_file r.dr_build_a.Builder_diff.bi_timestamp);
  Buffer.add_string buf (Printf.sprintf "Build B: %s (%s)\n\n" r.dr_build_b.Builder_diff.bi_log_file r.dr_build_b.Builder_diff.bi_timestamp);
  Buffer.add_string buf (Printf.sprintf "%-20s %-12s %s\n" "Node" "Status" "Detail");
  Buffer.add_string buf (Printf.sprintf "%-20s %-12s %s\n" (String.make 20 '-') (String.make 12 '-') (String.make 30 '-'));
  List.iter (fun (e : Builder_diff.node_diff_entry) ->
    let detail = match e.nde_status with
      | Builder_diff.Unchanged _ -> ""
      | Builder_diff.Changed { hash_a; hash_b } ->
          Printf.sprintf "hash %s -> %s" (String.sub hash_a 0 (min 7 (String.length hash_a)))
                                         (String.sub hash_b 0 (min 7 (String.length hash_b)))
      | Builder_diff.Added _ -> "new node"
      | Builder_diff.Removed _ -> "removed"
      | Builder_diff.Errored { error_class } -> Printf.sprintf "error: %s" error_class
    in
    Buffer.add_string buf (Printf.sprintf "%-20s %-12s %s\n" e.nde_name (Builder_diff.node_status_to_string e.nde_status) detail)
  ) r.dr_nodes;
  Buffer.add_string buf (Printf.sprintf "\nSummary: %d nodes, %d unchanged, %d changed, %d errored, %d added, %d removed\n"
    r.dr_total r.dr_unchanged r.dr_changed r.dr_errored r.dr_added r.dr_removed);
  Buffer.contents buf

let register env =
  Env.add "t_diff"
    (make_builtin_named ~name:"t_diff" ~variadic:true 1 (fun named_args _env ->
      let named_keys = List.filter_map (fun (k, _) -> k) named_args in
      let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
      match List.find_opt (fun k -> not (List.mem k ["file"; "json"; "log_a"; "log_b"])) named_keys with
      | Some k ->
          Error.type_error (Printf.sprintf "t_diff: unknown argument '%s'" k)
      | None when positional_count > 1 ->
          Error.make_error ArityError
            (Printf.sprintf "Function `t_diff` accepts at most 1 positional argument but received %d." positional_count)
      | None ->
        match Pipeline_args.get_arg "file" 1 (VNA NAGeneric) named_args with
        | (_, VString filename) ->
            let (_, json_val) = Pipeline_args.get_arg "json" 2 (VBool false) named_args in
            let (_, log_a_val) = Pipeline_args.get_arg "log_a" 3 (VInt 2) named_args in
            let (_, log_b_val) = Pipeline_args.get_arg "log_b" 4 (VInt 1) named_args in

            let json_result =
              match json_val with
              | VBool b -> Ok b
              | _ -> Error (Error.type_error "Function `t_diff` expects `json` to be a Bool.")
            in
            let log_a_result =
              match log_a_val with
              | VInt i when i >= 1 -> Ok i
              | VInt _ -> Error (Error.value_error "Function `t_diff` expects `log_a` to be >= 1.")
              | _ -> Error (Error.type_error "Function `t_diff` expects `log_a` to be an Int.")
            in
            let log_b_result =
              match log_b_val with
              | VInt i when i >= 1 -> Ok i
              | VInt _ -> Error (Error.value_error "Function `t_diff` expects `log_b` to be >= 1.")
              | _ -> Error (Error.type_error "Function `t_diff` expects `log_b` to be an Int.")
            in

            let (let*) x f = match x with Ok v -> f v | Error e -> e in
            let* do_json = json_result in
            let* do_log_a = log_a_result in
            let* do_log_b = log_b_result in

            let pipelines = Check_utils.extract_pipelines Typecheck.Strict filename Env.empty in
            (match pipelines with
             | Error err -> VError err
             | Ok [] ->
                 Error.make_error FileError
                   (Printf.sprintf "t_diff: no pipeline found in %s." filename)
             | Ok ((_, p) :: _) ->
                 let is_default = (do_log_a = 2 && do_log_b = 1) in
                 if is_default then
                   match Builder.find_two_matching_logs p with
                   | None ->
                       Error.make_error FileError
                         "t_diff: fewer than 2 matching build logs found. Run build_pipeline(p) at least twice."
                   | Some (log_a_path, log_b_path) ->
                       (match Builder_diff.compute_diff log_a_path log_b_path with
                        | Error msg ->
                            Error.make_error RuntimeError
                              (Printf.sprintf "t_diff: %s" msg)
                        | Ok diff_result ->
                            if do_json then
                              VString (Yojson.Safe.pretty_to_string (Builder_diff.diff_result_to_yojson diff_result))
                            else
                              VString (format_diff_result diff_result))
                 else
                   let logs = Builder.get_logs () in
                   let try_log log_file =
                     let full_path = Filename.concat Builder.pipeline_dir log_file in
                     match Builder.read_log full_path with
                     | Ok entries when Builder_read_node.pipeline_matches_logged_entries p entries -> Some full_path
                     | _ -> None
                   in
                   let matching = List.filter_map try_log logs in
                   let n_matching = List.length matching in
                   if n_matching < 2 then
                     Error.make_error FileError
                       (Printf.sprintf "t_diff: need at least 2 matching build logs to diff. Found %d." n_matching)
                   else if do_log_a > n_matching || do_log_b > n_matching then
                     Error.make_error FileError
                       (Printf.sprintf "t_diff: requested rank exceeds available builds: --log-a %d --log-b %d but only %d matching builds found."
                          do_log_a do_log_b n_matching)
                   else
                     let path_a = List.nth matching (do_log_a - 1) in
                     let path_b = List.nth matching (do_log_b - 1) in
                     (match Builder_diff.compute_diff path_a path_b with
                      | Error msg ->
                          Error.make_error RuntimeError
                            (Printf.sprintf "t_diff: %s" msg)
                      | Ok diff_result ->
                          if do_json then
                            VString (Yojson.Safe.pretty_to_string (Builder_diff.diff_result_to_yojson diff_result))
                          else
                            VString (format_diff_result diff_result)))
        | (_, other) ->
            Error.type_error
              (Printf.sprintf "Function `t_diff` expects a file path (String) as first argument, but got %s."
                 (Utils.type_name other))
    )) env
