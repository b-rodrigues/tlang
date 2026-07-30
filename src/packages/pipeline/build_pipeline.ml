open Ast
open Pipeline_utils

let write_atelier_diagrams p env =
  if not (Builder_utils.is_atelier_active ()) then ()
  else
    let root = Builder_utils.get_atelier_project_root () in
    Builder_utils.ensure_atelier_dir root;
    (match Env.find_opt "pipeline_to_dot" env with
     | Some (VBuiltin { b_func; _ }) ->
       let args = [(None, VPipeline p)] in
       let env_ref = ref env in
       (try match b_func args env_ref with
            | VString s ->
              Builder_utils.write_file (Builder_utils.atelier_dot_path root) s |> ignore
            | _ -> ()
        with _ -> ())
     | _ -> ());
    (match Env.find_opt "pipeline_to_mermaid" env with
     | Some (VBuiltin { b_func; _ }) ->
       let args = [(None, VPipeline p)] in
       let env_ref = ref env in
       (try match b_func args env_ref with
            | VString s ->
              Builder_utils.write_file (Builder_utils.atelier_mermaid_path root) s |> ignore
            | _ -> ()
        with _ -> ())
     | _ -> ())

let register ~(rerun_pipeline : ?strict:bool -> ?verbose:bool -> value Env.t -> pipeline_result -> value) env =
  let build_fn named_args env =
    if !Ast.check_mode then
      VString "<check mode: build_pipeline skipped>"
    else
    let fn_name = "build_pipeline" in
    match Pipeline_builder_post.check_unknown_keys ~known_keys:["p"; "verbose"; "nix_options"; "dry_run"; "pipeline_name"] ~fn_name named_args with
    | Some err -> err
    | None ->
    match Pipeline_builder_post.check_arity ~max:5 ~fn_name named_args with
    | Some err -> err
    | None ->
      match Pipeline_args.get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
          (match Pipeline_expand.expand_pipeline_for_build p env with
           | Error e -> e
           | Ok p ->
            let (let*) x f = match x with Ok v -> f v | Error e -> e in
            let* verbose = Pipeline_builder_post.parse_verbose ~fn_name ~pos:2 named_args in
            let* nix_options = Pipeline_builder_post.parse_nix_options ~fn_name ~pos:3 named_args in
            let* dry_opt = Pipeline_builder_post.parse_dry_run ~fn_name ~pos:4 named_args in
            let* pipeline_name_explicit = Pipeline_builder_post.parse_pipeline_name ~fn_name ~pos:5 named_args in
        let final_nix_options = Pipeline_builder_post.combine_nix_options ?dry_opt nix_options in
        (match rerun_pipeline ?strict:(Some true) ~verbose:false env p with
         | VPipeline p_resolved ->
             let pipeline_name =
               match pipeline_name_explicit with
               | Some _ -> pipeline_name_explicit
               | None -> resolve_pipeline_name env p
             in
             (match Builder.populate_pipeline ~build:true ?verbose ?pipeline_name ?nix_options:final_nix_options p_resolved with
              | Ok (VDataFrame _ as df) ->
                  write_atelier_diagrams p_resolved env;
                  df
              | Ok (VDict _ as out) ->
                  write_atelier_diagrams p_resolved env;
                  let stats = Pipeline_builder_post.extract_build_stats out in
                  Pipeline_builder_post.print_build_success ~pipeline_name ~p_nodes:p_resolved.p_nodes stats;
                  if stats.built > 0 || stats.cached > 0 then (
                    match Pipeline_builder_post.register_build_logs
                      ~p_exprs_keys:[p.p_exprs; p_resolved.p_exprs]
                      ~p_nodes:p_resolved.p_nodes
                      ~out_path:stats.out_path with
                    | Some _ when stats.built > 0 ->
                        Builder.parse_json_log_to_vbuildlog stats.out_path
                    | Some _ -> out
                    | None when stats.built > 0 ->
                        Error.make_error FileError
                          (Printf.sprintf
                             "No build log matching output path `%s` was found after build completed."
                             stats.out_path)
                    | None -> out
                  ) else
                    out
              | Ok other -> other
              | Error msg -> Error.make_error StructuralError msg)
         | VError _ as err -> err
         | other ->
             Error.make_error RuntimeError
               ("build_pipeline expected pipeline resolution to return a Pipeline or Error, but got: "
                 ^ Utils.value_to_string other)))
       | _ -> Error.type_error "Function `build_pipeline` expects a Pipeline."
  in
  Env.add "build_pipeline" (make_builtin_named ~name:"build_pipeline" ~variadic:true 1 build_fn) env
