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

  print_newline ()
