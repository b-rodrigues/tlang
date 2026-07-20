open Ast

(*
--# Summarize Output Changes Across Builds
--#
--# Compares the two most recent builds of a pipeline and returns a DataFrame
--# summarizing which nodes changed, were added, or were removed.
--#
--# Uses per-node Nix content hashes stored in build logs to detect changes
--# without loading artifacts. Only loads artifacts for nodes that actually changed.
--#
--# @name diff_summary
--# @param p :: Pipeline The pipeline to compare builds for.
--# @return :: DataFrame A summary with columns: name, status, hash_a, hash_b.
--# @family pipeline
--# @export
*)
let register env =
  Env.add "diff_summary"
    (make_builtin ~name:"diff_summary" 1 (fun args _env ->
      match args with
      | [VPipeline p] ->
          (match Builder.find_two_matching_logs p with
           | None ->
               Error.make_error FileError
                 "diff_summary: fewer than 2 matching build logs found. Run build_pipeline(p) at least twice."
           | Some (log_a_path, log_b_path) ->
               (match Builder.compute_diff log_a_path log_b_path with
                | Error msg ->
                    Error.make_error RuntimeError
                      (Printf.sprintf "diff_summary: failed to compute diff: %s" msg)
                | Ok diff_result ->
                    let nrows = diff_result.dr_total in
                    let arr_name = Array.make nrows None in
                    let arr_status = Array.make nrows None in
                    let arr_hash_a = Array.make nrows None in
                    let arr_hash_b = Array.make nrows None in
                    let arr_class_a = Array.make nrows None in
                    let arr_class_b = Array.make nrows None in
                    List.iteri (fun i e ->
                      arr_name.(i) <- Some e.Builder_diff.nde_name;
                      arr_status.(i) <- Some (Builder_diff.node_status_to_string e.nde_status);
                      arr_class_a.(i) <- Some e.nde_class_a;
                      arr_class_b.(i) <- Some e.nde_class_b;
                      (match e.nde_status with
                       | Builder_diff.Unchanged { hash } ->
                           arr_hash_a.(i) <- Some hash;
                           arr_hash_b.(i) <- Some hash
                       | Builder_diff.Changed { hash_a; hash_b } ->
                           arr_hash_a.(i) <- Some hash_a;
                           arr_hash_b.(i) <- Some hash_b
                       | Builder_diff.Added { hash } ->
                           arr_hash_b.(i) <- Some hash
                       | Builder_diff.Removed { hash } ->
                           arr_hash_a.(i) <- Some hash
                       | Builder_diff.Errored _ -> ())
                    ) diff_result.dr_nodes;
                    let columns = [
                      ("name", Arrow_table.StringColumn arr_name);
                      ("status", Arrow_table.StringColumn arr_status);
                      ("hash_a", Arrow_table.StringColumn arr_hash_a);
                      ("hash_b", Arrow_table.StringColumn arr_hash_b);
                      ("class_a", Arrow_table.StringColumn arr_class_a);
                      ("class_b", Arrow_table.StringColumn arr_class_b);
                    ] in
                    let arrow_table = Arrow_table.create columns nrows in
                    VDataFrame { arrow_table; group_keys = [] }))
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `diff_summary` expects a Pipeline, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "diff_summary" 1 (List.length args)
    )) env
