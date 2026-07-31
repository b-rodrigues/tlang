open Ast

(*
--# Set Pipeline Global Options (pure)
--#
--# Pure function that returns a new pipeline with the given defaults merged
--# into every node.  The original pipeline is not modified.
--#
--# @name set_pipeline_global_options
--# @param pipeline :: Pipeline The input pipeline.
--# @param functions :: Dict (Optional) Runtime-shorthand to function-file mappings.
--#   Per-node `functions` are appended after these global files.
--# @param include :: String | List[String] (Optional) File path(s) to include
--#   in every node's sandbox.  Per-node `include` arguments are appended after.
--# @param env_vars :: Dict (Optional) Environment variables for every node.
--#   Per-node env vars are appended after (same key overrides global value).
--# @param serializer :: String | Symbol (Optional) Default serializer for every node.
--#   Overrides per-node serializer.
--# @param deserializer :: String | Symbol (Optional) Default deserializer for every node.
--#   Overrides per-node deserializer.
--# @param noop :: Bool (Optional) If true, every node becomes a no-op.
--# @param args :: Dict (Optional) Runtime arguments for every node.
--#   Per-node args are appended after (same key overrides global value).
--# @param shell :: String (Optional) Shell interpreter for every node.
--#   Overrides per-node shell.
--# @param shell_args :: String | List[String] (Optional) Shell arguments.
--#   Prepended before per-node shell args.
--# @param flake :: String (Optional) Nix flake path for every node.
--#   Overrides per-node flake.
--# @param dependencies :: String | List[String] (Optional) Explicit dependencies.
--#   Prepended before per-node dependencies.
--# @return :: Pipeline A new pipeline with the settings merged into every node.
--# @family pipeline
--# @export
--# @example
--*)

let register env =
  Env.add "set_pipeline_global_options"
    (make_builtin_named ~name:"set_pipeline_global_options" ~variadic:true 1 (fun named_args _env ->
      let known_keys = ["functions"; "include"; "env_vars"; "serializer"; "deserializer";
                        "noop"; "args"; "shell"; "shell_args"; "flake"; "dependencies"] in
      match List.find_opt (fun (k, _) -> k <> None && not (List.mem (Option.get k) known_keys)) named_args with
      | Some (Some k, _) ->
          Error.type_error (Printf.sprintf
            "set_pipeline_global_options: unknown argument '%s'. Supported arguments are: functions, include, env_vars, serializer, deserializer, noop, args, shell, shell_args, flake, dependencies."
            k)
      | _ ->
        match List.assoc_opt None named_args with
        | Some (VPipeline p) ->
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
              | VSerializer s -> Ok (Some (mk_expr (Value (VString s.s_format))))
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
              | VString s -> Ok [s]
              | VSymbol s -> Ok [s]
              | VList items ->
                  Ok (List.filter_map (fun (_, v') ->
                    match v' with VString s | VSymbol s -> Some s | _ -> None
                  ) items)
              | VNA _ -> Ok []
              | other ->
                  Error (Error.type_error
                    (Printf.sprintf
                       "set_pipeline_global_options: expected a string or list of strings for `dependencies`, but got %s."
                       (Utils.type_name other)))
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
              | None -> Ok []
            in

            (* --- apply all results, bailing on first error --- *)

            (match functions_result, env_vars_result, serializer_result, deserializer_result,
                    noop_result, args_result, shell_result, flake_result, deps_result with
             | Error e, _, _, _, _, _, _, _, _ -> e
             | _, Error e, _, _, _, _, _, _, _ -> e
             | _, _, Error e, _, _, _, _, _, _ -> e
             | _, _, _, Error e, _, _, _, _, _ -> e
             | _, _, _, _, Error e, _, _, _, _ -> e
             | _, _, _, _, _, Error e, _, _, _ -> e
             | _, _, _, _, _, _, Error e, _, _ -> e
             | _, _, _, _, _, _, _, Error e, _ -> e
             | _, _, _, _, _, _, _, _, Error e -> e
             | Ok global_functions, Ok global_env_vars, Ok global_serializer, Ok global_deserializer,
                 Ok global_noop, Ok global_args, Ok global_shell, Ok global_flake, Ok global_deps ->

                 let updated_functions = List.map (fun (name, funcs) ->
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
                   (name, includes @ incs)
                 ) p.p_includes in

                 let updated_env_vars = List.map (fun (name, vars) ->
                   (name, global_env_vars @ vars)
                 ) p.p_env_vars in

                 let updated_args = List.map (fun (name, rt_args) ->
                   (name, global_args @ rt_args)
                 ) p.p_args in

                 let updated_serializers = match global_serializer with
                   | Some s -> List.map (fun (name, _) -> (name, s)) p.p_serializers
                   | None -> p.p_serializers
                 in

                 let updated_deserializers = match global_deserializer with
                   | Some d -> List.map (fun (name, _) -> (name, d)) p.p_deserializers
                   | None -> p.p_deserializers
                 in

                 let updated_noops = if global_noop then
                   List.map (fun (name, _) -> (name, true)) p.p_noops
                 else
                   p.p_noops
                 in

                 let updated_shells = match global_shell with
                   | Some s -> List.map (fun (name, _) -> (name, Some s)) p.p_shells
                   | None -> p.p_shells
                 in

                 let updated_shell_args = List.map (fun (name, args) ->
                   (name, shell_args @ args)
                 ) p.p_shell_args in

                 let updated_flakes = match global_flake with
                   | Some f -> List.map (fun (name, _) -> (name, Some f)) p.p_flakes
                   | None -> p.p_flakes
                 in

                 let updated_deps = List.map (fun (name, deps) ->
                   let merged = global_deps @ match deps with Some d -> d | None -> [] in
                   (name, Some merged)
                 ) p.p_explicit_deps in

                 VPipeline {
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
                 })
        | Some other ->
            Error.type_error (Printf.sprintf "set_pipeline_global_options: expected a pipeline, got %s." (Utils.type_name other))
        | None ->
            Error.arity_error_named "set_pipeline_global_options" 1 0
    ))
    env
