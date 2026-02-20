open Ast

let pipeline_nix_path = "pipeline.nix"
let pipeline_registry_path = ".t_pipeline_registry.json"
let local_artifact_dir = ".t_pipeline_artifacts"

let write_file path content =
  try
    let oc = open_out path in
    output_string oc content;
    close_out oc;
    Ok ()
  with exn ->
    Error (Printexc.to_string exn)

let command_exists cmd =
  Sys.command (Printf.sprintf "command -v %s >/dev/null 2>&1" cmd) = 0

let run_command_capture cmd =
  try
    let ic = Unix.open_process_in cmd in
    let b = Buffer.create 256 in
    (try
       while true do
         Buffer.add_string b (input_line ic);
         Buffer.add_char b '\n'
       done
     with End_of_file -> ());
    let status = Unix.close_process_in ic in
    Ok (status, String.trim (Buffer.contents b))
  with exn ->
    Error (Printexc.to_string exn)

let ensure_local_node_dir node =
  let root = local_artifact_dir in
  let node_dir = Filename.concat root node in
  if not (Sys.file_exists root) then Unix.mkdir root 0o755;
  if not (Sys.file_exists node_dir) then Unix.mkdir node_dir 0o755;
  node_dir

let materialize_local_artifacts (p : Ast.pipeline_result) =
  try
    let entries =
      p.p_nodes
      |> List.map (fun (name, value) ->
        let node_dir = ensure_local_node_dir name in
        let artifact_path = Filename.concat node_dir "artifact.tobj" in
        match Serialization.serialize_to_file artifact_path value with
        | Ok () -> Ok (name, artifact_path)
        | Error msg -> Error msg)
    in
    let rec collect acc = function
      | [] -> Ok (List.rev acc)
      | Ok x :: xs -> collect (x :: acc) xs
      | Error e :: _ -> Error e
    in
    collect [] entries
  with exn ->
    Error (Printexc.to_string exn)

let write_registry entries =
  Serialization.write_registry pipeline_registry_path entries

let build_pipeline (p : Ast.pipeline_result) =
  let nix_content = Nix_emitter.emit_pipeline p in
  match write_file pipeline_nix_path nix_content with
  | Error msg -> Error ("Failed to write pipeline.nix: " ^ msg)
  | Ok () ->
      if command_exists "nix-build" then
        (match run_command_capture "nix-build pipeline.nix --no-out-link --print-out-paths 2>/dev/null" with
         | Ok (Unix.WEXITED 0, out_path) when out_path <> "" ->
             let registry =
               List.map (fun (name, _) ->
                 (name, Filename.concat (Filename.concat out_path name) "artifact.tobj")
               ) p.p_nodes
             in
             (match write_registry registry with
             | Ok () -> Ok out_path
             | Error msg -> Error ("Failed to write registry: " ^ msg))
         | _ ->
             (match materialize_local_artifacts p with
             | Error msg -> Error ("Failed to materialize local artifacts: " ^ msg)
             | Ok registry ->
                 (match write_registry registry with
                 | Ok () -> Ok local_artifact_dir
                 | Error msg -> Error ("Failed to write registry: " ^ msg))))
      else
        match materialize_local_artifacts p with
        | Error msg -> Error ("Failed to materialize local artifacts: " ^ msg)
        | Ok registry ->
            (match write_registry registry with
            | Ok () -> Ok local_artifact_dir
            | Error msg -> Error ("Failed to write registry: " ^ msg))

let read_node name =
  match Serialization.read_registry pipeline_registry_path with
  | Error _ ->
      Error.make_error FileError
        (Printf.sprintf "Pipeline registry `%s` not found. Run `build_pipeline(p)` first." pipeline_registry_path)
  | Ok entries ->
      (match List.assoc_opt name entries with
      | None ->
          Error.make_error KeyError (Printf.sprintf "Node `%s` not found in pipeline registry." name)
      | Some path ->
          (match Serialization.deserialize_from_file path with
          | Ok v -> v
          | Error msg ->
              Error.make_error FileError
                (Printf.sprintf "Failed to read node `%s` from `%s`: %s" name path msg)))
