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
{ pkgs ? import <nixpkgs> {} }:
let
  stdenv = pkgs.stdenv;
  # Use local env.nix if it exists, otherwise fallback to empty buildInputs
  env = if builtins.pathExists ./env.nix then import ./env.nix { inherit pkgs; } else { buildInputs = []; };
  t_lang_env = env.buildInputs or [];
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
    buildInputs = t_lang_env ++ [ %s ];
    buildCommand = ''
      mkdir -p $out
%s
    '';
  };
}
|} nodes (String.concat " " node_names) final_copy
