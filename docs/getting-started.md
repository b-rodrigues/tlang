# Getting Started with T

Welcome to T! This guide will help you install T, write your first program, and understand the basic workflow.

## Prerequisites

T requires:

- **Nix package manager** (version 2.4 or later) with flakes enabled
- **Linux or macOS** (Windows via WSL2)
- Basic familiarity with command-line tools

## Installation

### 1. Install Nix

If you don't have Nix installed:

```bash
# Install Nix with flakes enabled
sh <(curl -L https://nixos.org/nix/install) --daemon

# Enable flakes (add to ~/.config/nix/nix.conf)
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 2. Clone T Repository

```bash
git clone https://github.com/b-rodrigues/tlang.git
cd tlang
```

### 3. Enter Development Environment

```bash
nix develop
```

This will:
- Download and cache all dependencies
- Set up OCaml, Apache Arrow, and build tools
- Create an isolated development shell

### 4. Build T

```bash
dune build
```

### 5. Start the REPL

```bash
dune exec src/repl.exe
```

You should see:

```
T Language REPL (Alpha 0.1)
Type 'exit' to quit
> 
```

## Your First T Program

### Interactive REPL Session

```t
> 2 + 3
5

> x = 42
42

> double = \(n) n * 2
<function>

> double(x)
84

> [1, 2, 3, 4, 5] |> map(\(x) x * x) |> sum
55

> exit
```

### Writing a T Script

Create a file `hello.t`:

```t
-- hello.t
name = "World"
message = "Hello, " + name + "!"
print(message)
```

Run it (assuming you've created a runner - for now, REPL only):

```bash
# Currently T is REPL-only; file execution coming soon
```

## Understanding T Scripts

### Basic Syntax

```t
-- Comments start with double dash

-- Variables are immutable
x = 42
name = "Alice"
active = true

-- Lists
numbers = [1, 2, 3, 4, 5]

-- Dictionaries
person = {name: "Bob", age: 30}

-- Functions
add = \(a, b) a + b
square = \(x) x * x
```

### Working with Data

```t
-- Load CSV data
df = read_csv("data.csv")

-- Inspect the data
nrow(df)      -- number of rows
ncol(df)      -- number of columns
colnames(df)  -- column names
head(df.age)  -- first few values of age column

-- Filter and select using NSE dollar-prefix syntax
young_people = df |> filter($age < 30)
names_only = young_people |> select($name)

-- Compute statistics
mean(df.age, na_rm = true)
sd(df.salary, na_rm = true)
```

### Building Pipelines

```t
-- Create a reproducible analysis pipeline
analysis = pipeline {
  -- Load data
  raw = read_csv("sales.csv")
  
  -- Clean and filter
  clean = raw
    |> filter($amount > 0)
    |> mutate($profit, \(row) row.revenue - row.cost)
  
  -- Aggregate
  summary = clean
    |> group_by($region)
    |> summarize($total_profit, \(g) sum(g.profit))
}

-- Access pipeline results
print(analysis.summary)
```

## Common Patterns

### Error Handling

```t
-- Errors are values, not exceptions
result = 1 / 0
is_error(result)        -- true
error_message(result)   -- "Division by zero"

-- Conditional pipe short-circuits on errors
safe_chain = error("oops") |> double |> triple  -- Error
unsafe_chain = error("oops") ?|> handle         -- Can recover

-- Recovery function
handle = \(x) if (is_error(x)) 0 else x
```

### Working with NA Values

```t
-- NA must be handled explicitly
data_with_missing = [1, 2, NA, 4]

-- This errors
mean(data_with_missing)  -- Error: NA encountered

-- Explicit handling
mean(data_with_missing, na_rm = true)  -- 2.33...

-- Check for NA
is_na(NA)        -- true
is_na(42)        -- false
```

### Data Transformations

```t
-- Select specific columns
subset = df |> select($name, $age, $salary)

-- Filter rows by condition
adults = df |> filter($age >= 18)

-- Add or modify columns
with_bonus = df |> mutate($bonus, \(row) row.salary * 0.1)

-- Sort data
sorted = df |> arrange($salary, "desc")

-- Group and summarize
by_dept = df
  |> group_by($dept)
  |> summarize($avg_salary, \(g) mean(g.salary))
```

## REPL Tips

### Multiline Input

The REPL supports multiline expressions:

```t
> long_pipeline = [1, 2, 3, 4, 5]
    |> map(\(x) x * x)
    |> filter(\(x) x > 10)
    |> sum
55
```

### Inspecting Values

```t
> type(42)
"Int"

> type(df)
"DataFrame"

> explain(df)
DataFrame(100 rows x 5 cols: [name, age, dept, salary, active])
```

### Getting Help

```t
-- Check available packages
> packages()

-- View package functions (implementation dependent)
> package_info("stats")
```

## Next Steps

Now that you've got T running, explore:

1. **[Language Overview](language_overview.md)** — Learn all language features
2. **[Data Manipulation Examples](data_manipulation_examples.md)** — Master data verbs
3. **[Pipeline Tutorial](pipeline_tutorial.md)** — Build reproducible workflows
4. **[API Reference](api-reference.md)** — Complete function documentation

## Common Issues

### Flakes Not Enabled

If you get `unrecognized command 'develop'`:

```bash
# Add to ~/.config/nix/nix.conf
experimental-features = nix-command flakes
```

### Build Errors

If `dune build` fails:

```bash
# Clean and rebuild
dune clean
dune build
```

### Missing Dependencies

Make sure you're in the Nix development shell:

```bash
nix develop
```

All dependencies should be automatically available.

## Learning Resources

- **Examples Directory**: `examples/` contains practical T programs
- **Tests Directory**: `tests/` shows expected behavior and usage patterns
- **Website**: [tstats-project.org](https://tstats-project.org) for comprehensive docs

## Getting Help

- **GitHub Issues**: [github.com/b-rodrigues/tlang/issues](https://github.com/b-rodrigues/tlang/issues)
- **Discussions**: Check existing issues for common questions

---

Ready to dive deeper? Check out the [Language Overview](language_overview.md)!
