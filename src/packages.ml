(* src/packages.ml *)
(* This module discovers and aggregates all built-in functions from the packages/ directory. *)

open Ast

(* The master list of all functions available in the T standard library. *)
let all_functions =
  [
    (* package: core *)
    ("read_csv", Packages_core_read_csv.v);
    (* ("print", Packages_core_print.v); *) (* We would add this once the file exists *)

    (* package: colcraft *)
    (* ("select", Packages_colcraft_select.v); *)
    (* ("filter", Packages_colcraft_filter.v); *)
  ]

(**
 * Loads all the functions from the master list into a given environment.
 * This is called once when the evaluator starts.
 *)
let load (env: environment) : environment =
  List.fold_left
    (fun current_env (name, fn_val) -> Eval.Env.add name fn_val current_env)
    env
    all_functions 
