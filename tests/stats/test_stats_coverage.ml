let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Stats coverage boosters:\n";

  Printf.printf "  Basis + distribution helpers:\n";
  test "cut with integer breaks returns vector"
    "type(cut([1, 2, 3, 4], 2))"
    {|"Vector"|};
  test "cut with explicit breaks preserves length"
    "length(cut([1, 2, 3, 4], [0.0, 2.0, 4.0]))"
    "4";
  test "cut rejects NA input"
    "cut([1, NA, 3], 2)"
    {|Error(TypeError: "Function `cut` expects a numeric vector/list without NAs.")|};
  test "poly returns requested number of terms"
    "length(poly([1, 2, 3], 3))"
    "3";
  test "poly rejects non integer degree"
    "poly([1, 2, 3], 1.5)"
    {|Error(TypeError: "Function `poly` expects a numeric Vector/List and an integer Degree.")|};
  test "pnorm at zero"
    "pnorm(0) > 0.49 && pnorm(0) < 0.51"
    "true";
  test "pt at zero"
    "pt(0, 5) > 0.49 && pt(0, 5) < 0.51"
    "true";
  test "pf at unity"
    "pf(1, 1, 1) > 0.49 && pf(1, 1, 1) < 0.51"
    "true";
  test "pchisq at zero"
    "pchisq(0, 2) < 0.0001"
    "true";
  print_newline ();

  Printf.printf "  Model comparison + diagnostics:\n";
  test "compare returns dataframe for variadic models"
    {|df = dataframe([
        [x: 1, z: 2, y: 4],
        [x: 2, z: 1, y: 5],
        [x: 3, z: 0, y: 6],
        [x: 4, z: 1, y: 9]
      ]);
      m1 = lm(data = df, formula = y ~ x);
      m2 = lm(data = df, formula = y ~ x + z);
      type(compare(m1, m2))|}
    {|"DataFrame"|};
  test "compare supports list input"
    {|df = dataframe([
        [x: 1, z: 2, y: 4],
        [x: 2, z: 1, y: 5],
        [x: 3, z: 0, y: 6],
        [x: 4, z: 1, y: 9]
      ]);
      m1 = lm(data = df, formula = y ~ x);
      m2 = lm(data = df, formula = y ~ x + z);
      colnames(compare([m1, m2]))|}
    {|["term", "estimate_1", "std_error_1", "statistic_1", "p_value_1", "estimate_2", "std_error_2", "statistic_2", "p_value_2"]|};
  test "compare rejects models without tidy tables"
    {|compare([name: "broken"])|}
    {|Error(TypeError: "Model broken has no tidy coefficient table.")|};
  test "score returns core regression metrics"
    {|df = dataframe([
        [x: 1, z: 2, y: 4],
        [x: 2, z: 1, y: 5],
        [x: 3, z: 0, y: 6],
        [x: 4, z: 1, y: 9]
      ]);
      model = lm(data = df, formula = y ~ x + z);
      colnames(score(df, model))|}
    {|["rmse", "mae", "r2"]|};
  test "score includes log_loss for binomial-style models"
    {|df = dataframe([
        [x: -2, y: 0],
        [x: -1, y: 0],
        [x: 1, y: 1],
        [x: 2, y: 1]
      ]);
      model = [coefficients: [x: 2.0], formula: y ~ x, _model_data: [family: "binomial"], link: "logit"];
      colnames(score(df, model))|}
    {|["rmse", "mae", "r2", "log_loss"]|};
  test "residuals support pearson type"
    {|df = dataframe([
        [x: 1, z: 2, y: 4],
        [x: 2, z: 1, y: 5],
        [x: 3, z: 0, y: 6],
        [x: 4, z: 1, y: 9]
      ]);
      model = lm(data = df, formula = y ~ x + z);
      nrow(residuals(df, model, type = "pearson"))|}
    "4";
  test "augment adds standardized residuals"
    {|df = dataframe([
        [x: 1, z: 2, y: 4],
        [x: 2, z: 1, y: 5],
        [x: 3, z: 0, y: 6],
        [x: 4, z: 1, y: 9]
      ]);
      model = lm(data = df, formula = y ~ x + z);
      colnames(augment(df, model))|}
    {|["x", "z", "y", "fitted", "resid", "std_resid"]|};
  test "predict supports named data/model arguments"
    {|df = dataframe([x: [1, 2, 3, 4]]);
      predict(data = df, model = [coefficients: [x: 2.0]])|}
    {|Vector[2., 4., 6., 8.]|};
  test "predict surfaces forest model shape errors"
    {|df = dataframe([x: [1]]);
      predict(df, [model_type: "random_forest"])|}
    {|Error(TypeError: "Function `predict` expects a forest model with a `forest` field.")|};
  test "sigma rejects dispersion-only models"
    {|sigma([dispersion: 1.2])|}
    {|Error(TypeError: "Function `sigma` not applicable for this model. Use `dispersion()` instead.")|};
  test "dispersion rejects sigma-only models"
    {|dispersion([sigma: 1.2])|}
    {|Error(TypeError: "Function `dispersion` not applicable for this model. Use `sigma()` instead.")|};
  test "df_residual coerces float payloads"
    "df_residual([df_residual: 3.7])"
    "3";
  test "nobs coerces float payloads"
    "nobs([nobs: 5.9])"
    "5";
  test "deviance extracts float payloads"
    "deviance([deviance: 12.34])"
    "12.34";
  test "vcov falls back to diagonal matrix from std errors"
    {|tidy = dataframe([
        [term: "a", std_error: 2],
        [term: "b", std_error: 3]
      ]);
      vcov([_tidy_df: tidy]).a|}
    {|Vector[4., 0.]|};
  print_newline ();

  Printf.printf "  Scalar statistics edge cases:\n";
  test "max handles dataframe vector columns"
    {|df = dataframe([x: [1, 2, 3]]); max(df.x)|}
    "3.";
  test "min handles dataframe vector columns"
    {|df = dataframe([x: [1, 2, 3]]); min(df.x)|}
    "1.";
  test "cov rejects unequal lengths"
    "cov([1, 2], [1])"
    {|Error(ValueError: "Function `cov` requires vectors of equal length.")|};
  test "cov rejects single paired observation"
    "cov([1], [2])"
    {|Error(ValueError: "Function `cov` requires at least 2 paired values.")|};
  test "standardize rejects zero variance"
    "standardize([1, 1, 1])"
    {|Error(ValueError: "Function `standardize` undefined for zero-variance data.")|};
  test "scale rejects zero variance"
    "scale([1, 1, 1])"
    {|Error(ValueError: "Function `scale` undefined for zero-variance data.")|};
  test "cv rejects zero mean"
    "cv([-1, 1])"
    {|Error(ValueError: "Function `cv` undefined when mean is zero.")|};
  test "skewness returns zero for constant data"
    "skewness([2, 2, 2])"
    "0.";
  test "kurtosis returns minus three for constant data"
    "kurtosis([2, 2, 2, 2])"
    "-3.";
  test "median returns NA after removing all missing values"
    "median([NA], na_rm = true)"
    "NA(Float)";
  test "var rejects single value"
    "var([1])"
    {|Error(ValueError: "Function `var` requires at least 2 values.")|};
  test "trimmed_mean returns NA on empty data"
    "trimmed_mean([], 0.25)"
    "NA(Float)";
  test "trimmed_mean rejects non numeric trim"
    {|trimmed_mean([1, 2, 3], "x")|}
    {|Error(TypeError: "Function `trimmed_mean` expects (x, trim) where trim is numeric.")|};
  test "range returns NA after removing all missing values"
    "range([NA], na_rm = true)"
    "NA(Float)";
  test "iqr returns NA after removing all missing values"
    "iqr([NA], na_rm = true)"
    "NA(Float)";
  test "winsorize accepts two-sided limits"
    "length(winsorize([1, 2, 3, 4], [0.25, 0.0]))"
    "4";
  test "huber_loss rejects non numeric values in lists"
    {|huber_loss([1, "a"], 1)|}
    {|Error(TypeError: "Function `huber_loss` requires numeric values.")|};
  test "huber_loss rejects non positive delta"
    "huber_loss(1, 0)"
    {|Error(ValueError: "Function `huber_loss` expects positive delta.")|};
  print_newline ();

  Printf.printf "  PMML helper errors:\n";
  test "t_read_pmml rejects non string input"
    "t_read_pmml(1)"
    {|Error(TypeError: "t_read_pmml expects a single String argument.")|};
  test "t_read_pmml surfaces file errors"
    {|t_read_pmml("/definitely/not/a/real/model.pmml")|}
    {|Error(FileError: "PMML Parse Error:.*")|};
  test "t_score_pmml requires a source-backed PMML model"
    {|df = dataframe([x: [1]]);
      t_score_pmml(df, [model_type: "random_forest"])|}
    {|Error(RuntimeError: "Function `predict` (PMML): model does not have an attached source PMML path. Native T PMML export is not yet implemented for JPMML-backed scoring.")|};
  test "compare_native_vs_pmml_scores requires PMML source metadata"
    {|df = dataframe([x: [1]]);
      compare_native_vs_pmml_scores(df, [model_type: "random_forest"])|}
    {|Error(ValueError: "compare_native_vs_pmml_scores: Model does not have a PMML source path.")|};
  print_newline ()
