(* Dogfooding: functional invariants of core primitives exercised via
   prop_named / prop_test over generated domains. Each property runs under
   several fixed seeds via prop_test_seeded. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — core:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_map_length    = prop_named("map_length",    \(xs) length(map(xs, \(x) x * 2)) == length(xs))
      m_identical     = prop_named("identical_self", \(x) identical(x, x) == true)
      m_ifelse_true   = prop_named("ifelse_true",   \(x) ifelse(true, x, -1) == x)
      m_ifelse_false  = prop_named("ifelse_false",  \(x) ifelse(false, -1, x) == x)
      m_roundtrip_int = prop_named("int_float_rt",  \(x) to_integer(to_float(x)) == x)
      m_map_identity  = prop_named("map_identity",  \(xs) identical(map(xs, \(x) x), xs))
      m_map_compose   = prop_named("map_compose",   \(xs) identical(map(map(xs, \(x) x + 1), \(x) x * 2), map(xs, \(x) (x + 1) * 2)))
      m_head_len      = prop_named("head_len",      \(xs) length(head(xs, 3)) == min([3, length(xs)]))
      m_tail_len      = prop_named("tail_len",      \(xs) length(tail(xs, 5)) == min([5, length(xs)]))
      m_sum_shift     = prop_named("sum_shift",     \(xs) sum(map(xs, \(x) x + 1)) == sum(xs) + length(xs))
      m_head_cap      = prop_named("head_cap",      \(xs) identical(head(xs, 100), xs))
      m_sum_const     = prop_named("sum_const",     \(xs) sum(map(xs, \(x) 5)) == 5 * length(xs))
      m_get_first     = prop_named("get_first",     \(xs) get(xs, 0) == get(head(xs, 1), 0))
      m_seq_len       = prop_named("seq_len",       \(ab) length(seq(get(ab, 0), get(ab, 1))) == max([get(ab, 0), get(ab, 1)]) - min([get(ab, 0), get(ab, 1)]) + 1)
      m_seq_sum       = prop_named("seq_sum",       \(ab) abs(to_float(sum(seq(get(ab, 0), get(ab, 1)))) - (to_float(get(ab, 0) + get(ab, 1)) * to_float(max([get(ab, 0), get(ab, 1)]) - min([get(ab, 0), get(ab, 1)]) + 1) / 2.0)) < 0.0001)
      m_seq_commute   = prop_named("seq_sum_commute", \(ab) sum(seq(get(ab, 0), get(ab, 1))) == sum(seq(get(ab, 1), get(ab, 0))))
      m_seq_endpoints = prop_named("seq_endpoints", \(ab) get(seq(get(ab, 0), get(ab, 1)), 0) == get(ab, 0) && get(seq(get(ab, 0), get(ab, 1)), length(seq(get(ab, 0), get(ab, 1))) - 1) == get(ab, 1))
    |} env
  in

  let seeds = [ 1; 7; 42 ] in
  let int_gen    = "prop_gen_int_range(-100, 100)" in
  let bool_gen   = "prop_gen_bool()" in
  let list3_gen  = "prop_gen_list(prop_gen_int_range(-10, 10), 5)" in
  let pair_gen   = "prop_gen_list(prop_gen_int_range(1, 50), 2)" in

  Test_helpers.prop_test_seeded test_env env "map preserves list length" "m_map_length" list3_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "identical(x, x) is always true (int)" "m_identical" int_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "identical(x, x) is always true (bool)" "m_identical" bool_gen 10 seeds;
  Test_helpers.prop_test_seeded test_env env "ifelse(true, x, -1) == x" "m_ifelse_true" int_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "ifelse(false, -1, x) == x" "m_ifelse_false" int_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "to_integer(to_float(x)) == x round-trip" "m_roundtrip_int" int_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "map with identity preserves the list" "m_map_identity" list3_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "map composes f then g like a single lambda" "m_map_compose" list3_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "head returns at most the requested prefix" "m_head_len" list3_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "tail returns at most the requested suffix" "m_tail_len" list3_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "sum of (x + 1) == sum(x) + length(x)" "m_sum_shift" list3_gen 30 seeds;

  (* Hardened invariants *)
  Test_helpers.prop_test_seeded test_env env "head never exceeds the list length" "m_head_cap" list3_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "sum of a constant map == 5 * length" "m_sum_const" list3_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "get(xs, 0) agrees with head(xs, 1)" "m_get_first" list3_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "seq(a, b) length == |a - b| + 1" "m_seq_len" pair_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "seq(a, b) sums to the arithmetic series" "m_seq_sum" pair_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "sum(seq(a, b)) == sum(seq(b, a))" "m_seq_commute" pair_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "seq(a, b) starts at a and ends at b" "m_seq_endpoints" pair_gen 30 seeds;

  Printf.printf "\n"
