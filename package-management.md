# T Package Management System

> A plan for user-contributed packages using Nix flakes for reproducibility

---

## Overview

T's package management philosophy prioritizes reproducibility above all else. Rather than implementing a traditional package manager with version resolution and registry systems, T leverages **Nix flakes** to ensure that projects are perfectly reproducible across all environments.

The core principle: **T's package manager is Nix itself.**

This approach provides:

- **Perfect reproducibility**: Same inputs always produce the same environment
- **No dependency hell**: Nix guarantees consistent package versions
- **Decentralized ecosystem**: Each package lives in its own git repository
- **Flexible distribution**: Authors maintain and release their own packages
- **Version pinning**: Packages are pinned via git tags/releases for reproducibility

---

## Package Structure: `t init package`

### Command

```bash
t init package <package-name>
```

This command creates a folder structure for a new T package, inspired by R package conventions:

### Folder Layout

```
my-package/
├── DESCRIPTION.toml       # Package metadata
├── flake.nix             # Nix flake for the package
├── README.md             # Package documentation
├── LICENSE               # License file (default: EUPL-1.2)
├── CHANGELOG.md          # Version history
├── src/                  # T source files
│   ├── function1.t
│   ├── function2.t
│   └── helpers.t
├── tests/                # Test files
│   ├── test-function1.t
│   └── test-function2.t
├── examples/             # Example scripts
│   └── demo.t
└── docs/                 # Generated documentation (auto-created)
    ├── index.md
    └── reference/
        ├── function1.md
        └── function2.md
```

### DESCRIPTION.toml

The `DESCRIPTION.toml` file contains package metadata:

```toml
[package]
name = "my-package"
version = "0.1.0"
description = "A brief description of what the package does"
authors = ["Your Name <email@example.com>"]
license = "EUPL-1.2"
homepage = "https://github.com/username/my-package"
repository = "https://github.com/username/my-package"

[dependencies]
# T packages this package depends on
# Format: package = { git = "repository-url", tag = "version" }
stats = { git = "https://github.com/t-lang/stats", tag = "v0.5.0" }
colcraft = { git = "https://github.com/t-lang/colcraft", tag = "v0.2.1" }

[t]
# Minimum T language version required
min_version = "0.5.0"
```

### Package flake.nix

Each package includes a `flake.nix` that provides both a package output and a development shell:

```nix
{
  description = "My T package";

  inputs = {
    nixpkgs.url = "github:rstats-on-nix/nixpkgs/2026-02-10";
    flake-utils.url = "github:numtide/flake-utils";
    t-lang.url = "github:b-rodrigues/tlang/v0.5.0";
    # Package dependencies as flake inputs
    stats.url = "github:t-lang/stats/v0.5.0";
    colcraft.url = "github:t-lang/colcraft/v0.2.1";
  };

  outputs = { self, nixpkgs, flake-utils, t-lang, stats, colcraft }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # The package itself
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "t-my-package";
          version = "0.1.0";
          src = ./.;
          
          buildInputs = [ 
            t-lang.packages.${system}.default 
            stats.packages.${system}.default
            colcraft.packages.${system}.default
          ];
          
          installPhase = ''
            mkdir -p $out/lib/t/packages/my-package
            cp -r src/* $out/lib/t/packages/my-package/
          '';
          
          meta = {
            description = "My T package";
            homepage = "https://github.com/username/my-package";
          };
        };
        
        # Development shell for hacking on the package
        devShells.default = pkgs.mkShell {
          buildInputs = [
            t-lang.packages.${system}.default
            stats.packages.${system}.default
            colcraft.packages.${system}.default
            pkgs.pandoc  # For documentation generation
          ];
          
          shellHook = ''
            echo "=========================================="
            echo "T Package Development Environment"
            echo "Package: my-package"
            echo "=========================================="
            echo ""
            echo "Available commands:"
            echo "  t repl              - Start T REPL"
            echo "  t run <file>        - Run a T file"
            echo "  t test              - Run package tests"
            echo "  t document .        - Generate documentation"
            echo ""
            echo "Source files: src/"
            echo "Tests: tests/"
            echo ""
          '';
        };
      }
    );
}
```

