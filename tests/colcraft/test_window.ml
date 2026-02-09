let run_tests pass_count fail_count _eval_string _eval_string_env test =
  Printf.printf "Window Functions — Ranking:\n";

  (* row_number: ties broken by position *)
  test "row_number simple"
    {|row_number([1, 2, 3])|}
    "Vector[1, 2, 3]";
  test "row_number with ties"
    {|row_number([1, 1, 2, 2, 2])|}
    "Vector[1, 2, 3, 4, 5]";
  test "row_number empty"
    {|row_number([])|}
    "Vector[]";

  (* min_rank: ties get minimum rank *)
  test "min_rank simple"
    {|min_rank([1, 2, 3])|}
    "Vector[1, 2, 3]";
  test "min_rank with ties"
    {|min_rank([1, 1, 2, 2, 2])|}
    "Vector[1, 1, 3, 3, 3]";
  test "min_rank empty"
    {|min_rank([])|}
    "Vector[]";

  (* dense_rank: ties get same rank, no gaps *)
  test "dense_rank simple"
    {|dense_rank([1, 2, 3])|}
    "Vector[1, 2, 3]";
  test "dense_rank with ties"
    {|dense_rank([1, 1, 2, 2, 2])|}
    "Vector[1, 1, 2, 2, 2]";
  test "dense_rank empty"
    {|dense_rank([])|}
    "Vector[]";

  (* cume_dist: proportion of values <= current *)
  test "cume_dist simple"
    {|cume_dist([1, 2, 3, 4, 5])|}
    "Vector[0.2, 0.4, 0.6, 0.8, 1.]";
  test "cume_dist with ties"
    {|cume_dist([1, 1, 2, 2, 2])|}
    "Vector[0.4, 0.4, 1., 1., 1.]";

  (* percent_rank: (rank - 1) / (n - 1) *)
  test "percent_rank simple"
    {|percent_rank([1, 2, 3, 4, 5])|}
    "Vector[0., 0.25, 0.5, 0.75, 1.]";
  test "percent_rank single element"
    {|percent_rank([42])|}
    "Vector[0.]";

  (* ntile: divide into n groups *)
  test "ntile into 2 groups"
    {|ntile([1, 2, 3, 4], 2)|}
    "Vector[1, 1, 2, 2]";
  test "ntile into 4 groups"
    {|ntile([1, 2, 3, 4], 4)|}
    "Vector[1, 2, 3, 4]";

  (* Error cases for ranking *)
  test "row_number with NA"
    {|row_number([1, NA, 3])|}
    {|Error(TypeError: "row_number() encountered NA value. Handle missingness explicitly.")|};
  test "ntile non-positive"
    {|ntile([1, 2, 3], 0)|}
    {|Error(ValueError: "ntile() requires a positive number of tiles")|};
  print_newline ();

  Printf.printf "Window Functions — Offset (lead/lag):\n";

  (* lag: shift forward, fill with NA *)
  test "lag simple"
    {|lag([1, 2, 3, 4, 5])|}
    "Vector[NA, 1, 2, 3, 4]";
  test "lag with offset 2"
    {|lag([1, 2, 3, 4, 5], 2)|}
    "Vector[NA, NA, 1, 2, 3]";
  test "lag empty"
    {|lag([])|}
    "Vector[]";
  test "lag strings"
    {|lag(["a", "b", "c"])|}
    {|Vector[NA, "a", "b"]|};

  (* lead: shift backward, fill with NA *)
  test "lead simple"
    {|lead([1, 2, 3, 4, 5])|}
    "Vector[2, 3, 4, 5, NA]";
  test "lead with offset 2"
    {|lead([1, 2, 3, 4, 5], 2)|}
    "Vector[3, 4, 5, NA, NA]";
  test "lead empty"
    {|lead([])|}
    "Vector[]";

  (* Error cases for offset *)
  test "lag negative offset"
    {|lag([1, 2, 3], -1)|}
    {|Error(ValueError: "lag() offset must be non-negative")|};
  test "lead negative offset"
    {|lead([1, 2, 3], -1)|}
    {|Error(ValueError: "lead() offset must be non-negative")|};
  print_newline ();

  Printf.printf "Window Functions — Cumulative:\n";

  (* cumsum *)
  test "cumsum integers"
    {|cumsum([1, 2, 3, 4, 5])|}
    "Vector[1, 3, 6, 10, 15]";
  test "cumsum floats"
    {|cumsum([1.0, 2.0, 3.0])|}
    "Vector[1., 3., 6.]";
  test "cumsum empty"
    {|cumsum([])|}
    "Vector[]";

  (* cummin *)
  test "cummin integers"
    {|cummin([3, 1, 4, 1, 5])|}
    "Vector[3, 1, 1, 1, 1]";
  test "cummin empty"
    {|cummin([])|}
    "Vector[]";

  (* cummax *)
  test "cummax integers"
    {|cummax([1, 3, 2, 5, 4])|}
    "Vector[1, 3, 3, 5, 5]";
  test "cummax empty"
    {|cummax([])|}
    "Vector[]";

  (* cummean *)
  test "cummean integers"
    {|cummean([1, 2, 3, 4])|}
    "Vector[1., 1.5, 2., 2.5]";
  test "cummean empty"
    {|cummean([])|}
    "Vector[]";

  (* cumall *)
  test "cumall all true"
    {|cumall([true, true, true])|}
    "Vector[true, true, true]";
  test "cumall with false"
    {|cumall([true, true, false, true])|}
    "Vector[true, true, false, false]";
  test "cumall empty"
    {|cumall([])|}
    "Vector[]";

  (* cumany *)
  test "cumany all false"
    {|cumany([false, false, false])|}
    "Vector[false, false, false]";
  test "cumany with true"
    {|cumany([false, false, true, false])|}
    "Vector[false, false, true, true]";
  test "cumany empty"
    {|cumany([])|}
    "Vector[]";

  (* Error cases for cumulative *)
  test "cumsum with NA"
    {|cumsum([1, NA, 3])|}
    {|Error(TypeError: "cumsum() encountered NA value. Handle missingness explicitly.")|};
  test "cummin with string"
    {|cummin(["a", "b"])|}
    {|Error(TypeError: "cummin() requires numeric values")|};
  print_newline ();

  (* Clean up *)
  ignore (pass_count, fail_count)
