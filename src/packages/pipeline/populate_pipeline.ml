open Ast

(*
--# Populate Pipeline
--#
--# Generates the `_pipeline/` directory with `pipeline.nix` and `dag.json`.
--# Optionally builds the pipeline.
--#
--# @name populate_pipeline
--# @param p :: Pipeline The pipeline to populate.
--# @param build :: Bool (Optional) Whether to trigger the Nix build immediately. Defaults to false.
--# @return :: String A status message or the output path if build=true.
--# @family pipeline
--# @export
*)
let register env =
  let populate_fn named_args _env =
    let get_arg name pos default named_args =
      match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
      | Some v -> (true, v)
      | None ->
          let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
          if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
          else (false, default)
    in
    match get_arg "p" 1 VNull named_args with
    | (_, VPipeline p) ->
        let (build_provided, build_val) = get_arg "build" 2 (VBool false) named_args in
        let build_result =
          match build_val with
          | VBool b -> Ok b
          | _ when build_provided ->
              Error (Error.type_error "Function `populate_pipeline` expects `build` to be a Bool.")
          | _ ->
              Ok false
        in
        (match build_result with
         | Error e -> e
         | Ok build ->
             let has_errors = List.exists (fun (_, v) -> is_error_value v) p.p_nodes in
             if has_errors then
               Error.value_error ("Cannot populate pipeline with errors: " ^ (Utils.value_to_string (VPipeline p)))
             else
               match Builder.populate_pipeline ~build p with
               | Ok out -> VString out
               | Error msg -> Error.make_error FileError msg)
    | _ ->
        Error.type_error "Function `populate_pipeline` expects a Pipeline."
  in
  Env.add "populate_pipeline" (make_builtin_named ~name:"populate_pipeline" ~variadic:true 1 populate_fn) env
