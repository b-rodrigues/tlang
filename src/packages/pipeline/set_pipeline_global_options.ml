open Ast

(*
--# Set Pipeline Global Options (pure)
--#
--# Pure function that returns a new pipeline with the given defaults merged
--# into nodes.  The original pipeline is not modified.  By default the settings
--# are merged into every node; pass `runtimes` and/or `nodes` to restrict the
--# merge to a subset (union semantics when both are given).  Omitting both
--# scoping arguments (or passing `na()`) targets every node; an explicitly
--# empty list (`nodes = []`) targets no nodes.
--#
--# Merge semantics vary per option:
--#   * Combine (prepend): `functions`, `include`, `env_vars`, `args`, `shell_args`,
--#     `dependencies`.  Global values come first; per-node values follow (for
--#     same-key dict entries, the later per-node value wins).
--#   * Override: `serializer`, `deserializer`, `shell`, `flake`.  A provided
--#     global value replaces the node's per-node value entirely.
--#   * Force-only: `noop`.  `noop = true` forces nodes to no-op;
--#     `noop = false` has no effect and cannot un-set a per-node `noop = true`.
--#
--# @name set_pipeline_global_options
--# @param pipeline :: Pipeline The input pipeline.
--# @param functions :: Dict (Optional) Combine (prepend). Runtime-shorthand to
--#   function-file mappings.  Per-node `functions` are appended after.
--# @param include :: String | List[String] (Optional) Combine (prepend). File
--#   path(s) to include in the node sandbox.  Per-node `include` appended after.
--# @param env_vars :: Dict (Optional) Combine (prepend). Environment variables.
--#   Per-node env vars override same keys.
--# @param serializer :: String | Symbol (Optional) Override. Default serializer;
--#   replaces per-node serializer.
--# @param deserializer :: String | Symbol (Optional) Override. Default deserializer;
--#   replaces per-node deserializer.
--# @param noop :: Bool (Optional) Force-only. If true, nodes become no-ops.
--#   Setting false has no effect — it cannot un-set a per-node noop.
--# @param args :: Dict (Optional) Combine (prepend). Runtime arguments.  Per-node
--#   args override same keys.
--# @param shell :: String (Optional) Override. Shell interpreter.
--# @param shell_args :: String | List[String] (Optional) Combine (prepend). Shell
--#   arguments, prepended before per-node shell args.
--# @param flake :: String (Optional) Override. Nix flake path.
--# @param dependencies :: String | List[String] (Optional) Combine (prepend).
--#   Explicit dependencies, prepended before per-node deps.  Note: per-node node
--#   constructors use the shorter `deps` argument name for the same field.
--# @param runtimes :: String | List[String] (Optional) Scope the merge to nodes
--#   whose runtime is in this set.  Accepts translated runtimes (`"R"`,
--#   `"Python"`) or constructor shorthands (`"rn"`, `"pyn"`).  An unmatched
--#   runtime is a `TypeError`.  Omitted (or `na()`) targets all nodes; an
--#   explicit empty list targets no nodes.
--# @param nodes :: String | List[String] (Optional) Scope the merge to exactly
--#   these node names.  An unknown node name is a `TypeError`.  When both
--#   `runtimes` and `nodes` are given, the target is their union.  Omitted (or
--#   `na()`) targets all nodes; an explicit empty list targets no nodes.
--# @return :: Pipeline A new pipeline with the settings merged into the target nodes.
--# @family pipeline
--# @export
--# @example
--#   set_pipeline_global_options(p, runtimes = ["R"], serializer = ^arrow)
--#   set_pipeline_global_options(p, nodes = ["n1", "n3"], noop = true)
--*)

