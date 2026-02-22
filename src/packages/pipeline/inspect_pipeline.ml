open Ast

(*
--# Inspect Pipeline Logs
--#
--# Reads the latest (or specified) build log and returns a DataFrame showing the pipeline status.
--#
--# @name inspect_pipeline
--# @param which_log :: String (Optional) A regex pattern to match a specific build log filename.
--# @return :: DataFrame A DataFrame with columns: derivation, build_success, path, output.
--# @family pipeline
--# @export
*)
let register env =
  let inspect_fn named_args _env =
    let get_arg name pos default named_args =
      match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
      | Some v -> v
      | None ->
          let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
          if List.length positionals >= pos then List.nth positionals (pos - 1)
          else default
    in
    match get_arg "which_log" 1 VNull named_args with
    | VNull ->
        Builder.inspect_pipeline ()
    | VString s ->
        Builder.inspect_pipeline ~which_log:s ()
    | _ ->
        Error.type_error "inspect_pipeline: expected String or Null for argument 'which_log'"
  in
  let env = Env.add "inspect_pipeline" (make_builtin_named ~name:"inspect_pipeline" ~variadic:true 0 inspect_fn) env in

  (*
  --# List Pipeline Logs
  --#
  --# Lists all available build logs in the `_pipeline/` directory.
  --#
  --# @name list_pipelines
  --# @return :: List[String] A list of build log filenames, newest first.
  --# @family pipeline
  --# @export
  *)
  let env = Env.add "list_pipelines" (make_builtin ~name:"list_pipelines" 0 (fun _args _env -> Builder.list_pipelines ())) env in
  env
