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

weighted_quantile_midpoint <- function(x, w, p) {
  keep <- w > 0
  x <- x[keep]
  w <- w[keep]
  if (length(x) == 0) {
    return(NA_real_)
  }
  ord <- order(x)
  x <- x[ord]
  w <- w[ord]
  q_points <- (cumsum(w) - 0.5 * w) / sum(w)
  if (length(x) == 1) {
    return(x[[1]])
  }
  if (p <= q_points[[1]]) {
    return(x[[1]])
  }
  if (p >= q_points[[length(q_points)]]) {
    return(x[[length(x)]])
  }
  for (i in seq_len(length(x) - 1)) {
    if (p <= q_points[[i + 1]]) {
      left_q <- q_points[[i]]
      right_q <- q_points[[i + 1]]
      if (right_q <= left_q) {
        return(x[[i + 1]])
      }
      frac <- (p - left_q) / (right_q - left_q)
      return(x[[i]] + frac * (x[[i + 1]] - x[[i]]))
    }
  }
  x[[length(x)]]
}

weighted_var_manual <- function(x, w) {
  mu <- weighted.mean(x, w)
  sum(w * (x - mu)^2) / sum(w)
}

weighted_cov_manual <- function(x, y, w) {
  mx <- weighted.mean(x, w)
  my <- weighted.mean(y, w)
  sum(w * (x - mx) * (y - my)) / sum(w)
}

weighted_skewness_manual <- function(x, w) {
  mu <- weighted.mean(x, w)
  m2 <- sum(w * (x - mu)^2) / sum(w)
  if (m2 == 0) {
    return(0)
  }
  m3 <- sum(w * (x - mu)^3) / sum(w)
  m3 / (m2^(1.5))
}

weighted_kurtosis_manual <- function(x, w) {
  mu <- weighted.mean(x, w)
  m2 <- sum(w * (x - mu)^2) / sum(w)
  if (m2 == 0) {
    return(-3)
  }
  m4 <- sum(w * (x - mu)^4) / sum(w)
  (m4 / (m2^2)) - 3
}

weighted_trimmed_mean_manual <- function(x, w, trim) {
  lo <- weighted_quantile_midpoint(x, w, trim)
  hi <- weighted_quantile_midpoint(x, w, 1 - trim)
  keep <- x >= lo & x <= hi & w > 0
  weighted.mean(x[keep], w[keep])
}

