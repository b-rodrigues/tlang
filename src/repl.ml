open Ast
open Eval
open Parser
open Lexer

let package_dir = "packages"

(* Load a single package from disk *)
let load_package env name =
  let path = Filename.concat package_dir (Filename.concat name "init.t") in
  if Sys.file_exists path then (
    let ch = open_in path in
    let rec loop () =
      try
        let source = input_line ch in
        if String.trim source = "" then loop () else
        let tokens = Lexer.lex source in
        let expr = Parser.parse tokens in
        ignore (eval env expr);
        loop ()
      with End_of_file -> close_in ch
         | exn -> Printf.eprintf "Error loading package %s: %s\n" name (Printexc.to_string exn); close_in ch
    in
    loop ()
  )

(* Load core packages at startup *)
let load_builtin_packages env =
  List.iter (load_package env) [ "core"; "stats"; "dplyr" ]

(* Main REPL loop *)
let rec repl env =
  print_string "T> ";
  flush stdout;
  match read_line () with
  | exception End_of_file ->
      print_endline "\nGoodbye.";
      ()
  | line ->
      let trimmed = String.trim line in
      if trimmed = "" then repl env
      else if trimmed = ":quit" || trimmed = ":q" then (
        print_endline "Exiting T REPL.";
        ()
      ) else (
        try
          let tokens = Lexer.lex line in
          let expr = Parser.parse tokens in
          let result = eval env expr in
          print_value result;
        with
        | RuntimeError msg ->
            Printf.printf "Error: %s\n" msg
        | Failure msg | EvalError msg ->
            Printf.printf "Parse error: %s\n" msg
        | exn ->
            Printf.printf "Unknown error: %s\n" (Printexc.to_string exn)
        ;
        repl env
      )

let () =
  let env = Eval.Env.empty () in
  load_builtin_packages env;
  Printf.printf "T language REPL — version 0.1\nType :quit or :q to exit.\n";
  repl env 
