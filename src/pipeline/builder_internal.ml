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
let nix_build_args = ref []

let build_pipeline_internal (p : Ast.pipeline_result) =
  if not (command_exists "nix-build") then
    Error "build_pipeline requires `nix-build` to be available."
  else begin
    let node_names = List.map fst p.p_exprs in
    let statuses = Hashtbl.create (List.length node_names) in
    List.iter (fun n -> Hashtbl.add statuses n "Pending") node_names;
    
    let captured_output = Buffer.create 1024 in
    let extra_args = String.concat " " (List.map Filename.quote !nix_build_args) in
    let cmd = Printf.sprintf "nix-build --impure %s -A pipeline_output --no-out-link %s" (Filename.quote pipeline_nix_path) extra_args in
    
    Printf.printf "\nStarting pipeline build...\n";
    
    let contains_substring line pattern =
      try
        let len_p = String.length pattern in
        let len_l = String.length line in
        let rec loop i =
          if i + len_p > len_l then false
          else if String.sub line i len_p = pattern then true
          else loop (i + 1)
        in
        loop 0
      with _ -> false
    in

    let contains_substring_idx line pattern =
      let len_p = String.length pattern in
      let len_l = String.length line in
      let rec loop i =
        if i + len_p > len_l then -1
        else if String.sub line i len_p = pattern then i
        else loop (i + 1)
      in
      loop 0
    in

    let callback line =
      Buffer.add_string captured_output line;
      Buffer.add_char captured_output '\n';
      
      let line = String.trim line in
      (* Each branch performs a single List.find_opt scan to both detect and
         identify the matching node, avoiding a separate exists + find_opt double
         scan that the previous version performed per line. *)
      if String.starts_with ~prefix:"building '/nix/store/" line then (
        (* Building a derivation *)
        match List.find_opt (fun name -> contains_substring line ("-" ^ name ^ ".drv")) node_names with
        | Some name -> 
            if Hashtbl.find statuses name = "Pending" then (
              Hashtbl.replace statuses name "Building";
              Printf.printf "  + %s building\n%!" name
            )
        | None -> ()
      )
      else if String.starts_with ~prefix:"/nix/store/" line
           && not (String.ends_with ~suffix:".drv" line) then (
        (* Completed: nix-build prints the output store path without ".drv" *)
        match List.find_opt (fun name -> contains_substring line ("-" ^ name)) node_names with
        | Some name ->
            if Hashtbl.find statuses name <> "Completed" then (
              Hashtbl.replace statuses name "Completed";
              Printf.printf "  ✓ %s built\n%!" name
            )
        | None -> ()
      )
      else (
        (* Error detection: only scan for a matching node when error keywords
           are present, to avoid a find_opt scan on every non-build/output line. *)
        if contains_substring line "error:" || contains_substring line "failed" then (
          match List.find_opt (fun name -> contains_substring line ("-" ^ name ^ ".drv")) node_names with
          | Some name ->
              if Hashtbl.find statuses name <> "Errored" then (
                Hashtbl.replace statuses name "Errored";
                let drv_path = 
                  try
                    let start_idx = contains_substring_idx line "/nix/store/" in
                    if start_idx >= 0 then
                      let sub = String.sub line start_idx (String.length line - start_idx) in
                      (* Stop at closing quote or whitespace; do NOT stop at '.' so that
                         the full ".drv" suffix is preserved in the extracted path. *)
                      let end_idx = try String.index sub '\'' with _ ->
                                    try String.index sub ' ' with _ ->
                                    String.length sub in
                      String.sub sub 0 end_idx
                    else "<path>"
                  with _ -> "<path>"
                in
                Printf.eprintf "  ✖ Node %s failed! For full logs, run: nix log %s\n%!" name drv_path
              )
          | None -> ()
        )
      )
    in
    
    match run_command_stream cmd callback with
    | Ok status ->
        let output = String.trim (Buffer.contents captured_output) in
        (match status with
         | Unix.WEXITED 0 when output <> "" ->
            let lines = String.split_on_char '\n' output in
            let store_paths = List.filter (fun l ->
              String.length l > 11 && String.sub l 0 11 = "/nix/store/"
            ) lines in
            (match store_paths with
            | [] -> Error "nix-build succeeded but did not return a store path."
            | _ ->
                let out_path = List.nth store_paths (List.length store_paths - 1) in
                
                (* Reconcile statuses: if nix-build succeeded, check which nodes were built (cached or otherwise) *)
                List.iter (fun name ->
                  if Hashtbl.find statuses name <> "Completed" && 
                     Hashtbl.find statuses name <> "Errored" then (
                    let node_path = Filename.concat out_path name in
                    if Sys.file_exists node_path then
                      Hashtbl.replace statuses name "Completed"
                  )
                ) node_names;

                let timestamp = get_timestamp () in
                let hash = try
                  let parts = String.split_on_char '-' (Filename.basename out_path) in
                  List.hd parts
                with _ -> "no_hash"
                in
                
                (* Success Summary *)
                let completed = List.filter (fun n -> Hashtbl.find statuses n = "Completed") node_names in
                Printf.printf "\n✓ Pipeline build completed [%d/%d nodes built successfully]\n%!" 
                  (List.length completed) (List.length node_names);
                
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
         | Unix.WEXITED 0 ->
            Error "nix-build succeeded but did not return an output path."
         | _ ->
            let errored = List.filter (fun n -> Hashtbl.find statuses n = "Errored") node_names in
            let error_summary = 
              if List.length errored > 0 then
                Printf.sprintf "%d nodes errored: %s" (List.length errored) (String.concat ", " errored)
              else "General Nix build failure (check dependencies or environment)."
            in
            Printf.eprintf "\n✖ Pipeline build failed [%s]\n%!" error_summary;
            let raw_output = String.trim (Buffer.contents captured_output) in
            let max_len = 4000 in
            let output_len = String.length raw_output in
            let displayed_output =
              if output_len > max_len then
                String.sub raw_output (output_len - max_len) max_len
              else
                raw_output
            in
            Error (Printf.sprintf "nix-build failed: %s\n\nCaptured output (last %d characters):\n%s"
              error_summary
              (String.length displayed_output)
              displayed_output))
    | Error msg ->
        Error (Printf.sprintf "Failed to run nix-build: %s" msg)
  end
