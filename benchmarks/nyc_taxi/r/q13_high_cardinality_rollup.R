args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("usage: Rscript q13_high_cardinality_rollup.R <parquet-dataset-path>", call. = FALSE)
}

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

started <- Sys.time()
dataset_path <- args[[1]]
ds_tbl <- open_dataset(dataset_path, format = "parquet")

result <- ds_tbl |>
  filter(!is.na(fare_amount), !is.na(tip_amount), total_amount > 0) |>
  group_by(VendorID, RatecodeID, PULocationID, DOLocationID) |>
  summarise(
    avg_fare = mean(fare_amount, na.rm = TRUE),
    avg_tip = mean(tip_amount, na.rm = TRUE),
    avg_total = mean(total_amount, na.rm = TRUE),
    total_tolls = sum(tolls_amount, na.rm = TRUE),
    trips = n(),
    max_passengers = max(passenger_count, na.rm = TRUE)
  ) |>
  arrange(desc(trips)) |>
  collect()

print(head(result, 10))
cat("ROWS_SCANNED=NA\n")
cat(sprintf("ROWS_RETURNED=%s\n", nrow(result)))
cat(sprintf("ELAPSED_SEC=%.6f\n", as.numeric(difftime(Sys.time(), started, units = "secs"))))
