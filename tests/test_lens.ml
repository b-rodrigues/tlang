
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

  (* 2. col_lens on DataFrame *)
  test "col_lens over on DataFrame"
    {|df = dataframe([[x: 1, y: 3], [x: 2, y: 4]]); l = col_lens("x"); df2 = over(df, l, \(v) v .* 10); df2.x|}
    "Vector[10, 20]";

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

  test "env_var_lens on Pipeline"
    {|p = pipeline { a = node(command = <{ 1 }>, runtime = R, env_vars = [DEBUG: "false"]) }; l = env_var_lens("a", "DEBUG"); p2 = set(p, l, "true"); get(p2, l)|}
    {|"true"|};

  (* 6. Library Extensions *)
  test "idx_lens on List"
    {|v = [10, 20, 30]; l = idx_lens(1); set(v, l, 99)|}
    "[10, 99, 30]";

  test "idx_lens on Vector (manual call)"
    {|v = select(dataframe([[a: 1, b: 2], [a: 3, b: 4]]), $a); l = idx_lens(0); set(v, l, 5)|}
    "Vector[5, 3]";

  test "row_lens on DataFrame"
    {|df = dataframe([[x: 1, y: 3], [x: 2, y: 4]]); l = row_lens(0); set(df, l, [x: 10, y: 20]).x|}
    "Vector[10, 2]";

  test "filter_lens on List"
    {|v = [1, 2, 3, 4]; l = filter_lens(\(x) x > 2); set(v, l, 0)|}
    "[1, 2, 0, 0]";

  test "filter_lens on DataFrame"
    {|df = dataframe([[x: 1, y: 10], [x: 2, y: 20], [x: 3, y: 30]]); l = filter_lens(\(r) r.x > 1); set(df, l, [x: 0, y: 0]).y|}
    "Vector[10, 0, 0]";

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
