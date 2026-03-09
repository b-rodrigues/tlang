args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("usage: Rscript q1_long_trips.R <parquet-dataset-path>", call. = FALSE)
}

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

started <- Sys.time()
dataset_path <- args[[1]]
ds_tbl <- open_dataset(dataset_path, format = "parquet")
rows_scanned <- ds_tbl |> summarise(rows = n()) |> collect() |> pull(rows)

result <- ds_tbl |>
  filter(trip_distance > 10) |>
  summarise(avg_fare = mean(fare_amount, na.rm = TRUE), trips = n()) |>
  collect()

print(result)
cat(sprintf("ROWS_SCANNED=%s\n", rows_scanned))
cat(sprintf("ROWS_RETURNED=%s\n", nrow(result)))
cat(sprintf("ELAPSED_SEC=%.6f\n", as.numeric(difftime(Sys.time(), started, units = "secs"))))
