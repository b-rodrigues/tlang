open Ast
open Nix_unparse
open Nix_emit_node

let emit_pipeline (p : Ast.pipeline_result) =
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
      let functions = match List.assoc_opt name p.p_functions with Some f -> f | None -> [] in
      let includes = match List.assoc_opt name p.p_includes with Some f -> f | None -> [] in
      let noop = match List.assoc_opt name p.p_noops with Some b -> b | None -> false in
      emit_node (name, expr) deps import_lines runtime serializer deserializer functions includes noop)
    |> String.concat "\n"
  in
  let final_copy =
    node_names
    |> List.map (fun n -> Printf.sprintf "      cp -r ${%s} $out/%s" n n)
    |> String.concat "\n"
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
  tBin   = (flake.inputs.t-lang or flake).packages.${system}.default;
  stdenv = pkgs.stdenv;

  # Filter out _pipeline/, .git/, and other non-source directories
  sources = builtins.filterSource
    (path: type:
      let baseName = builtins.baseNameOf path;
      in !(baseName == "_pipeline" || baseName == ".git" || baseName == ".direnv"))
    ./..;

  toml = if builtins.pathExists ../tproject.toml then builtins.fromTOML (builtins.readFile ../tproject.toml) else {};
  
  rPackagesList = toml.r-dependencies.packages or [];
  r-env = pkgs.rWrapper.override {
    packages = (builtins.map (p: pkgs.rPackages.${p}) rPackagesList) ++ [ pkgs.rPackages.jsonlite ];
  };

  pyVersion = toml.py-dependencies.version or "python314";
  pyPackagesList = toml.py-dependencies.packages or [];
  py-env = pkgs.${pyVersion}.withPackages (ps: builtins.map (p: ps.${p}) pyPackagesList);
in
rec {
%s
  pipeline_output = stdenv.mkDerivation {
    name = "pipeline_output";
    buildInputs = [ tBin %s ];
    buildCommand = ''
      mkdir -p $out
%s
    '';
  };
}
|} nodes (String.concat " " node_names) final_copy
