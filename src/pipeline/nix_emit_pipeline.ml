open Ast
open Nix_unparse
open Nix_emit_node

let sanitize_flake_path path =
  let buf = Buffer.create (String.length path) in
  String.iter (fun c ->
    match c with
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> Buffer.add_char buf c
    | _ ->
        let len = Buffer.length buf in
        if len > 0 && Buffer.nth buf (len - 1) <> '_' then Buffer.add_char buf '_'
  ) path;
  let s = Buffer.contents buf in
  let s = if String.length s > 0 && s.[0] = '_' then String.sub s 1 (String.length s - 1) else s in
  let s = if String.length s > 0 && s.[String.length s - 1] = '_' then String.sub s 0 (String.length s - 1) else s in
  if s = "" then "custom" else String.lowercase_ascii s

let emit_pipeline ?(rel_root="..") (p : Ast.pipeline_result) =
  let import_lines = List.filter_map (fun stmt ->
    let s = unparse_import_stmt stmt in
    if s = "" then None else Some s
  ) p.p_imports in
  let node_names = List.map fst p.p_exprs in

  (* Collect per-node flake settings.
     p_flakes is (string * string option) list: node_name -> optional flake path.
     Build a map: flake path -> sanitized env variable name. *)
  let node_flakes = List.filter_map (fun (name, flake_opt) ->
    match flake_opt with
    | None -> None
    | Some path -> Some (name, path)
  ) p.p_flakes in
  let unique_flake_paths =
    let seen = Hashtbl.create 8 in
    List.iter (fun (_, path) -> Hashtbl.replace seen path ()) node_flakes;
    Hashtbl.fold (fun path () acc -> path :: acc) seen []
  in
  let flake_env_map =
    let tbl = Hashtbl.create 8 in
    List.iter (fun path ->
      let env_name = "env_" ^ sanitize_flake_path path in
      Hashtbl.replace tbl path env_name
    ) unique_flake_paths;
    tbl
  in
  (* Per-node flake env assignment: node_name -> Some env_name or None *)
  let node_to_flake_env =
    List.map (fun (name, path) ->
      name, Some (Hashtbl.find flake_env_map path)
    ) node_flakes
  in

  let per_node_flake_env = List.to_seq node_to_flake_env |> Hashtbl.of_seq in

  let flake_env_bindings =
    unique_flake_paths
    |> List.map (fun path ->
         let env_name = Hashtbl.find flake_env_map path in
         Printf.sprintf "  %s = mkNodeEnv %s;" env_name (if String.starts_with ~prefix:":" path || String.starts_with ~prefix:"github:" path || String.starts_with ~prefix:"gitlab:" path || String.starts_with ~prefix:"sourcehut:" path || String.starts_with ~prefix:"https:" path then path else "\"" ^ path ^ "\""))
    |> String.concat "\n"
  in

  let nodes =
    p.p_exprs
    |> List.map (fun (name, expr) ->
      let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
      let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
      let serializer = match List.assoc_opt name p.p_serializers with Some s -> s | None -> Ast.mk_expr (Ast.Var "default") in
      let deserializer = match List.assoc_opt name p.p_deserializers with Some d -> d | None -> Ast.mk_expr (Ast.Var "default") in
      let env_vars = match List.assoc_opt name p.p_env_vars with Some vars -> vars | None -> [] in
      let runtime_args = match List.assoc_opt name p.p_args with Some args -> args | None -> [] in
      let functions = match List.assoc_opt name p.p_functions with Some f -> f | None -> [] in
      let includes = match List.assoc_opt name p.p_includes with Some f -> f | None -> [] in
      let noop = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
      let script = match List.assoc_opt name p.p_scripts with Some s -> s | None -> None in
      let shell = match List.assoc_opt name p.p_shells with Some s -> s | None -> None in
      let shell_args = match List.assoc_opt name p.p_shell_args with Some args -> args | None -> [] in
      let flake_env = match Hashtbl.find_opt per_node_flake_env name with Some f -> f | None -> None in
      emit_node (name, expr) deps node_names import_lines runtime serializer deserializer env_vars runtime_args functions includes noop script shell shell_args ~flake_env_name:flake_env)
    |> String.concat "\n"
  in
  let final_copy =
    node_names
    |> List.map (fun n -> Printf.sprintf "      cp -r ${%s} $out/%s" n n)
    |> String.concat "\n"
  in
  let has_julia = List.exists (fun (name, _) ->
    let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
    runtime = "Julia"
  ) p.p_exprs in
  let has_pmml = List.exists (fun (name, _) ->
    let ser = match List.assoc_opt name p.p_serializers with Some s -> s | None -> Ast.mk_expr (Ast.Var "default") in
    let des = match List.assoc_opt name p.p_deserializers with Some d -> d | None -> Ast.mk_expr (Ast.Var "default") in
    is_pmml_ser ser || is_pmml_des des
  ) p.p_exprs in
  let julia_build_input = if has_julia && has_pmml then "\n                      ++ [ juliaPkg pkgs.gcc.cc.lib pkgs.avahi ]" 
                           else if has_julia then "\n                      ++ [ juliaPkg ]"
                           else "" in

  let julia_packages_injection = if has_pmml then "\"DataFrames\" \"CSV\" \"StatsModels\" \"JSON\" \"JLD2\" \"JavaCall\"" else "\"DataFrames\" \"CSV\" \"StatsModels\" \"JSON\" \"JLD2\"" in

  Printf.sprintf {|
{ system ? builtins.currentSystem }:
let
  # mkNodeEnv: build a runtime environment from an arbitrary flake path.
  # R/Python/Julia package lists still come from the project's tproject.toml.
  # The flake provides nixpkgs version, t-lang version, and R/Python/Julia versions.
  # Each component is resolved independently: if the flake provides `t-lang` (or
  # has the relevant package), it is used; otherwise it falls back to the
  # project-level binding. This allows e.g. an R-only flake (like jbedo/rshells)
  # to provide R packages while T serialization infrastructure comes from the project.
  # Note: toString is required to convert the path to a string
  # that builtins.getFlake accepts.
  mkNodeEnv = flakePath:
    let
      flake = builtins.getFlake flakePath;
      pkgs   = if (builtins.hasAttr "legacyPackages" flake && builtins.hasAttr system flake.legacyPackages.${system}) 
               then flake.legacyPackages.${system} 
               else flake.inputs.nixpkgs.legacyPackages.${system};
      stdenv = pkgs.stdenv;
      tlangPkgSet = (flake.inputs.t-lang or flake).packages.${system};
      tBin   = if tlangPkgSet ? default then tlangPkgSet.default else projectTBin;
      r-env = pkgs.rWrapper.override {
        packages = (builtins.map (p: pkgs.rPackages.${p}) rPackagesList) ++ (if tlangPkgSet ? tlang-r then [ tlangPkgSet.tlang-r ] else []);
      };
      py-env = pkgs.${pyVersion}.withPackages (ps: [ ps.deepdiff ] ++ (builtins.map (p: ps.${p}) pyPackagesList));
      juliaPkg = let
        juliaBase = pkgs.${juliaPackageName};
      in if juliaPackagesList == [] then juliaBase else juliaBase.withPackages juliaPackagesList;
      tlangJl = if tlangPkgSet ? tlang-julia-path then tlangPkgSet.tlang-julia-path else projectTlangJl;
    in { inherit tBin pkgs stdenv tlangPkgSet r-env py-env juliaPkg tlangJl; };

  # Pull exact pinned inputs from the project flake.
  # The flake.lock guarantees reproducibility.
  projectFlake  = builtins.getFlake (toString %s/.);
  projectPkgs   = if (builtins.hasAttr "legacyPackages" projectFlake && builtins.hasAttr system projectFlake.legacyPackages.${system}) 
           then projectFlake.legacyPackages.${system} 
           else projectFlake.inputs.nixpkgs.legacyPackages.${system};
  projectTBin   = let
             base = (projectFlake.inputs.t-lang or projectFlake).packages.${system}.default;
           in if builtins.pathExists %s/dune-project then
             base.overrideAttrs (old: { src = sources; })
           else base;
  projectStdenv = projectPkgs.stdenv;
  projectTlangPkgSet = (projectFlake.inputs.t-lang or projectFlake).packages.${system};
  projectREnv = projectPkgs.rWrapper.override {
    packages = (builtins.map (p: projectPkgs.rPackages.${p}) rPackagesList) ++ [ projectTlangPkgSet.tlang-r ];
  };
  projectPyEnv = projectPkgs.${pyVersion}.withPackages (ps: [ ps.deepdiff ] ++ (builtins.map (p: ps.${p}) pyPackagesList));
  projectJuliaPkg = let
    juliaBase = projectPkgs.${juliaPackageName};
  in if juliaPackagesList == [] then juliaBase else juliaBase.withPackages juliaPackagesList;
  projectTlangJl = projectTlangPkgSet.tlang-julia-path;

  # Backward-compat aliases (used by nodes without a custom flake)
  flake  = projectFlake;
  pkgs   = projectPkgs;
  tBin   = projectTBin;
  stdenv = projectStdenv;
  tlangPkgSet = projectTlangPkgSet;
  "r-env" = projectREnv;
  "py-env" = projectPyEnv;
  juliaPkg = projectJuliaPkg;
  tlangJl = projectTlangJl;

  # Filter out _pipeline/, .git/, and other non-source directories
  sources = builtins.filterSource
    (path: type:
      let baseName = builtins.baseNameOf path;
      in !(baseName == "_pipeline" || baseName == ".git" || baseName == ".direnv" || baseName == "_build"))
    %s/.;

  toml = if builtins.pathExists %s/tproject.toml then builtins.fromTOML (builtins.readFile %s/tproject.toml) else {};
  
  rPackagesList = (toml.r-dependencies or {}).packages or [];
  pyDeps = toml.py-dependencies or toml.python-dependencies or {};
  pyVersion = pyDeps.version or "python3";
  pyPackagesList = pyDeps.packages or [];
  juliaDeps = toml.jl-dependencies or {};
  juliaVersion = juliaDeps.version or "lts";
  juliaPackageName = if juliaVersion == "lts" then "julia-lts" else "julia_" + (builtins.replaceStrings ["."] ["_"] juliaVersion);
  juliaPackagesList = (juliaDeps.packages or []) ++ [ %s ];

  # Additional Tools & LaTeX
  additionalTools = (toml.additional-tools or {}).packages or [];
  latexPkgs = (toml.latex or {}).packages or [];
  
  latexCombined = if latexPkgs == [] then null 
                  else pkgs.texlive.combine (builtins.listToAttrs (builtins.map (name: { name = name; value = pkgs.texlive.${name}; }) (["scheme-small"] ++ latexPkgs)));
                  
  globalBuildInputs = (builtins.map (p: pkgs.${p}) (builtins.filter (p: p != "atelier") additionalTools))%s
                      ++ (if latexCombined == null then [] else [ latexCombined ]);

  # Per-node flake environments
%s
in
rec {
%s
  pipeline_output = stdenv.mkDerivation {
    name = "pipeline_output";
    buildInputs = [ tBin %s projectTlangPkgSet.tlang-julia-path ] ++ globalBuildInputs;
    buildCommand = ''
      mkdir -p $out
%s
    '';
  };
}
|} rel_root rel_root rel_root rel_root rel_root julia_packages_injection julia_build_input flake_env_bindings nodes (String.concat " " node_names) final_copy
