let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Converters:\n";
  (* to_integer *)
  test "to_integer bool true" "to_integer(true)" "1";
  test "to_integer bool false" "to_integer(false)" "0";
  test "to_integer string int" {|to_integer("42")|} "42";
  test "to_integer string float" {|to_integer("12.3")|} "12";
  test "to_integer string spaces" {|to_integer(" 12 300 ")|} "12300";
  test "to_integer string percent" {|to_integer("15%")|} "15";
  test "to_integer string T" {|to_integer("T")|} "1";
  test "to_integer string FALSE" {|to_integer("FALSE")|} "0";
  test "to_integer string comma" {|to_integer("3,14")|} "3";
  test "to_integer string semi-colon" {|to_integer("16;5")|} "16";
  test "to_integer vector" {|to_integer(["15%", "T", "3,14"])|} "[15, 1, 3]";
  test "to_integer invalid" {|to_integer("hello")|} "NA";

  (* to_float / to_numeric *)
  test "to_float bool true" "to_float(true)" "1.";
  test "to_float bool false" "to_numeric(false)" "0.";
  test "to_float string float" {|to_float("3.14")|} "3.14";
  test "to_numeric string spaces" {|to_numeric(" 12 300.5 ")|} "12300.5";
  test "to_numeric string percent" {|to_float("15.5%")|} "15.5";
  test "to_float string TRUE" {|to_float("TRUE")|} "1.";
  test "to_float string F" {|to_numeric("F")|} "0.";
  test "to_numeric string comma" {|to_numeric("3,14")|} "3.14";
  test "to_float string semi-colon" {|to_float("16;5")|} "16.5";
  test "to_float list" {|to_float(["15.5%", "TRUE", "3,14", "hello"])|} "[15.5, 1., 3.14, NA]";
  test "to_float invalid" {|to_float("hello")|} "NA";
  print_newline ()
