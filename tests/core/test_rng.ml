let run_tests pass_count fail_count _failures _eval_string eval_string_env test =
  Printf.printf "RNG:\n";
  test "set_seed returns NA" "set_seed(42)" "NA";
  test "sample returns a List (bracket syntax)" "type(sample([1,2,3,4,5]))" {|"List"|};
  test "sample returns correct length" "length(sample([1,2,3,4,5], n=3))" "3";
  test "sample default n=1 returns length 1" "length(sample([1,2,3,4,5]))" "1";
  test "sample replace=true can exceed length" "length(sample([1,2,3], n=5, replace=true))" "5";
  test "sample n=0 returns empty list" "sample([1,2,3], n=0)" "[]";
  test "sample without replace error when n > len"
    "sample([1,2,3], n=5)"
    {|Error(ValueError: "Function `sample` cannot sample 5 items from a population of size 3 without replacement.")|};
  test "sample negative n error" "sample([1], n=-1)"
    {|Error(ValueError: "Function `sample` expects `n` to be non-negative, got -1.")|};
  test "sample non-int n error" "sample([1], n=true)"
    {|Error(TypeError: "Function `sample` expects `n` to be an Int, got Bool.")|};
  test "sample non-vector/list argument" "sample(42)"
    {|Error(TypeError: "Function `sample` expects a Vector or List.")|};
  test "sample on empty list" "sample([], n=0)" "[]";
  test "set_seed non-int argument" "set_seed(true)"
    {|Error(TypeError: "Function `set_seed` expects an integer seed.")|};
  print_newline ();

  Printf.printf "RNG determinism:\n";

  (* Determinism test: same seed → same result via identical() *)
  let expr = {|
    set_seed(42);
    a = sample([1,2,3,4,5,6,7,8,9,10], n=5);
    set_seed(42);
    b = sample([1,2,3,4,5,6,7,8,9,10], n=5);
    identical(a, b)
  |} in
  let env = Packages.init_env () in
  let (result, _env) = eval_string_env expr env in
  let str = Ast.Utils.value_to_string result in
  if str = "true" then begin
    incr pass_count; Printf.printf "  ✓ sample determinism: same seed → same result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ sample determinism: expected true, got %s\n" str
  end;

  (* Different seeds → different results *)
  let diff_expr = {|
    set_seed(42);
    a = sample([1,2,3,4,5,6,7,8,9,10], n=5);
    set_seed(99);
    b = sample([1,2,3,4,5,6,7,8,9,10], n=5);
    identical(a, b)
  |} in
  let env2 = Packages.init_env () in
  let (result2, _env2) = eval_string_env diff_expr env2 in
  let str2 = Ast.Utils.value_to_string result2 in
  if str2 = "false" then begin
    incr pass_count; Printf.printf "  ✓ sample different seeds → different results\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ sample different seeds: expected false, got %s\n" str2
  end;

  (* slice_sample determinism *)
  let slice_expr = {|
    set_seed(42);
    df = to_dataframe([[x: 1], [x: 2], [x: 3], [x: 4], [x: 5], [x: 6], [x: 7], [x: 8]]);
    a = slice_sample(df, n=3);
    set_seed(42);
    b = slice_sample(df, n=3);
    identical(a, b)
  |} in
  let env3 = Packages.init_env () in
  let (result3, _env3) = eval_string_env slice_expr env3 in
  let str3 = Ast.Utils.value_to_string result3 in
  if str3 = "true" then begin
    incr pass_count; Printf.printf "  ✓ slice_sample determinism: same seed → same result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ slice_sample determinism: expected true, got %s\n" str3
  end;

  print_newline ();

  Printf.printf "slice_sample:\n";

  test "slice_sample default n=1 returns DataFrame"
    {|df = to_dataframe([[x: 1], [x: 2], [x: 3]]); type(slice_sample(df))|}
    {|"DataFrame"|};

  test "slice_sample with n returns correct row count"
    {|df = to_dataframe([[x: 1], [x: 2], [x: 3], [x: 4], [x: 5]]); set_seed(7); nrow(slice_sample(df, n=3))|}
    "3";

  test "slice_sample replace=true allows n > nrow"
    {|df = to_dataframe([[x: 1], [x: 2]]); nrow(slice_sample(df, n=5, replace=true))|}
    "5";

  test "slice_sample error when n > nrow without replace"
    {|df = to_dataframe([[x: 1], [x: 2]]); slice_sample(df, n=5)|}
    {|Error(ValueError: "Function `slice_sample` cannot sample 5 rows from a DataFrame with 2 rows without replacement.")|};

  test "slice_sample negative n error"
    {|df = to_dataframe([[x: 1]]); slice_sample(df, n=-1)|}
    {|Error(ValueError: "Function `slice_sample` expects `n` to be non-negative, got -1.")|};

  test "slice_sample non-DataFrame argument"
    "slice_sample(42)"
    {|Error(TypeError: "Function `slice_sample` expects a DataFrame as first argument.")|};

  test "slice_sample with extra positional arguments returns ArityError"
    {|df = to_dataframe([[x: 1], [x: 2]]); slice_sample(df, 5)|}
    {|Error(ArityError: "Function `slice_sample` expects 1 arguments but received 2.")|};

  test "slice_sample replace=true on empty DataFrame returns ValueError"
    {|df = to_dataframe([]); slice_sample(df, n=5, replace=true)|}
    {|Error(ValueError: "Function `slice_sample` cannot sample from an empty DataFrame.")|};

  test "sample replace=true on empty List returns ValueError"
    {|sample([], n=5, replace=true)|}
    {|Error(ValueError: "Function `sample` cannot sample from an empty List.")|};

  test "sample replace=true on empty Vector returns ValueError"
    {|df = to_dataframe([[x: 1]]); empty_df = df |> filter($x > 100); sample(empty_df.x, n=5, replace=true)|}
    {|Error(ValueError: "Function `sample` cannot sample from an empty Vector.")|};

  print_newline ()
