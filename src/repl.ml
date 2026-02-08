(* src/repl.ml *)
(* Interactive REPL for the T language — Phase 0 Alpha *)

let parse_and_eval env input =
  let lexbuf = Lexing.from_string input in
  try
    let program = Parser.program Lexer.token lexbuf in
    Eval.eval_program program env
  with
  | Lexer.SyntaxError msg ->
      (Ast.VError { code = Ast.GenericError; message = "Syntax Error: " ^ msg; context = [] }, env)
  | Parser.Error ->
      let pos = Lexing.lexeme_start_p lexbuf in
      let msg = Printf.sprintf "Parse Error at line %d, column %d"
        pos.Lexing.pos_lnum
        (pos.Lexing.pos_cnum - pos.Lexing.pos_bol)
      in
      (Ast.VError { code = Ast.GenericError; message = msg; context = [] }, env)

let run_file filename env =
  try
    let ch = open_in filename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    parse_and_eval env content
  with
  | Sys_error msg -> (Ast.VError { code = Ast.FileError; message = "File Error: " ^ msg; context = [] }, env)

let () =
  (* Check for command-line arguments *)
  let args = Array.to_list Sys.argv in
  let env = Eval.initial_env () in
  match args with
  | _ :: "run" :: filename :: _ ->
      let (result, _env) = run_file filename env in
      (match result with
       | Ast.VError { code; message; _ } ->
           Printf.eprintf "Error(%s): %s\n" (Ast.Utils.error_code_to_string code) message; exit 1
       | Ast.VNull -> ()
       | v -> print_endline (Ast.Utils.value_to_string v))
  | _ :: "explain" :: rest ->
      (* Phase 6: t explain <expr> [--json] *)
      let is_json = List.mem "--json" rest in
      let expr_parts = List.filter (fun s -> s <> "--json") rest in
      let expr_str = String.concat " " expr_parts in
      if expr_str = "" then begin
        Printf.eprintf "Usage: t explain <expression> [--json]\n"; exit 1
      end else begin
        let (result, env') = parse_and_eval env expr_str in
        match result with
        | Ast.VError { code; message; _ } ->
            Printf.eprintf "Error(%s): %s\n" (Ast.Utils.error_code_to_string code) message; exit 1
        | _ ->
            let explain_expr = Printf.sprintf "explain(__explain_target__)" in
            let env'' = Ast.Env.add "__explain_target__" result env' in
            let (explain_result, _) = parse_and_eval env'' explain_expr in
            if is_json then
              print_endline (Ast.Utils.value_to_string explain_result)
            else begin
              (* Pretty-print explain output *)
              let rec print_dict indent pairs =
                List.iter (fun (k, v) ->
                  match v with
                  | Ast.VDict sub_pairs ->
                      Printf.printf "%s%s:\n" indent k;
                      print_dict (indent ^ "  ") sub_pairs
                  | Ast.VList items ->
                      Printf.printf "%s%s: [%s]\n" indent k
                        (String.concat ", " (List.map (fun (_, item) -> Ast.Utils.value_to_string item) items))
                  | _ ->
                      Printf.printf "%s%s: %s\n" indent k (Ast.Utils.value_to_string v)
                ) pairs
              in
              match explain_result with
              | Ast.VDict pairs -> print_dict "" pairs
              | Ast.VError { code; message; _ } ->
                  Printf.eprintf "Error(%s): %s\n" (Ast.Utils.error_code_to_string code) message; exit 1
              | v -> print_endline (Ast.Utils.value_to_string v)
            end
      end
  | _ ->
      (* Interactive REPL mode *)
      Printf.printf "T language REPL — version 0.4 (Phase 6 Alpha)\n";
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
               | Ast.VError { code; message; _ } -> Printf.printf "Error(%s): %s\n" (Ast.Utils.error_code_to_string code) message
               | v -> print_endline (Ast.Utils.value_to_string v));
              repl new_env
            end
      in
      repl env
