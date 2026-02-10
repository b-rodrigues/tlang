# LLM Collaboration with T

How T enables structured, auditable collaboration between humans and Large Language Models for data analysis.

## The LLM Code Generation Problem

Current LLM-assisted coding suffers from:

- **Opaque Generation**: LLMs generate complete scripts without structure
- **Context Loss**: Assumptions and constraints are implicit
- **Brittle Regeneration**: Changing one requirement breaks everything
- **No Audit Trail**: Hard to verify what LLM understood
- **Global Changes**: LLMs rewrite entire files instead of localized edits

**Result**: LLM-generated code is useful for prototyping but hard to maintain, audit, or regenerate.

---

## T's LLM-Native Design

T treats LLMs as **first-class collaborators** with structured boundaries:

### Key Principles

1. **Intent over Implementation**: Humans specify goals, LLMs generate code
2. **Local over Global**: LLMs generate pipeline nodes, not entire scripts
3. **Inspectable over Opaque**: Intent blocks make assumptions explicit
4. **Regenerable over Brittle**: Stable boundaries enable safe code updates

---

## Intent Blocks

Intent blocks are **machine-readable metadata** that capture analytical goals.

### Basic Intent

```t
intent {
  description: "Analyze customer churn patterns by age group",
  goal: "Identify age ranges with highest churn risk"
}

-- Analysis code follows...
```

### Comprehensive Intent

```t
intent {
  -- High-level description
  description: "Customer lifetime value segmentation",
  goal: "Segment customers into value tiers for targeted marketing",
  
  -- Data specifications
  data_source: "customers.csv from CRM export 2023-12-31",
  required_columns: ["customer_id", "total_spend", "purchase_count", "signup_date"],
  
  -- Analytical assumptions
  assumptions: [
    "Churn defined as no purchase in 90 days",
    "LTV calculated as total_spend / months_active",
    "Test accounts excluded"
  ],
  
  -- Business constraints
  constraints: [
    "Minimum 50 customers per segment",
    "Segment labels: high_value, medium_value, low_value",
    "Thresholds: high > $1000, medium > $500"
  ],
  
  -- Data quality rules
  validation: [
    "total_spend > 0",
    "purchase_count > 0",
    "signup_date between 2020-01-01 and 2023-12-31"
  ],
  
  -- Expected outputs
  outputs: [
    "customer_segments.csv with columns: customer_id, segment, ltv",
    "segment_summary.csv with counts and average LTV per segment"
  ],
  
  -- Metadata
  created: "2024-01-15",
  author: "Marketing Team",
  llm_assistant: "GPT-4",
  version: "1.0"
}

-- LLM generates implementation based on intent
analysis = pipeline {
  raw = read_csv("customers.csv", clean_colnames = true)
  
  validated = raw
    |> filter(\(row) row.total_spend > 0)
    |> filter(\(row) row.purchase_count > 0)
  
  with_ltv = validated
    |> mutate("ltv", \(row) row.total_spend / months_since(row.signup_date))
  
  segmented = with_ltv
    |> mutate("segment", \(row)
        if (row.ltv > 1000) "high_value"
        else if (row.ltv > 500) "medium_value"
        else "low_value"
      )
  
  summary = segmented
    |> group_by("segment")
    |> summarize("count", \(g) nrow(g))
    |> summarize("avg_ltv", \(g) mean(g.ltv))
}

write_csv(analysis.segmented, "customer_segments.csv")
write_csv(analysis.summary, "segment_summary.csv")
```

**Benefits**:
- LLM understands exact requirements
- Human can verify LLM understood correctly
- Future LLMs can regenerate code from intent
- Intent serves as documentation
- Changes to intent are versioned (Git)

---

## Local Code Generation

Instead of generating entire scripts, LLMs generate **pipeline nodes**.

### Traditional LLM Workflow (Problematic)

**Human prompt**: "Analyze sales by region"

**LLM generates** (entire script):
```python
import pandas as pd

df = pd.read_csv("sales.csv")
df = df[df['amount'] > 0]
df_grouped = df.groupby('region')['amount'].sum()
df_grouped = df_grouped.sort_values(ascending=False)
print(df_grouped)
```

