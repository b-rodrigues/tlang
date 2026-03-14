open Ast

type mode = Repl | Strict

let mode_of_string = function
  | "repl" -> Some Repl
  | "strict" -> Some Strict
  | _ -> None

let rec contains_type_var = function
  | TVar _ -> true
  | TList (Some t) -> contains_type_var t
  | TDict (Some k, Some v) -> contains_type_var k || contains_type_var v
  | TTuple ts -> List.exists contains_type_var ts
  | TDataFrame (Some schema) -> contains_type_var schema
  | _ -> false

let rec collect_type_vars = function
  | TVar name -> [name]
  | TList (Some t) -> collect_type_vars t
  | TDict (Some k, Some v) -> collect_type_vars k @ collect_type_vars v
  | TTuple ts -> List.concat_map collect_type_vars ts
  | TDataFrame (Some schema) -> collect_type_vars schema
  | _ -> []

let make_type_error ?location message =
  { code = Ast.TypeError; message; context = []; location }

let validate_lambda ?location name (l : lambda) =
  let all_params_annotated = List.for_all Option.is_some l.param_types in
  if not all_params_annotated then
    Error (make_type_error ?location (Printf.sprintf "Strict mode: top-level function '%s' must annotate all parameter types." name))
  else if Option.is_none l.return_type then
    Error (make_type_error ?location (Printf.sprintf "Strict mode: top-level function '%s' must annotate a return type." name))
  else
    (* Collect all type variables used in parameter types and return type *)
    let used_vars =
      let param_vars = List.concat_map (function Some t -> collect_type_vars t | None -> []) l.param_types in
      let return_vars = match l.return_type with Some t -> collect_type_vars t | None -> [] in
      List.sort_uniq String.compare (param_vars @ return_vars)
    in
    if used_vars <> [] && l.generic_params = [] then
      Error (make_type_error ?location (Printf.sprintf "Strict mode: top-level function '%s' uses generic type variables %s but declares none. Use syntax like \\<T, U>(...) -> ..."
        name (String.concat ", " used_vars)))
    else
      (* Check that all used type variables are declared *)
      let undeclared = List.filter (fun v -> not (List.mem v l.generic_params)) used_vars in
      if undeclared <> [] then
        Error (make_type_error ?location (Printf.sprintf "Strict mode: top-level function '%s' uses undeclared type variables: %s"
          name (String.concat ", " undeclared)))
      else
        Ok ()

let validate_program ~(mode : mode) (program : program) =
  match mode with
  | Repl -> Ok ()
  | Strict ->
      let rec go = function
        | [] -> Ok ()
        | stmt :: rest ->
            (match stmt.node with
            | Assignment { name; expr; _ } ->
                (match expr.node with
                | Lambda l ->
                    let location = match expr.loc with Some _ as loc -> loc | None -> stmt.loc in
                    (match validate_lambda ?location name l with
                    | Ok () -> go rest
                    | Error _ as e -> e)
                | _ -> go rest)
            | _ -> go rest)
      in
      go program
