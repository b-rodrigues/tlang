open Ast
open Nix_unparse
open Nix_emit_node

let emit_pipeline ?(rel_root="..") (p : Ast.pipeline_result) =
  let import_lines = List.filter_map (fun stmt ->
    let s = unparse_import_stmt stmt in
    if s = "" then None else Some s
  ) p.p_imports in
  let node_names = List.map fst p.p_exprs in

  let check_strategy name target =
    let ser_expr = List.assoc name p.p_serializers in
    let des_expr = List.assoc name p.p_deserializers in
    let eval_expr e = Eval.eval_expr (ref Ast.Env.empty) e in
    let ser = eval_expr ser_expr in
    let des = eval_expr des_expr in
    let has_fmt v =
      let get_fmt = function
        | Ast.VSerializer s -> Some s.s_format
        | Ast.VString s | Ast.VSymbol s -> Some (if String.starts_with ~prefix:"^" s then String.sub s 1 (String.length s - 1) else s)
        | Ast.VDict pairs -> (match List.assoc_opt "format" pairs with Some (VString s) | Some (VSymbol s) -> Some s | _ -> None)
        | _ -> None
      in
      match get_fmt v with
      | Some s ->
          let s = String.lowercase_ascii s in
          s = target || (target = "arrow" && (s = "write_parquet" || s = "read_parquet" || s = "write_feather" || s = "read_feather"))
      | None -> false
    in
    has_fmt ser || has_fmt des
  in
  let is_arrow_ser_or_des name = check_strategy name "arrow" in
  let needs_r_arrow = p.p_exprs |> List.exists (fun (name, _) ->
    let runtime = List.assoc name p.p_runtimes in
    runtime = "R" && is_arrow_ser_or_des name
  ) in
  let needs_py_arrow = p.p_exprs |> List.exists (fun (name, _) ->
    let runtime = List.assoc name p.p_runtimes in
    runtime = "Python" && is_arrow_ser_or_des name
  ) in

  let is_pmml_ser_or_des name = check_strategy name "pmml" in
  let needs_r_pmml = p.p_exprs |> List.exists (fun (name, _) ->
    let runtime = List.assoc name p.p_runtimes in
    runtime = "R" && is_pmml_ser_or_des name
  ) in
  let needs_py_pmml = p.p_exprs |> List.exists (fun (name, _) ->
    let runtime = List.assoc name p.p_runtimes in
    runtime = "Python" && is_pmml_ser_or_des name
  ) in

  let nodes =
    p.p_exprs
    |> List.map (fun (name, expr) ->
      let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
      let runtime = List.assoc name p.p_runtimes in
      let serializer = List.assoc name p.p_serializers in
      let deserializer = List.assoc name p.p_deserializers in
      let env_vars = match List.assoc_opt name p.p_env_vars with Some vars -> vars | None -> [] in
      let runtime_args = match List.assoc_opt name p.p_args with Some args -> args | None -> [] in
      let functions = match List.assoc_opt name p.p_functions with Some f -> f | None -> [] in
      let includes = match List.assoc_opt name p.p_includes with Some f -> f | None -> [] in
      let noop = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
      let script = match List.assoc_opt name p.p_scripts with Some s -> s | None -> None in
      let shell = match List.assoc_opt name p.p_shells with Some s -> s | None -> None in
      let shell_args = match List.assoc_opt name p.p_shell_args with Some args -> args | None -> [] in
      emit_node (name, expr) deps node_names import_lines runtime serializer deserializer env_vars runtime_args functions includes noop script shell shell_args)
    |> String.concat "\n"
  in
  let final_copy =
    node_names
    |> List.map (fun n -> Printf.sprintf "      cp -r ${%s} $out/%s" n n)
    |> String.concat "\n"
  in
  let is_csv_ser_or_des name = check_strategy name "csv" in
  let needs_py_csv = p.p_exprs |> List.exists (fun (name, _) ->
    let runtime = List.assoc name p.p_runtimes in
    runtime = "Python" && is_csv_ser_or_des name
  ) in
  let needs_r_csv = p.p_exprs |> List.exists (fun (name, _) ->
    let runtime = List.assoc name p.p_runtimes in
    runtime = "R" && is_csv_ser_or_des name
  ) in

  let r_extra_pkgs = 
    (if needs_r_arrow then " pkgs.rPackages.arrow" else "") ^
    (if needs_r_pmml then " pkgs.rPackages.r2pmml pkgs.rPackages.XML" else "") ^
    (if needs_r_csv then " pkgs.rPackages.readr pkgs.rPackages.dplyr" else "")
  in
  let py_extra_pkgs = 
    (if needs_py_arrow then " ++ [ ps.pyarrow ps.pandas ]" else "") ^
    (if needs_py_pmml then " ++ [ ps.sklearn2pmml ps.scikit-learn ps.pandas ps.scipy ps.numpy ps.statsmodels ]" else "") ^
    (if needs_py_csv then " ++ [ ps.pandas ps.pyarrow ]" else "")
  in
  Printf.sprintf {|
{ system ? builtins.currentSystem }:
let
  # Pull exact pinned inputs from the project flake.
  # The flake.lock guarantees reproducibility.
  # Note: toString is required to convert the path to a string
  # that builtins.getFlake accepts.
  flake  = builtins.getFlake (toString %s/.);
  pkgs   = flake.inputs.nixpkgs.legacyPackages.${system};
  tBin   = let
             base = (flake.inputs.t-lang or flake).packages.${system}.default;
           in if builtins.pathExists %s/dune-project then
             base.overrideAttrs (old: { src = sources; })
           else base;
  stdenv = pkgs.stdenv;

  # Filter out _pipeline/, .git/, and other non-source directories
  sources = builtins.filterSource
    (path: type:
      let baseName = builtins.baseNameOf path;
      in !(baseName == "_pipeline" || baseName == ".git" || baseName == ".direnv" || baseName == "_build"))
    %s/.;

  toml = if builtins.pathExists %s/tproject.toml then builtins.fromTOML (builtins.readFile %s/tproject.toml) else {};
  
  rPackagesList = (toml.r-dependencies or {}).packages or [];
  r-env = pkgs.rWrapper.override {
    packages = (builtins.map (p: pkgs.rPackages.${p}) rPackagesList) ++ [ pkgs.rPackages.jsonlite%s ];
  };

  pyDeps = toml.py-dependencies or toml.python-dependencies or {};
  pyVersion = pyDeps.version or "python3";
  pyPackagesList = pyDeps.packages or [];
  py-env = pkgs.${pyVersion}.withPackages (ps: (builtins.map (p: ps.${p}) pyPackagesList)%s);

  # Additional Tools & LaTeX
  additionalTools = (toml.additional-tools or {}).packages or [];
  latexPkgs = (toml.latex or {}).packages or [];
  
  latexCombined = if latexPkgs == [] then null 
                  else pkgs.texlive.combine (builtins.listToAttrs (builtins.map (name: { name = name; value = pkgs.texlive.${name}; }) (["scheme-small"] ++ latexPkgs)));
                  
  globalBuildInputs = (builtins.map (p: pkgs.${p}) additionalTools)
                      ++ (if latexCombined == null then [] else [ latexCombined ]);
in
rec {
%s
  pipeline_output = stdenv.mkDerivation {
    name = "pipeline_output";
    buildInputs = [ tBin %s ] ++ globalBuildInputs;
    buildCommand = ''
      mkdir -p $out
%s
    '';
  };
}
|} rel_root rel_root rel_root rel_root rel_root r_extra_pkgs py_extra_pkgs nodes (String.concat " " node_names) final_copy
