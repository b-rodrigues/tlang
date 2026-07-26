let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
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

  (* to_float / to_float *)
  test "to_float bool true" "to_float(true)" "1.";
  test "to_float bool false" "to_float(false)" "0.";
  test "to_float string float" {|to_float("3.14")|} "3.14";
  test "to_float string spaces" {|to_float(" 12 300.5 ")|} "12300.5";
  test "to_float string percent" {|to_float("15.5%")|} "15.5";
  test "to_float string TRUE" {|to_float("TRUE")|} "1.";
  test "to_float string F" {|to_float("F")|} "0.";
  test "to_float string comma" {|to_float("3,14")|} "3.14";
  test "to_float string semi-colon" {|to_float("16;5")|} "16.5";
  test "to_float list" {|to_float(["15.5%", "TRUE", "3,14", "hello"])|} "[15.5, 1., 3.14, NA]";
  test "to_float invalid" {|to_float("hello")|} "NA";

  (* to_bool *)
  test "to_bool true" "to_bool(true)" "true";
  test "to_bool false" "to_bool(false)" "false";
  test "to_bool int nonzero" "to_bool(1)" "true";
  test "to_bool int zero" "to_bool(0)" "false";
  test "to_bool float nonzero" "to_bool(3.14)" "true";
  test "to_bool float zero" "to_bool(0.0)" "false";
  test "to_bool string TRUE" {|to_bool("TRUE")|} "true";
  test "to_bool string T" {|to_bool("T")|} "true";
  test "to_bool string YES" {|to_bool("YES")|} "true";
  test "to_bool string Y" {|to_bool("Y")|} "true";
  test "to_bool string 1" {|to_bool("1")|} "true";
  test "to_bool string FALSE" {|to_bool("FALSE")|} "false";
  test "to_bool string F" {|to_bool("F")|} "false";
  test "to_bool string NO" {|to_bool("NO")|} "false";
  test "to_bool string N" {|to_bool("N")|} "false";
  test "to_bool string 0" {|to_bool("0")|} "false";
  test "to_bool string garbage" {|to_bool("banana")|} "NA";
  test "to_bool NA" "to_bool(NA)" "NA";
  test "to_bool list maps over elements"
    "to_bool([1, 0, 1])"
    "[true, false, true]";
  print_newline ()
