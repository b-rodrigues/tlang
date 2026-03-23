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
--#   -- Output = Hello World
--# @family core
--# @export
*)
(* Convert a value to a printable string (without quotes for strings) *)
let value_to_print_string = function
  | VString s -> Serialization.json_unescape s  (* Unescape characters for clean output *)
  | VShellResult { sr_stdout; _ } -> sr_stdout  (* Print shell stdout as-is *)
  | other -> Utils.value_to_string other

let cat named_args _env =
  let args = ref [] in
  let sep = ref " " in
  List.iter (fun (name, v) ->
    match name with
    | None -> args := v :: !args
    | Some "sep" | Some "separator" ->
        (match v with
         | VString s -> sep := s
         | _ -> ())
    | _ -> ()
  ) named_args;
  let args = List.rev !args in
  let first = ref true in
  List.iter (fun v ->
    if not !first then print_string !sep;
    print_string (value_to_print_string v);
    first := false
  ) args;
  flush stdout;
  VNull

let register env =
  let env = Env.add "print"
    (make_builtin ~name:"print" ~variadic:true 1 (fun args _env ->
      List.iter (fun v -> print_string (value_to_print_string v); print_char ' ') args;
      print_newline ();
      VNull
    ))
    env
  in
(*
--# Print values without escaping
--#
--# Prints one or more values to stdout using a custom separator. 
--# Unlike print(), it does not add a trailing newline and supports custom separators.
--# Strings are printed raw (with escape sequences like \n interpreted).
--#
--# @name cat
--# @param ... :: Any Values to print.
--# @param sep :: String = " " Separator between values.
--# @return :: Null
--# @example
--#   cat("Line 1", "Line 2", sep = "\n")
--# @family core
--# @export
*)
  let env = Env.add "cat"
    (VBuiltin { b_name = Some "cat"; b_arity = 0; b_variadic = true; b_func = cat })
    env
  in
  env
