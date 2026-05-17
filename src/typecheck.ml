open Ast

type mode = Repl | Strict

(** Parse a strictness mode from its string representation.
    
    @param str The string to parse.
    @return [Some Repl] for "repl", [Some Strict] for "strict", or [None] otherwise. *)
let mode_of_string = function
  | "repl" -> Some Repl
  | "strict" -> Some Strict
  | _ -> None

(** Recursively check if a type structure contains a type variable.
    
    @param t The type structure to check.
    @return [true] if a type variable is found, otherwise [false]. *)
let rec contains_type_var = function
  | TVar _ -> true
  | TList (Some t) -> contains_type_var t
  | TDict (Some k, Some v) -> contains_type_var k || contains_type_var v
  | TTuple ts -> List.exists contains_type_var ts
  | TDataFrame (Some schema) -> contains_type_var schema
  | _ -> false

(** Recursively collect all type variable names used inside a type structure.
    
    @param t The type structure to scan.
    @return A list of type variable names. *)
let rec collect_type_vars = function
  | TVar name -> [name]
  | TList (Some t) -> collect_type_vars t
  | TDict (Some k, Some v) -> collect_type_vars k @ collect_type_vars v
  | TTuple ts -> List.concat_map collect_type_vars ts
  | TDataFrame (Some schema) -> collect_type_vars schema
  | _ -> []

(** Helper to construct a type error info record.
    
    @param location Optional source location of the error.
    @param message Description of the type mismatch.
    @return A type error info record. *)
let make_type_error ?location message =
  { code = Ast.TypeError; message; context = []; location; na_count = 0 }

(** Validate that a lambda expression complies with Strict Mode.
    
    In Strict Mode, all parameters and return types must be fully annotated,
    and any generic type variables must be declared in the function's type parameter list.
    
    @param location Optional source location for the error.
    @param name The name of the function being assigned.
    @param l The lambda declaration to validate.
    @return [Ok ()] if valid, or [Error error_info] describing the strictness violation. *)
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

(** Validate an entire parsed program against strictness rules.
    
    In Strict Mode, all top-level lambda functions are fully checked. In Repl Mode,
    all checks are skipped.
    
    @param mode The strictness mode (Repl or Strict).
    @param program The list of parsed statements.
    @return [Ok ()] if all top-level functions are valid, or [Error error_info] on the first error. *)
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
