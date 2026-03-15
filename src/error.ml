(* src/error.ml *)
(* Centralized error construction for T Language *)
(* Validated against spec_files/archive/error-messages.md *)

open Ast

(** Create a raw error value *)
let make_error ?location ?(context=[]) code message =
  VError { code; message; context; location }

(** Check if a value is an error *)
let is_error_value = function VError _ -> true | _ -> false

(** Check if a value is NA *)
let is_na_value = function VNA _ -> true | _ -> false

(** Type Errors *)

let type_error ?location msg =
  make_error ?location TypeError msg

let op_type_error ?location op t1 t2 =
  let msg = Printf.sprintf "Operator `%s` expects %s and %s." op t1 t2 in
  make_error ?location TypeError msg

let op_type_error_with_hint ?location op t1 t2 hint =
  let msg = Printf.sprintf "Operator `%s` expects %s and %s.\nHint: %s" op t1 t2 hint in
  make_error ?location TypeError msg

let if_condition_error ?location received_type =
  let msg = Printf.sprintf "`if` condition must be Bool.\nReceived %s." received_type in
  make_error ?location TypeError msg

let not_callable_error ?location received_type =
  make_error ?location TypeError (Printf.sprintf "Value of type %s is not callable." received_type)

(** Arity Errors *)

let arity_error ?location expected received =
  make_error ?location ArityError (Printf.sprintf "Function expects %d arguments but received %d." expected received)

let arity_error_named ?location name expected received =
  make_error ?location ArityError (Printf.sprintf "Function `%s` expects %d arguments but received %d." name expected received)

(** Value Errors *)

let value_error ?location msg =
  make_error ?location ValueError msg

let na_value_error ?location ?(na_rm=false) function_name =
  let guidance =
    if na_rm then "Handle missingness explicitly or set `na_rm` to true."
    else "Handle missingness explicitly."
  in
  type_error ?location (Printf.sprintf "Function `%s` encountered NA value. %s" function_name guidance)

let broadcast_length_error ?location len1 len2 =
  let msg = Printf.sprintf "Broadcast requires lists of equal length.\nLeft has length %d, right has length %d." len1 len2 in
  make_error ?location ValueError msg

(** Index Errors *)

let index_error ?location index length =
  make_error ?location IndexError (Printf.sprintf "Index %d is out of bounds for List of length %d." index length)

(** Name Errors *)

let name_error ?location name =
  make_error ?location NameError (Printf.sprintf "Name `%s` is not defined." name)

let name_error_with_suggestion ?location name suggestion =
  make_error ?location NameError (Printf.sprintf "Name `%s` is not defined.\nDid you mean `%s`?" name suggestion)

(** Other Errors *)

let division_by_zero ?location () =
  make_error ?location DivisionByZero "Division by zero."

let internal_error ?location msg =
  make_error ?location GenericError (Printf.sprintf "InternalError: %s" msg)

let syntax_error ?location msg =
  make_error ?location SyntaxError msg

let match_error ?location msg =
  make_error ?location MatchError msg

let runtime_error ?location msg =
  make_error ?location RuntimeError msg
