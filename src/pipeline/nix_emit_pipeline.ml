open Ast
open Nix_unparse
open Nix_emit_node

let emit_pipeline (p : Ast.pipeline_result) =
  let import_lines = List.filter_map (fun stmt ->
    let s = unparse_import_stmt stmt in
    if s = "" then None else Some s
  ) p.p_imports in
  let node_names = List.map fst p.p_exprs in

  let is_arrow_ser_or_des name =
    let ser = List.assoc name p.p_serializers in
    let des = List.assoc name p.p_deserializers in
    (match ser with Value (VString "arrow") -> true | _ -> false) ||
    (match des with Value (VString "arrow") -> true | _ -> false)
  in
  let needs_r_arrow = p.p_exprs |> List.exists (fun (name, _) ->
    let runtime = List.assoc name p.p_runtimes in
    runtime = "R" && is_arrow_ser_or_des name
  ) in
  let needs_py_arrow = p.p_exprs |> List.exists (fun (name, _) ->
    let runtime = List.assoc name p.p_runtimes in
    runtime = "Python" && is_arrow_ser_or_des name
  ) in

  let is_pmml_ser_or_des name =
    let ser = List.assoc name p.p_serializers in
    let des = List.assoc name p.p_deserializers in
    (match ser with Value (VString "pmml") -> true | _ -> false) ||
    (match des with Value (VString "pmml") -> true | _ -> false)
  in
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
      emit_node (name, expr) deps node_names import_lines runtime serializer deserializer env_vars runtime_args functions includes noop script)

    |> String.concat "\n"
  in
  let final_copy =
    node_names
    |> List.map (fun n -> Printf.sprintf "      cp -r ${%s} $out/%s" n n)
    |> String.concat "\n"
  in
  let is_csv_ser_or_des name =
    let ser = List.assoc name p.p_serializers in
    let des = List.assoc name p.p_deserializers in
    (match ser with Value (VString "csv") -> true | _ -> false) ||
    (match des with
     | Value (VString "csv") -> true
     | ListLit items -> List.exists (fun (_, e) -> match e with Value (VString "csv") -> true | _ -> false) items
     | DictLit items -> List.exists (fun (_, e) -> match e with Value (VString "csv") -> true | _ -> false) items
     | _ -> false)
  in
  let needs_py_csv = p.p_exprs |> List.exists (fun (name, _) ->
    let runtime = List.assoc name p.p_runtimes in
    runtime = "Python" && is_csv_ser_or_des name
  ) in

  let r_extra_pkgs = 
    (if needs_r_arrow then " pkgs.rPackages.arrow" else "") ^
    (if needs_r_pmml then " pkgs.rPackages.r2pmml pkgs.rPackages.XML" else "")
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
  flake  = builtins.getFlake (toString ../.);
  pkgs   = flake.inputs.nixpkgs.legacyPackages.${system};
  tBin   = let
             base = (flake.inputs.t-lang or flake).packages.${system}.default;
           in if builtins.pathExists ../dune-project then
             base.overrideAttrs (old: { src = sources; })
           else base;
  stdenv = pkgs.stdenv;

  # Filter out _pipeline/, .git/, and other non-source directories
  sources = builtins.filterSource
    (path: type:
      let baseName = builtins.baseNameOf path;
      in !(baseName == "_pipeline" || baseName == ".git" || baseName == ".direnv" || baseName == "_build"))
    ./..;

  toml = if builtins.pathExists ../tproject.toml then builtins.fromTOML (builtins.readFile ../tproject.toml) else {};
  
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
|} r_extra_pkgs py_extra_pkgs nodes (String.concat " " node_names) final_copy
