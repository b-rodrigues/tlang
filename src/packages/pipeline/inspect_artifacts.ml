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
               let nrows = List.length results in
               let arr_node = Array.make nrows None in
               let arr_store_path = Array.make nrows None in
               let arr_hash = Array.make nrows None in
               let arr_size_bytes = Array.make nrows None in
               let arr_references = Array.make nrows None in
               List.iteri (fun i (name, store_path, hash, size, refs) ->
                 arr_node.(i) <- Some name;
                 arr_store_path.(i) <- Some store_path;
                 arr_hash.(i) <- Some hash;
                 arr_size_bytes.(i) <- Some size;
                 arr_references.(i) <- Some refs
               ) results;
               let columns = [
                 ("node",       Arrow_table.StringColumn arr_node);
                 ("store_path", Arrow_table.StringColumn arr_store_path);
                 ("hash",       Arrow_table.StringColumn arr_hash);
                 ("size_bytes", Arrow_table.IntColumn arr_size_bytes);
                 ("references", Arrow_table.StringColumn arr_references);
               ] in
               let arrow_table = Arrow_table.create columns nrows in
               VDataFrame { arrow_table; group_keys = [] })
      | [_] ->
          Error.type_error "Function `inspect_artifacts` expects a String argument."
      | _ ->
          Error.arity_error_named "inspect_artifacts" 1 (List.length args)
    ))
    env
