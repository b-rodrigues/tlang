library(arrow, warn.conflicts = FALSE)
library(dplyr, warn.conflicts = FALSE)
library(tidyr, warn.conflicts = FALSE)

args <- commandArgs(trailingOnly = TRUE)
parquet_dir <- args[1]

start_time <- Sys.time()
ds <- open_dataset(parquet_dir, partitioning = "hive")

df <- ds %>% collect()

# q20: nest and unnest
# This tests the tidyr/dplyr infrastructure for handling nested lists of dataframes.
result <- df %>%
  group_by(VendorID) %>%
  nest() %>%
  unnest(data)

end_time <- Sys.time()

print(head(result, 10))
cat("ROWS_SCANNED=NA\n")
cat(paste0("ROWS_RETURNED=", nrow(result), "\n"))
cat(paste0("ELAPSED_SEC=", as.numeric(end_time - start_time, units = "secs"), "\n"))
