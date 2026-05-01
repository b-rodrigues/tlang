#!/usr/bin/env Rscript

# Generate expected statistical outputs
# Linear models, correlations, etc.

library(dplyr)
library(readr)
library(broom)  # For tidy model outputs

data_dir <- "tests/golden/data"
output_dir <- "tests/golden/expected"

message("Generating expected statistical outputs...\n")

mtcars <- read_csv(file.path(data_dir, "mtcars.csv"), show_col_types = FALSE)

# ============================================================================
# Test Suite 8: LINEAR MODELS
# ============================================================================
message("=== LINEAR MODEL Tests ===")

# Test 8.1: Simple linear regression (mpg ~ hp) - coefficients
# Extract just intercept and slope for direct comparison with T's lm()
lm_mpg_hp <- lm(mpg ~ hp, data = mtcars)
lm_mpg_hp_coefficients <- tibble(
  intercept = coef(lm_mpg_hp)[1],
  slope = coef(lm_mpg_hp)[2]
)
write_csv(lm_mpg_hp_coefficients, file.path(output_dir, "lm_mpg_hp_coefficients.csv"))
message("✓ lm(mpg ~ hp) coefficients")

# Save model stats (full R stats)
lm_mpg_hp_stats <- tibble(
  r_squared = summary(lm_mpg_hp)$r.squared,
  adj_r_squared = summary(lm_mpg_hp)$adj.r.squared,
  sigma = summary(lm_mpg_hp)$sigma,
  df = summary(lm_mpg_hp)$df[2]
)
write_csv(lm_mpg_hp_stats, file.path(output_dir, "lm_mpg_hp_stats.csv"))
message("✓ lm(mpg ~ hp) statistics")

# Test 8.1b: Simple linear regression - T-compatible format
# T's lm() returns intercept, slope, r_squared
lm_mpg_hp_simple <- tibble(
  intercept = coef(lm_mpg_hp)[1],
  slope = coef(lm_mpg_hp)[2],
  r_squared = summary(lm_mpg_hp)$r.squared
)
write_csv(lm_mpg_hp_simple, file.path(output_dir, "lm_mpg_hp_simple.csv"))
message("✓ lm(mpg ~ hp) simple stats (T-compatible)")

# Test 8.2: Multiple regression (mpg ~ hp + wt)
lm_mpg_multi <- lm(mpg ~ hp + wt, data = mtcars)
lm_mpg_multi_tidy <- tidy(lm_mpg_multi)
write_csv(lm_mpg_multi_tidy, 
          file.path(output_dir, "lm_mpg_hp_wt_coefficients.csv"))
message("✓ lm(mpg ~ hp + wt) coefficients")

# Test 8.3: Linear model on iris (Sepal.Length ~ Petal.Length)
iris <- read_csv(file.path(data_dir, "iris.csv"), show_col_types = FALSE)
lm_iris <- lm(Sepal.Length ~ Petal.Length, data = iris)
lm_iris_tidy <- tidy(lm_iris)
write_csv(lm_iris_tidy, 
          file.path(output_dir, "lm_iris_sepal_petal_coefficients.csv"))
message("✓ lm(Sepal.Length ~ Petal.Length) coefficients")

# ============================================================================
# Test Suite 9: CORRELATIONS
# ============================================================================
message("\n=== CORRELATION Tests ===")

# Test 9.1: Simple correlation
cor_mpg_hp <- tibble(
  correlation = cor(mtcars$mpg, mtcars$hp)
)
write_csv(cor_mpg_hp, file.path(output_dir, "cor_mpg_hp.csv"))
message("✓ cor(mpg, hp)")

# Test 9.2: Correlation matrix
cor_matrix <- mtcars %>%
  select(mpg, hp, wt, qsec) %>%
  cor() %>%
  as.data.frame() %>%
  tibble::rownames_to_column("var1") %>%
  tidyr::pivot_longer(-var1, names_to = "var2", values_to = "correlation")
write_csv(cor_matrix, file.path(output_dir, "cor_matrix_mtcars.csv"))
message("✓ Correlation matrix (mpg, hp, wt, qsec)")

