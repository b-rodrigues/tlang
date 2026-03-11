args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("usage: Rscript q12_multi_stage_rollup.R <parquet-dataset-path>", call. = FALSE)
}

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

started <- Sys.time()
dataset_path <- args[[1]]
ds_tbl <- open_dataset(dataset_path, format = "parquet")

result <- ds_tbl |>
  filter(!is.na(trip_distance), !is.na(fare_amount), trip_distance > 0, total_amount > 0) |>
  mutate(
    fare_per_mile = fare_amount / trip_distance,
    tip_percent = (tip_amount / total_amount) * 100
  ) |>
  group_by(year, month, VendorID, payment_type) |>
  summarise(
    avg_fare_per_mile = mean(fare_per_mile, na.rm = TRUE),
    avg_tip_percent = mean(tip_percent, na.rm = TRUE),
    total_revenue = sum(total_amount, na.rm = TRUE),
    max_trip_distance = max(trip_distance, na.rm = TRUE),
    rides = n(),
    unique_pickups = n_distinct(PULocationID)
  ) |>
  arrange(desc(total_revenue)) |>
  collect()

print(head(result, 10))
cat("ROWS_SCANNED=NA\n")
cat(sprintf("ROWS_RETURNED=%s\n", nrow(result)))
cat(sprintf("ELAPSED_SEC=%.6f\n", as.numeric(difftime(Sys.time(), started, units = "secs"))))
