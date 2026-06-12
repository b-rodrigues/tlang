open Ast

(*
--# Inspect Artifact Archive
--#
--# Imports a pipeline archive into a temporary Nix store, extracts metadata
--# (node name, store path, hash, size in bytes, and reference basenames) for
--# each path, and returns a DataFrame of the results without modifying the local store.
--#
--# @name inspect_artifacts
--# @param archive_path :: String The path to the artifact archive file.
--# @return :: DataFrame A DataFrame with columns `node` (String), `store_path` (String), `hash` (String), `size_bytes` (Int), and `references` (String).
--# @family pipeline
--# @export
*)
let register env =
  Env.add "inspect_artifacts"
    (make_builtin ~name:"inspect_artifacts" 1 (fun args _env ->
      match args with
      | [VString archive_path] ->
          (match Builder_artifacts.inspect_artifacts archive_path with
           | Error err -> Error.make_error err.code err.message
           | Ok results ->
                let results_arr = Array.of_list results in
                let nrows = Array.length results_arr in
                let arr_node = Array.init nrows (fun i -> let (name, _, _, _, _) = results_arr.(i) in Some name) in
                let arr_store_path = Array.init nrows (fun i -> let (_, store_path, _, _, _) = results_arr.(i) in Some store_path) in
                let arr_hash = Array.init nrows (fun i -> let (_, _, hash, _, _) = results_arr.(i) in Some hash) in
                let arr_size_bytes = Array.init nrows (fun i -> let (_, _, _, size, _) = results_arr.(i) in Some size) in
                let arr_references = Array.init nrows (fun i -> let (_, _, _, _, refs) = results_arr.(i) in Some refs) in
                let columns = [
                 ("node",       Arrow_table.StringColumn arr_node);
                 ("store_path", Arrow_table.StringColumn arr_store_path);
                 ("hash",       Arrow_table.StringColumn arr_hash);
                 ("size_bytes", Arrow_table.IntColumn arr_size_bytes);
                 ("references", Arrow_table.StringColumn arr_references);
               ] in
               let arrow_table = Arrow_table.create columns nrows in
               VDataFrame { arrow_table; group_keys = [] })
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `inspect_artifacts` expects a String, but got %s."
               (Utils.type_name other))
      | _ ->
          Error.arity_error_named "inspect_artifacts" 1 (List.length args)
    ))
    env
