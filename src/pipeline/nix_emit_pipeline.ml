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
      emit_node (name, expr) deps import_lines)
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
