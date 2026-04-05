open Ast
open Nix_unparse
open Nix_emit_node

let emit_pipeline ?(rel_root="..") (p : Ast.pipeline_result) =
  let import_lines = List.filter_map (fun stmt ->
    let s = unparse_import_stmt stmt in
    if s = "" then None else Some s
  ) p.p_imports in
  let node_names = List.map fst p.p_exprs in

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
  let required = Pipeline_dependency_requirements.required_for_pipeline p in
  let auto_add =
    match Sys.getenv_opt "TLANG_AUTO_ADD_PIPELINE_DEPS" with
    | Some "1" | Some "true" | Some "TRUE" | Some "yes" | Some "YES" | Some "on" | Some "ON" -> true
    | _ -> false
  in
  let extra_r = if auto_add then Pipeline_dependency_requirements.String_set.elements required.r_deps else [] in
  let extra_py = if auto_add then Pipeline_dependency_requirements.String_set.elements required.py_deps else [] in
  let extra_tools = if auto_add then Pipeline_dependency_requirements.String_set.elements required.additional_tools else [] in
  let extra_latex = if auto_add then Pipeline_dependency_requirements.String_set.elements required.latex_pkgs else [] in

  let to_nix_list lst = "[" ^ (String.concat " " (List.map (Printf.sprintf "\"%s\"") lst)) ^ "]" in
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
  
  extraR = %s;
  extraPy = %s;
  extraTools = %s;
  extraLatex = %s;

  rPackagesList = ((toml.r-dependencies or {}).packages or []) ++ extraR;
  r-env = pkgs.rWrapper.override {
    packages = (builtins.map (p: pkgs.rPackages.${p}) rPackagesList);
  };

  pyDeps = toml.py-dependencies or toml.python-dependencies or {};
  pyVersion = pyDeps.version or "python3";
  pyPackagesList = (pyDeps.packages or []) ++ extraPy;
  py-env = pkgs.${pyVersion}.withPackages (ps: (builtins.map (p: ps.${p}) pyPackagesList));

  # Additional Tools & LaTeX
  additionalTools = ((toml.additional-tools or {}).packages or []) ++ extraTools;
  latexPkgs = ((toml.latex or {}).packages or []) ++ extraLatex;
  
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
|} rel_root rel_root rel_root rel_root rel_root 
   (to_nix_list extra_r) (to_nix_list extra_py) (to_nix_list extra_tools) (to_nix_list extra_latex)
   nodes (String.concat " " node_names) final_copy
