open Ast

(*
--# Set Pipeline Global Options
--#
--# Declares default settings applied to every node in subsequent pipeline blocks.
--# Call this at the top of a pipeline script to avoid repeating common arguments
--# (such as shared R/Python function files or config files) on every node.
--#
--# Currently supported options:
--#   `functions` :: Dict  A dictionary mapping runtime names to file path(s).
--#   `include`   :: Any  File path(s) to make available in every node's sandbox.
--#
--# @name pipeline_options
--# @param functions :: Dict (Optional) A dict of runtime shorthands to function files.
--#   For example: `[rn: "functions.R", pyn: ["preproc.py", "utils.py"]]`.
--#   Each value may be a single path (String) or a list of paths (List[String]).
--#   Supported runtime shorthands match the existing node constructors:
--#   `rn`, `pyn`, `jln`, `qn`, `shn`, and `node` for T nodes.
--#   Per-node `functions` arguments are appended after these global files.
--# @param include :: String | List[String] (Optional) File path(s) to include
--#   in every node's sandbox.  Per-node `include` arguments are appended after
--#   these global includes.
--# @return :: NullNode
--# @family pipeline
--# @export
--# @example
--#   pipeline_options(
--#     functions = [rn: "functions.R"],
--#     include = "shared/config.yaml"
--#   )
--*)

let register env =
  Env.add "pipeline_options"
    (make_builtin_named ~name:"pipeline_options" ~variadic:true 0 (fun named_args _env ->
      let known_keys = ["functions"; "include"] in
      match List.find_opt (fun (k, _) -> k <> None && not (List.mem (Option.get k) known_keys)) named_args with
      | Some (Some k, _) ->
          Error.type_error (Printf.sprintf "pipeline_options: unknown argument '%s'. Supported arguments are: functions, include." k)
      | _ ->
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
                | Some runtime -> Some (translate_runtime runtime, files_val)
                | None -> None
              ) pairs)
          | VDict pairs ->
              Ok (List.map (fun (runtime_name, files_val) ->
                (translate_runtime runtime_name, files_val)
              ) pairs)
          | VNA _ -> Ok []
          | other ->
              Error (Error.type_error
                (Printf.sprintf
                   "pipeline_options: expected `functions` to be a list or dict (e.g. [rn: \"f.R\"]), but got %s."
                   (Utils.type_name other)))
        in
        let functions_result = match List.assoc_opt (Some "functions") named_args with
          | Some expr -> parse_functions expr
          | None -> Ok []
        in
        let includes = match List.assoc_opt (Some "include") named_args with
          | Some expr -> Ast.options_value_to_strings expr
          | None -> []
        in
        match functions_result with
        | Error e -> e
        | Ok functions ->
            Ast.pipeline_global_settings := {
              global_functions = functions;
              global_includes = List.map (fun s -> VString s) includes;
            };
            VNullNode
    ))
    env
