open Ast

(*
--# Print values to standard output
--#
--# Prints one or more values to stdout, separated by spaces, followed by a newline.
--# Strings are printed without quotes.
--#
--# @name print
--# @param ... :: Any Values to print.
--# @return :: Null
--# @example
--#   print("Hello", "World")
--#   -- Output: Hello World
--# @family core
--# @export
*)
(* Convert a value to a printable string (without quotes for strings) *)
let value_to_print_string = function
  | VString s -> s  (* Print strings without quotes or escaping *)
  | other -> Utils.value_to_string other

let register env =
  Env.add "print"
    (make_builtin ~name:"print" ~variadic:true 1 (fun args _env ->
      List.iter (fun v -> print_string (value_to_print_string v); print_char ' ') args;
      print_newline ();
      VNull
    ))
    env
