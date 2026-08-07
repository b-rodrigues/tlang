let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Phase 2 — Colcraft: drop_na and factor functions:\n";

  let env = Packages.init_env () in
  let env = Test_helpers.eval_setup eval_string_env env "test_drop_na_and_factors:5" {|df = to_dataframe([x: [1, NA, 3], y: [4, 5, 6]])|} in
  let env = Test_helpers.eval_setup eval_string_env env "test_drop_na_and_factors:6" {|f = to_factor(["a", "a", "b", "c", "c", "c"])|} in

  Printf.printf "  drop_na():\n";
  test_env env "drop_na drops rows with any NA"
    "nrow(drop_na(df))"
    "2";
  test_env env "drop_na on specific column drops NA in that column"
    "nrow(drop_na(df, $x))"
    "2";
  test_env env "drop_na rejects nonexistent column"
    "drop_na(df, $nonexistent)"
    {|Error(KeyError: "Function `drop_na`: column(s) not found: nonexistent")|};
  test_env env "drop_na rejects non-column syntax"
    "drop_na(df, 42)"
    {|Error(TypeError: "Function `drop_na` expects all column arguments to use $col syntax.")|};
  test_env env "drop_na rejects non-DataFrame first arg"
    "drop_na(42)"
    {|Error(TypeError: "Function `drop_na` expects a DataFrame as first argument.")|};
  print_newline ();

  Printf.printf "  fct_infreq():\n";
  test_env env "fct_infreq reorders levels by frequency"
    "levels(fct_infreq(f))"
    {|Vector["c", "a", "b"]|};
  test_env env "fct_infreq rejects non-vector"
    "fct_infreq([1, 2, 3])"
    {|Error(ArityError: "fct_infreq expects 1 argument (vector of factors)")|};
  print_newline ();

  Printf.printf "  fct_rev():\n";
  test_env env "fct_rev reverses level order"
    "levels(fct_rev(f))"
    {|Vector["c", "b", "a"]|};
  test_env env "fct_rev rejects non-vector"
    "fct_rev([1, 2, 3])"
    {|Error(ArityError: "fct_rev expects 1 argument")|};
  print_newline ();

  Printf.printf "  fct_recode():\n";
  test_env env "fct_recode returns vector"
    "type(fct_recode(f))"
    {|"Vector"|};
  print_newline ();

  Printf.printf "  fct_relevel():\n";
  test_env env "fct_relevel moves level to front"
    "levels(fct_relevel(f, \"b\"))"
    {|Vector["b", "a", "c"]|};
  test_env env "fct_relevel rejects non-vector"
    "fct_relevel([1, 2, 3])"
    {|Error(ArityError: "fct_relevel expects at least 1 argument")|};
  print_newline ();

  Printf.printf "  fct_reorder():\n";
  test_env env "fct_reorder rejects non-vector"
    "fct_reorder([1, 2, 3])"
    {|Error(ArityError: "fct_reorder expects at least 2 arguments (.f and .x)")|};
  test_env env "fct_reorder rejects mismatched lengths"
    "fct_reorder(to_factor([\"a\", \"b\"]), [1.0])"
    {|Error(ArityError: "fct_reorder expects at least 2 arguments (.f and .x)")|};
  print_newline ();

  Printf.printf "  fct_lump_min():\n";
  test_env env "fct_lump_min groups infrequent levels"
    "levels(fct_lump_min(f, 2))"
    {|Vector["a", "c", "Other"]|};
  test_env env "fct_lump_min rejects non-vector"
    "fct_lump_min([1, 2, 3])"
    {|Error(ArityError: "fct_lump_min expects a to_factor vector and minimum count")|};
  print_newline ();

  Printf.printf "  fct_lump_prop():\n";
  test_env env "fct_lump_prop groups low proportion levels"
    "levels(fct_lump_prop(f, 0.4))"
    {|Vector["c", "Other"]|};
  test_env env "fct_lump_prop rejects proportion out of range"
    "fct_lump_prop(f, 1.5)"
    {|Error(ValueError: "Function `fct_lump_prop` proportion must be between 0 and 1.")|};
  test_env env "fct_lump_prop rejects non-numeric proportion"
    "fct_lump_prop(f, \"bad\")"
    {|Error(TypeError: "Function `fct_lump_prop` expects a numeric proportion.")|};
  print_newline ();
  print_newline ()
