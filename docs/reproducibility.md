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
    tlang.url = "github:b-rodrigues/tlang/v0.56.2";
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
t run src/pipeline.t

# Identical output, guaranteed
```

The `flake.lock` file ensures every dependency (OCaml, Arrow, system libraries) is pinned to the exact version used originally.

---

## Deterministic Execution

### No Hidden Randomness

T provides **explicit, reproducible randomness**:

- **`set_seed(seed)`**: Initializes a global random number generator with a given integer seed.
- **`sample(x, n, replace)`**: Draw a random sample of size n from a Vector or List.
- **`slice_sample(data, n, replace)`**: Draw a random sample of n rows from a DataFrame.

```t
-- Reproducible random sampling
set_seed(42)
my_sample = sample([1, 2, 3, 4, 5], n = 3)
my_rows = mtcars |> slice_sample(n = 5)
```

Without an explicit `set_seed()` call, the RNG is auto-seeded from system entropy and results are unpredictable. Always call `set_seed()` before sampling in reproducible workflows.

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
    t_version: "0.56.2",
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
├── src/
│   └── pipeline.t      # T analysis script
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
    tlang.url = "github:b-rodrigues/tlang/v0.56.2";
  };
  
  outputs = { self, nixpkgs, tlang }: {
    # ... configuration ...
  };
}
```

### Step 2: Write Analysis with Intent

**`src/pipeline.t`**:
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
t run src/pipeline.t

# Output: outputs/report.csv
```

### Step 4: Version Control

```bash
git init
git add flake.nix flake.lock src/ data/ README.md
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
t run src/pipeline.t

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

CMD ["nix", "develop", "--command", "t", "run", "src/pipeline.t"]
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
      - run: nix develop --command t run src/pipeline.t
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

## Offline Provenance Bundles with `t provenance`

Reproducibility requires not only bit-for-bit rebuilds, but also transparent audit trails for scientific peer review, regulatory compliance, and software supply chain security.

T provides the `t provenance` CLI command and the `t_provenance()` standard library function to generate self-contained, offline provenance bundles directly from your project's local state without requiring network access.

### Sources of Provenance Data

A provenance bundle aggregates metadata from four authoritative local sources:

1. **`tproject.toml`**: Project identity, authors, license, minimum language version, and declared runtime dependencies (R, Python, Julia).
2. **`flake.lock`**: Exact commit hashes, revisions, and content hashes (`narHash`) for all Nix inputs.
3. **`_pipeline/build_log_*.json`**: Execution timestamps, durations, Nix store paths, output artifact formats, and `meta` / `foreign_meta` sidecars (metrics, schemas, and model kinds).
4. **`intent { ... }` blocks**: High-level computational assumptions, data invariants, and modeling intentions declared in `.t` source scripts.

### Supported Standards

T exports provenance in three distinct formats:

#### 1. Research Object Crate (RO-Crate 1.1 JSON-LD)

[RO-Crate](https://www.researchobject.org/ro-crate/) is a community-driven specification for packaging research artifacts and their execution metadata as Linked Data (`ro-crate-metadata.json`).

- Conforms to the RO-Crate 1.1 specification and Workflow Run Crate profiles.
- Emits root dataset entities with mandatory `datePublished`, `license`, and descriptive metadata.
- Represents pipeline nodes as `CreateAction` (execution events) and `SoftwareApplication` (computational steps) entities.
- Preserves polyglot model metadata and metrics under stringified `foreignMeta` properties.

```bash
# Generate RO-Crate metadata to standard output
t provenance --format ro-crate

# Save directly to a file
t provenance --format ro-crate -o ro-crate-metadata.json
```

#### 2. Software Bill of Materials (CycloneDX 1.5 SBOM)

[CycloneDX](https://cyclonedx.org/) is a lightweight, widely adopted standard for Software Bill of Materials (SBOM) used in cybersecurity and software supply chain compliance.

- Formatted according to the CycloneDX 1.5 JSON specification.
- Translates Nix SRI content hashes (`sha256-<base64>`) to hexadecimal hashes (`SHA-256`) required by the CycloneDX schema.
- Emits declared packages with Package URLs (`purl`), including PyPI (`pkg:pypi/`), CRAN (`pkg:cran/`), and generic purls (`pkg:generic/julia`, `pkg:generic/nix`).
- Declares pipeline nodes as components with type `"data"` to ensure valid dependency graph references without dangling references.

```bash
# Generate CycloneDX 1.5 SBOM
t provenance --format sbom -o bom.cdx.json
```

#### 3. T-Native JSON

A direct, structured JSON serialization of the pipeline provenance graph, suitable for custom scripts and analysis:

```bash
t provenance --format json -o provenance.json
```

### CLI Command Options

```text
Usage: t provenance [options]

Options:
  --format <fmt>   Output format: 'ro-crate' (default), 'sbom', or 'json'
  --output, -o <s> Output file path (defaults to stdout)
  --dir <s>        Project root directory (defaults to current working directory)
  --file <s>       Target .t script to extract intent blocks from
  --no-meta        Exclude foreign metadata sidecars from the bundle
```

### Programmatic Usage

You can also generate provenance manifests inside T scripts or in the REPL using `t_provenance()`:

```t
-- Generate RO-Crate metadata
crate = t_provenance(format = "ro-crate")

-- Write CycloneDX SBOM directly to file
t_provenance(format = "sbom", output = "sbom.cdx.json")

-- Generate provenance excluding foreign metadata sidecars
t_provenance(format = "ro-crate", output = "ro-crate.json", include_meta = false)
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

## Next Steps

Now that you understand T's commitment to reproducibility, explore the language and its architecture:

1. **[Architecture](architecture.md)** — Understand the internal design and execution model of T.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — Build reproducible data pipelines.
3. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
4. **[API Reference](api-reference.md)** — Complete function reference by package.
