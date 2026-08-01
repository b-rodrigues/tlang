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

## Tiered AI Onboarding

T provides a structured way to onboard LLMs to new projects via the `t init` command. When a project is initialized, T generates two essential files that should be provided to the AI agent at the start of any conversation:

### 1. Project-Specific Guide (`AGENTS.md`)
This file tells the LLM exactly how the current project is structured and what the coding conventions are (e.g., "Nix is mandatory", "Use Arrow for data transfer"). It serves as the project's "rules of engagement" for AI assistants.

### 2. Tiered Language Reference (`T-LANGUAGE-REFERENCE.md`)
To handle different LLM context windows and project needs, T allows you to select a "Context Level" during initialization:

| Level | Description | Use Case |
| :--- | :--- | :--- |
| **small** | Core syntax and top 20 functions | Simple scripts, low-context models |
| **medium** | Exhaustive standard library index (Default) | General analysis and pipeline development |
| **full** | Comprehensive manual with detailed examples | Complex logic and package development |
| **huge** | Concatenated documentation of the entire ecosystem | Deep debugging and system-level tasks |

By providing these files, you ensure the LLM has the exact technical context needed to generate valid, idiomatic T code without trial-and-error.

---

## T's LLM-Native Design

T treats LLMs as **first-class collaborators** with structured boundaries:

### Key Principles

1. **Intent over Implementation**: Humans specify goals, LLMs generate code
2. **Local over Global**: LLMs generate pipeline nodes, not entire scripts
3. **Inspectable over Opaque**: Intent blocks make assumptions explicit
4. **Regenerable over Brittle**: Stable boundaries enable safe code updates
5. **Validatable over Trusting**: Instant static checks catch errors before Nix builds

---

## Instant Feedback: `t check`

Before an agent generates or modifies pipeline code, it should validate the result. T provides a tiered checking system that runs in seconds — no Nix builds required.

### Three Tiers of Checking

| Command | What it checks | Nix required? |
| :--- | :--- | :--- |
| `t check <file.t>` | Pipeline DAG structure, dependency cycles, node syntax | No |
| `t check --schema <file.t>` | + column references, schema propagation | No |

**REPL-callable versions** (same options, returns `String`):

```t
result = t_check("src/pipeline.t")             -- same as: t check
result = t_check("src/pipeline.t", schema=true) -- same as: t check --schema
result = t_diff("src/pipeline.t")              -- same as: t diff
result = t_fix("src/pipeline.t")               -- same as: t fix
```
| `t check --env <file.t>` | + `tproject.toml` declarations, lockfile consistency, Nix eval | Yes |
| `t check --json <file.t>` | Structured JSON diagnostics (works with any tier) | Depends on tier |

The first two tiers are the workhorses for agent iteration. They catch structural errors and schema mismatches in seconds, letting agents fix problems before triggering expensive Nix builds.

### Watch Mode

Use `--watch` during active development for continuous feedback:

```bash
t check --watch --schema src/pipeline.t
```

This runs immediately, then re-runs on every file save. Press Ctrl+C to stop. The exit code reflects the last check's result, making it usable in CI and editor integrations.

### Structured Diagnostics

`t check --json` emits machine-readable diagnostics:

```json
{
  "diagnostics": [
    {
      "error_class": "schema_mismatch",
      "message": "Column 'score' not found in DataFrame. Did you mean 'scorer'?",
      "node": "clean",
      "span": { "start": [12, 5], "end": [12, 50] },
      "suggested_fix": {
        "kind": "rename_column",
        "old_name": "score",
        "new_name": "scorer",
        "edit_distance": 1,
        "is_unique": true
      }
    }
  ],
  "exit_code": 1
}
```

Each diagnostic includes:

- `error_class`: categorizes the issue (`schema_mismatch`, `type_mismatch`, `cycle_detected`, etc.)
- `node`: the pipeline node where the issue was found
- `span`: source location `[line, column]`
- `suggested_fix`: a mechanical fix the agent can apply (see `t fix` below)