This flake provides:
- **`packages.default`**: The package as a Nix derivation
- **`devShells.default`**: A development environment with T and all dependencies
- **Automatic composition**: When used as an input, both the package and its dependencies are available

### src/ Directory Convention

T source files are placed in the `src/` directory:

- Each file should define one or more related functions
- File names should be lowercase with hyphens: `data-manipulation.t`
- Helper functions can be in separate files: `helpers.t`, `utils.t`
- Internal functions should be prefixed with `.` (e.g., `.internal_helper`)

### Docstrings and Documentation

Functions should include docstrings for automatic documentation generation:

```t
-- @doc
-- Summarize numeric columns with common statistics
--
-- @description
-- This function takes a dataframe and computes summary statistics
-- (mean, standard deviation, min, max) for all numeric columns.
--
-- @param df A dataframe with numeric columns
-- @return A dataframe with summary statistics
-- @example
-- data = read_csv("data.csv")
-- summary = summarize_numeric(data)
-- print(summary)
-- @end
summarize_numeric = \(df) -> {
  df |> select_if(\(col) is_numeric(col))
     |> summarize(
          mean = mean(__column__),
          sd = sd(__column__),
          min = min(__column__),
          max = max(__column__)
        )
}
```

Docstring format:
- **`@doc`**: Marks the start of a docstring block
- **`@description`**: Detailed description of the function
- **`@param`**: Parameter description (one per parameter)
- **`@return`**: Description of return value
- **`@example`**: Usage example
- **`@end`**: Marks the end of the docstring block

Generate documentation with:
```bash
# From within the package directory
t document .

# Or specify the package path
t document my-package/

# Or by package name (if installed)
t document my-package
```

This generates markdown documentation in the `docs/` directory using pandoc.

### Example Package Function

File: `src/summarize-numeric.t`

```t
-- @doc
-- Summarize numeric columns with common statistics
--
-- @description
-- Computes mean, standard deviation, minimum, and maximum
-- for all numeric columns in a dataframe.
--
-- @param df A dataframe with one or more numeric columns
-- @return A dataframe containing summary statistics
-- @example
-- data = read_csv("sales.csv")
-- summary = summarize_numeric(data)
-- print(summary)
-- @end
summarize_numeric = \(df) -> {
  df |> select_if(\(col) is_numeric(col))
     |> summarize(
          mean = mean(__column__),
          sd = sd(__column__),
          min = min(__column__),
          max = max(__column__)
        )
}
```

---

## Project Structure: `t init project`

### Command

```bash
t init project <project-name>
```

This command creates a reproducible T project with Nix flake configuration:

### Project Layout

```
my-project/
├── flake.nix            # Nix flake with pinned dependencies
├── flake.lock           # Lockfile (auto-generated by Nix)
├── tproject.toml        # T project configuration
├── README.md            # Project documentation
├── .gitignore           # Git ignore patterns
├── src/                 # Project source code
│   └── analysis.t
├── data/                # Data files
│   └── dataset.csv
├── outputs/             # Generated outputs
└── tests/               # Project tests
    └── test-analysis.t
```

### Project flake.nix

The project uses `tproject.toml` for declaring dependencies, and the `t` CLI tool helps synchronize these with the `flake.nix` inputs.

**Design decision: tproject.toml vs tproject.nix**

We use **`tproject.toml`** because:
- More accessible to non-Nix users
- Clear separation of concerns (project config vs build logic)
- Can be parsed by the `t` CLI for commands like `t install`
- Human-readable and easy to edit

When you add a package to `tproject.toml` and run `t install`, it automatically updates your `flake.nix` to include the package as an input.

**Example project flake.nix:**

