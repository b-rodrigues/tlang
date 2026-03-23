-- examples/statistics_example.t
-- End-to-end statistics example for T alpha
-- Demonstrates: math functions, stats functions, linear regression

print("=== T Statistics Example ===")
print("")

-- Math functions
print("Step 1: Math functions")
print("sqrt(16) =")
print(sqrt(16))
print("abs(-42) =")
print(abs(0 - 42))
print("log(exp(1)) =")
print(log(exp(1)))
print("pow(2, 10) =")
print(pow(2, 10))
print("")

-- Statistics on a list
print("Step 2: Descriptive statistics")
data = [12, 15, 18, 22, 25, 28, 30, 35, 40, 45]
print("Data:")
print(data)
print("Mean:")
print(mean(data))
print("Standard deviation:")
print(sd(data))
print("Median (Q50):")
print(quantile(data, 0.5))
print("Q25:")
print(quantile(data, 0.25))
print("Q75:")
print(quantile(data, 0.75))
print("")

-- Correlation
print("Step 3: Correlation")
x = [1, 2, 3, 4, 5]
y = [2, 4, 6, 8, 10]
print("x:")
print(x)
print("y:")
print(y)
print("cor(x, y) =")
print(cor(x, y))
print("")

-- Linear regression
print("Step 4: Linear regression")
df = read_csv("examples/regression_data.csv")
model = lm(data = df, formula = y ~ x)
print("Model: y ~ x")
print("Slope:")
print(model.slope)
print("Intercept:")
print(model.intercept)
print("R-squared:")
print(model.r_squared)
print("Observations:")
print(model.n)
print("")

-- Pipe with math
print("Step 5: Pipes with math/stats")
result = [1, 4, 9, 16, 25]
  |> map(\(x) sqrt(x))
  |> mean
print("Mean of sqrt([1,4,9,16,25]) =")
print(result)
print("")

print("=== Statistics Example Complete ===")
