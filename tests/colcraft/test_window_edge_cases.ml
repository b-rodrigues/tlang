let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  (* === Window Function Edge Cases === *)

  Printf.printf "Window Edge Cases — lag/lead with offset > length:\n";

  (* lag with offset larger than array length — all NA *)
  test "lag offset > length"
    {|lag([1, 2, 3], 10)|}
    "Vector[NA, NA, NA]";
  test "lag offset = length"
    {|lag([1, 2, 3], 3)|}
    "Vector[NA, NA, NA]";
  test "lag offset = 0"
    {|lag([1, 2, 3], 0)|}
    "Vector[1, 2, 3]";

  (* lead with offset larger than array length — all NA *)
  test "lead offset > length"
    {|lead([1, 2, 3], 10)|}
    "Vector[NA, NA, NA]";
  test "lead offset = length"
    {|lead([1, 2, 3], 3)|}
    "Vector[NA, NA, NA]";
  test "lead offset = 0"
    {|lead([1, 2, 3], 0)|}
    "Vector[1, 2, 3]";

  (* lag/lead on single element *)
  test "lag single element"
    {|lag([42])|}
    "Vector[NA]";
  test "lead single element"
    {|lead([42])|}
    "Vector[NA]";

  print_newline ();

  Printf.printf "Window Edge Cases — ntile with more tiles than rows:\n";

  (* ntile with n > length: each element gets its own tile *)
  test "ntile more tiles than rows"
    {|ntile([1, 2, 3], 10)|}
    "Vector[1, 2, 3]";
  test "ntile tiles = rows"
    {|ntile([1, 2, 3], 3)|}
    "Vector[1, 2, 3]";
  test "ntile single element into many"
    {|ntile([42], 5)|}
    "Vector[1]";

  print_newline ();

  Printf.printf "Window Edge Cases — Ranking with all-identical values:\n";

  (* All identical values — test tie handling *)
  test "row_number all identical"
    {|row_number([5, 5, 5, 5])|}
    "Vector[1, 2, 3, 4]";
  test "min_rank all identical"
    {|min_rank([5, 5, 5, 5])|}
    "Vector[1, 1, 1, 1]";
  test "dense_rank all identical"
    {|dense_rank([5, 5, 5, 5])|}
    "Vector[1, 1, 1, 1]";
  test "cume_dist all identical"
    {|cume_dist([5, 5, 5, 5])|}
    "Vector[1., 1., 1., 1.]";
  test "percent_rank all identical"
    {|percent_rank([5, 5, 5, 5])|}
    "Vector[0., 0., 0., 0.]";

  print_newline ();

  Printf.printf "Window Edge Cases — Ranking with single element:\n";

  test "min_rank single"
    {|min_rank([42])|}
    "Vector[1]";
  test "dense_rank single"
    {|dense_rank([42])|}
    "Vector[1]";
  test "cume_dist single"
    {|cume_dist([42])|}
    "Vector[1.]";

  print_newline ();

  Printf.printf "Window Edge Cases — Cumulative with alternating NA:\n";

  (* Alternating NA should propagate from first NA onward *)
  test "cumsum alternating NA"
    {|cumsum([1, NA, 2, NA, 3])|}
    "Vector[1, NA(Float), NA(Float), NA(Float), NA(Float)]";
  test "cummin alternating NA"
    {|cummin([5, NA, 3, NA, 1])|}
    "Vector[5, NA(Float), NA(Float), NA(Float), NA(Float)]";
  test "cummax alternating NA"
    {|cummax([1, NA, 5, NA, 3])|}
    "Vector[1, NA(Float), NA(Float), NA(Float), NA(Float)]";
  test "cummean alternating NA"
    {|cummean([10, NA, 20, NA, 30])|}
    "Vector[10., NA(Float), NA(Float), NA(Float), NA(Float)]";
  test "cumall alternating NA"
    {|cumall([true, NA, true, NA, false])|}
    "Vector[true, NA(Bool), NA(Bool), NA(Bool), NA(Bool)]";
  test "cumany alternating NA"
    {|cumany([false, NA, true, NA, false])|}
    "Vector[false, NA(Bool), NA(Bool), NA(Bool), NA(Bool)]";

  print_newline ();

  Printf.printf "Window Edge Cases — Cumulative single element:\n";

  test "cumsum single"
    {|cumsum([42])|}
    "Vector[42]";
  test "cummin single"
    {|cummin([42])|}
    "Vector[42]";
  test "cummax single"
    {|cummax([42])|}
    "Vector[42]";
  test "cummean single"
    {|cummean([42])|}
    "Vector[42.]";
  test "cumall single true"
    {|cumall([true])|}
    "Vector[true]";
  test "cumany single false"
    {|cumany([false])|}
    "Vector[false]";

  print_newline ();

  Printf.printf "Window Edge Cases — lag/lead with all NA input:\n";

  test "lag all NA"
    {|lag([NA, NA, NA])|}
    "Vector[NA, NA, NA]";
  test "lead all NA"
    {|lead([NA, NA, NA])|}
    "Vector[NA, NA, NA]";

  print_newline ();

  Printf.printf "Window Edge Cases — ntile error cases:\n";

  test "ntile negative tiles"
    {|ntile([1, 2, 3], -1)|}
    {|Error(ValueError: "Function `ntile` requires a positive number of tiles.")|};
  test "ntile zero tiles"
    {|ntile([1, 2, 3], 0)|}
    {|Error(ValueError: "Function `ntile` requires a positive number of tiles.")|};
  test "ntile on empty"
    {|ntile([], 3)|}
    "Vector[]";

  print_newline ()