```nix
{
  description = "My T Data Analysis Project";

  inputs = {
    # Pin to a specific date for reproducibility
    nixpkgs.url = "github:rstats-on-nix/nixpkgs/2026-02-10";
    flake-utils.url = "github:numtide/flake-utils";
    t-lang.url = "github:b-rodrigues/tlang/v0.5.0";
    
    # T packages - auto-added by 't install' command from tproject.toml
    stats.url = "github:t-lang/stats/v0.5.0";
    colcraft.url = "github:t-lang/colcraft/v0.2.1";
    my-viz-package.url = "github:johndoe/t-viz/v1.2.0";
  };

  # Configure cachix for R packages
  nixConfig = {
    extra-substituters = [
      "https://rstats-on-nix.cachix.org"
    ];
    extra-trusted-public-keys = [
      "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
    ];
  };

  outputs = { self, nixpkgs, flake-utils, t-lang, stats, colcraft, my-viz-package }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Collect all T package dependencies
        tPackages = [
          stats.packages.${system}.default
          colcraft.packages.${system}.default
          my-viz-package.packages.${system}.default
        ];

      in
      {
        # Development environment
        devShells.default = pkgs.mkShell {
          buildInputs = [
            t-lang.packages.${system}.default
            pkgs.pandoc  # For documentation generation
          ] ++ tPackages;

          shellHook = ''
            echo "=================================================="
            echo "T Project Environment: my-project"
            echo "=================================================="
            echo ""
            echo "T version: $(t --version)"
            echo "Nixpkgs date: 2026-02-10"
            echo ""
            echo "Loaded packages:"
            echo "  - stats (v0.5.0)"
            echo "  - colcraft (v0.2.1)"
            echo "  - my-viz-package (v1.2.0)"
            echo ""
            echo "Available commands:"
            echo "  t repl              - Start T REPL"
            echo "  t run src/analysis.t - Run analysis"
            echo "  t document .        - Generate documentation"
            echo "  t install <pkg-url> - Add a new package"
            echo ""
          '';
        };

        # Make the project runnable
        apps.default = {
          type = "app";
          program = "${t-lang.packages.${system}.default}/bin/t";
        };
      }
    );
}
```

The `t install` command reads `tproject.toml`, and automatically updates the `flake.nix` inputs section and the `tPackages` list in the outputs.

### tproject.toml

The `tproject.toml` file specifies project metadata and T package dependencies. When you run `t install`, it reads this file and synchronizes your `flake.nix`.

```toml
[project]
name = "my-project"
version = "0.1.0"
description = "Data analysis for customer segmentation"
authors = ["Data Team <data@example.com>"]

[environment]
# Date-pinned nixpkgs from rstats-on-nix
nixpkgs = "github:rstats-on-nix/nixpkgs/2026-02-10"
t_version = "0.5.0"

[dependencies]
# T packages from decentralized repositories
# Each package is hosted in its own git repository and pinned to a release tag
# Format: package-name = { git = "repository-url", tag = "version-tag" }
# 
# Simply add packages here - the flake will automatically fetch and include them!
stats = { git = "https://github.com/t-lang/stats", tag = "v0.5.0" }
colcraft = { git = "https://github.com/t-lang/colcraft", tag = "v0.2.1" }
dataframe = { git = "https://github.com/t-lang/dataframe", tag = "v0.3.0" }

# User-contributed packages from the community
my-viz-package = { git = "https://github.com/johndoe/t-viz", tag = "v1.2.0" }
advanced-stats = { git = "https://github.com/janedoe/t-advanced-stats", tag = "v2.0.1" }

[dependencies.dev]
# Development-only dependencies (for testing, etc.)
test-helpers = { git = "https://github.com/t-lang/test-helpers", tag = "v0.1.0" }

[r-packages]
# R packages available via rstats-on-nix
# These are specified in flake.nix but documented here
dplyr = "*"
ggplot2 = "*"
readr = "*"

[targets]
# Optional: Define project targets (inspired by R's {targets})
# This section is reserved for future pipeline/DAG specification
```

