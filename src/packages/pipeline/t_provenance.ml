(* src/packages/pipeline/t_provenance.ml *)

open Ast

(*
--# Generate Reproducibility & Audit Provenance Bundle
--#
--# Collects local project metadata (`tproject.toml`), locked Nix flake inputs
--# (`flake.lock`), the latest `_pipeline/build_log_*.json` with `foreign_meta`
--# sidecars, and `intent { ... }` blocks into an offline, deterministic
--# provenance manifest. Supports RO-Crate 1.1 JSON-LD (`"ro-crate"`),
--# CycloneDX 1.5 SBOM (`"sbom"`), and T-native JSON (`"json"`).
--#
--# @name t_provenance
--# @param format :: String = "ro-crate" Output format: "ro-crate", "sbom", or "json".
--# @param output :: String = NA Optional file path to write the manifest to.
--# @param dir :: String = "." Optional project root directory.
--# @param file :: String = NA Optional `.t` file to extract `intent` blocks from.
--# @param include_meta :: Bool = true Include `foreign_meta` sidecars in the manifest.
--# @return :: String The formatted JSON provenance manifest.
--# @example
--#   t_provenance()
--#   t_provenance(format = "sbom", output = "sbom.cdx.json")
--#   t_provenance(format = "ro-crate", output = "ro-crate-metadata.json", include_meta = false)
--# @family pipeline
--# @seealso pipeline_report, pipeline_overview, pipeline_metrics
--# @export
*)

let allowed_args = ["format"; "output"; "dir"; "file"; "include_meta"]

let t_provenance_fn named_args _env =
  let unknown =
    List.find_map (fun (k, _) ->
      match k with
      | Some n when not (List.mem n allowed_args) -> Some n
      | _ -> None
    ) named_args
  in
  match unknown with
  | Some name ->
      Error.type_error
        (Printf.sprintf "Function `t_provenance` got an unknown argument `%s`. Supported arguments: format, output, dir, file, include_meta." name)
  | None ->
      let get_opt_str key pos_idx =
        let named = List.find_map (fun (k, v) -> if k = Some key then Some v else None) named_args in
        let positional = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        let v_opt = match named with Some v -> Some v | None -> List.nth_opt positional pos_idx in
        match v_opt with
        | None | Some (VNA _) -> Ok None
        | Some (VString s) -> Ok (Some s)
        | Some v ->
            Error (Error.type_error
              (Printf.sprintf "Function `t_provenance` argument `%s` must be a String, but got %s."
                 key (Utils.type_name v)))
      in
      let get_bool key default =
        match List.find_map (fun (k, v) -> if k = Some key then Some v else None) named_args with
        | None | Some (VNA _) -> Ok default
        | Some (VBool b) -> Ok b
        | Some v ->
            Error (Error.type_error
              (Printf.sprintf "Function `t_provenance` argument `%s` must be a Bool, but got %s."
                 key (Utils.type_name v)))
      in
      (match get_opt_str "format" 0, get_opt_str "output" 1, get_opt_str "dir" 2, get_opt_str "file" 3, get_bool "include_meta" true with
       | Error e, _, _, _, _ | _, Error e, _, _, _ | _, _, Error e, _, _ | _, _, _, Error e, _ | _, _, _, _, Error e -> e
       | Ok fmt_opt, Ok output, Ok dir_opt, Ok file, Ok include_meta ->
           let format = Option.value ~default:"ro-crate" fmt_opt in
           let dir = Option.value ~default:"." dir_opt in
           (match Provenance.write_bundle ~dir ?file ?output ~include_meta ~format () with
            | Ok payload -> VString payload
            | Error msg -> Error.value_error (Printf.sprintf "t_provenance: %s" msg)))

let register env =
  Env.add "t_provenance"
    (make_builtin_named ~name:"t_provenance" ~variadic:true 0 t_provenance_fn)
    env