weighted_winsorize_manual <- function(x, w, limits) {
  lo <- weighted_quantile_midpoint(x, w, limits[[1]])
  hi <- weighted_quantile_midpoint(x, w, 1 - limits[[2]])
  pmin(pmax(x, lo), hi)
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

weighted_stats <- tibble(
  weighted_mean = weighted.mean(c(1, 2, 3, 4), c(1, 1, 2, 2)),
  weighted_sd = sqrt(weighted_var_manual(c(1, 2, 3, 4), c(1, 1, 2, 2))),
  weighted_var = weighted_var_manual(c(1, 2, 3, 4), c(1, 1, 2, 2)),
  weighted_median = weighted_quantile_midpoint(c(1, 2, 3, 4), c(1, 1, 2, 2), 0.5),
  weighted_quantile_75 = weighted_quantile_midpoint(c(1, 2, 3, 4), c(1, 1, 2, 2), 0.75),
  weighted_cov = weighted_cov_manual(c(1, 2, 3), c(2, 4, 9), c(1, 1, 4)),
  weighted_cor = weighted_cov_manual(c(1, 2, 3), c(2, 4, 9), c(1, 1, 4)) /
    sqrt(weighted_var_manual(c(1, 2, 3), c(1, 1, 4)) * weighted_var_manual(c(2, 4, 9), c(1, 1, 4))),
  weighted_cv = sqrt(weighted_var_manual(c(1, 2, 10), c(1, 1, 4))) / weighted.mean(c(1, 2, 10), c(1, 1, 4)),
  weighted_iqr = weighted_quantile_midpoint(c(1, 2, 3, 4), c(1, 1, 2, 2), 0.75) -
    weighted_quantile_midpoint(c(1, 2, 3, 4), c(1, 1, 2, 2), 0.25),
  weighted_fivenum_min = min(c(1, 2, 3, 4)),
  weighted_fivenum_q1 = weighted_quantile_midpoint(c(1, 2, 3, 4), c(1, 1, 2, 2), 0.25),
  weighted_fivenum_med = weighted_quantile_midpoint(c(1, 2, 3, 4), c(1, 1, 2, 2), 0.5),
  weighted_fivenum_q3 = weighted_quantile_midpoint(c(1, 2, 3, 4), c(1, 1, 2, 2), 0.75),
  weighted_fivenum_max = max(c(1, 2, 3, 4)),
  weighted_trimmed_mean = weighted_trimmed_mean_manual(c(1, 2, 3, 100), c(1, 1, 2, 2), 0.25),
  weighted_skewness = weighted_skewness_manual(c(1, 2, 10), c(1, 1, 4)),
  weighted_kurtosis = weighted_kurtosis_manual(c(1, 2, 10, 10), c(1, 1, 3, 3)),
  winsor_1 = weighted_winsorize_manual(c(1, 2, 3, 100), c(1, 1, 2, 2), c(0.25, 0.25))[[1]],
  winsor_2 = weighted_winsorize_manual(c(1, 2, 3, 100), c(1, 1, 2, 2), c(0.25, 0.25))[[2]],
  winsor_3 = weighted_winsorize_manual(c(1, 2, 3, 100), c(1, 1, 2, 2), c(0.25, 0.25))[[3]],
  winsor_4 = weighted_winsorize_manual(c(1, 2, 3, 100), c(1, 1, 2, 2), c(0.25, 0.25))[[4]]
)
write_csv(weighted_stats, file.path(output_dir, "weighted_stats_baselines.csv"))
message("✓ weighted descriptive statistics baselines")

weighted_df <- tibble(
  x = c(1, 2, 3, 4),
  y = c(1, 2, 2, 4),
  w = c(1, 1, 2, 2)
)
weighted_lm <- lm(y ~ x, data = weighted_df, weights = w)
weighted_lm_stats <- tibble(
  intercept = coef(weighted_lm)[1],
  slope = coef(weighted_lm)[2],
  r_squared = summary(weighted_lm)$r.squared,
  sigma = summary(weighted_lm)$sigma
)
write_csv(weighted_lm_stats, file.path(output_dir, "weighted_lm_baselines.csv"))
message("✓ weighted lm baselines")

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

# Test Suite 14: SPECIALIZED STATS
message("\n=== SPECIALIZED STATS Tests ===")

cv_manual <- function(x) {
  sd(x) / mean(x)
}

# T's trimmed_mean floor(trim * n)
t_trimmed_mean <- function(x, trim) {
  x <- sort(x)
  n <- length(x)
  k <- floor(trim * n)
  if (k > 0) {
    x <- x[(k+1):(n-k)]
  }
  mean(x)
}

# T's fivenum uses type 7 quantiles
t_fivenum <- function(x) {
  c(min(x), quantile(x, 0.25, type = 7), median(x), quantile(x, 0.75, type = 7), max(x))
}

specialized_stats <- tibble(
  cv_mpg = cv_manual(mtcars$mpg),
  fivenum_min = t_fivenum(mtcars$mpg)[1],
  fivenum_q1 = t_fivenum(mtcars$mpg)[2],
  fivenum_med = t_fivenum(mtcars$mpg)[3],
  fivenum_q3 = t_fivenum(mtcars$mpg)[4],
  fivenum_max = t_fivenum(mtcars$mpg)[5],
  trimmed_mean_mpg_10 = t_trimmed_mean(mtcars$mpg, 0.1),
  mad_mpg = mad(mtcars$mpg), 
  iqr_mpg = quantile(mtcars$mpg, 0.75, type = 7) - quantile(mtcars$mpg, 0.25, type = 7),
  range_min = min(mtcars$mpg),
  range_max = max(mtcars$mpg),
  var_mpg = var(mtcars$mpg),
  cov_mpg_hp = cov(mtcars$mpg, mtcars$hp)
)
write_csv(specialized_stats, file.path(output_dir, "stats_specialized_baselines.csv"))
message("✓ specialized stats (cv, fivenum, trimmed_mean, mad, iqr, range, var, cov)")

# Advanced measures (skewness, kurtosis, winsorize, huber_loss, normalize, sd, quantile)
skewness_pop <- function(x) {
  n <- length(x)
  m <- mean(x)
  m2 <- sum((x - m)^2) / n
  m3 <- sum((x - m)^3) / n
  if (m2 == 0) return(0)
  m3 / (m2^1.5)
}

kurtosis_pop <- function(x) {
  n <- length(x)
  m <- mean(x)
  m2 <- sum((x - m)^2) / n
  m4 <- sum((x - m)^4) / n
  if (m2 == 0) return(-3)
  (m4 / (m2^2)) - 3
}

winsorize_r <- function(x, limits) {
  if (length(limits) == 1) limits <- c(limits, limits)
  lo <- limits[1]
  hi <- limits[2]
  qs <- quantile(x, probs = c(lo, 1 - hi), type = 7, names = FALSE)
  x[x < qs[1]] <- qs[1]
  x[x > qs[2]] <- qs[2]
  x
}

huber_loss_r <- function(x, delta) {
  ax <- abs(x)
  ifelse(ax <= delta, 0.5 * x^2, delta * (ax - 0.5 * delta))
}

normalize_r <- function(x) {
  mn <- min(x)
  mx <- max(x)
  (x - mn) / (mx - mn)
}

advanced_stats <- tibble(
  skew_mpg = skewness_pop(mtcars$mpg),
  kurt_mpg = kurtosis_pop(mtcars$mpg),
  sd_mpg = sd(mtcars$mpg),
  quantile_mpg_25 = quantile(mtcars$mpg, 0.25, type = 7, names = FALSE),
  quantile_mpg_75 = quantile(mtcars$mpg, 0.75, type = 7, names = FALSE)
)

write_csv(advanced_stats, file.path(output_dir, "stats_advanced_measures.csv"))
message("✓ advanced measures (skewness, kurtosis, sd, quantile)")

# Vectorized advanced measures
vector_advanced <- tibble(
  winsor_mpg_05 = winsorize_r(mtcars$mpg, 0.05),
  huber_mpg_2 = huber_loss_r(mtcars$mpg, 2),
  norm_mpg = normalize_r(mtcars$mpg)
)

write_csv(vector_advanced, file.path(output_dir, "stats_advanced_vectorized.csv"))
message("✓ vectorized advanced measures (winsorize, huber_loss, normalize)")

# Distributions and Correlation
dist_stats <- tibble(
  pnorm_0 = pnorm(0.0),
  pnorm_1 = pnorm(1.0),
  pnorm_neg1 = pnorm(-1.0),
  pt_2_10 = pt(2.0, 10),
  pf_3_5_20 = pf(3.0, 5, 20),
  pchisq_4_2 = pchisq(4.0, 2),
  cor_mpg_hp = cor(mtcars$mpg, mtcars$hp)
)

write_csv(dist_stats, file.path(output_dir, "stats_distributions_baselines.csv"))
message("✓ distributions and correlation (pnorm, pt, pf, pchisq, cor)")

message("\n✅ All statistical outputs generated!")