**Using packages in your project:**

1. Edit `tproject.toml` and add the package to `[dependencies]`
2. Run `t install` to update flake.nix with the new package
3. Run `nix flake lock` to update the lockfile
4. Run `nix develop` to enter the environment with all packages loaded
5. That's it! The packages are now available in your T code

The `t install` command synchronizes `tproject.toml` with `flake.nix` automatically.

---

## Dependency Resolution

### How It Works

1. **tproject.toml declaration**: You declare packages in `tproject.toml` with git URLs and tags.

2. **t install sync**: The `t install` command reads `tproject.toml` and updates `flake.nix` to add the package as a flake input.

3. **Nix flake lock**: When you run `nix flake lock`, Nix resolves all flake inputs and creates a `flake.lock` file with exact commits/hashes.

4. **rstats-on-nix date pins**: The nixpkgs input is pinned to a specific date branch (e.g., `2026-02-10`), which corresponds to a snapshot of all R packages at that date.

5. **T package git tags**: T packages are referenced from their git repositories using release tags (e.g., `v0.5.0`), ensuring exact reproducibility.

6. **Transitive dependencies**: All dependencies of dependencies are also pinned through Nix's evaluation.

### Package Releases and Versioning

**Critical requirement**: All T packages **must have releases** to be used as dependencies.

Package authors should:

1. **Use semantic versioning**: `v0.1.0`, `v1.2.3`, etc.
2. **Create git tags** for each release:
   ```bash
   git tag -a v0.1.0 -m "Release version 0.1.0"
   git tag -l v0.1.0  # Verify tag was created
   git push origin v0.1.0
   ```
3. **Update CHANGELOG.md** with release notes
4. **Test thoroughly** before tagging a release

Projects reference packages by their **git repository URL** and **tag**:
```toml
my-package = { git = "https://github.com/user/my-package", tag = "v0.1.0" }
```

This approach ensures:
- **Exact pinning**: Tags are immutable once pushed
- **Reproducibility**: Same tag = same code, always
- **Discoverability**: Users can browse releases on GitHub
- **Flexibility**: Authors control their own release schedule

### Date-Based Pinning

The `rstats-on-nix/nixpkgs` repository maintains branches for each date:

- `https://github.com/rstats-on-nix/nixpkgs/tree/2026-02-10`
- `https://github.com/rstats-on-nix/nixpkgs/tree/2026-02-09`
- `https://github.com/rstats-on-nix/nixpkgs/tree/2026-01-19`

When initializing a project, `t init project` automatically:

1. Gets the current date (e.g., `2026-02-10`)
2. Sets `nixpkgs.url = "github:rstats-on-nix/nixpkgs/2026-02-10"`
3. Runs `nix flake lock` to generate the lockfile

This ensures that running the project in 5 years will use the **exact same** package versions.

---

## Package Discovery

In a decentralized ecosystem, package discovery happens through:

### 1. Community Package Index

A curated, community-maintained index (e.g., at `https://t-packages.org`) could list:
- Package name and description
- Git repository URL
- Latest release version
- Author information
- Categories/tags
- Documentation link

Example entry:
```toml
[advanced-stats]
description = "Advanced statistical functions for T"
repository = "https://github.com/janedoe/t-advanced-stats"
latest = "v2.0.1"
author = "Jane Doe"
tags = ["statistics", "data-analysis"]
```

### 2. GitHub Topics and Search

Package authors should:
- Use the `t-lang-package` topic on GitHub
- Include clear description and keywords
- Maintain good documentation

Users can discover packages via GitHub search:
```
https://github.com/search?q=topic:t-lang-package+stars:>10
```

Or using GitHub's advanced search interface with the `topic:t-lang-package` filter.

### 3. Community Resources

