args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("usage: Rscript q11_heavy_summarize.R <parquet-dataset-path>", call. = FALSE)
}

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

started <- Sys.time()
dataset_path <- args[[1]]
ds_tbl <- open_dataset(dataset_path, format = "parquet")

result <- ds_tbl |>
  filter(!is.na(trip_distance)) |>
  group_by(VendorID) |>
  summarise(
    mean_fare = mean(fare_amount, na.rm = TRUE),
    mean_tip = mean(tip_amount, na.rm = TRUE),
    total_rev = sum(total_amount, na.rm = TRUE),
    max_dist = max(trip_distance, na.rm = TRUE),
    min_dist = min(trip_distance, na.rm = TRUE),
    total_passengers = sum(passenger_count, na.rm = TRUE),
    trips = n(),
    unique_locs = n_distinct(PULocationID)
  ) |>
  collect()

print(head(result, 10))
cat("ROWS_SCANNED=NA\n")
cat(sprintf("ROWS_RETURNED=%s\n", nrow(result)))
cat(sprintf("ELAPSED_SEC=%.6f\n", as.numeric(difftime(Sys.time(), started, units = "secs"))))
