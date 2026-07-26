let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Phase 1 — Stats Model Accessors:\n";

  let env = Packages.init_env () in
  let (_, env) = eval_string_env {|df = to_dataframe([x: [1, 2, 3, 4, 5], z: [3, 1, 4, 2, 5], y: [2, 4, 5, 4, 5]])|} env in
  let (_, env) = eval_string_env {|m1 = lm(data = df, formula = y ~ x)|} env in
  let (_, env) = eval_string_env {|m2 = lm(data = df, formula = y ~ x + z)|} env in
  test_env env "coef returns DataFrame with term and estimate columns"
    "colnames(coef(m1))"
    {|["term", "estimate"]|};
  test_env env "coef has 2 rows (intercept + slope)"
    "nrow(coef(m1))"
    "2";
  test_env env "coef rejects string"
    {|coef("hello")|}
    {|Error(TypeError: "Function `coef` expects a model returned by `lm` or `glm`.")|};
  test_env env "coef rejects plain dict without model keys"
    "coef([a: 1])"
    {|Error(TypeError: "Function `coef` expects a model with tidy coefficients.")|};
  test_env env "coef rejects extra positional arg"
    "coef(m1, m2)"
    {|Error(ArityError: "Function `coef` expects 1 arguments but received 2.")|};
  print_newline ();

  Printf.printf "  conf_int():\n";
  test_env env "conf_int returns DataFrame with term lower upper columns"
    "colnames(conf_int(m1))"
    {|["term", "lower", "upper"]|};
  test_env env "conf_int has 2 rows"
    "nrow(conf_int(m1))"
    "2";
  test_env env "conf_int with custom level"
    "nrow(conf_int(m1, 0.99))"
    "2";
  test_env env "conf_int rejects level out of range"
    "conf_int(m1, 1.5)"
    {|Error(TypeError: "Function `conf_int` level must be between 0 and 1 (e.g. 0.95).")|};
  test_env env "conf_int rejects non-model"
    {|conf_int("hello")|}
    {|Error(TypeError: "Function `conf_int` expects model or (model, level).")|};
  print_newline ();

  Printf.printf "  anova():\n";
  test_env env "anova returns DataFrame comparing two models"
    "type(anova(m1, m2))"
    "DataFrame";
  test_env env "anova has 2 rows for 2 models"
    "nrow(anova(m1, m2))"
    "2";
  test_env env "anova has correct columns"
    "colnames(anova(m1, m2))"
    {|["model", "df_residual", "deviance", "delta_df", "delta_deviance", "statistic", "p_value"]|};
  test_env env "anova rejects single model"
    "anova(m1)"
    {|Error(ValueError: "Function `anova` requires at least two models to compare.")|};
  test_env env "anova rejects non-model arguments"
    "anova(1, 2, 3)"
    {|Error(ValueError: "Function `anova` requires at least two models to compare.")|};
  print_newline ();

  Printf.printf "  wald_test():\n";
  test_env env "wald_test returns DataFrame with 1 row"
    "nrow(wald_test(model = m1, terms = [\"x\"]))"
    "1";
  test_env env "wald_test has statistic and p_value columns"
    "colnames(wald_test(model = m1, terms = [\"x\"]))"
    {|["terms", "statistic", "df", "p_value", "test_type"]|};
  test_env env "wald_test rejects nonexistent terms"
    "wald_test(model = m1, terms = [\"nonexistent\"])"
    {|Error(ValueError: "wald_test: some terms not found in model coefficients.")|};
  test_env env "wald_test rejects empty terms list"
    "wald_test(model = m1, terms = [])"
    {|Error(ValueError: "wald_test: 'terms' must be a list of coefficient names.")|};
  test_env env "wald_test works with positional model arg"
    "nrow(wald_test(m1, terms = [\"x\"]))"
    "1";
  test_env env "wald_test rejects non-model first arg"
    "wald_test(\"hello\", terms = [\"x\"])"
    {|Error(TypeError: "Function `wald_test` expects (Model, terms: List[String]).")|};
  print_newline ();
  print_newline ()