- **Awesome T Packages**: Curated list on GitHub
- **T Community Forum**: Package announcements
- **Social media**: #TLang hashtag for package releases

### 4. Direct References

Projects can depend on any git repository:
```toml
# Even experimental/private packages
my-internal-package = { git = "https://gitlab.company.com/data/t-utils", tag = "v0.1.0" }
```

---

## Workflow for Package Authors

### Creating a New Package

1. **Initialize package structure**:
   ```bash
   t init package my-awesome-package
   cd my-awesome-package
   ```

2. **Write your T functions** in the `src/` directory:
   ```bash
   # src/cool-function.t
   -- @doc
   -- Add 42 to a number
   -- @param x A number
   -- @return The number plus 42
   -- @end
   cool_function = \(x) -> x + 42
   ```

3. **Add tests** in the `tests/` directory:
   ```bash
   # tests/test-cool-function.t
   result = cool_function(8)
   assert(result == 50, "cool_function should add 42")
   ```

4. **Update DESCRIPTION.toml** with metadata

5. **Test your package**:
   ```bash
   nix develop
   t run tests/test-cool-function.t
   ```

6. **Initialize git repository and publish**:
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   ```

7. **Create a GitHub repository**:
   - Create a new repository on GitHub (e.g., `https://github.com/username/my-awesome-package`)
   - Push your code:
     ```bash
     git remote add origin https://github.com/username/my-awesome-package
     git push -u origin main
     ```

8. **Create your first release**:
   ```bash
   # Update CHANGELOG.md with release notes
   git add CHANGELOG.md
   git commit -m "Prepare v0.1.0 release"
   
   # Create and push a release tag
   git tag -a v0.1.0 -m "Release version 0.1.0"
   git push origin v0.1.0
   ```

9. **Share your package**:
   - Add a clear README.md explaining usage
   - Share on social media, forums, or the T community
   - Users can now add it to their projects via tproject.toml

### Package Publishing Guidelines

All published packages should:

1. Follow the standard folder structure
2. Include comprehensive tests
3. Have clear documentation in README.md
4. Use semantic versioning with git tags
5. Include examples
6. Have automated tests
7. Use an open-source license (EUPL-1.2 or compatible)
8. **Create releases** for version pinning
9. Maintain a CHANGELOG.md

---

## Workflow for Project Authors

### Starting a New Project

1. **Initialize project**:
   ```bash
   t init project customer-segmentation
   cd customer-segmentation
   ```

2. **Enter development environment**:
   ```bash
   nix develop
   ```

3. **Edit tproject.toml** to add dependencies:
   ```toml
   [dependencies]
   stats = { git = "https://github.com/t-lang/stats", tag = "v0.5.0" }
   colcraft = { git = "https://github.com/t-lang/colcraft", tag = "v0.2.1" }
   my-awesome-package = { git = "https://github.com/username/my-awesome-package", tag = "v0.2.0" }
   ```

4. **Synchronize flake with tproject.toml**:
   ```bash
   t install
   ```
   
   This reads `tproject.toml` and updates `flake.nix` to add the packages as inputs.

5. **Lock dependencies**:
   ```bash
   nix flake lock
   ```

6. **Enter development environment**:
   ```bash
   nix develop
   ```

7. **Write your analysis** in `src/`:
   ```bash
   # src/analysis.t
   data = read_csv("data/customers.csv")
   result = data |> cool_function()
   ```

8. **Run your analysis**:
   ```bash
   t run src/analysis.t
   ```

### Sharing Your Project

When sharing a project with collaborators:

1. **Commit both tproject.toml and flake.lock** to version control
2. **Share the repository** (e.g., GitHub)
3. **Collaborators run**:
   ```bash
   git clone <repo-url>
   cd <repo>
   nix develop
   ```

The exact same environment will be reproduced, regardless of:
- Operating system (Linux, macOS)
- Time (works the same in 5 years)
- Global system packages

---

## Reproducibility Guarantees