**Problems**:
- If requirements change, LLM rewrites everything
- No separation between data loading, cleaning, analysis
- Hard to modify one step without breaking others

### T LLM Workflow (Structured)

**Human writes intent**:
```t
intent {
  description: "Sales analysis by region",
  steps: {
    load: "Load sales.csv",
    clean: "Remove zero/negative amounts",
    analyze: "Sum revenue by region, sort descending"
  }
}
```

**LLM generates pipeline nodes**:
```t
analysis = pipeline {
  -- Node 1: Load (stable)
  raw = read_csv("sales.csv")
  
  -- Node 2: Clean (can regenerate independently)
  cleaned = raw |> filter(\(row) row.amount > 0)
  
  -- Node 3: Analyze (can regenerate independently)
  by_region = cleaned
    |> group_by("region")
    |> summarize("total", \(g) sum(g.amount))
    |> arrange("total", "desc")
}
```

**Benefits**:
- **Change request**: "Also filter by date"
  - LLM only regenerates `cleaned` node
  - `raw` and `by_region` unchanged
- **Local reasoning**: Each node is independently understandable
- **Cacheable**: Unchanged nodes don't re-execute

---

## LLM Workflow Patterns

### Pattern 1: Intent-Driven Generation

**Step 1**: Human writes intent
```t
intent {
  description: "Customer cohort analysis",
  cohort_definition: "First purchase month",
  metric: "Average order value by cohort",
  timeframe: "2023-01-01 to 2023-12-31"
}
```

**Step 2**: LLM generates implementation
```t
cohort_analysis = pipeline {
  orders = read_csv("orders.csv")
  -- LLM fills in details based on intent
}
```

**Step 3**: Human reviews, provides feedback
```
"Include only completed orders"
```

**Step 4**: LLM updates (localized change)
```t
  cleaned = orders |> filter(\(row) row.status == "completed")
```

### Pattern 2: Explain and Generate

**Step 1**: Human provides data sample
```t
sample = read_csv("data.csv")
explain(sample)
-- DataFrame(100 rows x 5 cols: [date, product, region, quantity, price])
```

**Step 2**: Human requests analysis
```
"Calculate total revenue by product, show top 10"
```

**Step 3**: LLM generates with intent
```t
intent {
  description: "Top 10 products by revenue",
  data: "data.csv with date, product, region, quantity, price",
  computation: "revenue = quantity * price, group by product, sort descending, top 10"
}

top_products = sample
  |> mutate("revenue", \(row) row.quantity * row.price)
  |> group_by("product")
  |> summarize("total_revenue", \(g) sum(g.revenue))
  |> arrange("total_revenue", "desc")
  |> head(10)
```

### Pattern 3: Iterative Refinement

**Iteration 1**: Basic implementation
```t
intent { description: "Average sales by month" }

monthly = sales |> group_by("month") |> summarize("avg", \(g) mean(g.amount))
```

**Iteration 2**: Add NA handling
```t
intent { 
  description: "Average sales by month",
  requirements: "Handle missing amounts"
}

monthly = sales |> group_by("month") |> summarize("avg", \(g) mean(g.amount, na_rm = true))
```

**Iteration 3**: Add validation
```t
intent { 
  description: "Average sales by month",
  requirements: "Handle missing amounts, exclude zero sales"
}

monthly = sales
  |> filter(\(row) row.amount > 0)
  |> group_by("month")
  |> summarize("avg", \(g) mean(g.amount, na_rm = true))
```

**Each iteration**: Intent updated, LLM regenerates, human verifies.

---

## Introspection for LLMs

T provides introspection functions for LLM context:

### Explain Data

```t
df = read_csv("customers.csv")
explain(df)
-- "DataFrame(1000 rows x 5 cols: [id, name, age, city, ltv])"

-- JSON format for LLM consumption
explain_json(df)
-- {"type": "DataFrame", "rows": 1000, "columns": [...], "sample": [...]}
```

### Intent Fields

```t
i = intent { description: "Analysis", goal: "Insights" }

intent_fields(i)
-- {description: "Analysis", goal: "Insights"}

intent_get(i, "description")
-- "Analysis"
```

