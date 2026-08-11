(* Dogfooding: structural invariants of the explain package exercised via
   prop_named / prop_test over generated scalars, dicts, vectors, lists, NA
   values, errors, symbols, and DataFrames (including Date/Datetime columns).
   `explain` must report consistent kinds/types and agree with the actual
   structure of the value: scalars round-trip through `value`, lists/vectors
   report row/column and NA counts that match `length` / `is_na`, NA scalars
   report their type, errors report code/message, symbols report name, schema
   entries agree with `colnames`, intent_get/intent_fields agree with the
   source dict and with `explain(i).fields`, and `explain_json` always yields
   a non-empty string. Static edge cases cover empty frames, formulas,
   functions, pipelines, and the KeyError raised by `intent_get` on a missing
   field. Each property runs under several fixed seeds via prop_test_seeded. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — explain:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_explain_scalar = prop_named("explain_scalar", \(x) { e = explain(x); e.kind == "value" && e.type == type(x) && identical(e.value, x) })
      m_explain_vec     = prop_named("explain_vector", \(df) { sum(map(colnames(df), \(c) { v = pull(df, c); e = explain(v); ifelse(e.kind == "value" && e.type == "Vector" && e.length == length(v) && e.na_count == sum(map(v, \(x) ifelse(is_na(x), 1, 0))) && length(e.examples) == min([5, length(v)]) && type(e.element_types) == "String", 1, 0) })) == ncol(df) })
      m_explain_na = prop_named("explain_na", \(x) { e = explain(x); e.kind == "value" && e.type == "NA" && type(e.na_type) == "String" })
      m_explain_list = prop_named("explain_list", \(xs) { e = explain(xs); e.kind == "value" && e.type == "List" && e.length == length(xs) && e.na_count == sum(map(xs, \(x) ifelse(is_na(x), 1, 0))) && length(e.examples) == min([5, length(xs)]) })
      m_explain_err = prop_named("explain_error", \(p) { e = explain(error("ValueError", p.s)); e.type == "Error" && e.error_code == "ValueError" && e.error_message == p.s })
      m_explain_symbol = prop_named("explain_symbol", \(s) { e = explain(to_symbol(s)); e.kind == "symbol" && e.name == s && type(e.hint) == "String" })
      m_explain_df_shape = prop_named("explain_df_shape", \(df) { e = explain(df); e.kind == "to_dataframe" && e.nrow == nrow(df) && e.ncol == ncol(df) && type(e.hint) == "String" })
      m_explain_df_examples = prop_named("explain_df_examples", \(df) { e = explain(df); length(e.example_rows) == min([5, nrow(df)]) })
      m_explain_df_schema = prop_named("explain_df_schema", \(df) { e = explain(df); length(e.schema) == ncol(df) && sum(map(seq(0, ncol(df) - 1), \(i) ifelse(get(e.schema, i).name == get(colnames(df), i), 1, 0))) == ncol(df) })
      m_explain_df_na_stats = prop_named("explain_df_na_stats", \(df) { e = explain(df); identical(map(colnames(df), \(c) get(e.na_stats, c)), map(colnames(df), \(c) sum(map(pull(df, c), \(x) ifelse(is_na(x), 1, 0))))) })
      m_explain_df_backend = prop_named("explain_df_backend", \(df) { e = explain(df); (e.storage_backend == "native_arrow") == e.native_path_active && type(e.performance_note) == "String" })
      m_explain_dict = prop_named("explain_dict", \(p) { e = explain(p); e.kind == "value" && e.type == "Dict" && e.length == length(p) && length(e.keys) == length(p) })
      m_intent_roundtrip = prop_named("intent_roundtrip", \(p) { i = intent { a: p.a, b: p.b }; intent_get(i, "a") == p.a && intent_get(i, "b") == p.b })
      m_intent_fields = prop_named("intent_fields_consistent", \(p) { i = intent { a: p.a, b: p.b }; f = intent_fields(i); f.a == p.a && f.b == p.b && f.a == explain(i).fields.a && f.b == explain(i).fields.b })
      m_explain_json_str = prop_named("explain_json_string", \(x) { s = explain_json(x); type(s) == "String" && str_nchar(s) > 0 })
    |} env
  in

  let seeds = [ 1; 7; 42 ] in
  let int_gen    = "prop_gen_int_range(-100, 100)" in
  let float_gen  = "prop_gen_float_range(-10.0, 10.0)" in
  let bool_gen   = "prop_gen_bool()" in
  let str_gen    = "prop_gen_string_from(\"ab \", 0, 5)" in
  let sym_gen    = "prop_gen_string_from(\"ab\", 1, 5)" in
  let na_gen     = "prop_map_gen(prop_gen_int_range(0, 0), \\(x) NA)" in
  let list_gen   = "prop_gen_list(prop_gen_frequency([[4, prop_gen_int_range(0, 5)], [1, " ^ na_gen ^ "]]), 6)" in
  let df_gen     = "prop_gen_df([i: prop_gen_int_range(-100, 100), f: prop_gen_float_range(-10.0, 10.0), b: prop_gen_bool(), s: prop_gen_string_from(\"ab \", 0, 5), g: prop_gen_factor([\"a\", \"b\", \"c\"]), d: prop_gen_ymd(2000, 2024), dt: prop_gen_date_range(ymd_hms(\"2020-01-01 00:00:00\"), ymd_hms(\"2024-12-31 23:59:59\"))], nrows = 25, na_prob = 0.15)" in
  let dict_gen   = "prop_gen_dict([a: prop_gen_string_from(\"ab\", 0, 4), b: prop_gen_string_from(\"xy\", 1, 4)], na_prob = 0.0)" in
  let err_gen    = "prop_gen_dict([s: prop_gen_string_from(\"ab \", 1, 5)], na_prob = 0.0)" in

  Test_helpers.prop_test_seeded test_env env "explain(scalar) reports kind/type/value (int)" "m_explain_scalar" int_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(scalar) reports kind/type/value (float)" "m_explain_scalar" float_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(scalar) reports kind/type/value (bool)" "m_explain_scalar" bool_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(scalar) reports kind/type/value (string)" "m_explain_scalar" str_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(vector) length and NA counts agree with is_na" "m_explain_vec" df_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(NA) reports kind/type/na_type" "m_explain_na" na_gen 10 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(list) reports length/na_count/examples" "m_explain_list" list_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(error) reports code and message" "m_explain_err" err_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(symbol) reports kind/name/hint" "m_explain_symbol" sym_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(df) reports shape" "m_explain_df_shape" df_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(df) example_rows capped at 5" "m_explain_df_examples" df_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(df) schema names agree with colnames" "m_explain_df_schema" df_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(df) na_stats agree with is_na counts" "m_explain_df_na_stats" df_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(df) storage_backend matches native_path_active" "m_explain_df_backend" df_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain(dict) reports kind/type/length/keys" "m_explain_dict" dict_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "intent_get returns generated field values" "m_intent_roundtrip" dict_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "intent_fields agrees with explain(i).fields" "m_intent_fields" dict_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain_json returns a non-empty string (int)" "m_explain_json_str" int_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "explain_json returns a non-empty string (string input)" "m_explain_json_str" str_gen 20 seeds;

  test_env env "explain(empty df) reports zero shape"
    {|e = explain(to_dataframe([])); e.kind == "to_dataframe" && e.nrow == 0 && e.ncol == 0 && length(e.example_rows) == 0 && length(e.schema) == 0|}
    "true";
  test_env env "explain(formula) reports response and predictors"
    {|e = explain(y ~ x); e.kind == "formula" && identical(e.response, ["y"]) && identical(e.predictors, ["x"])|}
    "true";
  test_env env "explain(lambda) reports Function with arguments"
    {|e = explain(\(x, y) x + y); e.type == "Function" && length(e.arguments) == 2|}
    "true";
  test_env env "explain(builtin) reports Function"
    {|explain(mean).type == "Function"|}
    "true";
  test_env env "explain(pipeline) reports node_count and node fields"
    {|p = pipeline { a = 1; b = 2; c = 3 }; e = explain(p); e.kind == "pipeline" && e.node_count == 3 && length(e.nodes) == 3 && sum(map(e.nodes, \(n) ifelse(type(n.name) == "String" && type(n.dependencies) == "List", 1, 0))) == 3|}
    "true";
  test_env env "intent_get on missing field raises KeyError"
    {|i = intent { a: 1 }; intent_get(i, "missing")|}
    {|Error(KeyError: "Intent field `missing` not found.")|};

  Printf.printf "\n"
