open Ast

(*
--# Set Pipeline Global Options (pure)
--#
--# Pure function that returns a new pipeline with the given defaults merged
--# into every node.  The original pipeline is not modified.
--#
--# Currently supported options:
--#   `functions` :: Dict  A dictionary mapping runtime names to file path(s).
--#   `include`   :: Any   File path(s) to make available in every node's sandbox.
--#
--# @name set_pipeline_global_options
--# @param pipeline :: Pipeline The input pipeline.
--# @param functions :: Dict (Optional) A dict of runtime shorthands to function files.
--#   For example: `[rn: "functions.R", pyn: ["preproc.py", "utils.py"]]`.
--#   Each value may be a single path (String) or a list of paths (List[String]).
--#   Supported runtime shorthands match the existing node constructors:
--#   `rn`, `pyn`, `jln`, `qn`, `shn`, and `node` for T nodes.
--#   Per-node `functions` arguments are appended after these global files.
--# @param include :: String | List[String] (Optional) File path(s) to include
--#   in every node's sandbox.  Per-node `include` arguments are appended after
--#   these global includes.
--# @return :: Pipeline A new pipeline with the settings merged into every node.
--# @family pipeline
--# @export
--# @example
--#   p = pipeline { n1 = rn(command = <{ 1 + 1 }>) }
--#   q = set_pipeline_global_options(p,
--#         functions = [rn: "functions.R"],
--#         include = "shared/config.yaml"
--#       )
--*)

let register env =
  Env.add "set_pipeline_global_options"
    (make_builtin_named ~name:"set_pipeline_global_options" ~variadic:true 1 (fun named_args _env ->
      let known_keys = ["functions"; "include"] in
      match List.find_opt (fun (k, _) -> k <> None && not (List.mem (Option.get k) known_keys)) named_args with
      | Some (Some k, _) ->
          Error.type_error (Printf.sprintf "set_pipeline_global_options: unknown argument '%s'. Supported arguments are: functions, include." k)
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
            let functions_result = match List.assoc_opt (Some "functions") named_args with
              | Some expr -> parse_functions expr
              | None -> Ok []
            in
            let includes = match List.assoc_opt (Some "include") named_args with
              | Some expr -> options_value_to_expr_list expr
              | None -> []
            in
            (match functions_result with
             | Error e -> e
             | Ok global_functions ->
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
                 VPipeline { p with p_functions = updated_functions; p_includes = updated_includes })
        | Some other ->
            Error.type_error (Printf.sprintf "set_pipeline_global_options: expected a pipeline, got %s." (Utils.type_name other))
        | None ->
            Error.arity_error_named "set_pipeline_global_options" 1 0
    ))
    env