let register env =
  Env.add "set_pipeline_global_options"
    (make_builtin_named ~name:"set_pipeline_global_options" ~variadic:true 1 (fun named_args _env ->
      let known_keys = ["functions"; "include"; "env_vars"; "serializer"; "deserializer";
                        "noop"; "args"; "shell"; "shell_args"; "flake"; "dependencies";
                        "runtimes"; "nodes"] in
      match List.find_opt (fun (k, _) -> k <> None && not (List.mem (Option.get k) known_keys)) named_args with
      | Some (Some k, _) ->
          Error.type_error (Printf.sprintf
            "set_pipeline_global_options: unknown argument '%s'. Supported arguments are: functions, include, env_vars, serializer, deserializer, noop, args, shell, shell_args, flake, dependencies, runtimes, nodes."
            k)
      | _ ->
        match List.assoc_opt None named_args with
        | Some (VPipeline p) ->
            let ( >>= ) r f = Result.bind r f in

            let translate_runtime = function
              | "rn"   -> "R"
              | "pyn"  -> "Python"
              | "jln"  -> "Julia"
              | "qn"   -> "Quarto"
              | "shn"  -> "sh"
              | "node" -> "T"
              | other  -> other
            in

            (* --- parsing helpers --- *)

            let parse_functions value =
              match value with
              | VList pairs ->
                  Ok (List.filter_map (fun (runtime_name_opt, files_val) ->
                    match runtime_name_opt with
                    | Some runtime -> Some (translate_runtime runtime, options_value_to_expr_list files_val)
                    | None -> None
                  ) pairs)
              | VDict pairs ->
                  Ok (List.map (fun (runtime_name, files_val) ->
                    (translate_runtime runtime_name, options_value_to_expr_list files_val)
                  ) pairs)
              | VNA _ -> Ok []
              | other ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: expected `functions` to be a list or dict (e.g. [rn: \"f.R\"]), but got %s."
                       (Utils.type_name other)))
            in

            let parse_dict v =
              match v with
              | VDict pairs -> Ok pairs
              | VNA _ -> Ok []
              | other ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: expected a dict (e.g. [key: value]), but got %s."
                       (Utils.type_name other)))
            in

            let parse_expr_opt v =
              match v with
              | VSerializer s -> Ok (Some (mk_expr (Value (VSerializer s))))
              | VSymbol "default" | VString "default" -> Ok (Some (mk_expr (Var "default")))
              | VString s -> Ok (Some (mk_expr (Value (VString s))))
              | VSymbol s -> Ok (Some (mk_expr (Value (VString s))))
              | VNA _ -> Ok None
              | other ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: expected a string or symbol for serializer/deserializer, but got %s."
                       (Utils.type_name other)))
            in

            let parse_bool v =
              match v with
              | VBool b -> Ok b
              | VNA _ -> Ok false
              | other ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: expected a bool, but got %s."
                       (Utils.type_name other)))
            in

            let parse_string_opt v =
              match v with
              | VString s -> Ok (Some s)
              | VSymbol s -> Ok (Some s)
              | VNA _ -> Ok None
              | other ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: expected a string, but got %s."
                       (Utils.type_name other)))
            in

            let parse_deps v =
              match v with
              | VString s -> Ok (Some [s])
              | VSymbol s -> Ok (Some [s])
              | VList items ->
                  Ok (Some (List.filter_map (fun (_, v') ->
                    match v' with VString s | VSymbol s -> Some s | _ -> None
                  ) items))
              | VNA _ -> Ok (Some [])
              | other ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: expected a string or list of strings for `dependencies`, but got %s."
                       (Utils.type_name other)))
            in

            let parse_names param_name v =
              match v with
              | VString s -> Ok (Some [s])
              | VSymbol s -> Ok (Some [s])
              | VList items ->
                  Ok (Some (List.filter_map (fun (_, v') ->
                    match v' with VString s | VSymbol s -> Some s | _ -> None
                  ) items))
              | VNA _ -> Ok None
              | other ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: expected a string or list of strings for `%s`, but got %s."
                       param_name (Utils.type_name other)))
            in

            (* --- extract values from named_args --- *)

            let functions_result = match List.assoc_opt (Some "functions") named_args with
              | Some v -> parse_functions v
              | None -> Ok []
            in
            let includes = match List.assoc_opt (Some "include") named_args with
              | Some v -> options_value_to_expr_list v
              | None -> []
            in
            let env_vars_result = match List.assoc_opt (Some "env_vars") named_args with
              | Some v -> parse_dict v
              | None -> Ok []
            in
            let serializer_result = match List.assoc_opt (Some "serializer") named_args with
              | Some v -> parse_expr_opt v
              | None -> Ok None
            in
            let deserializer_result = match List.assoc_opt (Some "deserializer") named_args with
              | Some v -> parse_expr_opt v
              | None -> Ok None
            in
            let noop_result = match List.assoc_opt (Some "noop") named_args with
              | Some v -> parse_bool v
              | None -> Ok false
            in
            let args_result = match List.assoc_opt (Some "args") named_args with
              | Some v -> parse_dict v
              | None -> Ok []
            in
            let shell_result = match List.assoc_opt (Some "shell") named_args with
              | Some v -> parse_string_opt v
              | None -> Ok None
            in
            let shell_args = match List.assoc_opt (Some "shell_args") named_args with
              | Some v -> options_value_to_expr_list v
              | None -> []
            in
            let flake_result = match List.assoc_opt (Some "flake") named_args with
              | Some v -> parse_string_opt v
              | None -> Ok None
            in
            let deps_result = match List.assoc_opt (Some "dependencies") named_args with
              | Some v -> parse_deps v
              | None -> Ok None
            in
            let nodes_result = match List.assoc_opt (Some "nodes") named_args with
              | Some v -> parse_names "nodes" v
              | None -> Ok None
            in
            let runtimes_result = match List.assoc_opt (Some "runtimes") named_args with
              | Some v -> parse_names "runtimes" v
              | None -> Ok None
            in

            (* --- compute the target node set, bailing on unknown names/runtimes --- *)

            let compute_target nodes_opt raw_runtimes =
              let runtimes_opt = Option.map (List.map translate_runtime) raw_runtimes in
              let node_names = List.map fst p.p_exprs in
              let present_runtimes = List.map snd p.p_runtimes in
              let nodes_specified = match nodes_opt with Some ns -> ns | None -> [] in
              let runtimes_specified = match runtimes_opt with Some rts -> rts | None -> [] in
              let unknown_nodes = List.filter (fun n -> not (List.mem n node_names)) nodes_specified in
              let unmatched = List.filter (fun rt -> not (List.mem rt present_runtimes)) runtimes_specified in
              match unknown_nodes, unmatched with
              | _ :: _, _ ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: unknown node name(s): %s. Valid node names are: %s."
                       (String.concat ", " (List.map (fun s -> "`" ^ s ^ "`") unknown_nodes))
                       (String.concat ", " (List.map (fun s -> "`" ^ s ^ "`") node_names))))
              | [], _ :: _ ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: unknown runtime(s) in pipeline: %s. Pipeline runtimes are: %s."
                       (String.concat ", " (List.map (fun s -> "`" ^ s ^ "`") unmatched))
                       (String.concat ", " (List.map (fun s -> "`" ^ s ^ "`") (List.sort_uniq String.compare present_runtimes)))))
              | [], [] ->
                  let runtime_of name = match List.assoc_opt name p.p_runtimes with
                    | Some r -> r
                    | None -> ""
                  in
                  let target =
                    match nodes_opt, runtimes_opt with
                    | None, None -> node_names
                    | Some ns, None ->
                        List.filter (fun name -> List.mem name ns) node_names
                    | None, Some rts ->
                        List.filter (fun name -> List.mem (runtime_of name) rts) node_names
                    | Some ns, Some rts ->
                        List.filter (fun name ->
                          List.mem name ns || List.mem (runtime_of name) rts
                        ) node_names
                  in
                  Ok target
            in

            (* --- apply all results, bailing on first error --- *)

            let apply_global_options target global_functions global_env_vars global_serializer
                global_deserializer global_noop global_args global_shell global_flake global_deps =
              let should_apply name = List.mem name target in
              let updated_functions = List.map (fun (name, funcs) ->
                if not (should_apply name) then (name, funcs)
                else
                  let runtime = match List.assoc_opt name p.p_runtimes with
                    | Some r -> r
                    | None -> "T"
                  in
                  let global_funcs =
                    List.filter_map (fun (rt, fs) -> if rt = runtime then Some fs else None)
                      global_functions
                    |> List.flatten
                  in
                  (name, global_funcs @ funcs)
              ) p.p_functions in

              let updated_includes = List.map (fun (name, incs) ->
                if should_apply name then (name, includes @ incs) else (name, incs)
              ) p.p_includes in

              let updated_env_vars = List.map (fun (name, vars) ->
                if should_apply name then (name, global_env_vars @ vars) else (name, vars)
              ) p.p_env_vars in

              let updated_args = List.map (fun (name, rt_args) ->
                if should_apply name then (name, global_args @ rt_args) else (name, rt_args)
              ) p.p_args in

              let updated_serializers = match global_serializer with
                | Some s -> List.map (fun (name, orig) ->
                    if should_apply name then (name, s) else (name, orig)
                  ) p.p_serializers
                | None -> p.p_serializers
              in

              let updated_deserializers = match global_deserializer with
                | Some d -> List.map (fun (name, orig) ->
                    if should_apply name then (name, d) else (name, orig)
                  ) p.p_deserializers
                | None -> p.p_deserializers
              in

              let updated_noops = if global_noop then
                List.map (fun (name, orig) ->
                  if should_apply name then (name, true) else (name, orig)
                ) p.p_noops
              else
                p.p_noops
              in

              let updated_shells = match global_shell with
                | Some s -> List.map (fun (name, orig) ->
                    if should_apply name then (name, Some s) else (name, orig)
                  ) p.p_shells
                | None -> p.p_shells
              in

              let updated_shell_args = List.map (fun (name, args) ->
                if should_apply name then (name, shell_args @ args) else (name, args)
              ) p.p_shell_args in

              let updated_flakes = match global_flake with
                | Some f -> List.map (fun (name, orig) ->
                    if should_apply name then (name, Some f) else (name, orig)
                  ) p.p_flakes
                | None -> p.p_flakes
              in

              let updated_deps = match global_deps with
                | Some gd -> List.map (fun (name, deps) ->
                    if should_apply name then
                      let gd_no_self = List.filter (fun d -> d <> name) gd in
                      let merged = gd_no_self @ match deps with Some d -> d | None -> [] in
                      (name, Some merged)
                    else (name, deps)
                  ) p.p_explicit_deps
                | None -> p.p_explicit_deps
              in

              (* Reconcile p_deps so global dependencies are visible to the
                 build DAG, read-back, and cycle detection — not just to
                 p_explicit_deps.  Dedupe against existing edges and exclude
                 self-references (a node can never depend on itself). *)
              let updated_p_deps = match global_deps with
                | Some gd -> List.map (fun (name, deps) ->
                    if should_apply name then
                      let gd_no_self = List.filter (fun d -> d <> name) gd in
                      (name, gd_no_self @ List.filter (fun d -> not (List.mem d gd_no_self)) deps)
                    else (name, deps)
                  ) p.p_deps
                | None -> p.p_deps
              in

              let updated_provenance = List.map (fun (name, prov) ->
                if not (should_apply name) then (name, prov)
                else
                  let runtime = match List.assoc_opt name p.p_runtimes with
                    | Some r -> r
                    | None -> "T"
                  in
                  let global_funcs =
                    List.filter_map (fun (rt, fs) -> if rt = runtime then Some fs else None)
                      global_functions
                    |> List.flatten
                  in
                  let prov_explicit_deps =
                    match global_deps with
                    | Some gd ->
                        let gd_no_self = List.filter (fun d -> d <> name) gd in
                        List.map (fun d -> (d, Source_global)) gd_no_self @ prov.prov_explicit_deps
                    | None -> prov.prov_explicit_deps
                  in
                  (name, {
                    prov_functions = List.map (fun f -> (f, Source_global)) global_funcs @ prov.prov_functions;
                    prov_includes = List.map (fun i -> (i, Source_global)) includes @ prov.prov_includes;
                    prov_env_vars = List.map (fun (k, _) -> (k, Source_global)) global_env_vars @ prov.prov_env_vars;
                    prov_args = List.map (fun (k, _) -> (k, Source_global)) global_args @ prov.prov_args;
                    prov_shell_args = List.map (fun sa -> (sa, Source_global)) shell_args @ prov.prov_shell_args;
                    prov_explicit_deps;
                    prov_serializer =
                      (match global_serializer with Some _ -> Some Source_global | None -> prov.prov_serializer);
                    prov_deserializer =
                      (match global_deserializer with Some _ -> Some Source_global | None -> prov.prov_deserializer);
                    prov_noop =
                      (if global_noop then Some Source_global else prov.prov_noop);
                    prov_shell =
                      (match global_shell with Some _ -> Some Source_global | None -> prov.prov_shell);
                    prov_flake =
                      (match global_flake with Some _ -> Some Source_global | None -> prov.prov_flake);
                  })
              ) p.p_provenance in

              Ok (VPipeline (Ast.Utils.attach_node_configs {
                p with
                p_functions = updated_functions;
                p_includes = updated_includes;
                p_env_vars = updated_env_vars;
                p_args = updated_args;
                p_serializers = updated_serializers;
                p_deserializers = updated_deserializers;
                p_noops = updated_noops;
                p_shells = updated_shells;
                p_shell_args = updated_shell_args;
                p_flakes = updated_flakes;
                p_explicit_deps = updated_deps;
                p_deps = updated_p_deps;
                p_provenance = updated_provenance;
              }))
            in

            (match
               nodes_result >>= fun nodes_opt ->
               runtimes_result >>= fun raw_runtimes ->
               compute_target nodes_opt raw_runtimes >>= fun target ->
               functions_result >>= fun global_functions ->
               env_vars_result >>= fun global_env_vars ->
               serializer_result >>= fun global_serializer ->
               deserializer_result >>= fun global_deserializer ->
               noop_result >>= fun global_noop ->
               args_result >>= fun global_args ->
               shell_result >>= fun global_shell ->
               flake_result >>= fun global_flake ->
               deps_result >>= fun global_deps ->
               apply_global_options target global_functions global_env_vars global_serializer
                 global_deserializer global_noop global_args global_shell global_flake global_deps
             with
             | Error e -> e
             | Ok v -> v)
        | Some other ->
            Error.type_error (Printf.sprintf "set_pipeline_global_options: expected a pipeline, got %s." (Utils.type_name other))
        | None ->
            Error.arity_error_named "set_pipeline_global_options" 1 0
    ))
    env
