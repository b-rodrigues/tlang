open Ast

let ordered_unique_strings names =
  let rec go seen acc = function
    | [] -> List.rev acc
    | name :: rest when String_set.mem name seen -> go seen acc rest
    | name :: rest -> go (String_set.add name seen) (name :: acc) rest
  in
  go String_set.empty [] names

let pipeline_entry_bindings_key = "__tlang_internal_pipeline_entry_bindings__"

let is_internal_key name =
  Import_registry.is_internal_key name
  || name = pipeline_entry_bindings_key

(** Extract user-authored top-level bindings from a script so pipeline entry
    reloads can clear them before reevaluation. Internal framework keys are
    excluded, and names are deduplicated while preserving their first-seen
    order to keep cleanup predictable. *)
let top_level_assigned_names (program : program) =
  List.filter_map (fun stmt ->
    match stmt.node with
    | Assignment { name; _ }
    | Reassignment { name; _ } when not (is_internal_key name) ->
        Some name
    | _ -> None
  ) program
  |> ordered_unique_strings

let normalize_relative_path filename =
  if not (Filename.is_relative filename) then
    None
  else
    let normalized_separators =
      String.map (fun c -> if c = '\\' then '/' else c) filename
    in
    let components =
      String.split_on_char '/' normalized_separators
    in
    let rec normalize acc = function
      | [] -> Some (List.rev acc)
      | "" :: rest
      | "." :: rest -> normalize acc rest
      | ".." :: rest ->
          begin match acc with
          | [] -> None
          | _ :: acc_rest -> normalize acc_rest rest
          end
      | part :: rest -> normalize (part :: acc) rest
    in
    match normalize [] components with
    | Some parts -> Some (String.concat Filename.dir_sep parts)
    | None -> None

let is_pipeline_entry_file filename =
  let expected = Filename.concat "src" "pipeline.t" in
  match normalize_relative_path filename with
  | Some normalized -> normalized = expected
  | None -> false

let get_pipeline_entry_binding_names (env : environment) =
  match Env.find_opt pipeline_entry_bindings_key env with
  | Some (VList values) ->
      values
      |> List.filter_map (fun (_, value) ->
        match value with
        | VString name when not (is_internal_key name) -> Some name
        | _ -> None)
      |> ordered_unique_strings
  | _ -> []

let set_pipeline_entry_binding_names (env : environment) names =
  Env.add pipeline_entry_bindings_key
    (VList (ordered_unique_strings names |> List.map (fun name -> (None, VString name))))
    env

let reload_env_for_pipeline_entry ~filename (program : program) (env : environment) =
  if is_pipeline_entry_file filename then
    let names_to_remove =
      ordered_unique_strings
        (get_pipeline_entry_binding_names env @ top_level_assigned_names program)
    in
    List.fold_left (fun acc name -> Env.remove name acc) env names_to_remove
  else
    env

let remember_pipeline_entry_bindings ~filename (program : program) (env : environment) =
  if is_pipeline_entry_file filename then
    set_pipeline_entry_binding_names env (top_level_assigned_names program)
  else
    env

let validate_t_make_filename filename =
  if is_pipeline_entry_file filename then
    Ok ()
  else
    Error "Function `t_make` requires the pipeline entrypoint to be `src/pipeline.t`."
