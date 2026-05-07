-- Test: weighted descriptive statistics against R baselines
result = dataframe([
  weighted_mean: mean([1, 2, 3, 4], weights = [1, 1, 2, 2]),
  weighted_sd: sd([1, 2, 3, 4], weights = [1, 1, 2, 2]),
  weighted_var: var([1, 2, 3, 4], weights = [1, 1, 2, 2]),
  weighted_median: median([1, 2, 3, 4], weights = [1, 1, 2, 2]),
  weighted_quantile_75: quantile([1, 2, 3, 4], 0.75, weights = [1, 1, 2, 2]),
  weighted_cov: cov([1, 2, 3], [2, 4, 9], weights = [1, 1, 4]),
  weighted_cor: cor([1, 2, 3], [2, 4, 9], weights = [1, 1, 4]),
  weighted_cv: cv([1, 2, 10], weights = [1, 1, 4]),
  weighted_iqr: iqr([1, 2, 3, 4], weights = [1, 1, 2, 2]),
  weighted_fivenum_min: get(fivenum([1, 2, 3, 4], weights = [1, 1, 2, 2]), 0),
  weighted_fivenum_q1: get(fivenum([1, 2, 3, 4], weights = [1, 1, 2, 2]), 1),
  weighted_fivenum_med: get(fivenum([1, 2, 3, 4], weights = [1, 1, 2, 2]), 2),
  weighted_fivenum_q3: get(fivenum([1, 2, 3, 4], weights = [1, 1, 2, 2]), 3),
  weighted_fivenum_max: get(fivenum([1, 2, 3, 4], weights = [1, 1, 2, 2]), 4),
  weighted_trimmed_mean: trimmed_mean([1, 2, 3, 100], 0.25, weights = [1, 1, 2, 2]),
  weighted_skewness: skewness([1, 2, 10], weights = [1, 1, 4]),
  weighted_kurtosis: kurtosis([1, 2, 10, 10], weights = [1, 1, 3, 3]),
  winsor_1: get(winsorize([1, 2, 3, 100], 0.25, weights = [1, 1, 2, 2]), 0),
  winsor_2: get(winsorize([1, 2, 3, 100], 0.25, weights = [1, 1, 2, 2]), 1),
  winsor_3: get(winsorize([1, 2, 3, 100], 0.25, weights = [1, 1, 2, 2]), 2),
  winsor_4: get(winsorize([1, 2, 3, 100], 0.25, weights = [1, 1, 2, 2]), 3)
])

write_csv(result, "tests/golden/t_outputs/weighted_stats_baselines.csv")
print("✓ weighted stats baselines complete")