Agents consume this output to make targeted decisions — no parsing of human-readable error strings required.

### Mechanical Fixes with `t fix`

When `t check --schema` emits a `suggested_fix`, the agent can apply it mechanically:

```bash
t fix src/pipeline.t          -- apply fixes and rewrite the file
t fix --dry-run src/pipeline.t -- preview changes without modifying
```

Currently supported fix types:

| Fix type | What it does |
| :--- | :--- |
| **Rename_column** | Renames `$old_name` column references to `$new_name` throughout the file |
| **Add_node_arg** | Adds a missing argument to a node function call |
| **Pin_package_version** | Pins a dependency to a specific version in `tproject.toml` |

The agent workflow is: run `t check --schema`, parse the JSON output for `suggested_fix` entries, then run `t fix` to apply them. Always review the diff before committing.

### Build Diffing with `t diff`

After iterative development, `t diff` compares the last two Nix builds of a pipeline:

```bash
t diff src/pipeline.t
```

It reports per-node status:

| Status | Meaning |
| :--- | :--- |
| **Unchanged** | Same content hash in both builds |
| **Changed** | Different content hash |
| **Added** | Present in second build, absent in first |
| **Removed** | Present in first build, absent in second |
| **Errored** | Node failed in one or both builds |

For programmatic access, use `diff_summary(p)` in the REPL:

```t
diff_summary(p)
-- DataFrame with columns: name, status, hash_a, hash_b, class_a, class_b
```

This is useful for verifying that a code change only affected the intended nodes.

---

## Programmatic Test Results: `t test --json`

When agents modify code, they need to verify that existing tests still pass. T provides
structured test output via `t test --json`:

```bash
t test --json tests/
t test --format junit tests/  # JUnit XML for CI
```

**Filtering tests:**

```bash
t test --only "stats"     # run only tests matching "stats"
t test --not "slow"       # skip tests matching "slow"
t test --only "stats" --not "anova"  # combine filters
t test --failfast         # stop on first failure
t test --list             # list tests without running
t test --timeout 30       # mark slow tests as failed
```

**Excluding tests with `.tignore`:**

Create `tests/.tignore` to automatically exclude test files:

```
# tests/.tignore
slow_integration.t
*_benchmark.t
legacy/
```

This returns a JSON object with test results:

```json
{
  "schema_version": "1",
  "status": "passed",
  "total": 15,
  "passed": 14,
  "failed": 1,
  "duration_ms": 2340,
  "results": [
    {
      "file": "tests/test_arithmetic.t",
      "status": "passed",
      "duration_ms": 120,
      "error": null
    },
    {
      "file": "tests/test_strings.t",
      "status": "failed",
      "duration_ms": 85,
      "error": "Assertion failed at line 42: expected \"hello\" but got \"world\""
    }
  ]
}
```

**Agent workflow:**

1. Agent modifies code
2. Agent runs `t test --json tests/`
3. Agent parses JSON to check `status` field
4. If `status` is `"failed"`, agent reads `error` field from failed results
5. Agent fixes the issue and re-runs tests

The JSON output follows the same schema version as `t check --json` and `t run --json`,
enabling consistent tooling across all T commands.

### REPL-callable version

For agents working in the REPL, `t_test()` returns a DataFrame with the same results:

```t
results = t_test()
-- DataFrame with columns: file, status, duration_ms, error

-- Filter to show only failed tests
failed = results |> filter($status == "failed")
nrow(failed)  -- 0 if all tests passed
```

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
    |> filter($total_spend > 0)
    |> filter($purchase_count > 0)
  
  with_ltv = validated
    |> mutate($ltv, \(row) row.total_spend / months_since(row.signup_date))
  
  segmented = with_ltv
    |> mutate($segment, \(row)
        if (row.ltv > 1000) "high_value"
        else if (row.ltv > 500) "medium_value"
        else "low_value"
      )
  
  summary = segmented
    |> group_by($segment)
    |> summarize($count = nrow($segment), $avg_ltv = mean($ltv))
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
  cleaned = raw |> filter($amount > 0)
  
  -- Node 3: Analyze (can regenerate independently)
  by_region = cleaned
    |> group_by($region)
    |> summarize($total = sum($amount))
    |> arrange($total, "desc")
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
  cleaned = orders |> filter($status == "completed")
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
  |> mutate($revenue = $quantity * $price)
  |> group_by($product)
  |> summarize($total_revenue = sum($revenue))
  |> arrange($total_revenue, "desc")
  |> head(10)