### What is Guaranteed

1. **Exact package versions**: All T packages, R packages, and system libraries are pinned
2. **Build reproducibility**: Same source code produces identical binaries
3. **Environment isolation**: No interference from global packages
4. **Time independence**: Locked projects work identically years later

### What is NOT Guaranteed

1. **Data reproducibility**: Data files must be version-controlled separately
2. **Random seeds**: Use explicit `set_seed()` calls in T code
3. **External APIs**: Web APIs may change; cache responses when possible

---

## Migration from Traditional Package Managers

### Comparison with npm/PyPI/CRAN

| Feature | npm/PyPI | CRAN | T (Nix) |
|---------|----------|------|---------|
| **Reproducibility** | Lockfiles (fragile) | Single version policy | Perfect (Nix) |
| **Contribution** | Decentralized | Centralized, opaque | Decentralized, transparent |
| **Dependency Hell** | Common | Rare | Impossible |
| **Version Conflicts** | Common | Managed | Impossible |
| **Setup Complexity** | Low | Low | Medium (learning Nix) |
| **Long-term Stability** | Poor | Good | Excellent |
| **Package Discovery** | Central registry | CRAN website | GitHub/community curated lists |

### Why Not a Traditional Package Manager?

T deliberately avoids:

1. **Version resolution algorithms**: Nix handles this perfectly
2. **Central package registries**: Decentralized git repositories provide flexibility
3. **Dependency hell**: Nix makes it impossible
4. **Breaking changes**: Git tags and date-pinning prevent surprise breakage

### Why Decentralized?

The decentralized approach provides:

1. **Author autonomy**: Package authors control their own release schedule
2. **No gatekeepers**: Anyone can publish packages without approval
3. **Flexibility**: Packages can be hosted anywhere (GitHub, GitLab, self-hosted)
4. **Resilience**: No single point of failure for the ecosystem
5. **Direct attribution**: Clear ownership and provenance of each package

The tradeoff is a steeper learning curve (Nix), but the payoff is **guaranteed reproducibility**.

---

## Documentation Generation

T packages can include docstrings that are automatically converted to documentation using `t document`.

### Docstring Format

Docstrings use a special comment syntax with tags:

```t
-- @doc
-- Brief one-line description of the function
--
-- @description
-- Longer, detailed description of what the function does,
-- how it works, and any important notes.
--
-- @param param_name Description of the parameter
-- @param other_param Description of another parameter
--
-- @return Description of what the function returns
--
-- @example
-- # Usage example
-- result = my_function(arg1, arg2)
-- print(result)
--
-- @see related_function, other_function
-- @end
function_name = \(param_name, other_param) -> {
  -- function body
}
```

### Documentation Tags

- **`@doc`**: Marks the start of a docstring block (required)
- **`@description`**: Detailed description (optional but recommended)
- **`@param name desc`**: Parameter documentation (one per parameter)
- **`@return desc`**: Return value description
- **`@example`**: Usage examples (can have multiple)
- **`@see`**: Cross-references to related functions
- **`@deprecated`**: Mark function as deprecated
- **`@since version`**: Version when function was added
- **`@end`**: Marks the end of the docstring (required)

### Generating Documentation

```bash
# Generate docs for current package
t document .

# Generate docs for specific package
t document path/to/package/

# Generate docs for installed package by name
t document my-package

# Options
t document . --format html   # Generate HTML (default: markdown)
t document . --output docs/  # Specify output directory
```

### Documentation Output

The `t document` command:

1. Scans all `.t` files in `src/` for docstrings
2. Parses the docstring tags
3. Generates markdown files in `docs/reference/`
4. Creates an index in `docs/index.md`
5. Uses pandoc to convert to HTML if requested

**Generated structure:**
```
docs/
├── index.md                 # Package overview and function index
├── reference/
│   ├── function1.md        # Function documentation
│   ├── function2.md
│   └── helpers.md
└── html/                    # HTML output (if --format html)
    ├── index.html
    └── reference/
        ├── function1.html
        └── function2.html
```