### Pipeline Introspection

```t
p = pipeline {
  x = 10
  y = x * 2
  z = y + 5
}

pipeline_nodes(p)
-- ["x", "y", "z"]

pipeline_deps(p, "z")
-- ["y"]

-- LLM can understand dependency graph
```

---

## LLM Best Practices

### For Humans

1. **Write Intent First**: Specify goals before code
2. **Be Specific**: Include assumptions, constraints, expected outputs
3. **Review Generated Code**: Verify LLM understood correctly
4. **Iterate Locally**: Request changes to specific nodes, not entire scripts
5. **Version Intents**: Track intent changes in Git

### For LLMs

1. **Parse Intent**: Extract requirements from intent block
2. **Generate Pipelines**: Use pipeline structure for modularity
3. **Include Error Handling**: Use `na_rm`, validation checks
4. **Preserve Intents**: Keep intent blocks in generated code
5. **Explain Assumptions**: Document why specific approaches were chosen

---

## Example: Full LLM Collaboration

**Human**: "I need to analyze employee salaries by department and identify outliers"

**LLM Response**:
```t
intent {
  description: "Employee salary analysis with outlier detection",
  
  data_source: "employees.csv",
  required_columns: ["employee_id", "department", "salary"],
  
  analysis_steps: [
    "Calculate statistics by department (mean, SD)",
    "Identify outliers (>2 SD from department mean)",
    "Generate summary report"
  ],
  
  outlier_definition: "Salary > department_mean + 2*department_sd",
  
  outputs: [
    "department_stats.csv: mean, sd, count per department",
    "outliers.csv: employees with salaries > 2 SD from mean"
  ],
  
  created: "2024-01-15",
  llm_assistant: "Claude"
}

salary_analysis = pipeline {
  -- Load data
  employees = read_csv("employees.csv", clean_colnames = true)
  
  -- Department statistics
  dept_stats = employees
    |> group_by("department")
    |> summarize("mean_salary", \(g) mean(g.salary, na_rm = true))
    |> summarize("sd_salary", \(g) sd(g.salary, na_rm = true))
    |> summarize("count", \(g) nrow(g))
  
  -- Identify outliers
  -- (Join would be manual or use a join function if available)
  -- For now, calculate globally
  overall_mean = mean(employees.salary, na_rm = true)
  overall_sd = sd(employees.salary, na_rm = true)
  threshold = overall_mean + 2 * overall_sd
  
  outliers = employees
    |> filter(\(row) row.salary > threshold)
    |> select("employee_id", "department", "salary")
}

-- Export results
write_csv(salary_analysis.dept_stats, "department_stats.csv")
write_csv(salary_analysis.outliers, "outliers.csv")

print("Analysis complete:")
print("Department stats: department_stats.csv")
print("Outliers: outliers.csv")
```

**Human Review**: "Good! But I want outliers per department, not overall"

**LLM Update** (regenerates `outliers` node):
```t
  -- Update: Per-department outliers
  with_dept_stats = employees
    |> group_by("department")
    |> mutate("dept_mean", \(g) mean(g.salary, na_rm = true))
    |> mutate("dept_sd", \(g) sd(g.salary, na_rm = true))
  
  outliers = with_dept_stats
    |> filter(\(row) row.salary > row.dept_mean + 2 * row.dept_sd)
    |> select("employee_id", "department", "salary", "dept_mean", "dept_sd")
```

**Note**: Only `outliers` node changed; `dept_stats` and `employees` nodes unchanged.

---

## Audit Trail

Intent blocks + version control = complete audit trail:

```bash
git log --oneline intent_blocks/

abc123 Update: Exclude test accounts from churn analysis
def456 Add validation: minimum transaction amount $1
789ghi Initial: Customer churn analysis

git show abc123:analysis.t
# Shows exactly what assumptions changed and why
```

---

**See Also**:
- [Reproducibility](reproducibility.md) — Nix for reproducible environments
- [Examples](examples.md) — Intent-driven analysis examples
- [Pipeline Tutorial](pipeline_tutorial.md) — Pipeline structure
