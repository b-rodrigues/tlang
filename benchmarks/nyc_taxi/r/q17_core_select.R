args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("usage: Rscript q17_core_select.R <materialized-parquet-path>", call. = FALSE)
}

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

started <- Sys.time()
input_path <- args[[1]]
frame <- read_parquet(input_path, as_data_frame = TRUE)

result <- frame |>
  select(VendorID, passenger_count, trip_distance, fare_amount, tip_amount, total_amount)

print(head(result, 10))
cat(sprintf("ROWS_SCANNED=%s\n", nrow(frame)))
cat(sprintf("ROWS_RETURNED=%s\n", nrow(result)))
cat(sprintf("ELAPSED_SEC=%.6f\n", as.numeric(difftime(Sys.time(), started, units = "secs"))))
