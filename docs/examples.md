# Comprehensive Examples

Real-world examples demonstrating T's capabilities for data analysis and manipulation.

## Table of Contents

- [Basic Data Analysis](#basic-data-analysis)
- [Data Cleaning](#data-cleaning)
- [Statistical Analysis](#statistical-analysis)
- [Group Operations](#group-operations)
- [Window Functions](#window-functions)
- [Reproducible Pipelines](#reproducible-pipelines)
- [Error Handling Patterns](#error-handling-patterns)
- [LLM Collaboration](#llm-collaboration)

---

## Basic Data Analysis

### Loading and Inspecting Data

```t
-- Load customer data
customers = read_csv("customers.csv", clean_colnames = true)

-- Inspect structure
nrow(customers)        -- 1000
ncol(customers)        -- 5
colnames(customers)    -- ["name", "age", "city", "purchases", "active"]

-- View sample
head(customers.age, 10)
```

### Basic Statistics

```t
-- Summary statistics
mean_age = mean(customers.age, na_rm = true)
sd_age = sd(customers.age, na_rm = true)
median_purchases = quantile(customers.purchases, 0.5, na_rm = true)

print("Average age: " + string(mean_age))
print("Age SD: " + string(sd_age))
print("Median purchases: " + string(median_purchases))

-- Distribution analysis
q25 = quantile(customers.purchases, 0.25, na_rm = true)
q75 = quantile(customers.purchases, 0.75, na_rm = true)
iqr = q75 - q25

print("IQR: " + string(iqr))
```

### Simple Filtering and Selection

```t
-- Active customers only
active = customers |> filter($active == true)

-- High-value customers
high_value = customers 
  |> filter($purchases > 100)
  |> select($name, $purchases)

-- Age groups
young = customers |> filter($age < 30)
mature = customers |> filter($age >= 30 and $age < 50)
senior = customers |> filter($age >= 50)

print("Young customers: " + string(nrow(young)))
print("Mature customers: " + string(nrow(mature)))
print("Senior customers: " + string(nrow(senior)))
```

---

## Data Cleaning

### Handling Missing Values

```t
-- Check for NA
sales = read_csv("sales.csv")

-- Count NA per column
na_count_revenue = length(filter(sales.revenue, \(x) is_na(x)))
na_count_cost = length(filter(sales.cost, \(x) is_na(x)))

print("NA in revenue: " + string(na_count_revenue))
print("NA in cost: " + string(na_count_cost))

-- Remove rows with any NA
clean = sales |> filter(\(row) 
  not is_na(row.revenue) and not is_na(row.cost)
)

-- Or use na_rm in calculations
total_revenue = sum(sales.revenue, na_rm = true)
avg_revenue = mean(sales.revenue, na_rm = true)
```

### Column Name Cleaning

```t
-- Messy column names
raw = read_csv("messy_data.csv")
colnames(raw)
-- ["Product ID", "Sales (€)", "Growth%", "2023 Total"]

-- Clean names
clean = read_csv("messy_data.csv", clean_colnames = true)
colnames(clean)
-- ["product_id", "sales_euro", "growth_percent", "x_2023_total"]

-- Now accessible with dot notation
avg_sales = mean(clean.sales_euro, na_rm = true)
```

### Data Type Conversions

```t
-- Assuming string to number conversion functions exist
-- (In T, types are inferred from CSV, but you can transform)

-- Create derived columns with correct types
data = data |> mutate("price_num", \(row) parse_float(row.price_str))

-- Boolean flags
data = data |> mutate("is_premium", \(row) row.price > 100)

-- Categorical to numeric
data = data |> mutate("region_code", \(row) 
  if (row.region == "North") 1
  else if (row.region == "South") 2
  else if (row.region == "East") 3
  else 4
)
```

### Outlier Detection and Removal

```t
-- Calculate bounds
values = df.salary
q25 = quantile(values, 0.25, na_rm = true)
q75 = quantile(values, 0.75, na_rm = true)
iqr = q75 - q25
lower_bound = q25 - 1.5 * iqr
upper_bound = q75 + 1.5 * iqr

-- Remove outliers
cleaned = df |> filter(\(row) 
  row.salary >= lower_bound and row.salary <= upper_bound
)

print("Original rows: " + string(nrow(df)))
print("After outlier removal: " + string(nrow(cleaned)))
```

---

## Statistical Analysis

### Correlation Analysis

```t
-- Load data
economics = read_csv("economics.csv")

-- Compute correlation
cor_gdp_unemployment = cor(
  economics.gdp, 
  economics.unemployment_rate,
  na_rm = true
)

print("GDP vs Unemployment: r = " + string(cor_gdp_unemployment))

-- Multiple correlations
cor_consumption_income = cor(economics.consumption, economics.income, na_rm = true)
cor_savings_income = cor(economics.savings, economics.income, na_rm = true)

print("Consumption vs Income: r = " + string(cor_consumption_income))
print("Savings vs Income: r = " + string(cor_savings_income))
```

### Linear Regression

```t
-- Simple regression
advertising = read_csv("advertising.csv")

model = lm(
  data = advertising,
  formula = sales ~ ad_spend
)

-- Inspect model
print("Slope: " + string(model.slope))
print("Intercept: " + string(model.intercept))
print("R²: " + string(model.r_squared))
print("N: " + string(model.n))

-- Manual prediction
predict = \(x) model.intercept + model.slope * x
predicted_sales = predict(5000)

print("Predicted sales for $5000 ad spend: " + string(predicted_sales))
```

### Hypothesis Testing (Manual t-test example)

```t
-- Compare two groups
group_a = df |> filter(\(row) row.treatment == "A") |> \(d) d.outcome
group_b = df |> filter(\(row) row.treatment == "B") |> \(d) d.outcome

-- Calculate means and SDs
mean_a = mean(group_a, na_rm = true)
mean_b = mean(group_b, na_rm = true)
sd_a = sd(group_a, na_rm = true)
sd_b = sd(group_b, na_rm = true)

-- Effect size (Cohen's d)
pooled_sd = sqrt((sd_a * sd_a + sd_b * sd_b) / 2)
cohens_d = (mean_a - mean_b) / pooled_sd

print("Group A mean: " + string(mean_a))
print("Group B mean: " + string(mean_b))
print("Cohen's d: " + string(cohens_d))
```

---

## Group Operations

### Basic Grouping and Aggregation

```t
sales = read_csv("sales_data.csv")

-- Group by region, count rows (using $col = expr syntax)
by_region = sales
  |> group_by($region)
  |> summarize($count = nrow($region))

print(by_region)

-- Multiple aggregations
by_product = sales
  |> group_by($product)
  |> summarize($total_revenue = sum($revenue))
  
by_product = by_product
  |> mutate($avg_price = $total_revenue / $count)
```

### Grouped Statistics

```t
employees = read_csv("employees.csv")

-- Average salary by department
dept_stats = employees
  |> group_by($department)
  |> summarize($avg_salary = mean($salary))

-- Multiple groups
regional_dept_stats = employees
  |> group_by($region, $department)
  |> summarize($avg_salary = mean($salary))
  |> arrange($avg_salary, "desc")

print(regional_dept_stats)
```

### Grouped Mutations (Broadcast)

```t
-- Add department size to each row
employees_with_size = employees
  |> group_by($department)
  |> mutate($dept_size, \(g) nrow(g))

-- Add group mean to each row
employees_with_avg = employees
  |> group_by($department)
  |> mutate($dept_avg_salary, \(g) mean(g.salary, na_rm = true))
  
-- Calculate z-score within group
employees_normalized = employees_with_avg
  |> group_by($department)
  |> mutate($salary_z, \(g) 
      (g.salary - mean(g.salary, na_rm = true)) / sd(g.salary, na_rm = true)
    )
```

---

## Window Functions

### Ranking

```t
-- Load sales data
sales = read_csv("sales.csv")

-- Add row numbers
sales_ranked = sales
  |> mutate("row_num", \(row) row_number(sales.revenue))

-- Rank by revenue
sales_ranked = sales_ranked
  |> mutate("revenue_rank", \(row) min_rank(sales.revenue))
  |> arrange("revenue_rank")

-- Dense rank (no gaps)
sales_ranked = sales_ranked
  |> mutate("dense_revenue_rank", \(row) dense_rank(sales.revenue))

-- Percentiles
sales_ranked = sales_ranked
  |> mutate("percentile", \(row) percent_rank(sales.revenue))

print(sales_ranked)
```

### Offset Functions (lag/lead)

```t
-- Time series data
ts = read_csv("time_series.csv")

-- Previous value
ts_with_lag = ts
  |> mutate("prev_value", \(row) lag(ts.value))

-- Next value
ts_with_lead = ts
  |> mutate("next_value", \(row) lead(ts.value))

-- Calculate change
ts_with_change = ts_with_lag
  |> mutate("change", \(row) row.value - row.prev_value)

-- Multi-period lag
ts_with_lag2 = ts
  |> mutate("value_2_periods_ago", \(row) lag(ts.value, 2))
```

### Cumulative Functions

```t
-- Daily sales
daily = read_csv("daily_sales.csv")

-- Cumulative sum
daily_cumsum = daily
  |> mutate("cumulative_sales", \(row) cumsum(daily.sales))

-- Running average
daily_cumavg = daily
  |> mutate("running_avg", \(row) cummean(daily.sales))

-- Cumulative max
daily_cummax = daily
  |> mutate("peak_so_far", \(row) cummax(daily.sales))

-- Cumulative min
daily_cummin = daily
  |> mutate("lowest_so_far", \(row) cummin(daily.sales))

print(daily_cumsum)
```

---

## Reproducible Pipelines

### Data Analysis Pipeline

```t
intent {
  description: "Customer lifetime value analysis",
  assumes: "Data from 2023-01-01 to 2023-12-31",
  requires: "All monetary values in USD"
}

analysis = pipeline {
  -- Load raw data
  raw = read_csv("transactions.csv", clean_colnames = true)
  
  -- Clean data
  cleaned = raw
    |> filter(not is_na($amount) and $amount > 0)
    |> filter($date >= "2023-01-01" and $date <= "2023-12-31")
  
  -- Customer aggregations
  customer_stats = cleaned
    |> group_by($customer_id)
    |> summarize($total_spend = sum($amount))
    |> summarize($purchase_count = nrow($customer_id))
    |> mutate($avg_order_value = $total_spend / $purchase_count)
  
  -- Segment customers
  segments = customer_stats
    |> mutate($segment, \(row)
        if (row.total_spend > 1000) "high_value"
        else if (row.total_spend > 500) "medium_value"
        else "low_value"
      )
  
  -- Summary by segment
  segment_summary = segments
    |> group_by($segment)
    |> summarize($customer_count = nrow($segment), $avg_ltv = mean($total_spend))
    |> arrange($avg_ltv, "desc")
}

-- Access results
print(analysis.segment_summary)
write_csv(analysis.segments, "customer_segments.csv")
```

### Multi-Source Pipeline

```t
etl = pipeline {
  -- Load multiple sources
  sales = read_csv("sales.csv")
  customers = read_csv("customers.csv")
  products = read_csv("products.csv")
  
  -- Clean each source
  sales_clean = sales |> filter($amount > 0)
  
  -- Aggregate sales by customer
  customer_sales = sales_clean
    |> group_by($customer_id)
    |> summarize($total_sales = sum($amount))
  
  -- Combine with customer data (manual join via filter/map)
  -- (Assuming a join function exists or using manual matching)
  
  -- Final report
  report = customer_sales
    |> arrange($total_sales, "desc")
}

write_csv(etl.report, "sales_report.csv")
```

---

## Error Handling Patterns

### Defensive Programming

```t
-- Check for empty data
df = read_csv("data.csv")

safe_mean = if (nrow(df) == 0)
  error("ValueError", "Empty dataset")
else
  mean(df.value, na_rm = true)

-- Handle errors in pipeline
result = safe_mean ?|> \(x)
  if (is_error(x)) {
    print("Error: " + error_message(x))
    0.0  -- Default value
  } else {
    x
  }
```

### Validation Pipeline

```t
validate = pipeline {
  raw = read_csv("input.csv")
  
  -- Validation checks
  check_rows = if (nrow(raw) == 0)
    error("ValidationError", "No data found")
  else
    raw
  
  check_columns = if (ncol(check_rows) < 3)
    error("ValidationError", "Insufficient columns")
  else
    check_rows
  
  check_values = check_columns |> filter(\(row)
    not is_na(row.value) and row.value > 0
  )
  
  -- If validation passes, proceed
  processed = if (nrow(check_values) > 100)
    check_values
  else
    error("ValidationError", "Too few valid rows")
}

-- Use maybe-pipe for error recovery
final = validate.processed ?|> \(x)
  if (is_error(x)) {
    print("Validation failed: " + error_message(x))
    -- Return empty placeholder or default
    null
  } else {
    x
  }
```

### Graceful Degradation

```t
-- Try to load data, fall back if fails
data = read_csv("primary.csv") ?|> \(x)
  if (is_error(x)) {
    print("Primary source failed, trying backup...")
    read_csv("backup.csv")
  } else {
    x
  }

-- Chain multiple fallbacks
robust_load = read_csv("source1.csv")
  ?|> \(x) if (is_error(x)) read_csv("source2.csv") else x
  ?|> \(x) if (is_error(x)) read_csv("source3.csv") else x
  ?|> \(x) if (is_error(x)) error("AllSourcesFailed", "No data available") else x
```

---

## LLM Collaboration

### Intent-Driven Analysis

```t
intent {
  description: "Identify revenue drivers for Q4 2023",
  goal: "Determine which product categories drive revenue growth",
  assumes: "Complete sales data for Q4 2023",
  constraints: "Exclude returns and refunds",
  success_criteria: "R² > 0.7 for predictive model",
  stakeholder: "Product team"
}

-- Analysis follows intent
q4_sales = read_csv("q4_2023_sales.csv")

analysis = pipeline {
  clean = q4_sales
    |> filter(\(row) row.type != "return" and row.type != "refund")
  
  by_category = clean
    |> group_by("category")
    |> summarize("total_revenue", \(g) sum(g.revenue))
    |> arrange("total_revenue", "desc")
  
  top_categories = by_category
    |> filter(\(row) row.total_revenue > 10000)
}

print(analysis.top_categories)
```

### Structured Collaboration

```t
intent {
  task: "customer_segmentation",
  description: "Segment customers by behavior for targeted marketing",
  
  inputs: {
    data_source: "customers.csv",
    date_range: "2023-01-01 to 2023-12-31",
    required_fields: ["customer_id", "purchase_frequency", "total_spend"]
  },
  
  methodology: "RFM analysis (Recency, Frequency, Monetary)",
  
  outputs: {
    segments: ["champions", "loyal", "at_risk", "churned"],
    format: "CSV with segment labels"
  },
  
  validation: {
    min_customers_per_segment: 50,
    total_customers_check: "should match input count"
  }
}

-- LLM generates implementation following intent structure
-- (This serves as a contract for regeneration)
```

### Audit Trail

```t
-- Intent blocks create audit trail for LLM-assisted work
intent {
  version: "1.0",
  author: "Data Team",
  llm_assistant: "GPT-4",
  created: "2024-01-15",
  last_modified: "2024-01-20",
  
  change_log: [
    {date: "2024-01-15", change: "Initial implementation"},
    {date: "2024-01-18", change: "Added NA handling"},
    {date: "2024-01-20", change: "Optimized grouping logic"}
  ],
  
  human_review: true,
  human_reviewer: "Alice Smith",
  review_date: "2024-01-21"
}

-- Rest of analysis...
```

---

## Complete Example: Sales Dashboard Data Prep

```t
-- Complete workflow: load, clean, analyze, export

intent {
  description: "Prepare sales data for dashboard",
  frequency: "Daily",
  outputs: ["summary_stats.csv", "top_products.csv", "regional_breakdown.csv"]
}

dashboard_prep = pipeline {
  -- 1. Load data
  raw_sales = read_csv("daily_sales.csv", clean_colnames = true)
  
  -- 2. Data quality
  clean_sales = raw_sales
    |> filter(not is_na($revenue) and $revenue > 0)
    |> filter(not is_na($product_id))
  
  -- 3. Summary statistics
  summary = {
    total_revenue: sum(clean_sales.revenue),
    total_orders: nrow(clean_sales),
    avg_order_value: mean(clean_sales.revenue),
    median_order: quantile(clean_sales.revenue, 0.5)
  }
  
  -- 4. Top products
  top_products = clean_sales
    |> group_by($product_name)
    |> summarize($revenue = sum($revenue))
    |> arrange($revenue, "desc")
  
  -- 5. Regional breakdown
  by_region = clean_sales
    |> group_by($region)
    |> summarize($revenue = sum($revenue), $orders = nrow($region))
    |> mutate($avg_order_value = $revenue / $orders)
    |> arrange($revenue, "desc")
}

-- Export results
write_csv(dashboard_prep.top_products, "top_products.csv")
write_csv(dashboard_prep.by_region, "regional_breakdown.csv")

print("Dashboard data prepared successfully")
print("Total revenue: " + string(dashboard_prep.summary.total_revenue))
```

---

**See Also**:
- [API Reference](api-reference.md) — Function documentation
- [Data Manipulation](data_manipulation_examples.md) — More data verb examples
- [Pipeline Tutorial](pipeline_tutorial.md) — Detailed pipeline guide