```

### Pattern 3: Iterative Refinement

**Iteration 1**: Basic implementation
```t
intent { description: "Average sales by month" }

monthly = sales |> group_by($month) |> summarize($avg = mean($amount))
```

**Iteration 2**: Add NA handling
```t
intent { 
  description: "Average sales by month",
  requirements: "Handle missing amounts"
}

monthly = sales |> group_by($month) |> summarize($avg = mean($amount))
```

**Iteration 3**: Add validation
```t
intent { 
  description: "Average sales by month",
  requirements: "Handle missing amounts, exclude zero sales"
}

monthly = sales
  |> filter($amount > 0)
  |> group_by($month)
  |> summarize($avg = mean($amount))
```

**Each iteration**: Intent updated, LLM regenerates, human verifies.

### Pattern 4: Check-Fix-Verify

This pattern uses T's static checking tools to catch and fix errors before running the pipeline.

**Step 1**: Agent generates pipeline

```t
analysis = pipeline {
  raw = read_csv("sales.csv")
  cleaned = raw
    |> filter($amount > 0)
  by_region = cleaned
    |> group_by($region)
    |> summarize($total = sum($amount))
}
```

**Step 2**: Run `t check --schema` to validate

```bash
$ t check --schema src/pipeline.t
error [schema_mismatch] Column 'regin' not found. Did you mean 'region'?
```

**Step 3**: Agent fixes the typo (localized change)

```t
  by_region = cleaned
    |> group_by($region)
    |> summarize($total = sum($amount))
```

**Step 4**: Run `t check --schema` again — clean

```bash
$ t check --schema src/pipeline.t
$
```

**Step 5**: Only now trigger the Nix build

```bash
$ t run src/pipeline.t
```

This loop — **generate, check, fix, build** — ensures agents never waste time on Nix builds that would fail for structural or schema reasons. The check step takes seconds; the build step takes minutes.

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

### Structured Diagnostics via CLI

For machine consumption, agents use `t check --json` and `t fix --dry-run`:

```bash
$ t check --json --schema src/pipeline.t
{
  "diagnostics": [
    {
      "error_class": "schema_mismatch",
      "message": "Column 'regin' not found. Did you mean 'region'?",
      "node": "by_region",
      "span": { "start": [12, 5], "end": [12, 60] },
      "suggested_fix": {
        "kind": "rename_column",
        "old_name": "regin",
        "new_name": "region",
        "edit_distance": 1,
        "is_unique": true
      }
    }
  ],
  "exit_code": 1
}
```

```bash
$ t fix --dry-run src/pipeline.t
dry-run: would apply 1 fix to src/pipeline.t:
  [Rename_column] line 12: rename column 'regin' to 'region'
```

```bash
$ t fix --dry-run src/pipeline.t
dry-run: would apply 1 fix to src/pipeline.t:
  [Cast] line 12: insert mutate($amount = as.numeric($amount))
