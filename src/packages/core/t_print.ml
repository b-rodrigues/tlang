open Ast

(* Convert a value to a printable string (without quotes for strings) *)
let value_to_print_string = function
  | VString s -> s  (* Print strings without quotes or escaping *)
  | other -> Utils.value_to_string other

let register env =
  Env.add "print"
    (make_builtin ~variadic:true 1 (fun args _env ->
      List.iter (fun v -> print_string (value_to_print_string v); print_char ' ') args;
      print_newline ();
      VNull
    ))
    env
