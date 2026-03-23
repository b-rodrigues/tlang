(* tests/core/test_bitwise_error.ml *)

let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Bitwise Error Message Tests:\n";

  (* Test BitOr with List *)
  test "BitOr True List" "true | [true, false]" 
    {|Error(TypeError: "Operator `|` expects Bool and Bool.
Hint: Use `.|` for element-wise boolean operations.")|};

  (* Test BitAnd with List *)
  test "BitAnd True List" "true & [true, false]" 
    {|Error(TypeError: "Operator `&` expects Bool and Bool.
Hint: Use `.&` for element-wise boolean operations.")|};

  (* Test List with BitOr *)
  test "BitOr List True" "[true, false] | true" 
    {|Error(TypeError: "Operator `|` expects Bool and Bool.
Hint: Use `.|` for element-wise boolean operations.")|};

  (* Test List with BitAnd *)
  test "BitAnd List True" "[true, false] & true" 
    {|Error(TypeError: "Operator `&` expects Bool and Bool.
Hint: Use `.&` for element-wise boolean operations.")|};
