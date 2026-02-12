(* src/package_manager/update_manager.ml *)
(* Handles dependency updates via Nix *)

open Release_manager

(** Update the project's flake.lock using 'nix flake update' *)
let update_flake_lock () =
  Printf.printf "Updating dependencies (nix flake update)...\n";
  match run_command "nix flake update" with
  | Ok _ -> Ok ()
  | Error msg -> Error ("Failed to update dependencies: " ^ msg)

(* Future: check remote tags *)
let check_remote_tags () =
  (* This would require parsing tproject.toml and git ls-remote *)
  (* For now, we rely on nix flake update *)
  Printf.printf "Note: Checking for newer tags is not yet implemented. 'nix flake update' will fetch latest commits.\n";
  Ok []
