open Ast

let ordered_unique_strings names =
  let rec go seen acc = function
    | [] -> List.rev acc
    | name :: rest when String_set.mem name seen -> go seen acc rest
    | name :: rest -> go (String_set.add name seen) (name :: acc) rest
  in
  go String_set.empty [] names

(** Extract user-authored top-level bindings from a script so pipeline entry
    reloads can clear them before reevaluation. Internal framework keys are
    excluded, and names are deduplicated while preserving their first-seen
    order to keep cleanup predictable. *)
let top_level_assigned_names (program : program) =
  List.filter_map (fun stmt ->
    match stmt.node with
    | Assignment { name; _ }
    | Reassignment { name; _ } when not (Import_registry.is_internal_key name) ->
        Some name
    | _ -> None
  ) program
  |> ordered_unique_strings

let is_pipeline_entry_file filename =
  Filename.basename filename = "pipeline.t"
  && Filename.basename (Filename.dirname filename) = "src"

let reload_env_for_pipeline_entry ~filename (program : program) (env : environment) =
  if is_pipeline_entry_file filename then
    List.fold_left (fun acc name -> Env.remove name acc) env (top_level_assigned_names program)
  else
    env

let validate_t_make_filename filename =
  if is_pipeline_entry_file filename then
    Ok ()
  else
    Error "Function `t_make` requires the pipeline entrypoint to be `src/pipeline.t`."
