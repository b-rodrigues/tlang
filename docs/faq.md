# Frequently Asked Questions (FAQ)

Common questions about T programming language.

## General Questions

### What is T?

T is an experimental programming language for data analysis designed with three core principles:
1. **Reproducibility-first**: Nix-managed dependencies ensure identical results across time and environments
2. **Explicit semantics**: No silent failures or hidden behavior
3. **LLM-native**: Intent blocks enable structured AI collaboration

### Who is T for?

- **Data analysts** who prioritize reproducibility
- **Researchers** who need auditable analyses
- **Teams** using LLMs for data work
- **Anyone** frustrated by R/Python dependency management

### How is T different from R?

| Aspect | R | T |
|--------|---|---|
| Dependency management | CRAN (version drift) | Nix (frozen) |
| NA propagation | Automatic (silent) | Explicit (`na_rm`) |
| Error handling | Exceptions | Errors as values |
| Reproducibility | Best-effort | Guaranteed |
| LLM integration | None | Intent blocks |
| Performance | Mature, optimized | Alpha, improving |

### How is T different from Python/Pandas?

| Aspect | Python/Pandas | T |
|--------|---------------|---|
| Type system | Dynamic | Dynamic |
| Syntax | Imperative | Functional |
| Pipelines | Method chaining | Pipe operators |
| Data backend | NumPy | Apache Arrow |
| Reproducibility | venv/conda | Nix flakes |

### Is T production-ready?

**No.** T is in **alpha (v0.1)**. It's suitable for:
- Exploratory analysis
- Research projects
- Learning functional data analysis
- Reproducibility experiments

**Not yet suitable for**:
- Production data pipelines
- High-performance computing
- Mission-critical applications

---

## Installation & Setup

### Do I need to learn Nix?

**Basic usage**: No. Just run `nix develop` and you're done.

**Advanced usage**: Understanding Nix helps with:
- Custom dependency management
- Performance tuning
- Troubleshooting build issues

### Can I use T without Nix?

**Technically yes**, but you lose reproducibility guarantees. You'd need to:
- Manually install OCaml, Dune, Menhir, Arrow
- Manage version compatibility yourself
- Accept platform-specific differences

**We strongly recommend using Nix.**

### Does T work on Windows?

**Yes**, via **WSL2** (Windows Subsystem for Linux):
1. Install WSL2
2. Install Nix inside WSL2
3. Follow standard installation steps

**Native Windows support** is not planned for alpha.

### How much disk space does T require?

- **Nix store**: ~2-3 GB (one-time download)
- **T repository**: ~50 MB
- **Build artifacts**: ~100 MB

Total: ~2.5 GB for first install (cached for future use).

---

## Language Features

### Does T have static types?

**No.** T is dynamically typed (runtime type checking).

**Rationale**: For alpha, dynamic typing matches exploratory REPL workflow. Static typing may come in future versions.

### Can I write loops?

**No explicit loops.** Use functional patterns:

```t
-- Instead of for loop, use map
numbers = [1, 2, 3, 4, 5]
squared = map(numbers, \(x) x * x)

-- Instead of while loop, use recursion
factorial = \(n)
  if (n <= 1) 1 else n * factorial(n - 1)
```

### Can I define custom types?

**Not in alpha.** You can use:
- Lists and dictionaries for structured data
- Functions for behavior
- DataFrames for tabular data

**Future**: User-defined types and pattern matching.

### Does T support object-oriented programming?

**No.** T is functional. Use:
- Functions for behavior
- Dictionaries for data encapsulation
- Closures for state

### Can I import external libraries?

**Not yet.** Alpha has a fixed standard library. 

**Future**: Package system for user-contributed libraries.

---

## Data Analysis

### Can T replace R for my workflow?

**It depends.**

**T is good for**:
- Descriptive statistics
- Data cleaning and transformation
- Simple linear regression
- Reproducible pipelines

**T is not (yet) good for**:
- Advanced statistical models
- Machine learning
- Complex visualizations
- Domain-specific packages (bioinformatics, finance)

**Strategy**: Use T for data preparation, export to CSV, use R/Python for specialized analysis.

### How do I visualize data in T?

**Alpha has no visualization.**

**Workaround**: Export to CSV, visualize in R/Python:

```t
-- In T
result = df |> group_by("category") |> summarize("count", nrow)
write_csv(result, "plot_data.csv")

# In R
library(ggplot2)
data <- read.csv("plot_data.csv")
ggplot(data, aes(x = category, y = count)) + geom_bar(stat = "identity")
```

**Future**: Native plotting via Arrow integration.

### Can I read Parquet/Excel/databases?

**Alpha**: Only CSV via `read_csv()`

**Future** (planned):
- Parquet (via Arrow)
- Excel (via external library)
- Databases (SQL integration)

**Workaround**: Convert to CSV first:
```python
# In Python
import pandas as pd
df = pd.read_parquet("data.parquet")
df.to_csv("data.csv", index=False)

# In T
df = read_csv("data.csv")
```

### How do I join DataFrames?

**Alpha has no built-in join.**

**Workaround**: Manual matching with filters and maps (inefficient) or use R/Python:

```python
# In Python/Pandas
import pandas as pd
a = pd.read_csv("a.csv")
b = pd.read_csv("b.csv")
merged = a.merge(b, on="id")
merged.to_csv("merged.csv", index=False)

# In T
result = read_csv("merged.csv")
```

**Future**: `join()` function with multiple strategies.

---

## Performance

### Is T slow?

**For alpha, yes.** T uses a tree-walking interpreter (slow but simple).

**Benchmarks** (preliminary):
- 10k row filter: ~10ms
- 10k row group-by-summarize: ~50ms
- Linear regression (1k points): ~20ms

**Future optimizations**:
- Bytecode compilation
- JIT for hot paths
- More Arrow compute kernels

### Can T handle large datasets?

**It depends.**

**Comfortable**: Up to ~1 million rows
**Possible**: Up to ~10 million rows (slow)
**Not recommended**: >10 million rows

**For large data**: Use Pandas/Polars for ETL, T for final analysis.

### Will T get faster?

**Yes.** Roadmap includes:
- Bytecode VM
- Lazy evaluation for pipelines
- GPU support (via Arrow Compute)

---

## Reproducibility

### How does Nix ensure reproducibility?

Nix uses **content-addressed storage**: Every dependency is identified by a cryptographic hash of its build inputs. Same hash → identical binary, guaranteed.

**flake.lock** pins exact hashes, so the same code always uses the same dependencies.

### Can I reproduce analyses from years ago?

**Yes**, if you have:
1. Source code
2. `flake.lock` file
3. Nix installed

Even if packages have been updated or removed from repositories, Nix can rebuild from source using pinned versions.

### Do I need to commit data files?

**Ideally, yes** (or use data versioning like DVC).

**Alternatives**:
- Store data in external archive (Zenodo, OSF)
- Include download script in project
- Document exact data source and version

---

## LLM Collaboration

### Can I use T without LLMs?

**Yes!** Intent blocks are optional. They're useful for:
- Documentation
- Team communication
- Future regeneration

You can write pure T code without any intent blocks.

### What LLMs work with T?

T's design is **LLM-agnostic**. Any LLM can:
- Parse intent blocks
- Generate T code
- Follow pipeline structure

**Tested with**: GPT-4, Claude, open-source models.

### Do I need an LLM to learn T?

**No.** T is a normal programming language. Intent blocks are just structured comments.

---

## Troubleshooting

### Build fails with "command not found: nix"

**Solution**: Install Nix first (see [Installation Guide](installation.md)).

### Tests fail on macOS vs Linux

**Possible causes**:
- Floating-point precision differences (acceptable if small)
- Platform-specific Arrow behavior

**Solution**: Check if differences are significant. Small numerical differences (<1e-6) are acceptable.

### REPL crashes on large datasets

**Workaround**: 
- Process data in chunks
- Use filters to reduce size early
- Export intermediate results

**Future**: Lazy evaluation will help.

---

## Contributing

### How can I contribute?

See [Contributing Guide](contributing.md) for:
- Bug reports
- Feature requests
- Code contributions
- Documentation improvements

### I found a bug. What should I do?

1. Check if it's already reported in [GitHub Issues](https://github.com/b-rodrigues/tlang/issues)
2. If not, create a new issue with:
   - Clear title
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details

### Can I add a new standard library function?

**Yes!** See [Development Guide](development.md) for:
- Adding functions to packages
- Writing tests
- Updating documentation

---

## Future Plans

### What's the roadmap?

**Alpha (current)**: Core language, basic data analysis
**Beta**: Performance improvements, more functions
**1.0**: Production-ready, stable API

See [Changelog](changelog.md) for details.

### Will T support [feature X]?

Check [GitHub Issues](https://github.com/b-rodrigues/tlang/issues) or ask in Discussions.

### When will T be production-ready?

**No specific date.** T prioritizes correctness and design over speed.

**Estimate**: Beta in 6-12 months, 1.0 in 1-2 years.

---

## Philosophy

### Why create a new language instead of improving R/Python?

T explores **language-level reproducibility** and **LLM-native design** — concepts hard to retrofit into existing languages.

**Goal**: Learn what works, potentially influence mainstream languages.

### Why functional instead of imperative?

**Functional style**:
- Easier to reason about (no hidden state)
- Composable (pipelines)
- Easier for LLMs to generate (pure functions)

### Is T research or practical?

**Both.** T is:
- **Research**: Exploring reproducibility and LLM collaboration
- **Practical**: Usable for real data analysis (with caveats)

---

## Getting Help

### Where can I ask questions?

- **GitHub Issues**: Bug reports
- **GitHub Discussions**: General questions, ideas
- **Documentation**: Comprehensive guides

### I'm stuck. Who can help?

1. Check [Troubleshooting Guide](troubleshooting.md)
2. Search [GitHub Issues](https://github.com/b-rodrigues/tlang/issues)
3. Ask in GitHub Discussions
4. Read [Getting Started](getting-started.md)

---

**More Questions?** Open a [GitHub Discussion](https://github.com/b-rodrigues/tlang/discussions)!
