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

let validate_lambda name (l : lambda) =
  let all_params_annotated = List.for_all Option.is_some l.param_types in
  if not all_params_annotated then
    Error (Printf.sprintf "Strict mode: top-level function '%s' must annotate all parameter types." name)
  else if Option.is_none l.return_type then
    Error (Printf.sprintf "Strict mode: top-level function '%s' must annotate a return type." name)
  else
    let has_generic = List.exists (function Some t -> contains_type_var t | None -> false) l.param_types
      || (match l.return_type with Some t -> contains_type_var t | None -> false)
    in
    if has_generic && l.generic_params = [] then
      Error (Printf.sprintf "Strict mode: top-level function '%s' uses generic type variables but declares none." name)
    else
      Ok ()

let validate_program ~(mode : mode) (program : program) =
  match mode with
  | Repl -> Ok ()
  | Strict ->
      let rec go = function
        | [] -> Ok ()
        | Assignment { name; expr = Lambda l; _ } :: rest ->
            (match validate_lambda name l with
            | Ok () -> go rest
            | Error _ as e -> e)
        | _ :: rest -> go rest
      in
      go program
