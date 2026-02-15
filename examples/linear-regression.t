-- Linear Regression using Linear Algebra
-- Demonstrates: read_csv -> select -> to_matrix -> math

print("=== Linear Regression Demo ===")

-- 1. Read data
print("Reading data...")
print("Reading data...")
url = "https://raw.githubusercontent.com/b-rodrigues/rixpress_demos/refs/heads/master/r_python_quarto/data/mtcars.csv"
data_initial = read_csv(url, separator = "|")

local_path = "tests/golden/data/mtcars.csv"
data = if (type(data_initial) == "Error") (read_csv(local_path, separator = ",")) else data_initial

    -- 2. Prepare Target Vector (y)
print("Preparing y...")
y_vec = pull(data, "mpg")
n = length(y_vec)
-- Convert to n x 1 matrix
y = ndarray(y_vec, shape=[n, 1])

-- 3. Prepare Design Matrix (X)
print("Preparing X...")
-- Select predictors and convert to matrix
X_raw = data 
  |> select("hp", "disp", "drat") 
  |> to_array()

-- Create intercept column (column of 1s) using iota
-- iota(n) returns a Vector of 1.0s
intercept_vec = iota(n)
intercept = ndarray(intercept_vec, shape=[n, 1])

-- Bind intercept to X_raw
X = cbind(intercept, X_raw)
p = get(shape(X), 1) -- number of parameters

print("Dimensions of X:")
print(shape(X))

-- 4. Compute Coefficients: Beta = (X'X)^-1 X'y
print("Computing coefficients...")
Xt = transpose(X)
XtX = matmul(Xt, X)
XtX_inv = inv(XtX)
Xty = matmul(Xt, y)
beta = matmul(XtX_inv, Xty)

print("Coefficients (Manual):")
print(beta)

-- 5. Standard Errors
print("Computing statistics...")
y_hat = matmul(X, beta)

-- Compute residuals: y - y_hat
-- Note: Element-wise subtraction for NDArrays is supported
residuals = y - y_hat 

-- Residual Sum of Squares (RSS)
-- Flatten residuals to compute sum of squares
res_data = ndarray_data(residuals)
ss_res = sum(map(res_data, \(r) -> r * r))

-- Residual Variance (sigma^2)
sigma2 = ss_res / (n - p)

-- Covariance Matrix of Beta
cov_beta = XtX_inv * sigma2

-- Extract Standard Errors
-- Use diag to extract diagonal elements (variance), then sqrt
var_beta = diag(cov_beta)
std_errs_vec = sqrt(var_beta)
-- Convert to list/vector for printing if needed, or print directly
std_errs = ndarray_data(std_errs_vec)

print("Standard Errors (Manual):")
print(std_errs)

-- R-Squared
y_data = ndarray_data(y)
y_mean = mean(y_data)
ss_tot = sum(map(y_data, \(val) -> pow(val - y_mean, 2.0)))
r_squared = 1.0 - (ss_res / ss_tot)

print("R-Squared (Manual):")
print(r_squared)

-- 6. Compare with lm()
print("\n--- Comparing with lm() ---")
model = lm(data = data, formula = mpg ~ hp + disp + drat)

print("LM Coefficients:")
print(model.coefficients)

print("LM Standard Errors:")
print(model.std_errors)

print("LM R-Squared:")
print(model.r_squared)

print("=== Done ===")
