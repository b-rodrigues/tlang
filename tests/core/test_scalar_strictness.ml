let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Strict Scalar Operator Tests:\n";

  (* --- Scalar vs Collection Strictness NEGATIVE TESTS --- *)
  
  (* Scalar + List *)
  test "Scalar + List" "1 + [2]" {|Error(TypeError: "Operator '+' is defined for scalars only.
Use '.+' for element-wise (broadcast) operations.")|};

  (* List + Scalar *)
  test "List + Scalar" "[1] + 2" {|Error(TypeError: "Operator '+' is defined for scalars only.
Use '.+' for element-wise (broadcast) operations.")|};

  (* List + List *)
  test "List + List" "[1] + [2]" {|Error(TypeError: "Operator '+' is defined for scalars only.
Use '.+' for element-wise (broadcast) operations.")|};

  (* Scalar == List *)
  test "Scalar == List" "1 == [1]" {|Error(TypeError: "Operator '==' is defined for scalars only.
Use '.==' for element-wise (broadcast) operations.")|};

  (* Other operators *)
  test "Scalar - List" "1 - [1]" {|Error(TypeError: "Operator '-' is defined for scalars only.
Use '.-' for element-wise (broadcast) operations.")|};
  test "Scalar * List" "1 * [1]" {|Error(TypeError: "Operator '*' is defined for scalars only.
Use '.*' for element-wise (broadcast) operations.")|};
  test "Scalar / List" "1 / [1]" {|Error(TypeError: "Operator '/' is defined for scalars only.
Use './' for element-wise (broadcast) operations.")|};
  test "Scalar < List" "1 < [1]" {|Error(TypeError: "Operator '<' is defined for scalars only.
Use '.<' for element-wise (broadcast) operations.")|};
  
  (* --- Explicit Broadcasting POSITIVE TESTS --- *)
  test "Scalar .+ List" "1 .+ [2]" "[3]";
  test "List .+ Scalar" "[1] .+ 2" "[3]";
  test "List .+ List" "[1] .+ [2]" "[3]";

  print_newline ()
