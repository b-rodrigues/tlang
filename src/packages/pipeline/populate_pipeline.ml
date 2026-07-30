open Ast
open Pipeline_utils

let register env =
  let populate_fn named_args env =
    if !Ast.check_mode then
      VString "<check mode: populate_pipeline skipped>"
    else
    let fn_name = "populate_pipeline" in
    match Pipeline_builder_post.check_unknown_keys ~known_keys:["p"; "build"; "verbose"; "nix_options"; "dry_run"; "pipeline_name"] ~fn_name named_args with
    | Some err -> err
    | None ->
    match Pipeline_builder_post.check_arity ~max:6 ~fn_name named_args with
    | Some err -> err
    | None ->
      match Pipeline_args.get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
          let original_p_exprs = p.p_exprs in
          (match Pipeline_expand.expand_pipeline_for_build p env with
           | Error e -> e
           | Ok p ->
            let (let*) x f = match x with Ok v -> f v | Error e -> e in
            let* build = Pipeline_builder_post.parse_build ~fn_name ~pos:2 named_args in
            let* verbose = Pipeline_builder_post.parse_verbose ~fn_name ~pos:3 named_args in
            let* nix_options = Pipeline_builder_post.parse_nix_options ~fn_name ~pos:4 named_args in
            let* dry_opt = Pipeline_builder_post.parse_dry_run ~fn_name ~pos:5 named_args in
            let* pipeline_name_explicit = Pipeline_builder_post.parse_pipeline_name ~fn_name ~pos:6 named_args in
        let final_nix_options = Pipeline_builder_post.combine_nix_options ?dry_opt nix_options in
        let final_build =
          match final_nix_options with
          | Some opts ->
              (match opts.dry_run with
               | Some true -> true
               | _ -> build)
          | None -> build
        in
        let pipeline_name =
          match pipeline_name_explicit with
          | Some _ -> pipeline_name_explicit
          | None -> resolve_pipeline_name env p
        in
         (match Builder.populate_pipeline ~build:final_build ?verbose ?pipeline_name ?nix_options:final_nix_options p with
          | Ok out ->
              if final_build && (match final_nix_options with Some opts -> opts.dry_run <> Some true | None -> true) then (
                let stats = Pipeline_builder_post.extract_build_stats out in
                Pipeline_builder_post.print_build_success ~pipeline_name ~p_nodes:p.p_nodes stats;
                if stats.built > 0 || stats.cached > 0 then
                  ignore (Pipeline_builder_post.register_build_logs
                    ~p_exprs_keys:[original_p_exprs; p.p_exprs]
                    ~p_nodes:p.p_nodes
                    ~out_path:stats.out_path)
              );
               out
          | Error msg -> Error.make_error StructuralError msg))
       | _ ->
          Error.type_error "Function `populate_pipeline` expects a Pipeline."
  in
  Env.add "populate_pipeline" (make_builtin_named ~name:"populate_pipeline" ~variadic:true 1 populate_fn) env
