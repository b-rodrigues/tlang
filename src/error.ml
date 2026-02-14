(* src/error.ml *)
(* Centralized error construction for T Language *)
(* Validated against spec_files/error-messages.md *)

open Ast

(** Create a raw error value *)
let make_error ?(context=[]) code message =
  VError { code; message; context }

(** Check if a value is an error *)
let is_error_value = function VError _ -> true | _ -> false

(** Check if a value is NA *)
let is_na_value = function VNA _ -> true | _ -> false

(** Type Errors *)

let type_error msg =
  make_error TypeError msg

let op_type_error op t1 t2 =
  let msg = Printf.sprintf "Operator `%s` expects %s and %s." op t1 t2 in
  make_error TypeError msg

let op_type_error_with_hint op t1 t2 hint =
  let msg = Printf.sprintf "Operator `%s` expects %s and %s.\nHint: %s" op t1 t2 hint in
  make_error TypeError msg

let if_condition_error received_type =
  let msg = Printf.sprintf "`if` condition must be Bool.\nReceived %s." received_type in
  make_error TypeError msg

let not_callable_error received_type =
  make_error TypeError (Printf.sprintf "Value of type %s is not callable." received_type)

(** Arity Errors *)

let arity_error ~expected ~received =
  make_error ArityError (Printf.sprintf "Function expects %d arguments but received %d." expected received)

let arity_error_named name ~expected ~received =
  make_error ArityError (Printf.sprintf "Function `%s` expects %d arguments but received %d." name expected received)

(** Value Errors *)

let value_error msg =
  make_error ValueError msg

let broadcast_length_error len1 len2 =
  let msg = Printf.sprintf "Broadcast requires lists of equal length.\nLeft has length %d, right has length %d." len1 len2 in
  make_error ValueError msg

(** Index Errors *)

let index_error index length =
  make_error IndexError (Printf.sprintf "Index %d is out of bounds for List of length %d." index length)

(** Name Errors *)

let name_error name =
  make_error NameError (Printf.sprintf "Name `%s` is not defined." name)

let name_error_with_suggestion name suggestion =
  make_error NameError (Printf.sprintf "Name `%s` is not defined.\nDid you mean `%s`?" name suggestion)

(** Other Errors *)

let division_by_zero () =
  make_error DivisionByZero "Division by zero."

let internal_error msg =
  make_error GenericError (Printf.sprintf "InternalError: %s" msg)

let syntax_error msg =
  make_error SyntaxError msg

let match_error msg =
  make_error MatchError msg
