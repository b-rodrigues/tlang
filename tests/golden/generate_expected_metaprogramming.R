# tests/golden/generate_expected_metaprogramming.R
library(dplyr)
library(readr)
library(rlang)

data_dir <- "tests/golden/data"
expected_dir <- "tests/golden/expected"

if (!dir.exists(expected_dir)) dir.create(expected_dir, recursive = TRUE)

iris_data <- read_csv(file.path(data_dir, "iris.csv"), show_col_types = FALSE)

# 1. Basic Enquo Pattern
my_mutate <- function(df, col) {
  col_enq <- enquo(col)
  df %>% mutate(!!col_enq := !!col_enq + 10.0)
}

iris_mutated <- my_mutate(iris_data, Sepal.Length)
write_csv(iris_mutated, file.path(expected_dir, "metaprog_enquo_mutate.csv"))

# 2. Enquos Pattern
my_summarize <- function(df, ...) {
  cols <- enquos(...)
  df %>% summarize(!!!cols)
}

iris_summary <- my_summarize(iris_data, 
                             mean_Sepal.Length = mean(Sepal.Length), 
                             mean_Sepal.Width = mean(Sepal.Width))
write_csv(iris_summary, file.path(expected_dir, "metaprog_enquos_summarize.csv"))

# 3. Quasiquoted Expression Building
res_df <- iris_data %>% 
  summarize(val = (10 + 10 + 5)) %>% 
  head(1)

write_csv(res_df, file.path(expected_dir, "metaprog_expr_building.csv"))

# 4. Quos Pattern
multi_quos <- rlang::quos(a = 1 + 1, b = 2 + 2)
write_csv(iris_data %>% head(1) %>% mutate(!!!multi_quos), file.path(expected_dir, "metaprog_quos.csv"))

# 5. Dynamic Name in Mutate
new_name <- "Sepal.Large"
res_dyn <- iris_data %>% head(1) %>% mutate(!!new_name := Sepal.Length >= 5.1)
# Convert booleans to lowercase for T compatibility
res_dyn[[new_name]] <- ifelse(res_dyn[[new_name]], "true", "false")
write_csv(res_dyn, file.path(expected_dir, "metaprog_dyn_name.csv"))
