# Logical Operators Comparison

# Scalar Logic
cat("Scalar AND:\n")
print(TRUE && FALSE)
cat("Scalar OR:\n")
print(TRUE || FALSE)
cat("Scalar !:\n")
print(!TRUE)

# Vector Logic (Broadcasting)
v1 <- c(TRUE, FALSE, TRUE, FALSE)
v2 <- c(TRUE, TRUE, FALSE, FALSE)

cat("Vector AND:\n")
print(v1 & v2)
cat("Vector OR:\n")
print(v1 | v2)

# Mixed Types (R allows, T might be strict or error)
# T is strict, so we won't test mismatched types unless expecting error.