```

These tools give agents structured, parseable output instead of human-readable error strings. The agent can programmatically decide what to fix and verify the fix before applying it.

---

## LLM Best Practices

### For Humans

1. **Write Intent First**: Specify goals before code
2. **Be Specific**: Include assumptions, constraints, expected outputs
3. **Review Generated Code**: Verify LLM understood correctly
4. **Iterate Locally**: Request changes to specific nodes, not entire scripts
5. **Version Intents**: Track intent changes in Git
6. **Review `t fix` Diffs**: Use `t fix --dry-run` to preview changes before applying. Always review the diff before committing.
7. **Use `--watch`**: Run `t check --watch --schema` during active development for continuous feedback

### For LLMs

1. **Parse Intent**: Extract requirements from intent block
2. **Generate Pipelines**: Use pipeline structure for modularity
3. **Include Error Handling**: Use `na_rm`, validation checks
4. **Preserve Intents**: Keep intent blocks in generated code
5. **Explain Assumptions**: Document why specific approaches were chosen
6. **Always `t check` First**: Run `t check --schema` before `build_pipeline` — it catches structural and schema errors in seconds. In the REPL, use `t_check(file, schema=true)` (same behavior, returns a string).
7. **Use `t fix` for Mechanical Changes**: When `t check --json` reports a `suggested_fix`, apply it with `t fix` rather than manually editing — it handles line-number drift and word-boundary safety. In the REPL, use `t_fix(file)`.
9. **Verify with `t diff`**: After modifying a pipeline, run `t diff` to confirm only the intended nodes changed. In the REPL, use `t_diff(file)`.

---

## Example: Full LLM Collaboration

**Human**: "I need to analyze employee salaries by department and identify outliers"

**LLM generates** with intent:

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
  
  created: "2024-07-12",
  llm_assistant: "Claude"
}

salary_analysis = pipeline {
  -- Load data
  employees = read_csv("employees.csv", clean_colnames = true)
  
  -- Department statistics
  dept_stats = employees
    |> group_by($department)
    |> summarize($mean_salary = mean($salary),
                 $sd_salary = sd($salary),
                 $count = nrow($department))
  
  -- Per-department outliers (>2 SD from department mean)
  with_stats = employees
    |> group_by($department)
    |> mutate($dept_mean = mean($salary, na_rm = true))
    |> mutate($dept_sd = sd($salary, na_rm = true))
  
  outliers = with_stats
    |> filter($salary > $dept_mean + 2 * $dept_sd)
    |> select($employee_id, $department, $salary, $dept_mean, $dept_sd)
}

-- Export results
write_csv(salary_analysis.dept_stats, "department_stats.csv")
write_csv(salary_analysis.outliers, "outliers.csv")
```

**LLM validates** before building:

```bash
$ t check --schema src/pipeline.t
$
```

Clean. The pipeline structure is valid. Schema propagation confirms all column references are resolvable.

**LLM builds and runs**:

```bash
$ t run src/pipeline.t
```

**Human Review**: "Good! But the outliers should only flag employees making more than $200k, not just 2 SD from mean"

**LLM updates** the `outliers` node (localized change):

```t
  outliers = with_stats
    |> filter($salary > 200000)
    |> select($employee_id, $department, $salary, $dept_mean, $dept_sd)
```

**LLM validates** the change:

```bash
$ t check --schema src/pipeline.t
$
```

Clean. The filter predicate changed but the column references are still valid.

**LLM builds and verifies** with `t diff`:

```bash
$ t run src/pipeline.t
$ t diff src/pipeline.t
Name          Status    Class_a  Class_b
employees     Unchanged T        T
dept_stats    Unchanged T        T
with_stats    Unchanged T        T
outliers      Changed   T        T
```

The diff confirms only `outliers` changed. `employees`, `dept_stats`, and `with_stats` are unchanged — their cached artifacts are reused.

---

## Audit Trail

Intent blocks + version control = complete audit trail:

```bash
git log --oneline intent_blocks/

abc123 Update: Exclude test accounts from churn analysis
def456 Add validation: minimum transaction amount $1
789ghi Initial: Customer churn analysis

git show abc123:src/pipeline.t
# Shows exactly what assumptions changed and why
```

---

**See Also**:

- [Reproducibility](reproducibility.md) — Nix for reproducible environments
- [Examples](examples.md) — Intent-driven analysis examples
- [Pipeline Tutorial](pipeline_tutorial.md) — Pipeline structure
- [Debugging](debugging.md) — `t debug` for interactive node debugging
- [API Reference](api-reference.md) — `t_check()`, `t_diff()`, `t_fix()` REPL functions and `t check`, `t fix`, `t diff` CLI documentation
