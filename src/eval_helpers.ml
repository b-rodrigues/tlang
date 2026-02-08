(* src/eval_helpers.ml *)
(* Common helper functions for the T language evaluator. *)
(* This module centralizes logic needed by eval.ml, builtins.ml, and colcraft.ml. *)

open Ast

(**
 * Creates a standardized Type Error value.
 * @param expected A string describing the expected type (e.g., "String").
 * @param got The actual value that was received.
 * @return An Ast.Error value with a formatted message.
 *)
let type_error expected got =
  Error (Printf.sprintf "Type Error: Expected %s but got %s" expected (Utils.type_name got))

(**
 * A factory function to create a native function value (VBuiltin).
 * This makes the definitions in builtins.ml and colcraft.ml cleaner.
 * @param arity The number of arguments the function expects.
 * @param variadic Whether the function accepts a variable number of arguments after the main ones.
 * @param func The actual OCaml function to be wrapped. It takes a list of values and the environment.
 * @return An Ast.VBuiltin value.
 *)
let make_native_fn ?(variadic=false) arity func =
  VBuiltin { arity; variadic; func }

(**
 * A factory function to safely construct a DataFrame.
 * It ensures that all columns have the same number of rows.
 * @param names A list of column names.
 * @param values A list of columns, where each column is an array of Ast.value.
 * @return An Ast.VDataFrame value, or an Ast.Error if column lengths mismatch.
 *)
let make_dataframe (names: string list) (values: value array list) : value =
  let nrows =
    match values with
    | [] -> 0
    | arr :: _ -> Array.length arr
  in
  (* Validate that all columns have the same length *)
  if List.for_all (fun arr -> Array.length arr = nrows) values then
    VDataFrame {
      columns = List.combine names values;
      nrows = nrows;
      group_keys = []
    }
  else
    VError { code = GenericError; message = "DataFrame Error: All columns must have the same length."; context = [] }

(**
 * A helper for 1-indexed list access, as specified in the README.
 * @param lst The list to access.
 * @param idx The 1-based index from the user.
 * @return A result type containing the value if successful, or an Ast.Error on failure.
 *)
let get_nth_value (lst: 'a list) (idx: int) : ('a, value) result =
  if idx < 1 || idx > List.length lst then
    Result.Error (Error (Printf.sprintf "Index out of bounds: %d. Must be between 1 and %d." idx (List.length lst)))
  else
    Result.Ok (List.nth lst (idx - 1)) 
