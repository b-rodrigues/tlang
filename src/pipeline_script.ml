open Ast

let ordered_unique_strings names =
  let rec go seen acc = function
    | [] -> List.rev acc
    | name :: rest when String_set.mem name seen -> go seen acc rest
    | name :: rest -> go (String_set.add name seen) (name :: acc) rest
  in
  go String_set.empty [] names

let pipeline_entry_bindings_key = "__pipeline_entry_bindings__"

let is_internal_key name =
  Import_registry.is_internal_key name
  || name = pipeline_entry_bindings_key

type t_make_pipeline_contract =
  | MissingPipelineBuildCall
  | PopulateWithoutBuild
  | BuildRequested

let sanitize_pipeline_entry_binding_names names =
  List.filter (fun name -> not (is_internal_key name)) names
  |> ordered_unique_strings

let combine_t_make_pipeline_contract left right =
  match left, right with
  | BuildRequested, _
  | _, BuildRequested -> BuildRequested
  | PopulateWithoutBuild, _
  | _, PopulateWithoutBuild -> PopulateWithoutBuild
  | MissingPipelineBuildCall, MissingPipelineBuildCall -> MissingPipelineBuildCall

let extract_bool_literal = function
  | { node = Value (VBool b); _ } -> Some b
  | _ -> None

let populate_pipeline_requests_build args =
  let rec find_named_build = function
    | [] -> None
    | (Some "build", expr) :: _ -> Some (extract_bool_literal expr)
    | _ :: rest -> find_named_build rest
  in
  match find_named_build args with
  | Some (Some true) -> true
  | Some (Some false) -> false
  | Some None -> true
  | None ->
      let positional_args =
        List.filter_map (fun (name_opt, expr) ->
          match name_opt with
          | None -> Some expr
          | Some _ -> None) args
      in
      match positional_args with
      | _pipeline_arg :: build_arg :: _ ->
          begin match extract_bool_literal build_arg with
          | Some build -> build
          | None -> true
          end
      | _ -> false

let rec analyze_expr_for_pipeline_call expr =
  match expr.node with
  | Call { fn = { node = Var "build_pipeline"; _ }; args } ->
      List.fold_left
        (fun acc (_, arg) -> combine_t_make_pipeline_contract acc (analyze_expr_for_pipeline_call arg))
        BuildRequested
        args
  | Call { fn = { node = Var "populate_pipeline"; _ }; args } ->
      let call_contract =
        if populate_pipeline_requests_build args then BuildRequested
        else PopulateWithoutBuild
      in
      List.fold_left
        (fun acc (_, arg) -> combine_t_make_pipeline_contract acc (analyze_expr_for_pipeline_call arg))
        call_contract
        args
  | Call { fn; args } ->
      List.fold_left
        (fun acc (_, arg) -> combine_t_make_pipeline_contract acc (analyze_expr_for_pipeline_call arg))
        (analyze_expr_for_pipeline_call fn)
        args
  | BinOp { left; right; _ }
  | BroadcastOp { left; right; _ } ->
      combine_t_make_pipeline_contract
        (analyze_expr_for_pipeline_call left)
        (analyze_expr_for_pipeline_call right)
  | IfElse { cond; then_; else_ } ->
      combine_t_make_pipeline_contract
        (analyze_expr_for_pipeline_call cond)
        (combine_t_make_pipeline_contract
           (analyze_expr_for_pipeline_call then_)
           (analyze_expr_for_pipeline_call else_))
  | Match { scrutinee; cases } ->
      List.fold_left
        (fun acc (_, body) -> combine_t_make_pipeline_contract acc (analyze_expr_for_pipeline_call body))
        (analyze_expr_for_pipeline_call scrutinee)
        cases
  | Lambda { body; _ } -> analyze_expr_for_pipeline_call body
  | ListLit items ->
      List.fold_left
        (fun acc (_, item) -> combine_t_make_pipeline_contract acc (analyze_expr_for_pipeline_call item))
        MissingPipelineBuildCall
        items
  | DictLit pairs ->
      List.fold_left
        (fun acc (_, item) -> combine_t_make_pipeline_contract acc (analyze_expr_for_pipeline_call item))
        MissingPipelineBuildCall
        pairs
  | UnOp { operand; _ }
  | DotAccess { target = operand; _ }
  | Unquote operand
  | UnquoteSplice operand ->
      analyze_expr_for_pipeline_call operand
  | PipelineDef nodes
  | IntentDef nodes ->
      List.fold_left
        (fun acc (_, item) -> combine_t_make_pipeline_contract acc (analyze_expr_for_pipeline_call item))
        MissingPipelineBuildCall
        nodes
  | ListComp { expr; clauses } ->
      let clause_contract =
        List.fold_left
          (fun acc clause ->
            let clause_expr =
              match clause with
              | CFor { iter; _ } -> analyze_expr_for_pipeline_call iter
              | CFilter filter_expr -> analyze_expr_for_pipeline_call filter_expr
            in
            combine_t_make_pipeline_contract acc clause_expr)
          MissingPipelineBuildCall
          clauses
      in
      combine_t_make_pipeline_contract clause_contract (analyze_expr_for_pipeline_call expr)
  | Block stmts ->
      List.fold_left
        (fun acc stmt -> combine_t_make_pipeline_contract acc (analyze_stmt_for_pipeline_call stmt))
        MissingPipelineBuildCall
        stmts
  | Value _
  | Var _
  | ColumnRef _
  | RawCode _
  | ShellExpr _ -> MissingPipelineBuildCall

and analyze_stmt_for_pipeline_call stmt =
  match stmt.node with
  | Expression expr
  | Assignment { expr; _ }
  | Reassignment { expr; _ } ->
      analyze_expr_for_pipeline_call expr
  | Import _
  | ImportPackage _
  | ImportFrom _
  | ImportFileFrom _ -> MissingPipelineBuildCall

let analyze_program_for_pipeline_call (program : program) =
  List.fold_left
    (fun acc stmt -> combine_t_make_pipeline_contract acc (analyze_stmt_for_pipeline_call stmt))
    MissingPipelineBuildCall
    program

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
  |> sanitize_pipeline_entry_binding_names

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
        | VString name -> Some name
        | _ -> None)
      |> sanitize_pipeline_entry_binding_names
  | _ -> []

let set_pipeline_entry_binding_names (env : environment) names =
  Env.add pipeline_entry_bindings_key
    (VList (sanitize_pipeline_entry_binding_names names |> List.map (fun name -> (None, VString name))))
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

let validate_t_make_program (program : program) =
  match analyze_program_for_pipeline_call program with
  | BuildRequested -> Ok None
  | PopulateWithoutBuild ->
      Ok
        (Some
           "Warning: `t_make()` found `populate_pipeline(...)` without `build=true`, so the pipeline will only be populated. Use `populate_pipeline(..., build=true)` or `build_pipeline(...)` to request a build.\n")
  | MissingPipelineBuildCall ->
      Error
        "Function `t_make` requires `src/pipeline.t` to call `populate_pipeline(...)` or `build_pipeline(...)`."