# Test 9.3: Correlation on iris
cor_iris <- tibble(
  correlation = cor(iris$Sepal.Length, iris$Petal.Length)
)
write_csv(cor_iris, file.path(output_dir, "cor_iris_sepal_petal.csv"))
message("✓ cor(Sepal.Length, Petal.Length)")

# ============================================================================
# Test Suite 10: DESCRIPTIVE STATISTICS
# ============================================================================
message("\n=== DESCRIPTIVE STATS Tests ===")

# Test 10.1: Summary statistics
summary_stats <- mtcars %>%
  summarize(
    mean_mpg = mean(mpg),
    sd_mpg = sd(mpg),
    median_mpg = median(mpg),
    min_mpg = min(mpg),
    max_mpg = max(mpg),
    q25_mpg = quantile(mpg, 0.25),
    q75_mpg = quantile(mpg, 0.75)
  )
write_csv(summary_stats, file.path(output_dir, "summary_stats_mpg.csv"))
message("✓ Summary statistics for mpg")

# Test 10.2: Quantiles
quantiles <- tibble(
  quantile = c(0, 0.25, 0.50, 0.75, 1.0),
  value = quantile(mtcars$mpg, c(0, 0.25, 0.50, 0.75, 1.0))
)
write_csv(quantiles, file.path(output_dir, "quantiles_mpg.csv"))
message("✓ Quantiles for mpg")

# Test Suite 11: Extended descriptive functions
message("\n=== EXTENDED STATS Tests ===")

extended_stats <- tibble(
  median_1_2_10 = median(c(1, 2, 10)),
  var_1_to_5 = var(c(1, 2, 3, 4, 5)),
  cov_linear = cov(c(1, 2, 3), c(2, 4, 6)),
  iqr_1_to_5 = IQR(c(1, 2, 3, 4, 5)),
  round_pi_2 = round(pi, 2)
)
write_csv(extended_stats, file.path(output_dir, "extended_stats_basics.csv"))
message("✓ Extended stats baseline set")

skewness_manual <- function(x) {
  m <- mean(x)
  m2 <- mean((x - m)^2)
  if (m2 == 0) {
    return(0)
  }
  m3 <- mean((x - m)^3)
  m3 / (m2^(1.5))
}

kurtosis_manual <- function(x) {
  m <- mean(x)
  m2 <- mean((x - m)^2)
  if (m2 == 0) {
    return(-3)
  }
  m4 <- mean((x - m)^4)
  (m4 / (m2^2)) - 3
}

mode_manual <- function(x) {
  ux <- unique(x)
  ux[which.max(tabulate(match(x, ux)))]
}

shape_mode_stats <- tibble(
  sepal_length_skewness = skewness_manual(iris$Sepal.Length),
  petal_length_kurtosis = kurtosis_manual(iris$Petal.Length),
  skewness_na_rm = skewness_manual(c(1, 2, 3, 4)),
  kurtosis_na_rm = kurtosis_manual(c(1, 2, 3, 4, 5)),
  mode_numeric = mode_manual(c(1, 2, 2, 3, 3, 3, 4))
)
write_csv(shape_mode_stats, file.path(output_dir, "stats_shape_mode_baselines.csv"))
message("✓ skewness(), kurtosis(), and mode() baselines")

standardize_scale_iris <- tibble(
  Sepal.Length = iris$Sepal.Length,
  standardized = as.numeric(scale(iris$Sepal.Length)),
  scaled = as.numeric(scale(iris$Sepal.Length))
)
write_csv(standardize_scale_iris, file.path(output_dir, "stats_standardize_scale_iris.csv"))
message("✓ standardize() and scale() parity")

# ============================================================================
# Test Suite 12: ADVANCED STATS (vcov, residuals, augment, anova)
# ============================================================================
message("\n=== ADVANCED STATS Tests ===")

# Model 1: mpg ~ wt
m1 = lm(mpg ~ wt, data = mtcars)

# Model 2: mpg ~ wt + hp + qsec
m2 = lm(mpg ~ wt + hp + qsec, data = mtcars)

