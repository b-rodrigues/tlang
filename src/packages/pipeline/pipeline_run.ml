open Ast

(*
--# Run Pipeline
--#
--# Re-executes a pipeline from start to finish.
--#
--# @name pipeline_run
--# @param p :: Pipeline The pipeline to run.
--# @return :: Pipeline The executed pipeline.
--# @family pipeline
--# @seealso pipeline_nodes
--# @export
*)
let register ~(rerun_pipeline : ?strict:bool -> ?verbose:bool -> value Env.t -> pipeline_result -> value) env =
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> (true, v)
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
        else (false, default)
  in
  let run_fn named_args env =
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["p"; "targets"; "force"; "dry_run"; "max_jobs"; "cache"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "pipeline_run: unknown argument '%s'" k)
    | None when positional_count > 1 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `pipeline_run` accepts at most 1 positional argument but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (targets_provided, targets_val) = get_arg "targets" 2 (VNA NAGeneric) named_args in
        let (force_provided, force_val) = get_arg "force" 3 (VNA NAGeneric) named_args in
        let (dry_run_provided, dry_run_val) = get_arg "dry_run" 4 (VNA NAGeneric) named_args in
        let (max_jobs_provided, max_jobs_val) = get_arg "max_jobs" 5 (VNA NAGeneric) named_args in
        let (cache_provided, cache_val) = get_arg "cache" 6 (VNA NAGeneric) named_args in

        let targets_result =
          match targets_val with
          | VList _ | VVector _ | VString _ -> Ok (Some targets_val)
          | _ when targets_provided ->
              Error (Error.type_error "Function `pipeline_run` expects `targets` to be a String, List, or Vector.")
          | _ -> Ok None
        in
        let force_result =
          match force_val with
          | VBool _ | VList _ | VVector _ | VString _ -> Ok (Some force_val)
          | _ when force_provided ->
              Error (Error.type_error "Function `pipeline_run` expects `force` to be a Bool, String, List, or Vector.")
          | _ -> Ok None
        in
        let dry_run_result =
          match dry_run_val with
          | VBool b -> Ok (Some b)
          | _ when dry_run_provided ->
              Error (Error.type_error "Function `pipeline_run` expects `dry_run` to be a Bool.")
          | _ -> Ok None
        in
        let max_jobs_result =
          match max_jobs_val with
          | VInt n when n > 0 -> Ok (Some max_jobs_val)
          | _ when max_jobs_provided ->
              Error (Error.type_error "Function `pipeline_run` expects `max_jobs` to be a positive Int.")
          | _ -> Ok None
        in
        let cache_result =
          match cache_val with
          | VString _ -> Ok (Some cache_val)
          | _ when cache_provided ->
              Error (Error.type_error "Function `pipeline_run` expects `cache` to be a String.")
          | _ -> Ok None
        in

        (match targets_result, force_result, dry_run_result, max_jobs_result, cache_result with
         | Error e, _, _, _, _
         | _, Error e, _, _, _
         | _, _, Error e, _, _
         | _, _, _, Error e, _
         | _, _, _, _, Error e -> e
         | Ok targets, Ok force, Ok dry_run, Ok max_jobs, Ok cache ->
             (match rerun_pipeline ?strict:None env p with
              | VPipeline p_resolved ->
                  if targets_provided || force_provided || dry_run_provided || max_jobs_provided || cache_provided then
                    (match Builder.populate_pipeline ~build:true ?targets ?force ?dry_run ?max_jobs ?cache p_resolved with
                     | Ok (VDataFrame _ as df) -> df
                     | Ok (VString out_path) ->
                         VPipeline (Builder.update_pipeline_with_build_paths p_resolved out_path)
                     | Ok other -> other
                     | Error msg -> Error.make_error StructuralError msg)
                  else
                    VPipeline p_resolved
              | VError _ as err -> err
              | other ->
                  Error.make_error RuntimeError
                    ("pipeline_run expected pipeline resolution to return a Pipeline or Error, but got: "
                     ^ Utils.value_to_string other)))
      | _ -> Error.type_error "Function `pipeline_run` expects a Pipeline."
  in
  Env.add "pipeline_run" (make_builtin_named ~name:"pipeline_run" ~variadic:true 1 run_fn) env
