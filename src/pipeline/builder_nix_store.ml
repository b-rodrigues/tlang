(* src/pipeline/builder_nix_store.ml *)
open Builder_utils

let nix_store_path_of_executable () =
  let exe = try Unix.readlink "/proc/self/exe" with _ -> Sys.executable_name in
  if String.length exe > 11 && String.sub exe 0 11 = "/nix/store/" then
    let rest = String.sub exe 11 (String.length exe - 11) in
    match String.index_opt rest '/' with
    | Some i -> Some (String.sub exe 0 (11 + i))
    | None -> Some exe
  else
    None

let write_env_nix () =
  match nix_store_path_of_executable () with
  | Some store_path ->
      let content = Printf.sprintf {|{ pkgs ? import <nixpkgs> {} }:
let
  t_lang = builtins.storePath "%s";
in
{
  buildInputs = [ t_lang ];
}
|} store_path
      in
      ignore (write_file env_nix_path content)
  | None ->
      let content = {|{ pkgs ? import <nixpkgs> {} }:
{
  buildInputs = [];
}
|}
      in
      ignore (write_file env_nix_path content)
