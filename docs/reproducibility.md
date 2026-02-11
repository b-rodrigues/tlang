# Reproducibility in T

How T ensures perfect reproducibility for data analysis through Nix integration and deterministic execution.

## The Reproducibility Problem

Traditional data science faces a reproducibility crisis:

- **Dependency Drift**: Package versions change over time
- **Platform Differences**: Code behaves differently on Linux vs macOS vs Windows
- **Hidden State**: Random seeds, global variables, system time
- **Implicit Assumptions**: Undocumented data preprocessing steps

**Result**: "Works on my machine" syndrome — analyses that can't be reproduced months or years later.

---

## T's Reproducibility Guarantee

T provides **perfect reproducibility**: The same T code with the same data produces identical results, always.

### Three Pillars

1. **Nix Package Management**: Frozen dependency versions
2. **Deterministic Execution**: No hidden randomness or state
3. **Intent Blocks**: Document assumptions and constraints

---

## Nix Integration

### What is Nix?

Nix is a declarative package manager that ensures:
- **Bit-for-bit identical builds** across machines
- **Isolated environments** (no global state)
- **Versioned dependencies** (pinned to exact commits)

### How T Uses Nix

Every T project is a **Nix flake**:

**`flake.nix`**:
```nix
{
  description = "My T analysis project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    tlang.url = "github:b-rodrigues/tlang/v0.1.0";
  };

  outputs = { self, nixpkgs, tlang }: {
    devShell = nixpkgs.lib.mkShell {
      buildInputs = [
        tlang.packages.${system}.default
        # Any other dependencies
      ];
    };
  };
}
```

**Lock file** (`flake.lock`): Pins exact versions

```json
{
  "nodes": {
    "tlang": {
      "locked": {
        "narHash": "sha256-...",
        "rev": "abc123...",
        "type": "github"
      }
    }
  }
}
```

### Reproducibility Across Time

**Scenario**: You run an analysis today. A colleague tries to run it in 2026.

**Without Nix**:
- Package versions have changed
- APIs have breaking changes
- Results differ or code errors

**With Nix**:
```bash
# 2026: Same exact environment as 2024
nix develop github:myuser/my-analysis?rev=abc123
dune exec src/repl.exe < analysis.t

# Identical output, guaranteed
```

The `flake.lock` file ensures every dependency (OCaml, Arrow, system libraries) is pinned to the exact version used originally.

---

## Deterministic Execution

### No Hidden Randomness

T has **no built-in randomness**:
- No random number generators (RNG)
- No random seeds
- No sampling without explicit seed

**To add randomness** (future feature):
```t
-- Explicit, reproducible randomness
rng = random_seed(12345)
sample = random_sample(data, 100, rng)
```

### No Implicit State

- **No global variables**: All state is explicit in pipelines
- **No system time**: Computations don't depend on clock
- **No file system side effects** (except explicit I/O)

### Deterministic Pipelines

Pipelines execute in **topological order** (determined by dependencies):

```t
p = pipeline {
  z = x + y
  x = 10
  y = 20
}
-- Always executes: x, y, then z
-- Order of declaration doesn't matter
```

**Same inputs → Same outputs**, always.

---

## Documenting Assumptions with Intent Blocks

Intent blocks make **implicit knowledge explicit**:

```t
intent {
  description: "Customer churn prediction for Q4 2023",
  
  data_source: "customers.csv from Salesforce export 2023-12-31",
  
  assumptions: [
    "Churn defined as no purchase in 90 days",
    "Test accounts excluded (account_type != 'test')",
    "Incomplete records removed (age, email must be present)"
  ],
  
  constraints: [
    "Age between 18 and 100",
    "Email format validated",
    "Purchase amounts > 0"
  ],
  
  preprocessing: [
    "Column names cleaned (snake_case)",
    "NA values in 'income' imputed with median",
    "Outliers beyond 3σ removed"
  ],
  
  environment: {
    t_version: "0.1.0",
    nix_revision: "abc123",
    run_date: "2024-01-15"
  }
}

-- Analysis code follows...
```

**Benefits**:
- Future readers understand context
- LLMs can regenerate code correctly
- Auditors can verify assumptions
- Changes to assumptions are versioned (Git)

---

## Reproducible Workflow Example

### Project Structure

```
my-analysis/
├── flake.nix           # Nix configuration
├── flake.lock          # Locked dependencies
├── data/
│   └── sales.csv       # Input data (or fetch script)
├── scripts/
│   └── analysis.t      # T analysis script
├── outputs/
│   └── report.csv      # Generated results
└── README.md           # Documentation
```

### Step 1: Create Nix Flake

