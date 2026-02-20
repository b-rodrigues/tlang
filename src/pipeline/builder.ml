open Ast

let pipeline_nix_path = "pipeline.nix"
let pipeline_registry_path = ".t_pipeline_registry.json"

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

let write_registry entries =
  Serialization.write_registry pipeline_registry_path entries

let build_pipeline (p : Ast.pipeline_result) =
  let nix_content = Nix_emitter.emit_pipeline p in
  match write_file pipeline_nix_path nix_content with
  | Error msg -> Error ("Failed to write pipeline.nix: " ^ msg)
  | Ok () ->
      if not (command_exists "nix-build") then
        Error "build_pipeline requires `nix-build` to be available."
      else
        match run_command_capture
                (Printf.sprintf "nix-build %s --no-out-link --print-out-paths 2>&1" pipeline_nix_path) with
        | Ok (Unix.WEXITED 0, out_path) when out_path <> "" ->
            let registry =
              List.map (fun (name, _) ->
                (name, Filename.concat (Filename.concat out_path name) "artifact.tobj")
              ) p.p_nodes
            in
            (match write_registry registry with
            | Ok () -> Ok out_path
            | Error msg -> Error ("Failed to write registry: " ^ msg))
        | Ok (Unix.WEXITED 0, _) ->
            Error "nix-build succeeded but did not return an output path."
        | Ok (_, output) ->
            Error (Printf.sprintf "nix-build failed: %s" output)
        | Error msg ->
            Error (Printf.sprintf "Failed to run nix-build: %s" msg)

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
