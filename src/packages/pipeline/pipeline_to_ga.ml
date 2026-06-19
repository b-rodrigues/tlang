open Ast

let get_project_name () =
  try
    let root = Builder_utils.get_project_root () in
    let path = Filename.concat root "tproject.toml" in
    if Sys.file_exists path then
      let ic = open_in path in
      let content =
        Fun.protect ~finally:(fun () -> close_in_noerr ic)
          (fun () -> really_input_string ic (in_channel_length ic))
      in
      match Toml_parser.parse_tproject_toml content with
      | Ok cfg when String.length cfg.proj_name > 0 -> Some cfg.proj_name
      | _ -> None
    else None
  with _ -> None

let display_name name =
  let words = List.map (fun s ->
    if String.length s > 0 then
      String.make 1 (Char.uppercase_ascii s.[0]) ^ String.sub s 1 (String.length s - 1)
    else ""
  ) (String.split_on_char '_' name) in
  String.concat " " words

let job_name name =
  String.map (fun c -> if c = '_' then '-' else c) name

let generate_yaml ~name =
  let dj = job_name name in
  let dn = display_name name in
  let buf = Buffer.create 512 in
  let pf fmt = Printf.ksprintf (fun s -> Buffer.add_string buf s) fmt in
  pf "name: Demo %s\n" dn;
  pf "on:\n";
  pf "  push:\n";
  pf "    branches: [ main, master ]\n";
  pf "  pull_request:\n";
  pf "    branches: [ main, master ]\n";
  pf "  workflow_dispatch:\n";
  pf "env:\n";
  pf "  NAR_ARCHIVE: %s.nar\n" name;
  pf "jobs:\n";
  pf "  %s:\n" dj;
  pf "    runs-on: ubuntu-latest\n";
  pf "    permissions:\n";
  pf "      contents: write\n";
  pf "    steps:\n";
  pf "      - uses: actions/checkout@v4\n";
  pf "\n";
  pf "      - uses: cachix/install-nix-action@v31\n";
  pf "        with:\n";
  pf "          extra_nix_config: |\n";
  pf "            experimental-features = nix-command flakes\n";
  pf "            substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org\n";
  pf "            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=\n";
  pf "\n";
  pf "      - name: Restore cached artifacts\n";
  pf "        run: |\n";
  pf "          git fetch origin t-runs --depth=1 || true\n";
  pf "          git checkout origin/t-runs -- \"$NAR_ARCHIVE\" 2>/dev/null || true\n";
  pf "          [ -f \"$NAR_ARCHIVE\" ] && nix-store --import < \"$NAR_ARCHIVE\" || true\n";
  pf "\n";
  pf "      - name: Run pipeline\n";
  pf "        run: nix develop --command t run src/pipeline.t\n";
  pf "\n";
  pf "      - name: Cache artifacts to t-runs branch\n";
  pf "        run: |\n";
  pf "          t export_artifacts src/pipeline.t \"$NAR_ARCHIVE\"\n";
  pf "          git config user.name \"github-actions[bot]\"\n";
  pf "          git config user.email \"github-actions[bot]@users.noreply.github.com\"\n";
  pf "          git fetch origin t-runs || true\n";
  pf "          git checkout t-runs 2>/dev/null || git checkout --orphan t-runs\n";
  pf "          cp \"$NAR_ARCHIVE\" .\n";
  pf "          git add \"$NAR_ARCHIVE\"\n";
  pf "          git diff --cached --quiet || git commit -m \"Update artifacts for %s\"\n" name;
  pf "          git diff --cached --quiet || git push origin HEAD:t-runs --force\n";
  Buffer.contents buf

(*
--# Export Pipeline as GitHub Actions Workflow
--#
--# Generates a GitHub Actions CI workflow YAML that runs the pipeline on
--# push/PR. The workflow restores cached Nix artifacts from the `t-runs`
--# branch, executes the pipeline, and re-exports updated artifacts back
--# to `t-runs`. Use the `file` parameter to write the YAML directly to
--# `.github/workflows/<name>.yml`.
--#
--# @name pipeline_to_ga
--# @param p :: Pipeline The pipeline.
--# @param name :: String (Optional) Project name. Auto-detected from tproject.toml when omitted.
--# @param file :: String (Optional) Output file path. If omitted, returns the YAML string.
--# @return :: String The YAML workflow content or the output file path.
--# @example
--#   pipeline_to_ga(p)
--#   pipeline_to_ga(p, name = "my-project")
--#   pipeline_to_ga(p, file = ".github/workflows/ci.yml")
--# @family pipeline
--# @export
*)
let register env =
  let known = ["p"; "name"; "file"] in
  let ga_fn named_args _env =
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional = List.filter (fun (k, _) -> k = None) named_args in
    let get_named name default =
      match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
      | Some v -> v
      | None -> default
    in
    let get_named_str name default =
      match get_named name (VNA NAGeneric) with
      | VString s when String.length s > 0 -> s
      | _ -> default
    in
    match List.find_opt (fun k -> not (List.mem k known)) named_keys with
    | Some k ->
        Error.type_error
          (Printf.sprintf
             "Unknown argument `%s` for function `pipeline_to_ga`.\nValid arguments: p (positional, required), name, file."
             k)
    | None when List.length positional > 1 ->
        Error.arity_error_named "pipeline_to_ga" 1 (List.length positional)
    | None ->
    let pipeline_arg = List.find_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
    (match pipeline_arg with
     | Some (VPipeline _p) ->
         let name_res =
           let n = get_named_str "name" "" in
           if n <> "" then Ok n
           else match get_project_name () with
                | Some n -> Ok n
                | None ->
                    Error
                      "Could not determine project name.\nProvide `name = \"...\"` or ensure `tproject.toml` exists with a `[project] name` field."
         in
         (match name_res with
          | Error msg -> Error.make_error RuntimeError msg
          | Ok name ->
              let yaml = generate_yaml ~name in
              match get_named "file" (VNA NAGeneric) with
              | VString path when String.length path > 0 ->
                  let dir = Filename.dirname path in
                  let dir_result =
                    if dir <> "" && dir <> "." then
                      (try Ok (Builder_utils.ensure_dir dir)
                       with e -> Error (Printexc.to_string e))
                    else Ok ()
                  in
                  (match dir_result with
                   | Error reason ->
                       Error.make_error FileError
                         (Printf.sprintf
                            "Cannot create directory `%s` for output file `%s`.\nReason: %s"
                            dir path reason)
                   | Ok () ->
                       (match Builder_utils.write_file path yaml with
                        | Ok () -> VString (Printf.sprintf "Wrote workflow to %s" path)
                        | Error msg ->
                            Error.make_error FileError
                              (Printf.sprintf "Failed to write workflow to `%s`.\nReason: %s" path msg)))
              | VString "" ->
                  Error.value_error
                    "Argument `file` was an empty string.\nOmit `file` to get the YAML back as a String, or pass a path such as `\".github/workflows/ci.yml\"`."
              | _ -> VString yaml)
     | Some other ->
         Error.type_error ~arg_index:1
           (Printf.sprintf "Function `pipeline_to_ga` expects a Pipeline, but got %s." (Utils.type_name other))
     | None ->
         Error.arity_error_named "pipeline_to_ga" 1 (List.length positional))
  in
  Env.add "pipeline_to_ga" (make_builtin_named ~name:"pipeline_to_ga" ~variadic:true 1 ga_fn) env