**`flake.nix`**:
```nix
{
  description = "Q4 2023 Sales Analysis";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    tlang.url = "github:b-rodrigues/tlang/v0.1.0";
  };
  
  outputs = { self, nixpkgs, tlang }: {
    # ... configuration ...
  };
}
```

### Step 2: Write Analysis with Intent

**`scripts/analysis.t`**:
```t
intent {
  description: "Q4 2023 revenue analysis by region",
  data_source: "data/sales.csv (exported 2023-12-31)",
  assumptions: "All sales in USD, no refunds included",
  created: "2024-01-15",
  author: "Data Team"
}

sales = read_csv("data/sales.csv", clean_colnames = true)

analysis = pipeline {
  cleaned = sales
    |> filter($amount > 0)
    |> filter(not is_na($region))
  
  by_region = cleaned
    |> group_by($region)
    |> summarize($total_revenue = sum($amount))
    |> arrange($total_revenue, "desc")
}

write_csv(analysis.by_region, "outputs/report.csv")
```

### Step 3: Run Analysis

```bash
# Enter reproducible environment
nix develop

# Run analysis
dune exec src/repl.exe < scripts/analysis.t

# Output: outputs/report.csv
```

### Step 4: Version Control

```bash
git init
git add flake.nix flake.lock scripts/ data/ README.md
git commit -m "Initial Q4 2023 analysis"
git tag v1.0.0
git push
```

### Step 5: Reproduce Anywhere

**On any machine, any time**:
```bash
# Clone project
git clone https://github.com/myorg/q4-analysis.git
cd q4-analysis

# Enter exact same environment
nix develop

# Run analysis
dune exec src/repl.exe < scripts/analysis.t

# Verify identical output
diff outputs/report.csv expected_report.csv
# (No differences)
```

---

## Reproducibility Checklist

### For Every Analysis

- [ ] Use Nix flake with locked dependencies
- [ ] Add intent block documenting assumptions
- [ ] Explicit NA handling (`na_rm = true` where needed)
- [ ] No randomness without explicit seeds
- [ ] Version control everything (code + `flake.lock`)
- [ ] Document data sources and versions
- [ ] Test re-execution produces identical results

### For Sharing

- [ ] Include `flake.nix` and `flake.lock`
- [ ] Document data download/preparation steps
- [ ] Provide expected outputs for verification
- [ ] Include README with run instructions
- [ ] Tag releases with Git (`git tag v1.0.0`)

### For Long-Term Storage

- [ ] Archive with Zenodo or similar (DOI)
- [ ] Include all dependencies in archive
- [ ] Document minimum system requirements
- [ ] Provide checksum for verification

---

## Advanced Reproducibility

### Containerization

Nix + Docker for maximum portability:

```dockerfile
FROM nixos/nix

WORKDIR /analysis
COPY . .

RUN nix develop --command dune build

CMD ["nix", "develop", "--command", "dune", "exec", "src/repl.exe", "<", "analysis.t"]
```

### Continuous Integration

Verify reproducibility on every commit:

**`.github/workflows/reproduce.yml`**:
```yaml
name: Verify Reproducibility

on: [push]

jobs:
  reproduce:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: cachix/install-nix-action@v15
      - run: nix develop --command dune exec src/repl.exe < analysis.t
      - run: diff outputs/result.csv expected_result.csv
```

### Data Versioning

Use DVC or Git-LFS for data versioning:

```bash
# Track data files
dvc add data/sales.csv
git add data/sales.csv.dvc

# Data is versioned alongside code
```

---

## Reproducibility vs Performance

**Trade-off**: Perfect reproducibility sometimes costs performance.

**Strategies**:

1. **Cache expensive computations** (Nix store)
2. **Parallelize where deterministic** (map/reduce)
3. **Profile and optimize hot paths** (keep determinism)
4. **Document performance assumptions** (hardware, runtime)

**Example**:
```t
intent {
  performance: "Optimized for 8-core CPU, 16GB RAM",
  runtime_expected: "5 minutes on reference hardware",
  caching: "Pipeline nodes cached in .cache/"
}
```

---

## Reproducibility Best Practices

1. **Pin Everything**: Nix locks all dependencies
2. **Document Everything**: Intent blocks capture assumptions
3. **Test Everything**: Verify results are identical on re-run
4. **Version Everything**: Git for code, DVC for data
5. **Share Everything**: Public repos, archived datasets

---

**See Also**:
- [Installation Guide](installation.md) — Setting up Nix
- [Pipeline Tutorial](pipeline_tutorial.md) — Building reproducible workflows
- [LLM Collaboration](llm-collaboration.md) — Intent blocks for AI
