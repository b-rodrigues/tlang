open Ast

(*
--# Join strings with a separator
--#
--# Concatenates items of a List or Vector into a single string, separated by `sep`.
--#
--# @name join
--# @param items :: List | Vector The items to join.
--# @param sep :: String The separator string.
--# @return :: String The joined string.
--# @example
--#   join(["a", "b", "c"], "-")
--#   -- Returns: "a-b-c"
--# @family core
--# @seealso string
--# @export
*)
(*
--# Convert to string
--#
--# Converts any value to its string representation.
--#
--# @name string
--# @param x :: Any The value to convert.
--# @return :: String The string representation.
--# @example
--#   string(123)
--#   -- Returns: "123"
--# @family core
--# @seealso join
--# @export
*)
let register env =
  let env = Env.add "join"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VList items; VString sep] ->
          let strs = List.map (fun (_, v) -> Utils.value_to_raw_string v) items in
          VString (String.concat sep strs)
      | [VVector arr; VString sep] ->
          let strs = Array.map Utils.value_to_raw_string arr |> Array.to_list in
          VString (String.concat sep strs)
      | [val_; VString sep] ->
          VString (Utils.value_to_raw_string val_ ^ sep) (* Single value fallback *)
      | _ -> Error.type_error "Function `join` expects a List/Vector/Value and a separator String."
    ))
    env
  in
  let env = Env.add "string"
    (make_builtin 1 (fun args _env ->
      match args with
      | [v] -> VString (Utils.value_to_raw_string v)
      | _ -> Error.type_error "Function `string` expects a single argument."
    ))
    env
  in
  env
