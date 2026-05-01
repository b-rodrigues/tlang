open Ast

let run_tests pass_count fail_count _eval_string _eval_string_env test =
  let check name ok got =
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n    Got: %s\n" name got
    end
  in
  Printf.printf "Phase 1 — NA Values:\n";
  test "NA literal" "NA" "NA";
  test "typed NA bool" "na_bool()" "NA(Bool)";
  test "typed NA int" "na_int()" "NA(Int)";
  test "typed NA float" "na_float()" "NA(Float)";
  test "typed NA string" "na_string()" "NA(String)";
  test "generic NA" "na()" "NA";
  test "is_na on NA" "is_na(NA)" "true";
  test "is_na on typed NA" "is_na(na_int())" "true";
  test "is_na on value" "is_na(42)" "false";
  test "type of NA" "type(NA)" {|"NA"|};
  test "NA is falsy" "if (NA) 1 else 2" {|Error(NAPredicateError: "Cannot use NA as a condition")|};
  test "NA equality is error" "NA == NA" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "NA comparison with value is error" "NA == 1" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 1 — No Implicit NA Propagation:\n";
  test "NA + int is error" "NA + 1" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "int + NA is error" "1 + NA" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "NA * float is error" "NA * 2.0" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "negation of NA is error" "x = NA; 0 - x" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 1 — is_na container handling:\n";
  let test_env = Packages.init_env () in
  (match Env.find_opt "is_na" test_env with
   | Some (VBuiltin builtin) ->
       let vector_result =
         builtin.b_func
            [ (None, VVector [| VNA NAGeneric; VInt 1 |]) ]
            (ref test_env)
       in
       let vector_ok =
         match vector_result with
         | VVector arr -> Array.to_list arr = [ VBool true; VBool false ]
         | _ -> false
       in
       check "is_na maps over vectors" vector_ok (Utils.value_to_string vector_result);
       let list_result =
         builtin.b_func
            [ (None, VList [ (Some "missing", VNA NAString); (None, VInt 1) ]) ]
            (ref test_env)
       in
       let list_ok =
         match list_result with
         | VList [ (Some "missing", VBool true); (None, VBool false) ] -> true
         | _ -> false
       in
       check "is_na maps over lists and keeps names" list_ok (Utils.value_to_string list_result)
   | Some other ->
       check "is_na builtin registration" false (Utils.value_to_string other)
   | None ->
       check "is_na builtin registration" false "missing");
  print_newline ()
