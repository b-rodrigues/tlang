
let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Lenses:\n";

  (* 1. Basic col_lens on Dict *)
  test "col_lens set on Dict"
    {|d = [a: 1, b: 2]; l = col_lens("a"); set(d, l, 10)|}
    {|{`a`: 10, `b`: 2}|};

  test "col_lens over on Dict"
    {|d = [a: 1, b: 2]; l = col_lens("a"); over(d, l, \(x) x + 10)|}
    {|{`a`: 11, `b`: 2}|};

  test "col_lens get on Dict (manual call)"
    {|d = [a: 1, b: 2]; l = col_lens("a"); get(d, l)|}
    "1";

  test "col_lens get missing key returns NA"
    {|d = [a: 1, b: 2]; l = col_lens("missing"); get(d, l)|}
    "NA";

  test "col_lens supports bare symbol syntax"
    {|d = [a: 1, b: 2]; l = col_lens($a); get(d, l)|}
    "1";

  test "col_lens maps recursively over lists"
    {|items = [[a: 1], [a: 2]]; l = col_lens("a"); get(items, l)|}
    "[1, 2]";

  (* 2. col_lens on DataFrame *)
  test "col_lens over on DataFrame"
    {|df = dataframe([[x: 1, y: 3], [x: 2, y: 4]]); l = col_lens("x"); df2 = over(df, l, \(v) v .* 10); df2.x|}
    "Vector[10, 20]";

  test "col_lens set adds and recycles DataFrame column"
    {|df = dataframe([[x: 1], [x: 2], [x: 3]]); seed_values = select(dataframe([[seed: 10], [seed: 20]]), $seed); l = col_lens("y"); df2 = set(df, l, seed_values); df2.y|}
    "Vector[10, 20, 10]";

  test "col_lens set applies element-wise over lists"
    {|items = [[a: 1], [a: 2]]; l = col_lens("a"); updated = set(items, l, [10, 20]); get(updated, l)|}
    "[10, 20]";

  (* 3. Composition *)
  test "composed lens on nested Dict"
    {|d = [outer: [inner: 42]]; l = compose(col_lens("outer"), col_lens("inner")); over(d, l, \(x) x + 1)|}
    {|{`outer`: {`inner`: 43}}|};

  test "variadic composed lens (3 levels)"
    {|d = [a: [b: [c: 1]]]; l = compose(col_lens("a"), col_lens("b"), col_lens("c")); over(d, l, \(x) x + 9)|}
    {|{`a`: {`b`: {`c`: 10}}}|};

  (* 4. Modify (Variadic) *)
  test "modify with multiple lenses"
    {|d = [a: 1, b: 2]; l1 = col_lens("a"); l2 = col_lens("b"); modify(d, l1, \(x) x + 10, l2, \(x) x * 10)|}
    {|{`a`: 11, `b`: 20}|};

  test "modify on DataFrame"
    {|df = dataframe([[x: 1, y: 3], [x: 2, y: 4]]); lx = col_lens("x"); ly = col_lens("y"); df2 = modify(df, lx, \(v) v .+ 1, ly, \(v) v .* 2); [df2.x, df2.y]|}
    "[Vector[2, 3], Vector[6, 8]]";

  (* 5. Pipeline Lenses *)
  test "node_lens on Pipeline"
    {|p = pipeline { a = 1; b = 2 }; l = node_lens("a"); p2 = set(p, l, 10); p2.a|}
    "10";

  test "node_lens get missing node returns NA"
    {|p = pipeline { a = 1 }; get(p, node_lens("b"))|}
    "NA";

  test "node_lens set adds missing pipeline node"
    {|p = pipeline { a = 1 }; p2 = set(p, node_lens("b"), 2); get(p2, node_lens("b"))|}
    "2";

  test "node_meta_lens get runtime"
    {|p = pipeline { a = node(command = <{ 1 }>, runtime = R) }; get(p, node_meta_lens("a", "runtime"))|}
    {|"R"|};

  test "node_meta_lens set noop"
    {|p = pipeline { a = 1 }; p2 = set(p, node_meta_lens("a", "noop"), true); get(p2, node_meta_lens("a", "noop"))|}
    "true";

  test "node_meta_lens get unknown field returns NA"
    {|p = pipeline { a = 1 }; get(p, node_meta_lens("a", "missing"))|}
    "NA";

  test "env_var_lens on Pipeline"
    {|p = pipeline { a = node(command = <{ 1 }>, runtime = R, env_vars = [DEBUG: "false"]) }; l = env_var_lens("a", "DEBUG"); p2 = set(p, l, "true"); get(p2, l)|}
    {|"true"|};

  test "env_var_lens set creates missing env var"
    {|p = pipeline { a = 1 }; l = env_var_lens("a", "DEBUG"); p2 = set(p, l, "true"); get(p2, l)|}
    {|"true"|};

  (* 6. Library Extensions *)
  test "idx_lens on List"
    {|v = [10, 20, 30]; l = idx_lens(1); set(v, l, 99)|}
    "[10, 99, 30]";

  test "idx_lens on Vector (manual call)"
    {|v = select(dataframe([[a: 1, b: 2], [a: 3, b: 4]]), $a); l = idx_lens(0); set(v, l, 5)|}
    "Vector[5, 3]";

  test "idx_lens get out of bounds"
    {|v = [10, 20, 30]; get(v, idx_lens(5))|}
    {|Error(IndexError: "Index 5 is out of bounds for List of length 3.")|};

  test "row_lens on DataFrame"
    {|df = dataframe([[x: 1, y: 3], [x: 2, y: 4]]); l = row_lens(0); set(df, l, [x: 10, y: 20]).x|}
    "Vector[10, 2]";

  test "row_lens set adds missing columns and fills unspecified values with NA"
    {|df = dataframe([[x: 1, y: 3], [x: 2, y: 4]]); df2 = set(df, row_lens(0), [x: 10, z: 99]); updated_row = get(df2, row_lens(0)); [updated_row.x, updated_row.y, updated_row.z]|}
    "[10, NA, 99]";

  test "filter_lens on List"
    {|v = [1, 2, 3, 4]; l = filter_lens(\(x) x > 2); set(v, l, 0)|}
    "[1, 2, 0, 0]";

  test "filter_lens on DataFrame"
    {|df = dataframe([[x: 1, y: 10], [x: 2, y: 20], [x: 3, y: 30]]); l = filter_lens(\(r) r.x > 1); set(df, l, [x: 0, y: 0]).y|}
    "Vector[10, 0, 0]";

  test "filter_lens get on Pipeline metadata"
    {|p = pipeline { a = 1; b = node(command = <{ 2 }>, runtime = R) }; length(get(p, filter_lens(\(meta) meta.runtime == "R")))|}
    "1";

  test "filter_lens set with Vector replacement"
    {|df = dataframe([a: [1, 2, 3, 4]]); v = pull(df, "a"); replacement_values = pull(dataframe([a: [20, 30]]), "a"); set(v, filter_lens(\(x) x > 2), replacement_values)|}
    "Vector[1, 2, 20, 30]";

  test "filter_lens set with DataFrame replacement"
    {|df = dataframe([[x: 1, y: 10], [x: 2, y: 20], [x: 3, y: 30]]); replacement_rows = dataframe([[x: 20, y: 200], [x: 30, y: 300]]); df2 = set(df, filter_lens(\(r) r.x > 1), replacement_rows); df2.y|}
    "Vector[10, 200, 300]";

  test "filter_lens set on Pipeline"
    {|p = pipeline { a = 1; b = node(command = <{ 2 }>, runtime = R) }; l = filter_lens(\(meta) meta.runtime == "R"); p2 = set(p, l, 99); get(p2, node_lens("b"))|}
    "99";

  (* 7. Additional filter_lens coverage *)
  test "filter_lens over on List"
    {|v = [1, 2, 3, 4]; l = filter_lens(\(x) x > 2); over(v, l, \(x) x * 10)|}
    "[1, 2, 30, 40]";

  test "compose(filter_lens, col_lens) on DataFrame"
    {|df = dataframe([[x: 1, y: 10], [x: 2, y: 20], [x: 3, y: 30]]); lf = filter_lens(\(r) r.x > 1); ly = col_lens("y"); l = compose(lf, ly); df2 = over(df, l, \(v) v .* 2); df2.y|}
    "Vector[10, 40, 60]";

  test "filter_lens predicate must return Bool"
    {|v = [1, 2, 3]; l = filter_lens(\(x) x); get(v, l)|}
    {|Error(TypeError: "filter_lens predicate must return Bool, got Int")|};

  test "filter_lens preserves predicate errors"
    {|v = [1, 2, 3]; l = filter_lens(\(x) error("ValueError", "boom")); get(v, l)|}
    {|Error(ValueError: "boom")|};

  test "filter_lens list replacement length mismatch"
    {|v = [1, 2, 3, 4]; l = filter_lens(\(x) x > 2); set(v, l, [10])|}
    {|Error(TypeError: "filter_lens set on List: replacement has 1 elements but 2 were matched")|};

  test "filter_lens vector replacement length mismatch"
    {|df = dataframe([a: [1, 2, 3, 4]]); v = pull(df, "a"); repl = pull(dataframe([a: [10]]), "a"); set(v, filter_lens(\(x) x > 2), repl)|}
    {|Error(TypeError: "filter_lens set on Vector: replacement has 1 elements but 2 were matched")|};

  test "filter_lens dataframe replacement length mismatch"
    {|df = dataframe([[x: 1], [x: 2], [x: 3]]); repl = dataframe([[x: 10]]); set(df, filter_lens(\(r) r.x > 1), repl)|}
    {|Error(TypeError: "filter_lens set on DataFrame: replacement has 1 rows but 2 were matched")|};

  test "filter_lens rejects non-collections"
    {|set(1, filter_lens(\(x) true), 0)|}
    {|Error(TypeError: "filter_lens set expects a Collection, got Int")|};

  test "node_meta_lens rejects invalid runtime type"
    {|p = pipeline { a = 1 }; set(p, node_meta_lens("a", "runtime"), 1)|}
    {|Error(TypeError: "runtime must be a String")|};

  test "node_meta_lens rejects unknown field updates"
    {|p = pipeline { a = 1 }; set(p, node_meta_lens("a", "missing"), 1)|}
    {|Error(TypeError: "Unknown node metadata field: missing")|};

  test "compose rejects non-lenses"
    {|compose(col_lens("a"), 1)|}
    {|Error(TypeError: "compose expects Lenses")|};

  test "modify requires lens/function pairs"
    {|modify([a: 1], col_lens("a"))|}
    {|Error(TypeError: "modify expects (data, lens1, func1, lens2, func2, ...)")|};

  test "package_info lens functions"
    {|length(package_info("lens").functions)|}
    "12";

  (* 8. Regression Tests (Avoid core get/sym overrides/missing) *)
  test "regression: core get(string) lookup"
    {|my_var = 100; get("my_var")|}
    "100";

  test "regression: core sym(string)"
    {|type(sym("hello"))|}
    {|"Symbol"|};

  test "regression: get(list, index) fallback"
    {|lst = [10, 20, 30]; get(lst, 1)|}
    "20";

  test "regression: get(pipeline, node) lookup"
    {|p = pipeline { a = 123 }; get(p, "a")|}
    "123";

  print_newline ()
