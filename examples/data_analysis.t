-- examples/data_analysis.t
-- End-to-end data analysis example for T alpha
-- Demonstrates: read_csv, filter, select, mutate, arrange, group_by, summarize

print("=== T Data Analysis Example ===")
print("")

-- Step 1: Load data
print("Step 1: Loading data...")
df = read_csv("examples/sample_data.csv")
print("Loaded:")
print(df)
print("")

-- Step 2: Inspect the data
print("Step 2: Data inspection")
print("Rows:")
print(nrow(df))
print("Columns:")
print(ncol(df))
print("Column names:")
print(colnames(df))
print("")

-- Step 3: Filter rows
print("Step 3: Filter employees older than 28")
older = df |> filter(\(row) row.age > 28)
print("Filtered rows:")
print(nrow(older))
print("")

-- Step 4: Select columns
print("Step 4: Select name and score")
subset = older |> select("name", "score")
print(subset)
print("")

-- Step 5: Sort by score
print("Step 5: Sort by score descending")
sorted = older |> arrange("score", "desc")
print("Top scorer:")
print(head(sorted.name))
print("")

-- Step 6: Add computed column
print("Step 6: Add bonus column")
with_bonus = df |> mutate("bonus", \(row) row.score * 10)
print(with_bonus)
print("")

-- Step 7: Group and summarize
print("Step 7: Group by department and count")
dept_counts = df
  |> group_by("dept")
  |> summarize("count", \(g) nrow(g))
print(dept_counts)
print("")

-- Step 8: Statistics
print("Step 8: Score statistics")
print("Mean score:")
print(mean(df.score))
print("Std dev:")
print(sd(df.score))
print("Median:")
print(quantile(df.score, 0.5))
print("")

print("=== Analysis Complete ===")
