open Ast

(*
--# Set Global Nix Orchestration Defaults
--#
--# Sets persistent session-wide default Nix options.
--#
--# @name set_nix_defaults
--# @param nix_options :: Dict A dictionary of default Nix orchestration options:
--#   - `force` :: Bool|List[String] Force-rebuild nodes even if cached. Maps to `--check`.
--#   - `dry_run` :: Bool Return a planned build DataFrame without executing. Maps to `--dry-run`.
--#   - `max_jobs` :: Int Maximum parallel build jobs. Maps to `--max-jobs N`.
--#   - `cache` :: String Cachix cache name to configure as an extra binary substituter.
--#   - `builders` :: String Nix remote builders config.
--#   - `keep_env` :: List[String] Environment variables to pass through to the Nix sandbox.
--#   - `sandbox` :: Bool|String Nix isolation sandbox policy ("relaxed", "strict", "none").
--# @return :: String Returns "Nix defaults updated" upon successfully setting the defaults.
--# @family pipeline
--# @export
*)
let register env =
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> (true, v)
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
        else (false, default)
  in
  let set_fn named_args _env =
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["nix_options"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "set_nix_defaults: unknown argument '%s'" k)
    | None when positional_count > 1 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `set_nix_defaults` accepts at most 1 positional argument but received %d." positional_count)
    | None ->
      match get_arg "nix_options" 1 (VDict []) named_args with
      | (_, VDict pairs) ->
          (match Builder_utils.validate_nix_options "set_nix_defaults" pairs with
           | Ok opts ->
               Builder_utils.global_nix_defaults := opts;
               VString "Nix defaults updated"
           | Error e -> e)
      | _ -> Error.type_error "Function `set_nix_defaults` expects a Dictionary of options."
  in
  Env.add "set_nix_defaults" (make_builtin_named ~name:"set_nix_defaults" ~variadic:true 0 set_fn) env
