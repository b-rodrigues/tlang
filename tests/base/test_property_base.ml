(* Dogfooding: base package invariants exercised via prop_named / prop_test
   over generated values. Covers serialize/deserialize round-trips, JSON
   round-trips, is_na identity, error round-trips, sample determinism, and
   NA/assert interactions. *)
let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — base:\n";
  let env = Packages.init_env () in

  let _ = eval_string_env "set_seed(1)" env in

  (* ---- serialize / deserialize round-trip over scalars ---- *)

  test_env env "serialize/deserialize round-trip Int"
    {|prop_for_all(prop_gen_int_range(-1000, 1000), \(x) { serialize(x, "/tmp/rt_int.tobj"); y = deserialize("/tmp/rt_int.tobj"); y == x }, n = 30)|}
    "PASS";

  test_env env "serialize/deserialize round-trip Float"
    {|prop_for_all(prop_gen_float_range(-1000.0, 1000.0), \(x) { serialize(x, "/tmp/rt_float.tobj"); y = deserialize("/tmp/rt_float.tobj"); y == x }, n = 30)|}
    "PASS";

  test_env env "serialize/deserialize round-trip Bool"
    {|prop_for_all(prop_gen_bool(), \(x) { serialize(x, "/tmp/rt_bool.tobj"); y = deserialize("/tmp/rt_bool.tobj"); y == x }, n = 10)|}
    "PASS";

  test_env env "serialize/deserialize round-trip String"
    {|prop_for_all(prop_gen_string_from("abcdefghijklmnopqrstuvwxyz", 0, 20), \(x) { serialize(x, "/tmp/rt_str.tobj"); y = deserialize("/tmp/rt_str.tobj"); y == x }, n = 30)|}
    "PASS";

  test_env env "serialize returns NA on success"
    {|serialize(42, "/tmp/rt_na_ret.tobj")|} "NA";

  (* ---- NA round-trip through serialize/deserialize ---- *)

  test_env env "serialize/deserialize preserves NA"
    {|{ serialize(na(), "/tmp/rt_na.tobj"); deserialize("/tmp/rt_na.tobj") }|} "NA";

  test_env env "serialize/deserialize preserves NA(Int)"
    {|{ serialize(na_int(), "/tmp/rt_naint.tobj"); deserialize("/tmp/rt_naint.tobj") }|} "NA(Int)";

  test_env env "serialize/deserialize preserves NA(Float)"
    {|{ serialize(na_float(), "/tmp/rt_nafloat.tobj"); deserialize("/tmp/rt_nafloat.tobj") }|} "NA(Float)";

  test_env env "serialize/deserialize preserves NA(Bool)"
    {|{ serialize(na_bool(), "/tmp/rt_nabool.tobj"); deserialize("/tmp/rt_nabool.tobj") }|} "NA(Bool)";

  test_env env "serialize/deserialize preserves NA(String)"
    {|{ serialize(na_string(), "/tmp/rt_nastr.tobj"); deserialize("/tmp/rt_nastr.tobj") }|} "NA(String)";

  (* ---- is_na invariants ---- *)

  test_env env "is_na detects NA(Generic)"   {|is_na(na())|} "true";
  test_env env "is_na detects NA(Int)"       {|is_na(na_int())|} "true";
  test_env env "is_na detects NA(Float)"     {|is_na(na_float())|} "true";
  test_env env "is_na detects NA(Bool)"      {|is_na(na_bool())|} "true";
  test_env env "is_na detects NA(String)"    {|is_na(na_string())|} "true";

  test_env env "is_na on non-NA returns false"
    {|is_na(42) == false && is_na(3.14) == false && is_na("hello") == false && is_na(true) == false|}
    "true";

  test_env env "is_na is idempotent — never returns NA"
    {|is_na(is_na(42)) == false && is_na(is_na(na())) == false|}
    "true";

  test_env env "is_na false for any generated Int"
    {|prop_for_all(prop_gen_int_range(-100, 100), \(x) is_na(x) == false, n = 30)|} "PASS";

  test_env env "is_na false for any generated Float"
    {|prop_for_all(prop_gen_float_range(-100.0, 100.0), \(x) is_na(x) == false, n = 30)|} "PASS";

  test_env env "is_na false for any generated Bool"
    {|prop_for_all(prop_gen_bool(), \(x) is_na(x) == false, n = 10)|} "PASS";

  test_env env "is_na false for any generated String"
    {|prop_for_all(prop_gen_string_from("abc", 0, 10), \(x) is_na(x) == false, n = 30)|} "PASS";

  (* ---- error round-trip ---- *)

  test_env env "error_code round-trip (all known codes)"
    {|error_code(error("TypeError", "x")) == "TypeError" && error_code(error("ValueError", "x")) == "ValueError" && error_code(error("ArityError", "x")) == "ArityError" && error_code(error("NameError", "x")) == "NameError" && error_code(error("DivisionByZero", "x")) == "DivisionByZero" && error_code(error("KeyError", "x")) == "KeyError" && error_code(error("IndexError", "x")) == "IndexError" && error_code(error("AssertionError", "x")) == "AssertionError" && error_code(error("FileError", "x")) == "FileError" && error_code(error("SyntaxError", "x")) == "SyntaxError" && error_code(error("ShellError", "x")) == "ShellError" && error_code(error("RuntimeError", "x")) == "RuntimeError" && error_code(error("StructuralError", "x")) == "StructuralError"|}
    "true";

  test_env env "error_msg round-trip"
    {|error_msg(error("hello world"))|} "hello world";

  test_env env "error_msg round-trip with code"
    {|error_msg(error("TypeError", "bad type"))|} "bad type";

  test_env env "error_context returns Dict"
    {|error_context(error("msg"))|} "{";

  test_env env "error_context of coded error returns Dict"
    {|error_context(error("ValueError", "x"))|} "{";

  test_env env "error_chain preserves first error code"
    {|{ e = error_chain(error("TypeError", "msg"), error("RuntimeError", "cause")); error_code(e) == "TypeError" }|}
    "true";

  test_env env "error_chain preserves first error message"
    {|{ e = error_chain(error("TypeError", "outer"), error("RuntimeError", "inner")); error_msg(e) }|}
    "outer";

  test_env env "error_chain sets cause in context"
    {|{ e = error_chain(error("TypeError", "outer"), error("RuntimeError", "inner")); ctx = error_context(e); error_msg(ctx.cause) == "inner" }|}
    "true";

  test_env env "error_chain is associative — triple chain preserves outermost"
    {|{ e1 = error("TypeError", "e1"); e2 = error("RuntimeError", "e2"); e3 = error("ValueError", "e3"); chained = error_chain(error_chain(e1, e2), e3); error_code(chained) == "TypeError" && error_msg(chained) == "e1" }|}
    "true";

  (* ---- JSON round-trip ---- *)

  test_env env "t_write_json/t_read_json round-trip Int"
    {|prop_for_all(prop_gen_int_range(-1000, 1000), \(x) { t_write_json(x, "/tmp/rt_json_int.json"); y = t_read_json("/tmp/rt_json_int.json"); y == x }, n = 30)|}
    "PASS";

  test_env env "t_write_json/t_read_json round-trip Float"
    {|prop_for_all(prop_gen_float_range(-100.0, 100.0), \(x) { t_write_json(x, "/tmp/rt_json_flt.json"); y = t_read_json("/tmp/rt_json_flt.json"); y == x }, n = 30)|}
    "PASS";

  test_env env "t_write_json/t_read_json round-trip String"
    {|prop_for_all(prop_gen_string_from("abcdefghijklmnopqrstuvwxyz", 0, 20), \(x) { t_write_json(x, "/tmp/rt_json_str.json"); y = t_read_json("/tmp/rt_json_str.json"); y == x }, n = 30)|}
    "PASS";

  test_env env "t_write_json/t_read_json round-trip Bool"
    {|prop_for_all(prop_gen_bool(), \(x) { t_write_json(x, "/tmp/rt_json_bool.json"); y = t_read_json("/tmp/rt_json_bool.json"); y == x }, n = 10)|}
    "PASS";

  test_env env "t_write_json returns NA on success"
    {|t_write_json(42, "/tmp/rt_json_na.json")|} "NA";

  (* ---- sample + set_seed determinism ---- *)

  test_env env "sample is deterministic under same seed"
    {|{ set_seed(42); a = sample([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], n = 5); set_seed(42); b = sample([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], n = 5); identical(a, b) }|}
    "true";

  test_env env "sample with replace is deterministic"
    {|{ set_seed(7); a = sample([1, 2, 3], n = 10, replace = true); set_seed(7); b = sample([1, 2, 3], n = 10, replace = true); identical(a, b) }|}
    "true";

  test_env env "sample length equals n"
    {|prop_for_all(prop_gen_vector(prop_gen_int_range(0, 100), 10), \(v) { length(sample(v, n = 5)) == 5 }, n = 20)|}
    "PASS";

  test_env env "sample with replace length equals n"
    {|prop_for_all(prop_gen_vector(prop_gen_int_range(0, 100), 3), \(v) { length(sample(v, n = 10, replace = true)) == 10 }, n = 20)|}
    "PASS";

  (* ---- set_seed invariants ---- *)

  test_env env "set_seed always returns NA"     {|set_seed(42)|} "NA";
  test_env env "set_seed negative seed works"   {|set_seed(-1)|} "NA";

  test_env env "set_seed makes draws reproducible across prop_for_all"
    {|{ set_seed(42); a = prop_for_all(prop_gen_int_range(0, 1000), \(x) x >= 0, n = 20); set_seed(42); b = prop_for_all(prop_gen_int_range(0, 1000), \(x) x >= 0, n = 20); a == b }|}
    "true";

  (* ---- with_seed scoping ---- *)

  test_env env "with_seed different seeds produce different inner results"
    {|{ set_seed(1); a = with_seed(7, \(u) sample([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], n = 5)); b = with_seed(42, \(u) sample([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], n = 5)); !identical(a, b) }|}
    "true";

  (* ---- NA / assert interactions ---- *)

  test_env env "assert(na()) raises AssertionError"
    {|assert(na())|}
    "Assertion received NA";

  test_env env "NA is not truthy — assert fails on generated NA"
    {|set_seed(1); prop_for_all(prop_gen_one_of([na_int()]), \(x) assert(x), n = 1)|}
    "Assertion received NA";

  Printf.printf "\n"