### Integration with Package Development

Documentation generation is integrated into the package development workflow:

```bash
# Enter package dev environment
cd my-package
nix develop

# Write code with docstrings
# Edit src/my-function.t

# Generate documentation
t document .

# View generated docs
cat docs/reference/my-function.md

# Commit documentation to git
git add docs/
git commit -m "Update documentation"
```

The generated documentation is committed to the repository, making it available:
- In the GitHub repository UI
- In package managers/indexes
- For local reference by package users

---

## Future Enhancements

### Planned Features

- [x] `t install`: Synchronize tproject.toml with flake.nix (reads dependencies and updates flake inputs)
- [ ] `t install <package-url>`: Interactive package installation (prompts to add to tproject.toml)
- [ ] `t update`: Update packages to latest tagged releases in tproject.toml
- [ ] `t update <package>`: Update specific package to latest release
- [ ] `t test`: Run all package/project tests
- [ ] `t document`: Generate documentation from docstrings (covered above)
- [ ] `t publish`: Create initial release tag and push to git repository
- [ ] `t doctor`: Verify project setup and dependencies
- [ ] `t search <query>`: Search community package index for packages

### Package Discovery

In the future, we may add:

- **Community package index**: Curated list of T packages with metadata
- **Web UI** for browsing available packages
- **Automated documentation** generation from package repos
- **Package statistics**: Downloads, stars, recent updates
- **Dependency graph** visualization

Packages remain decentralized in individual git repositories; the index only provides discovery.

---

## Examples

### Example 1: Simple Analysis Package

```bash
# Create package
t init package simple-stats

# Edit src/descriptives.t
cat > src/descriptives.t <<EOF
-- @doc
-- Describe a dataframe with summary statistics
-- @param df A dataframe
-- @return Summary statistics
-- @end
describe = \(df) -> {
  df |> summarize(
    count = n(),
    mean = mean(__column__),
    sd = sd(__column__),
    min = min(__column__),
    max = max(__column__)
  )
}
EOF

# Generate documentation
nix develop
t document .

# Test it
t repl
```

### Example 2: Data Analysis Project

```bash
# Create project
t init project sales-analysis

# Enter environment
nix develop

# Add data
cp ~/sales_2026.csv data/

# Write analysis
cat > src/analyze.t <<EOF
sales = read_csv("data/sales_2026.csv")

monthly = sales 
  |> mutate(month = extract_month(date))
  |> group_by(month)
  |> summarize(total = sum(amount))

print(monthly)
EOF

# Run
t run src/analyze.t
```

### Example 3: Collaborative Research

Researcher A sets up a project:

```bash
t init project climate-analysis
cd climate-analysis

# Edit tproject.toml to add dependencies
# Commit to GitHub
git add .
git commit -m "Initial setup"
git push
```

Researcher B reproduces the exact environment:

```bash
git clone <repo>
cd climate-analysis
nix develop  # Exact same environment!
t run src/analysis.t  # Identical results
```

---

## Conclusion

T's package management system leverages Nix flakes to provide:

1. **Perfect reproducibility** through date-pinned nixpkgs and git-tagged releases
2. **Decentralized ecosystem** where each package lives in its own repository
3. **Zero dependency conflicts** through Nix's isolation
4. **Long-term stability** through immutable package snapshots

The workflow is simple:
- **Package authors**: `t init package` → develop → publish to git with tagged releases
- **Project authors**: `t init project` → add dependencies to tproject.toml → `nix develop`

Key principles:
- **Decentralized**: No central authority controls package distribution
- **Release-based**: All packages must use git tags for version pinning
- **Nix-powered**: T's package manager is Nix itself

This ensures reproducibility guarantees that traditional package managers cannot match, while maintaining the flexibility and autonomy of a decentralized ecosystem.
