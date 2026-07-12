(* src/packages/pipeline/t_check.ml *)
(* REPL-callable version of `t check` — validates pipeline structure,
   column references, schema contracts, and environment declarations. *)

open Ast

(*
--# Check a T Script for Errors
--#
--# Runs structural, wire-phase, schema, and environment checks on a T script.
--# Returns the same diagnostics as the CLI `t check` command.
--#
--# @name t_check
--# @param file :: String The path to the .t file to check.
--# @param json :: Bool = false Output diagnostics as JSON.
--# @param schema :: Bool = false Enable column-level schema validation.
--# @param env :: Bool = false Enable tproject.toml environment checks.
--# @param offline :: Bool = false Prevent network access during env checks.
--# @return :: String The formatted diagnostics (text or JSON).
--# @family pipeline
--# @export
*)

let register env =
  Env.add "t_check"
    (make_builtin_named ~name:"t_check" ~variadic:true 1 (fun named_args _env ->
      let named_keys = List.filter_map (fun (k, _) -> k) named_args in
      let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
      match List.find_opt (fun k -> not (List.mem k ["file"; "json"; "schema"; "env"; "offline"])) named_keys with
      | Some k ->
          Error.type_error (Printf.sprintf "t_check: unknown argument '%s'" k)
      | None when positional_count > 1 ->
          Error.make_error ArityError
            (Printf.sprintf "Function `t_check` accepts at most 1 positional argument but received %d." positional_count)
      | None ->
        match Pipeline_args.get_arg "file" 1 (VNA NAGeneric) named_args with
        | (_, VString filename) ->
            let (_, json_val) = Pipeline_args.get_arg "json" 2 (VBool false) named_args in
            let (_, schema_val) = Pipeline_args.get_arg "schema" 3 (VBool false) named_args in
            let (_, env_val) = Pipeline_args.get_arg "env" 4 (VBool false) named_args in
            let (_, offline_val) = Pipeline_args.get_arg "offline" 5 (VBool false) named_args in

            let json_result =
              match json_val with
              | VBool b -> Ok b
              | _ -> Error (Error.type_error "Function `t_check` expects `json` to be a Bool.")
            in
            let schema_result =
              match schema_val with
              | VBool b -> Ok b
              | _ -> Error (Error.type_error "Function `t_check` expects `schema` to be a Bool.")
            in
            let env_result =
              match env_val with
              | VBool b -> Ok b
              | _ -> Error (Error.type_error "Function `t_check` expects `env` to be a Bool.")
            in
            let offline_result =
              match offline_val with
              | VBool b -> Ok b
              | _ -> Error (Error.type_error "Function `t_check` expects `offline` to be a Bool.")
            in

            let (let*) x f = match x with Ok v -> f v | Error e -> e in
            let* do_json = json_result in
            let* do_schema = schema_result in
            let* do_env = env_result in
            let* do_offline = offline_result in

            let check_result = Check_utils.run_check ~schema:do_schema ~env_check:do_env ~offline:do_offline Typecheck.Strict filename Env.empty in
            VString (Check_utils.format_check_result ~json:do_json check_result)
        | (_, other) ->
            Error.type_error
              (Printf.sprintf "Function `t_check` expects a file path (String) as first argument, but got %s."
                 (Utils.type_name other))
    )) env
