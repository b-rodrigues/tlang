open Ast
open Eval

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test =
  Printf.printf "\nTesting pipeline comment stripping:\n";
  
  let env_init = Packages.init_env () in

  (* Test 1: comment stripping *)
  let code1 = {|
    res = node(command = <{
      # this is a python comment mentioning results
      x = 1
    }>)
    results = node(command = <{
      y = res + 1
    }>)
  |} in
  
  let lexbuf1 = Lexing.from_string code1 in
  let program1 = Parser.program Lexer.token lexbuf1 in
  let (_, env1) = eval_program program1 env_init in
  
  (match Env.find_opt "res" env1 with
  | Some (VNode un) ->
      let deps = match un.un_command.node with RawCode { raw_identifiers; _ } -> raw_identifiers | _ -> [] in
      if List.mem "results" deps then (
        incr fail_count;
        let msg = Printf.sprintf "  ✗ Error: Found 'results' in dependencies despite comment stripping\n" in
        failures := msg :: !failures;
        Printf.printf "%s" msg
      ) else (
        incr pass_count;
        Printf.printf "  ✓ comment stripping: 'results' correctly ignored in comment\n"
      )
  | Some _ ->
      incr fail_count;
      let msg = Printf.sprintf "  ✗ Error: 'res' not bound as a node\n" in
      failures := msg :: !failures;
      Printf.printf "%s" msg
  | None ->
      incr fail_count;
      let msg = Printf.sprintf "  ✗ Error: 'res' not found in environment\n" in
      failures := msg :: !failures;
      Printf.printf "%s" msg);

  (* Test 2: trailing comments and string literals (issue 527 follow-up).
     A bare `foo` in a trailing `#` comment or inside a string must not lex. *)
  let check_ids name text ~present ~absent =
    let ids = Ast.extract_identifiers text in
    let ok =
      List.for_all (fun w -> List.mem w ids) present
      && List.for_all (fun w -> not (List.mem w ids)) absent
    in
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ Error: %s (got [%s])\n" name (String.concat "; " ids) in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in
  check_ids "trailing comment words are ignored"
    "x <- data.frame(x = 1:3)  # independent of the foo node"
    ~present:["x"; "data"; "frame"] ~absent:["foo"; "independent"; "node"];
  check_ids "string literal words are ignored"
    "s <- \"the foo node\"\ny <- 1"
    ~present:["s"; "y"] ~absent:["foo"; "the"; "node"];
  check_ids "hash inside strings does not start a comment"
    "p <- \"R/foo#bar.R\"\nz <- p"
    ~present:["p"; "z"] ~absent:["R"; "foo"; "bar"];
  check_ids "escaped quotes stay inside strings"
    "s <- \"say \\\"hi foo\\\" loudly\"\nok <- 1"
    ~present:["s"; "ok"] ~absent:["foo"; "hi"; "loudly"];
  check_ids "R double negation survives"
    "y <- --x\nz <- y"
    ~present:["y"; "x"; "z"] ~absent:[];
  check_ids "whole-line comments still ignored"
    "# independent of the foo node\nx <- 1"
    ~present:["x"] ~absent:["foo"];
  check_ids "read_node literals are kept (Quarto rewrites them)"
    "```{r}\nread_node(\"data\")\nread_node('other')\n```"
    ~present:["read_node"; "data"; "other"; "r"] ~absent:[];

  (* Test 3: pipeline-level repro — bar/baz/qux must not depend on foo. *)
  let code3 = {|
    p = pipeline {
      foo = rn(command = <{ library(arrow); foo <- data.frame(a = 1:3) }>, serializer = ^ipc)
      bar = rn(command = <{ library(arrow); x <- data.frame(x = 1:3)  # independent of the foo node; x }>, serializer = ^ipc)
      baz = rn(command = <{ library(arrow); s <- "the foo node"; data.frame(x = 1:3) }>, serializer = ^ipc)
      qux = rn(command = <{ library(arrow); # independent of the foo node; data.frame(x = 1:3) }>, serializer = ^ipc)
    }
  |} in
  let lexbuf3 = Lexing.from_string code3 in
  let program3 = Parser.program Lexer.token lexbuf3 in
  let (_, env3) = eval_program program3 env_init in
  (match Env.find_opt "p" env3 with
   | Some (VPipeline p) ->
       List.iter (fun name ->
         match List.assoc_opt name p.p_deps with
         | Some [] ->
             incr pass_count;
             Printf.printf "  ✓ pipeline: `%s` has no phantom dependency on `foo`\n" name
         | Some deps ->
             incr fail_count;
             let msg = Printf.sprintf "  ✗ Error: pipeline: `%s` depends on [%s]\n" name (String.concat "; " deps) in
             failures := msg :: !failures;
             Printf.printf "%s" msg
         | None ->
             incr fail_count;
             let msg = Printf.sprintf "  ✗ Error: pipeline: node `%s` missing from deps\n" name in
             failures := msg :: !failures;
             Printf.printf "%s" msg
       ) ["bar"; "baz"; "qux"]
   | Some _ ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ Error: 'p' not bound as a pipeline\n" in
       failures := msg :: !failures;
       Printf.printf "%s" msg
   | None ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ Error: 'p' not found in environment\n" in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  print_newline ()
