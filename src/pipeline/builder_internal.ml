open Ast
open Builder_utils

(*
--# Build Pipeline Internally
--#
--# Calls `nix-build` on the generated `pipeline.nix` file. Extracts the store
--# path of the result and saves a build log with an exact mapping of node names
--# to artifact paths in the Nix store.
--#
--# @name build_pipeline_internal
--# @param p :: PipelineResult The pipeline AST structure.
--# @return :: Result[String] The output Nix store path or an error string.
--# @family pipeline
--# @export
*)
let build_pipeline_internal (p : Ast.pipeline_result) =
  if not (command_exists "nix-build") then
    Error "build_pipeline requires `nix-build` to be available."
  else
    match run_command_capture
            (Printf.sprintf "nix-build --impure %s -A pipeline_output --no-out-link 2>&1" (Filename.quote pipeline_nix_path)) with
    | Ok (Unix.WEXITED 0, output) when output <> "" ->
        let lines = String.split_on_char '\n' (String.trim output) in
        let store_paths = List.filter (fun l ->
          String.length l > 11 && String.sub l 0 11 = "/nix/store/"
        ) lines in
        (match store_paths with
        | [] -> Error "nix-build succeeded but did not return a store path."
        | _ ->
            let out_path = List.nth store_paths (List.length store_paths - 1) in
            let timestamp = get_timestamp () in
            let hash = try
              let parts = String.split_on_char '-' (Filename.basename out_path) in
              List.hd parts
            with _ -> "no_hash"
            in
            let log_name = Printf.sprintf "build_log_%s_%s.json" timestamp hash in
            let log_path = Filename.concat pipeline_dir log_name in
            let log_entries =
              List.map (fun (name, _) ->
                let node_path = Filename.concat out_path name in
                let artifact_path = Filename.concat node_path "artifact" in
                let class_path = Filename.concat node_path "class" in
                let class_val = match read_file_first_line class_path with Some c -> c | None -> "Unknown" in
                let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
                let serializer_expr = match List.assoc_opt name p.p_serializers with Some s -> s | None -> Ast.mk_expr (Ast.Var "default") in
                let serializer = Nix_unparse.expr_to_string serializer_expr in
                let deps = match List.assoc_opt name p.p_deps with Some d -> d| None -> [] in
                Serialization.json_dict [
                  ("node", "\"" ^ Serialization.json_escape name ^ "\"");
                  ("path", "\"" ^ Serialization.json_escape artifact_path ^ "\"");
                  ("runtime", "\"" ^ Serialization.json_escape runtime ^ "\"");
                  ("serializer", "\"" ^ Serialization.json_escape serializer ^ "\"");
                  ("class", "\"" ^ Serialization.json_escape class_val ^ "\"");
                  ("dependencies", Serialization.json_list deps);
                  ("success", "true")
                ]
              ) p.p_exprs
            in
            let log_json = Serialization.json_dict [
              ("timestamp", "\"" ^ timestamp ^ "\"");
              ("hash", "\"" ^ hash ^ "\"");
              ("out_path", "\"" ^ out_path ^ "\"");
              ("nodes", "[\n" ^ (String.concat ",\n" log_entries) ^ "\n]")
            ] in
            (match write_file log_path log_json with
            | Ok () -> Ok out_path
            | Error msg -> Error ("Failed to write build log: " ^ msg)))
    | Ok (Unix.WEXITED 0, _) ->
        Error "nix-build succeeded but did not return an output path."
    | Ok (_, output) ->
        Error (Printf.sprintf "nix-build failed: %s" output)
    | Error msg ->
        Error (Printf.sprintf "Failed to run nix-build: %s" msg)
