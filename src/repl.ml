(* src/repl.ml *)
(* Interactive REPL for the T language — Phase 0 Alpha *)

let parse_and_eval env input =
  let lexbuf = Lexing.from_string input in
  try
    let program = Parser.program Lexer.token lexbuf in
    Eval.eval_program program env
  with
  | Lexer.SyntaxError msg ->
      (Ast.VError ("Syntax Error: " ^ msg), env)
  | Parser.Error ->
      let pos = Lexing.lexeme_start_p lexbuf in
      let msg = Printf.sprintf "Parse Error at line %d, column %d"
        pos.Lexing.pos_lnum
        (pos.Lexing.pos_cnum - pos.Lexing.pos_bol)
      in
      (Ast.VError msg, env)

let run_file filename env =
  try
    let ch = open_in filename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    parse_and_eval env content
  with
  | Sys_error msg -> (Ast.VError ("File Error: " ^ msg), env)

let () =
  (* Check for command-line arguments *)
  let args = Array.to_list Sys.argv in
  let env = Eval.initial_env () in
  match args with
  | _ :: "run" :: filename :: _ ->
      let (result, _env) = run_file filename env in
      (match result with
       | Ast.VError msg -> Printf.eprintf "Error: %s\n" msg; exit 1
       | Ast.VNull -> ()
       | v -> print_endline (Ast.Utils.value_to_string v))
  | _ ->
      (* Interactive REPL mode *)
      Printf.printf "T language REPL — version 0.1 (Phase 0 Alpha)\n";
      Printf.printf "Type :quit or :q to exit.\n\n";
      let rec repl env =
        print_string "T> ";
        flush stdout;
        match input_line stdin with
        | exception End_of_file ->
            print_endline "\nGoodbye."
        | line ->
            let trimmed = String.trim line in
            if trimmed = "" then repl env
            else if trimmed = ":quit" || trimmed = ":q" then
              print_endline "Exiting T REPL."
            else begin
              let (result, new_env) = parse_and_eval env trimmed in
              (match result with
               | Ast.VNull -> ()
               | Ast.VError msg -> Printf.printf "Error: %s\n" msg
               | v -> print_endline (Ast.Utils.value_to_string v));
              repl new_env
            end
      in
      repl env
