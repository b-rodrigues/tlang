args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("usage: Rscript q10_vendor_revenue_pivot.R <parquet-dataset-path>", call. = FALSE)
}

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

started <- Sys.time()
dataset_path <- args[[1]]
ds_tbl <- open_dataset(dataset_path, format = "parquet")

grouped <- ds_tbl |>
  group_by(year, month, VendorID) |>
  summarise(rev = sum(total_amount, na.rm = TRUE)) |>
  collect() |>
  mutate(vendor_label = ifelse(is.na(VendorID), "vendor_NA", paste0("vendor_", as.character(VendorID))))

result <- reshape(
  as.data.frame(grouped[, c("year", "month", "vendor_label", "rev")]),
  idvar = c("year", "month"),
  timevar = "vendor_label",
  direction = "wide"
)

print(head(result, 10))
cat("ROWS_SCANNED=NA\n")
cat(sprintf("ROWS_RETURNED=%s\n", nrow(result)))
cat(sprintf("ELAPSED_SEC=%.6f\n", as.numeric(difftime(Sys.time(), started, units = "secs"))))
