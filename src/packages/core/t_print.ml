open Ast

let register env =
  Env.add "print"
    (make_builtin ~variadic:true 1 (fun args _env ->
      List.iter (fun v -> print_string (Utils.value_to_string v); print_char ' ') args;
      print_newline ();
      VNull
    ))
    env
