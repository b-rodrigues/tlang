open Ast
open Eval

let run_tests pass_count fail_count _eval_string _eval_string_env _test =
  Printf.printf "\nTesting pipeline comment stripping and @deps annotation:\n";
  
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
        Printf.printf "  ✗ Error: Found 'results' in dependencies despite comment stripping\n"
      ) else (
        incr pass_count;
        Printf.printf "  ✓ comment stripping: 'results' correctly ignored in comment\n"
      )
  | Some _ ->
      incr fail_count;
      Printf.printf "  ✗ Error: 'res' not bound as a node\n"
  | None ->
      incr fail_count;
      Printf.printf "  ✗ Error: 'res' not found in environment\n");

  (* Test 2: explicit @deps *)
  let code2 = {|
    n1 = node(command = <{ x = 1 }>)
    n2 = node(command = <{
      --# @deps n1
      y = 2
    }>)
  |} in
  
  let lexbuf2 = Lexing.from_string code2 in
  let program2 = Parser.program Lexer.token lexbuf2 in
  let (_, env2) = eval_program program2 env_init in
  
  let n2_val_opt = Env.find_opt "n2" env2 in
  (match n2_val_opt with
  | Some (VNode un) ->
      let deps = match un.un_command.node with RawCode { raw_identifiers; _ } -> raw_identifiers | _ -> [] in
      if List.mem "n1" deps then (
        incr pass_count;
        Printf.printf "  ✓ explicit @deps: 'n1' found via @deps annotation\n"
      ) else (
        incr fail_count;
        Printf.printf "  ✗ Error: 'n1' NOT found in dependencies via @deps\n"
      )
  | Some _ ->
      incr fail_count;
      Printf.printf "  ✗ Error: 'n2' not bound as a node\n"
  | None ->
      incr fail_count;
      Printf.printf "  ✗ Error: 'n2' not found in environment\n");

  (* Test 3: stripping from emitted script *)
  (match n2_val_opt with
  | Some (VNode un) ->
      let emitted = Nix_unparse.unparse_expr un.un_command in
      let deps_annotation = "--# @deps" in
      let has_deps_annotation =
        try ignore (Str.search_forward (Str.regexp_string deps_annotation) emitted 0); true
        with Not_found -> false
      in
      if has_deps_annotation then (
        incr fail_count;
        Printf.printf "  ✗ Error: '--# @deps' annotation line found in emitted script\n"
      ) else (
        incr pass_count;
        Printf.printf "  ✓ emission: @deps line correctly stripped from guest script\n"
      )
  | Some _ ->
      incr fail_count;
      Printf.printf "  ✗ Error: cannot check emission - 'n2' not bound as a node\n"
  | None ->
      incr fail_count;
      Printf.printf "  ✗ Error: cannot check emission - 'n2' not found in environment\n")