# 12.1: vcov matrix
write_csv(as_tibble(vcov(m1), rownames = "term"), file.path(output_dir, "lm_vcov_m1.csv"))
write_csv(as_tibble(vcov(m2), rownames = "term"), file.path(output_dir, "lm_vcov_m2.csv"))
message("✓ vcov matrix")

# 12.2: residuals
res_m1 = tibble(
  response = residuals(m1, type = "response"),
  pearson = residuals(m1, type = "pearson")
)
write_csv(res_m1, file.path(output_dir, "lm_residuals_m1.csv"))
message("✓ residuals (response & pearson)")

# 12.3: augment
# T's augment returns fitted, resid, std_resid
# R's augment includes more, we just need parity on the core ones
aug_m1 = augment(m1) %>%
  select(actual = mpg, fitted = .fitted, resid = .resid)
write_csv(aug_m1, file.path(output_dir, "lm_augment_m1.csv"))
message("✓ augment core columns")

# 12.4: anova
av = anova(m1, m2)
# T returns model, df_residual, deviance, delta_df, delta_deviance, statistic, p_value
av_tidy = tibble(
  model = c("m1", "m2"),
  df_residual = av$Res.Df,
  deviance = av$RSS,
  delta_df = c(NA, -diff(av$Res.Df)),
  delta_deviance = c(NA, -diff(av$RSS)),
  statistic = c(NA, av$F[2]),
  p_value = c(NA, av$`Pr(>F)`[2])
)
write_csv(av_tidy, file.path(output_dir, "lm_anova_m1_m2.csv"))
message("✓ anova table")

# 12.5: wald_test parity (for hp and qsec in m2)
# In OLS/F-test context, this is equivalent to comparing with m1 (which only has wt)
# but wait, m2 has wt, hp, qsec. m1 has wt. 
# So comparing m2 with m1 tests hp=0 and qsec=0 jointly.
wh = anova(m1, m2)
wh_tidy = tibble(
  terms = "hp, qsec",
  statistic = wh$F[2],
  df = wh$Df[2],
  p_value = wh$`Pr(>F)`[2],
  test_type = "F"
)
write_csv(wh_tidy, file.path(output_dir, "lm_wald_hp_qsec.csv"))
message("✓ wald_test parity")

# 12.6: coef, conf_int, and model accessors
m3 = lm(mpg ~ hp + wt, data = mtcars)
coef_m3 = tidy(m3) %>%
  select(term, estimate)
write_csv(coef_m3, file.path(output_dir, "lm_coef_mpg_hp_wt.csv"))

conf_int_m3 = confint(m3) %>%
  as.data.frame() %>%
  tibble::rownames_to_column("term") %>%
  rename(lower = `2.5 %`, upper = `97.5 %`)
write_csv(conf_int_m3, file.path(output_dir, "lm_conf_int_mpg_hp_wt.csv"))

conf_int99_m3 = confint(m3, level = 0.99) %>%
  as.data.frame() %>%
  tibble::rownames_to_column("term") %>%
  rename(lower = `0.5 %`, upper = `99.5 %`)
write_csv(conf_int99_m3, file.path(output_dir, "lm_conf_int99_mpg_hp_wt.csv"))

model_accessors_m3 = tibble(
  sigma = sigma(m3),
  nobs = nobs(m3),
  df_residual = df.residual(m3)
)
write_csv(model_accessors_m3, file.path(output_dir, "lm_model_accessors_mpg_hp_wt.csv"))
message("✓ coef(), conf_int(), sigma(), nobs(), and df_residual()")

# ============================================================================
# Test Suite 13: DISTRIBUTIONS
# ============================================================================
message("\n=== DISTRIBUTION Tests ===")

dist_tests <- tibble(
  pnorm_1 = pnorm(1.0),
  pnorm_196 = pnorm(1.96),
  pt_2_10 = pt(2.0, df = 10),
  pf_3_2_30 = pf(3.0, df1 = 2, df2 = 30),
  pchisq_384_1 = pchisq(3.84, df = 1)
)
write_csv(dist_tests, file.path(output_dir, "dist_baselines.csv"))
message("✓ Distribution functions")

message("\n✅ All statistical outputs generated!")
