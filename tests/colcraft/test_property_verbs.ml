(* Dogfooding: exercise colcraft and stats verbs with prop_for_all over
   generated DataFrames (with and without injected NAs). These properties
   codify row-count algebra and NA-handling invariants; a failing verb
   produces a shrunk DataFrame counterexample. *)

let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — colcraft/stats verbs:\n";
  let env = Packages.init_env () in

  (* Row-preserving verbs under NA injection *)
  test_env env "mutate preserves nrow under NA"
    "set_seed(1)\nprop_for_all(prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.2), \\(df) nrow(mutate(df, $z = $x * 2)) == nrow(df), n = 25)"
    "PASS";
  test_env env "arrange preserves nrow under NA"
    "set_seed(1)\nprop_for_all(prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.2), \\(df) nrow(arrange(df, $x)) == nrow(df), n = 25)"
    "PASS";
  test_env env "filter output never exceeds input under NA"
    "set_seed(1)\nprop_for_all(prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.2), \\(df) nrow(filter(df, $x > 50.0)) <= nrow(df), n = 25)"
    "PASS";

  (* Row-count algebra *)
  test_env env "group_by+summarize group sizes sum to nrow"
    "set_seed(1)\nprop_for_all(prop_gen_df([g: prop_gen_factor([\"a\", \"b\"])], nrows = 40, na_prob = 0.0), \\(df) to_integer(sum((df |> group_by($g) |> summarize($cnt = n())).cnt)) == nrow(df), n = 25)"
    "PASS";
  test_env env "distinct never grows rows"
    "set_seed(1)\nprop_for_all(prop_gen_df([x: prop_gen_int_range(0, 3)], nrows = 30, na_prob = 0.0), \\(df) nrow(distinct(df)) <= nrow(df), n = 25)"
    "PASS";
  test_env env "head slices to fixed size"
    "set_seed(1)\nprop_for_all(prop_gen_df([x: prop_gen_int_range(0, 3)], nrows = 30, na_prob = 0.0), \\(df) nrow(head(df, 5)) == 5, n = 25)"
    "PASS";
  test_env env "slice_sample keeps requested size"
    "set_seed(1)\nprop_for_all(prop_gen_df([x: prop_gen_int_range(0, 3)], nrows = 30, na_prob = 0.0), \\(df) nrow(slice_sample(df, n = 5)) == 5, n = 25)"
    "PASS";

  (* stats verbs with na_rm *)
  test_env env "mean with na_rm stays in range"
    "set_seed(1)\nprop_for_all(prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.2), \\(df) is_na(mean(df |> pull(\"x\"), na_rm = true)) || (mean(df |> pull(\"x\"), na_rm = true) >= 0.0 && mean(df |> pull(\"x\"), na_rm = true) <= 100.0), n = 25)"
    "PASS";
  test_env env "sd with na_rm is non-negative"
    "set_seed(1)\nprop_for_all(prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.2), \\(df) is_na(sd(df |> pull(\"x\"), na_rm = true)) || sd(df |> pull(\"x\"), na_rm = true) >= 0.0, n = 25)"
    "PASS";

  (* joins with a fixed lookup table *)
  test_env env "left_join preserves left row count with unique keys"
    "right = to_dataframe([[g: \"a\", val: 1], [g: \"b\", val: 2]])\nset_seed(1)\nprop_for_all(prop_gen_df([g: prop_gen_factor([\"a\", \"b\"])], nrows = 30, na_prob = 0.0), \\(df) nrow(left_join(df, right, by = $g)) == nrow(df), n = 25)"
    "PASS";
  test_env env "left_join preserves left row count under NA keys"
    "right = to_dataframe([[g: \"a\", val: 1], [g: \"b\", val: 2]])\nset_seed(1)\nprop_for_all(prop_gen_df([g: prop_gen_factor([\"a\", \"b\"])], nrows = 30, na_prob = 0.2), \\(df) nrow(left_join(df, right, by = $g)) == nrow(df), n = 25)"
    "PASS";

  (* fill preserves rows *)
  test_env env "fill preserves nrow under NA"
    "set_seed(1)\nprop_for_all(prop_gen_df([g: prop_gen_factor([\"a\", \"b\"]), x: prop_gen_int_range(1, 5)], nrows = 40, na_prob = 0.2), \\(df) nrow(fill(df, $x)) == nrow(df), n = 25)"
    "PASS";

  Printf.printf "\n"
