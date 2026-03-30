#!/usr/bin/env Rscript
library(dplyr)
library(readr)
library(lightgbm)
library(r2pmml)

base_dir <- getwd()
data_dir <- file.path(base_dir, "tests", "golden", "data")
expected_dir <- file.path(base_dir, "tests", "golden", "expected")

iris_df <- read_csv(file.path(data_dir, "iris.csv"))
# LightGBM likes clean names
iris_df <- iris_df %>% rename_all(~tolower(gsub("\\.", "_", .)))
iris_train <- iris_df %>% filter(species != "virginica")
iris_train$species <- as.integer(iris_train$species == "setosa")

# LightGBM (binary classification)
lgb_clf <- lightgbm(
  data = as.matrix(iris_train %>% select(-species)),
  label = iris_train$species,
  obj = "binary",
  nrounds = 10,
  verbose = -1,
  params = list(max_depth = 3, learning_rate = 0.1, min_data_in_leaf = 1, min_data_in_bin = 1)
)

r2pmml(lgb_clf, file.path(data_dir, "iris_lgb_bin.pmml"))

# Predictions
iris_preds <- predict(lgb_clf, as.matrix(iris_df %>% select(-species)))
write_csv(data.frame(pred = as.integer(iris_preds > 0.5)), file.path(expected_dir, "iris_lgb_bin_predictions.csv"))

# LightGBM (regression)
mtcars_df <- read_csv(file.path(data_dir, "mtcars.csv")) %>% select_if(is.numeric)
mtcars_df <- mtcars_df %>% rename_all(~tolower(gsub("\\.", "_", .)))
mtcars_y <- mtcars_df$mpg
mtcars_x <- mtcars_df %>% select(-mpg)

lgb_reg <- lightgbm(
  data = as.matrix(mtcars_x),
  label = mtcars_y,
  obj = "regression",
  nrounds = 20,
  verbose = -1,
  params = list(max_depth = 3, learning_rate = 0.1, min_data_in_leaf = 1, min_data_in_bin = 1)
)

r2pmml(lgb_reg, file.path(data_dir, "mtcars_lgb_reg.pmml"))

# Predictions
mtcars_preds <- predict(lgb_reg, as.matrix(mtcars_x))
write_csv(data.frame(pred = mtcars_preds), file.path(expected_dir, "mtcars_lgb_reg_predictions.csv"))
