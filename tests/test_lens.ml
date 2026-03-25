
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
    {|d = [a: 1, b: 2]; l = col_lens("a"); l.get(d)|}
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
    {|p = pipeline { a = node(command = <{ 1 }>, runtime = R, env_vars = [DEBUG: "false"]) }; l = env_var_lens("a", "DEBUG"); p2 = set(p, l, "true"); l.get(p2)|}
    {|"true"|};

  print_newline ()
