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

# T Language Package Documentation System Specification

**Version:** 1.0.0-draft  
**Status:** Design Specification  
**Target:** T Language v0.6.0+  
**Author:** System Specification  
**Date:** 2026-02-11

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Background & Motivation](#background--motivation)
3. [Design Goals](#design-goals)
4. [Documentation Format](#documentation-format)
5. [System Architecture](#system-architecture)
6. [Implementation Phases](#implementation-phases)
7. [API Reference](#api-reference)
8. [Examples](#examples)
9. [Migration Path](#migration-path)
10. [Future Considerations](#future-considerations)

---

## 1. Executive Summary

This specification defines a **documentation generation system** for the T programming language, providing roxygen2-like functionality adapted for T's unique features: reproducibility-first design, LLM-native workflows, and explicit semantics.

**Key Features:**
- **Structured documentation blocks** embedded in source code
- **Automatic documentation generation** from annotated functions
- **REPL-accessible help system** (`help(function_name)`)
- **Multiple output formats** (Markdown, HTML, JSON)
- **Integration with T's package system**
- **LLM-friendly documentation** with intent blocks

---

## 2. Background & Motivation

### Current State

T language (v0.5.0-alpha) has:
- ✅ Package system with 8 standard packages
- ✅ Function registry (`packages()`, `package_info()`)
- ✅ Introspection system (`explain()`, `type()`)
- ❌ No inline documentation for functions
- ❌ No help system in REPL
- ❌ No automated documentation generation

### Why Documentation Matters for T

1. **Reproducibility**: Documentation is part of the reproducible artifact
2. **LLM Collaboration**: Structured docs improve LLM code generation
3. **Onboarding**: Lower barrier for new users (critical in alpha)
4. **API Stability**: Forces explicit design decisions
5. **Community Growth**: Essential for open-source contributions

### Inspiration from R Ecosystem

| R Tool | Purpose | T Equivalent |
|--------|---------|--------------|
| roxygen2 | Parse inline docs | `tdoc parse` |
| devtools::document() | Generate man pages | `tdoc generate` |
| ?function | REPL help | `help(function)` |
| pkgdown | Website generation | `tdoc site` (future) |

---

## 3. Design Goals

### Core Principles

1. **Minimal Syntax**: Documentation should feel like natural comments
2. **Self-Documenting**: Good defaults without excessive annotation
3. **LLM-Native**: Structured format suitable for AI consumption
4. **Reproducible**: Documentation generation is deterministic
5. **Gradual Adoption**: Works with undocumented code (graceful degradation)

### Non-Goals (for v1)

- ❌ Cross-package dependency resolution
- ❌ Interactive documentation websites
- ❌ Version-aware documentation
- ❌ Code coverage analysis
- ❌ Automatic example testing (defer to future)

---

## 4. Documentation Format

### 4.1 T-Doc Block Syntax

Documentation uses **T-Doc blocks** — structured comments prefixed with `--#`:

```t
--# Brief one-line description of the function
--#
--# Longer description with multiple paragraphs. Markdown formatting
--# is supported, including **bold**, *italic*, and `code`.
--#
--# @param arg_name Description of the parameter
--# @param another_arg Another parameter (optional: na_rm)
--# @return Description of the return value
--# @example
--#   result = my_function(data, na_rm: true)
--#   print(result)
--# @seealso other_function, related_function
--# @family data-manipulation
--# @export
function_name = \(arg_name, another_arg) {
  -- implementation
}
```

### 4.2 Supported Tags

| Tag | Purpose | Example |
|-----|---------|---------|
| `@param` | Parameter documentation | `@param x A numeric vector` |
| `@return` | Return value documentation | `@return A DataFrame with filtered rows` |
| `@example` | Usage examples (code) | `@example result = mean([1, 2, 3])` |
| `@seealso` | Related functions | `@seealso median, sd` |
| `@family` | Function grouping | `@family statistics` |
| `@export` | Mark as public API | `@export` |
| `@note` | Additional notes/warnings | `@note This function is experimental` |
| `@details` | Extended description | `@details Implementation uses Arrow...` |
| `@references` | Citations/links | `@references Wickham (2014) doi:...` |
| `@intent` | LLM usage guidance | `@intent Use for exploratory data analysis` |

### 4.3 Type Annotations (Optional)

T-Doc supports **inline type hints** for parameters:

```t
--# @param x :: Vector[Float] Input data
--# @param threshold :: Float Cutoff value
--# @return :: Bool Whether threshold was exceeded
check_threshold = \(x, threshold) {
  mean(x) > threshold
}
```

### 4.4 NA Handling Documentation

Special syntax for documenting NA behavior:

```t
--# @param na_rm :: Bool = false Remove NA values before computation
--# @na_behavior Propagates NA by default. Use na_rm: true to ignore NA.
--# @return NA if any input is NA (unless na_rm: true)
mean = \(x, na_rm: false) {
  -- implementation
}
```

### 4.5 Intent Block Integration

T-Doc integrates with T's intent blocks:

```t
--# @intent
--#   purpose: "Compute descriptive statistics for a numeric vector"
--#   use_when: "Exploring data distributions"
--#   alternatives: "Use sd() for just standard deviation"
--# @export
summary_stats = \(x) {
  intent {
    purpose: "Summarize numeric data",
    columns: ["mean", "sd", "min", "max"]
  }
  -- implementation
}
```

---

## 5. System Architecture

### 5.1 Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   T Documentation System                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │   Parser     │───▶│   Registry   │───▶│  Generator   │ │
│  │ (tdoc_parse) │    │(tdoc_registry│    │(tdoc_output) │ │
│  └──────────────┘    └──────────────┘    └──────────────┘ │
│         │                    │                    │         │
│         ▼                    ▼                    ▼         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Documentation Database                   │  │
│  │  (JSON: .tdoc/docs.json, .tdoc/index.json)          │  │
│  └──────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         REPL Integration (help())                  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Directory Structure

```
project_root/
├── package.toml                 # Package manifest (with [documentation] section)
├── src/
│   ├── packages/
│   │   ├── stats/
│   │   │   ├── mean.ml          # Source code with T-Doc blocks
│   │   │   ├── sd.ml
│   │   │   └── ...
│   │   └── ...
│   └── ...
├── .tdoc/
│   ├── docs.json                # Parsed documentation database
│   ├── index.json               # Function index
│   └── metadata.json            # Package metadata cache
├── docs/
│   ├── reference/
│   │   ├── mean.md              # Generated Markdown per function
│   │   ├── sd.md
│   │   └── index.md             # Function index
│   ├── html/                    # Generated HTML (future)
│   │   └── ...
│   └── README.md                # Package-level documentation
└── flake.nix                    # Existing Nix configuration (unchanged)
```

**Key Points:**
- 📄 **No new top-level files**: Documentation config goes in existing `package.toml`
- 📁 **`.tdoc/` cache**: Generated files (gitignored, rebuilt on demand)
- 📁 **`docs/`**: Output directory (checked into git for GitHub Pages)
- 🔒 **Nix integration**: Documentation generation respects `flake.lock` for reproducibility

### 5.3 Integration with Existing T Package System

Documentation configuration integrates seamlessly with T's existing package infrastructure:

```toml
# package.toml - Complete example showing integration

[package]
name = "stats"
version = "0.5.0"
description = "Statistical functions for T"
authors = ["T Language Team"]
license = "EUPL-1.2"
repository = "https://github.com/b-rodrigues/tlang"

# Existing package dependencies (if any)
[dependencies]
# (Future: when T supports external packages)

# NEW: Documentation configuration (optional)
[documentation]
# If not specified, defaults to sensible values
source_dir = "src/packages/stats"  # Default: "src/"
output_dir = "docs/reference"       # Default: "docs/"
format = "markdown"                 # Default: "markdown"

[documentation.generation]
include_examples = true             # Default: true
include_source_links = true         # Default: true
base_url = "https://github.com/b-rodrigues/tlang"  # Default: from git remote

[documentation.tags]
statistics = "Statistical analysis functions"
aggregation = "Data aggregation operations"

[documentation.families]
descriptive-stats = ["mean", "median", "sd", "quantile"]
correlation = ["cor", "lm"]
```

**Loading Documentation Config:**

```ocaml
(* src/tdoc/tdoc_config.ml *)

type doc_config = {
  source_dir : string;
  output_dir : string;
  format : string;
  include_examples : bool;
  include_source_links : bool;
  base_url : string option;
  tags : (string * string) list;
  families : (string * string list) list;
}

(** Load documentation config from package.toml, using defaults if not present *)
let load_config (package_file : string) : doc_config =
  if Sys.file_exists package_file then
    (* Parse TOML and extract [documentation] section *)
    parse_package_toml package_file
  else
    (* Use sensible defaults *)
    {
      source_dir = "src/";
      output_dir = "docs/";
      format = "markdown";
      include_examples = true;
      include_source_links = true;
      base_url = infer_git_remote ();
      tags = [];
      families = [];
    }
```

**Reproducibility Note:**
- Documentation generation respects `flake.lock` (Nix dependencies)
- All doc generation is deterministic (same inputs → same outputs)
- CI can verify docs are up-to-date: `t doc --parse --generate && git diff --exit-code docs/`

### 5.4 Data Model

#### Documentation Entry Schema

```json
{
  "function_name": "mean",
  "package": "stats",
  "signature": "mean(x, na_rm: false)",
  "brief": "Compute arithmetic mean of numeric values",
  "description": "Calculates the average of a numeric vector...",
  "parameters": [
    {
      "name": "x",
      "type": "Vector[Float] | List[Float]",
      "description": "Input numeric data",
      "required": true
    },
    {
      "name": "na_rm",
      "type": "Bool",
      "description": "Remove NA values before computation",
      "default": "false",
      "required": false
    }
  ],
  "returns": {
    "type": "Float | NA",
    "description": "Mean value, or NA if input contains NA and na_rm is false"
  },
  "examples": [
    "mean([1, 2, 3]) -- Returns 2.0",
    "mean([1, NA, 3], na_rm: true) -- Returns 2.0"
  ],
  "seealso": ["median", "sd", "sum"],
  "family": "statistics",
  "notes": [],
  "intent": {
    "purpose": "Compute central tendency",
    "use_when": "Summarizing numeric data"
  },
  "source_location": "src/packages/stats/mean.ml:5-25",
  "exported": true,
  "added_version": "0.5.0",
  "tags": ["statistics", "aggregation"]
}
```

---

## 6. Implementation Phases

### Phase 1: Core Infrastructure (Week 1-2)

**Goal:** Basic parsing and storage

```ocaml
(* src/tdoc/tdoc_types.ml *)
type doc_entry = {
  name : string;
  package : string;
  brief : string;
  description : string;
  parameters : param_doc list;
  returns : return_doc;
  examples : string list;
  (* ... *)
}

(* src/tdoc/tdoc_parser.ml *)
val parse_tdoc_block : string -> doc_entry option
val scan_directory : string -> doc_entry list

(* src/tdoc/tdoc_registry.ml *)
val register_doc : doc_entry -> unit
val lookup_doc : string -> doc_entry option
val save_to_json : string -> unit
val load_from_json : string -> unit
```

**Deliverables:**
- ✅ Parse T-Doc blocks from source files
- ✅ Store in JSON database (`.tdoc/docs.json`)
- ✅ Basic CLI: `t doc --parse src/`

**Testing:**
- Parse 5 example functions with various tags
- Round-trip parse → JSON → load

---

### Phase 2: Documentation Generation (Week 3)

**Goal:** Markdown output

```ocaml
(* src/tdoc/tdoc_markdown.ml *)
val generate_function_doc : doc_entry -> string
val generate_package_index : string -> string
val generate_full_reference : unit -> unit
```

**Output Format (Markdown):**

```markdown
# mean

Compute arithmetic mean of numeric values

## Signature

```t
mean(x, na_rm: false) -> Float | NA
```

## Description

Calculates the average of a numeric vector...

## Parameters

- **x** (`Vector[Float] | List[Float]`): Input numeric data
- **na_rm** (`Bool`, optional, default: `false`): Remove NA values

## Returns

`Float | NA` — Mean value, or NA if input contains NA and na_rm is false

## Examples

```t
mean([1, 2, 3])
-- Returns: 2.0

mean([1, NA, 3], na_rm: true)
-- Returns: 2.0
```

## See Also

- [`median()`](median.md)
- [`sd()`](sd.md)
- [`sum()`](sum.md)

## Family

statistics

---

*Part of the `stats` package. Added in v0.5.0*
```

**Deliverables:**
- ✅ Generate Markdown per function
- ✅ Generate package index
- ✅ CLI: `t doc --generate`

---

### Phase 3: REPL Integration (Week 4)

**Goal:** Interactive help system

**New REPL Commands:**

```t
T> help("mean")
-- Shows full documentation for mean()


T> apropos("statistics")
-- Lists all functions with "statistics" tag

T> package_help("stats")
-- Shows stats package overview
```

**Implementation:**

```ocaml
(* src/packages/core/help.ml *)
val register : Ast.environment -> Ast.environment

(* Adds help(), apropos(), package_help() functions *)
```

**Deliverables:**
- ✅ `help()` builtin function
- ✅ `apropos()` for searching
- ✅ Load docs from `.tdoc/docs.json` at startup

---

### Phase 4: Retroactive Documentation (Week 5)

**Goal:** Document all existing functions

**Strategy:**
1. **Auto-generate stubs** for undocumented functions
2. **Manual review** and enhancement
3. **LLM-assisted** documentation (optional)

**Auto-Stub Generation:**

```bash
$ t doc --stub src/packages/stats/mean.ml
# Generates:
--# TODO: Document this function
--#
--# @param x (inferred: any)
--# @return (inferred: any)
--# @export
mean = \(x, na_rm: false) { ... }
```

**Deliverables:**
- ✅ Document all 50+ standard library functions
- ✅ Package-level README.md files
- ✅ CLI: `t doc --stub` for scaffolding

---

### Phase 5: Advanced Features (Week 6+)

**Optional Enhancements:**

1. **HTML Generation** (`tdoc_html.ml`)
   - Static site generation
   - Search functionality
   - Cross-references

2. **Documentation Testing**
   - Run examples as tests
   - Verify signatures match implementation

3. **LLM Integration**
   - Export docs in LLM-friendly format
   - Intent block validation

4. **Versioning**
   - Track documentation changes
   - Generate changelogs

---

## 7. API Reference

### 7.1 CLI Tool: `t doc`

#### CLI Design Philosophy

The `t doc` command uses **flag-based operations** rather than subcommands to maintain consistency with the existing T CLI:

```bash
t run <file>          # Existing pattern
t explain <expr>      # Existing pattern
t doc --parse <dir>   # New documentation pattern (flags, not subcommands)
```

This design:
- ✅ Consistent with T's existing CLI interface
- ✅ Allows flag combinations: `t doc --parse --generate`
- ✅ Clear separation between command (`doc`) and operation (`--parse`)
- ✅ Follows common Unix flag conventions

#### Implementation in repl.ml

```ocaml
(* src/repl.ml *)
let () =
  let args = Array.to_list Sys.argv in
  let env = Eval.initial_env () in
  match args with
  | _ :: "doc" :: flags ->
      (* Handle documentation commands *)
      if List.mem "--parse" flags then cmd_doc_parse flags
      else if List.mem "--generate" flags then cmd_doc_generate flags
      else if List.mem "--stub" flags then cmd_doc_stub flags
      else if List.mem "--coverage" flags then cmd_doc_coverage flags
      else if List.mem "--serve" flags then cmd_doc_serve flags
      else if List.mem "--build" flags then cmd_doc_build flags
      else if List.mem "--help" flags then cmd_doc_help ()
      else begin
        Printf.eprintf "Unknown doc flag. Use 't doc --help' for usage.\n";
        exit 1
      end
  | _ :: "run" :: filename :: _ -> cmd_run filename env
  | (* ... existing patterns ... *)
```

#### Available Commands

```bash
# Parse documentation from source files
t doc --parse [directory]

# Generate documentation (Markdown)
t doc --generate [--format=markdown|html|json]

# Generate stub documentation
t doc --stub <file.ml>

# Check documentation coverage
t doc --coverage

# Serve documentation locally
t doc --serve [--port=8000]

# Build full documentation site
t doc --build

# Show help for doc command
t doc --help
```

#### Practical Examples

```bash
# Parse source files and generate documentation in one command
t doc --parse src/ --generate

# Parse with specific output format
t doc --parse src/packages/stats --generate --format=markdown

# Generate stubs for all undocumented functions
t doc --stub src/packages/stats/*.ml

# Check coverage and generate report
t doc --coverage --format=json > coverage_report.json

# Development workflow: parse, generate, and serve
t doc --parse --generate --serve --port=8080

# Build production documentation site
t doc --parse src/ --generate --format=html --build
```

### 7.2 Configuration: Package Manifest

Documentation configuration is integrated into the existing package manifest file (e.g., `package.toml` or `T.toml`):

#### Minimal Configuration

**Simplest possible setup** (everything else uses defaults):

```toml
# package.toml
[package]
name = "my-package"
version = "0.1.0"

# That's it! Documentation uses these defaults:
# - source_dir = "src/"
# - output_dir = "docs/"
# - format = "markdown"
# - include_examples = true
```

#### Full Configuration

**Complete example** with all options specified:

```toml
# Existing package metadata
[package]
name = "stats"
version = "0.5.0"
description = "Statistical functions for T"
authors = ["T Language Team"]
license = "EUPL-1.2"

# NEW: Documentation section added to existing package.toml
[documentation]
source_dir = "src/packages/stats"
output_dir = "docs/reference"
format = "markdown"

[documentation.generation]
include_examples = true
include_source_links = true
base_url = "https://github.com/b-rodrigues/tlang"

[documentation.tags]
# Tag definitions for organization
statistics = "Statistical analysis functions"
aggregation = "Data aggregation operations"

[documentation.families]
# Function families for grouping
descriptive-stats = ["mean", "median", "sd", "quantile"]
correlation = ["cor", "lm"]
```

**Design Rationale:**
- ✅ **No new files**: Extends existing package configuration
- ✅ **Single source of truth**: Package metadata and doc config together
- ✅ **Familiar pattern**: Matches Rust's Cargo.toml approach
- ✅ **Optional**: Documentation section is entirely optional (defaults work)
- ✅ **Progressive disclosure**: Start minimal, add details as needed

**Default Behavior (no config needed):**
If `[documentation]` section is absent, T doc uses sensible defaults:
- Source: Current directory
- Output: `./docs/`
- Format: Markdown
- Examples: Included
- Base URL: Inferred from git remote

### 7.3 T Functions

```t
-- Get documentation for a function
help("mean") -> Dict

-- Search for functions by keyword
apropos("statistics") -> List[String]

-- Get package documentation
package_help("stats") -> Dict

-- Check if function is documented
is_documented("mean") -> Bool

-- Get all exported functions
exports("stats") -> List[String]
```

---

## 8. Examples

### Example 1: Documenting a Simple Function

**Before (current):**

```t
-- src/packages/stats/mean.ml
let register env =
  Env.add "mean"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VList items] -> (* implementation *)
```

**After (with T-Doc):**

```t
--# Compute arithmetic mean of numeric values
--#
--# The mean is the sum of values divided by the count. This function
--# handles NA values explicitly through the na_rm parameter.
--#
--# @param x :: Vector[Float] | List[Float]
--#   Input numeric data. Must contain at least one value.
--#
--# @param na_rm :: Bool = false
--#   Remove NA values before computation. If false (default),
--#   any NA in the input causes the result to be NA.
--#
--# @return :: Float | NA
--#   The arithmetic mean, or NA if input contains NA and na_rm is false
--#
--# @example
--#   mean([1, 2, 3])
--#   -- Returns: 2.0
--#
--#   mean([1, NA, 3], na_rm: true)
--#   -- Returns: 2.0
--#
--#   mean([1, NA, 3], na_rm: false)
--#   -- Returns: NA
--#
--# @seealso median, sd, sum
--# @family descriptive-statistics
--# @intent
--#   purpose: "Compute central tendency of numeric data"
--#   use_when: "Summarizing distributions or comparing groups"
--#   alternatives: "Use median() for robust center; sd() for spread"
--# @export
let register env =
  Env.add "mean"
    (make_builtin_named ~variadic:true 1 (fun named_args _env ->
      (* implementation unchanged *)
```

### Example 2: DataFrame Function Documentation

```t
--# Filter DataFrame rows based on a predicate
--#
--# Applies a boolean predicate to each row, keeping only rows
--# where the predicate returns true. The predicate receives a
--# Dict representation of each row.
--#
--# @param df :: DataFrame
--#   Input DataFrame to filter
--#
--# @param predicate :: Function(Dict -> Bool)
--#   Predicate function applied to each row. Receives a Dict
--#   with column names as keys. Must return Bool.
--#   Supports NSE: \(row) row.age > 30 or \(row) $age > 30
--#
--# @return :: DataFrame
--#   Filtered DataFrame with rows where predicate is true.
--#   Preserves grouping keys if input is grouped.
--#
--# @details
--#   ## Performance Notes
--#   - Simple predicates (\(row) row.col > scalar) are vectorized
--#   - Complex predicates fall back to row-by-row evaluation
--#   - Use arrange() after filter() for sorted results
--#
--# @example
--#   # Filter numeric threshold
--#   df |> filter(\(row) row.age > 30)
--#
--#   # Filter with multiple conditions
--#   df |> filter(\(row) row.age > 30 and row.salary < 100000)
--#
--#   # Filter using NSE (Non-Standard Evaluation)
--#   df |> filter(\(row) $age > 30)
--#
--# @seealso select, mutate, arrange
--# @family colcraft
--# @note Errors propagate: if predicate returns Error, filter() fails
--# @export
let register ~eval_call ~eval_expr ~uses_nse ~desugar_nse_expr env =
  (* implementation *)
```

### Example 3: Package-Level Documentation

```t
--# Statistical Functions Package
--#
--# @package stats
--# @description
--#   Provides statistical summaries and linear models for
--#   numeric data analysis in T.
--#
--# @details
--#   ## Included Functions
--#   - Descriptive: mean, median, sd, quantile
--#   - Correlation: cor
--#   - Modeling: lm (simple linear regression)
--#   - Extremes: min, max
--#
--#   ## Design Philosophy
--#   - NA handling is explicit (na_rm parameter)
--#   - Functions work on Vectors and Lists
--#   - Arrow-backed for performance
--#
--# @examples
--#   # Basic statistics
--#   x = [1, 2, 3, 4, 5]
--#   mean(x)  -- 3.0
--#   sd(x)    -- 1.58
--#
--#   # Linear regression
--#   df = read_csv("data.csv")
--#   model = lm(data: df, formula: y ~ x)
--#
--# @references
--#   - Wickham, H. (2014). Tidy Data. JSS.
--#   - Pedregosa et al. (2011). Scikit-learn. JMLR.
--#
--# @version 0.5.0
--# @license EUPL-1.2
```

---

## 9. Migration Path

### 9.1 Backward Compatibility

- **No breaking changes** to existing code
- Documentation is **opt-in** via T-Doc blocks
- Undocumented functions work exactly as before
- REPL `help()` shows "No documentation available" gracefully
- **Works without package.toml**: Sensible defaults are used
- **Incremental adoption**: Add `[documentation]` section when ready

### 9.2 Configuration Migration

**For projects without package.toml:**
```bash
# Works immediately with defaults
$ t doc --parse src/
# Uses: source_dir="src/", output_dir="docs/", format="markdown"
```

**For projects with existing package.toml:**
```bash
# Add [documentation] section to existing file
$ cat >> package.toml << 'EOF'

[documentation]
source_dir = "src/packages/stats"
output_dir = "docs/reference"
EOF

$ t doc --parse --generate
# Uses config from package.toml
```

**Creating package.toml from scratch:**
```bash
$ t doc --init
# Generates basic package.toml with sensible defaults
# (Alternative: create manually)
```

### 9.3 Phased Rollout

1. **v0.6.0**: Core infrastructure + 5 pilot functions documented
2. **v0.6.1**: All `core` and `stats` packages documented
3. **v0.7.0**: All standard library documented + HTML generation
4. **v1.0.0**: Documentation system considered stable API

### 9.4 Community Contributions

**Documentation-First PRs:**
- New functions **must** include T-Doc blocks
- CI checks enforce documentation coverage > 80%
- Documentation PRs welcome (no code knowledge required)

---

## 10. Future Considerations

### 10.1 Interactive Documentation

```t
-- Future: Live examples in documentation
T> help(mean)
[Show documentation with runnable examples]

T> [Run Example 1]  # Button in enhanced REPL
mean([1, 2, 3])
-- Returns: 2.0
```

### 10.2 LLM Integration

**Documentation as Training Data:**
- Export T-Doc to JSON for LLM fine-tuning
- Intent blocks guide LLM code generation
- Example-based few-shot learning

**LLM-Generated Documentation:**
```bash
$ t doc --generate --llm
# Uses Claude/GPT to draft documentation from signatures
# Human review required before commit
```

### 10.3 Docstrings vs. Separate Files

**Current Design:** T-Doc blocks embedded in source

**Future Option:** Separate `.tdoc` files

```
src/packages/stats/
├── mean.ml           # Implementation
└── mean.tdoc         # Documentation (optional)
```

**Trade-offs:**
- ✅ Cleaner source files
- ✅ Non-programmers can contribute docs
- ❌ Synchronization risk
- ❌ More files to manage

**Decision:** Start with embedded, add separate files if demand exists

### 10.4 Internationalization

```t
--# @lang en
--# Compute arithmetic mean
--#
--# @lang fr
--# Calculer la moyenne arithmétique
```

---

## Appendix A: Implementation Checklist

### Phase 1: Core Infrastructure
- [ ] Create `src/tdoc/` directory
- [ ] Implement `tdoc_types.ml` (data structures)
- [ ] Implement `tdoc_parser.ml` (T-Doc block parser)
- [ ] Implement `tdoc_registry.ml` (JSON storage)
- [ ] Implement `tdoc_config.ml` (load config from package.toml)
- [ ] Add `t doc --parse` CLI command
- [ ] Write unit tests for parser
- [ ] Document 3 pilot functions (mean, filter, read_csv)
- [ ] Test with and without package.toml (defaults should work)

### Phase 2: Generation
- [ ] Implement `tdoc_markdown.ml`
- [ ] Generate function-level Markdown
- [ ] Generate package index
- [ ] Add `t doc --generate` CLI command
- [ ] Add cross-references between functions
- [ ] Test with existing pilot functions

### Phase 3: REPL
- [ ] Implement `help()` builtin
- [ ] Implement `apropos()` search
- [ ] Load `.tdoc/docs.json` at REPL startup
- [ ] Pretty-print help output
- [ ] Test interactive workflows

### Phase 4: Retroactive Documentation
- [ ] Audit all 50+ functions
- [ ] Generate auto-stubs
- [ ] Manually enhance 20 most-used functions
- [ ] Write package-level docs
- [ ] Add examples to critical functions
- [ ] Code review by core team

### Phase 5: Polish
- [ ] HTML generation (optional)
- [ ] Documentation website
- [ ] Example testing
- [ ] CI integration
- [ ] Coverage reporting
- [ ] User guide

---

## Appendix B: Example Output

### Generated Markdown (Fragment)

````markdown
# T Language Reference — Stats Package

## mean

**Signature:** `mean(x, na_rm: false) -> Float | NA`

Compute arithmetic mean of numeric values.

**Parameters:**
- `x` (`Vector[Float] | List[Float]`): Input numeric data
- `na_rm` (`Bool`, optional): Remove NA values (default: `false`)

**Returns:** Mean value, or NA if input contains NA

**Examples:**
```t
mean([1, 2, 3])
-- 2.0
```

**See Also:** [median](median.md), [sd](sd.md)

---

## median

...
````

---

## Appendix C: Related Work

| Language | Tool | T Equivalent | Status |
|----------|------|--------------|--------|
| R | roxygen2 | T-Doc parser | ✅ Spec |
| Python | Sphinx | tdoc_html | 🔮 Future |
| Rust | rustdoc | tdoc_markdown | ✅ Spec |
| Julia | Documenter.jl | help() system | ✅ Spec |
| Elixir | ExDoc | tdoc site | 🔮 Future |

---

## Appendix D: Success Metrics

**Phase 1 (Core):**
- [ ] Parse 100% of T-Doc blocks without errors
- [ ] Round-trip fidelity (parse → JSON → load) = 100%

**Phase 2 (Generation):**
- [ ] Generate valid Markdown for all documented functions
- [ ] Cross-references resolve correctly

**Phase 3 (REPL):**
- [ ] `help()` response time < 50ms
- [ ] Help output fits in 80-column terminal

**Phase 4 (Coverage):**
- [ ] 100% of exported functions documented
- [ ] 80% of functions have examples
- [ ] All packages have README

**User Adoption:**
- [ ] 50% of new functions include T-Doc blocks (6 months)
- [ ] 10+ community documentation PRs (12 months)

---
I'll add a comprehensive phased implementation plan with checkboxes at the end of the document. Let me create this addition:

---

## Appendix E: Phased Implementation Plan

### Overview

This implementation plan breaks down the T documentation system into **6 phases** over approximately **8-10 weeks**. Each phase builds on the previous one and includes concrete deliverables with checkboxes for tracking progress.

**Timeline Summary:**
- **Phase 0:** Foundation & Setup (Week 1) — 5 days
- **Phase 1:** Core Parser Infrastructure (Week 1-2) — 7 days  
- **Phase 2:** Markdown Generation (Week 2-3) — 5 days
- **Phase 3:** REPL Integration (Week 3-4) — 7 days
- **Phase 4:** Standard Library Documentation (Week 4-6) — 10 days
- **Phase 5:** Advanced Features & Polish (Week 6-8+) — 10+ days

---

### Phase 0: Foundation & Setup (Week 1 — 5 days)

**Goal:** Establish project structure and tooling
prepare what is needed to document the included packages
with T (colcraft for example)

**Tasks:**

#### Project Structure
- [ ] Create `src/tdoc/` directory in T repository
- [ ] Create `.tdoc/` directory structure for caching
- [ ] Add `.tdoc/` to `.gitignore` (build artifacts)
- [ ] Create `docs/` directory for output
- [ ] Set up `docs/.gitkeep` to track directory in git

#### Configuration System
- [ ] Design `[documentation]` section for `package.toml` schema
- [ ] Implement `tdoc_config.ml` module
- [ ] Add default configuration fallbacks
- [ ] Write configuration loader with TOML parser
- [ ] Test config loading with/without `package.toml`

#### Development Environment
- [ ] Add tdoc modules to T's `dune` build file
- [ ] Set up unit test framework for tdoc
- [ ] Configure CI to run tdoc tests
- [ ] Document tdoc architecture in `docs/ARCHITECTURE.md`

**Success Criteria:**
- ✅ `src/tdoc/` directory exists with proper structure
- ✅ Configuration loads from `package.toml` or uses defaults
- ✅ Build system compiles tdoc modules
- ✅ Basic test suite runs successfully

**Estimated Time:** 5 days (1 week)

---

### Phase 1: Core Parser Infrastructure (Week 1-2 — 7 days)

**Goal:** Parse T-Doc blocks from source files and store in JSON

**Tasks:**

#### Data Model
- [ ] Define `tdoc_types.ml` with core types:
  - [ ] `doc_entry` type
  - [ ] `param_doc` type
  - [ ] `return_doc` type
  - [ ] `intent_block` type
- [ ] Add JSON serialization functions
- [ ] Add JSON deserialization functions
- [ ] Write round-trip tests (data → JSON → data)

#### Parser Implementation
- [ ] Create `tdoc_parser.ml` module
- [ ] Implement comment block scanner (`--#` prefix detection)
- [ ] Parse brief description (first line)
- [ ] Parse extended description (multiline)
- [ ] Parse `@param` tags with types
- [ ] Parse `@return` tags
- [ ] Parse `@example` blocks (preserve code)
- [ ] Parse `@seealso` tags
- [ ] Parse `@family` tags
- [ ] Parse `@export` flag
- [ ] Parse `@intent` blocks
- [ ] Parse optional tags (`@note`, `@details`, `@references`)

#### Registry System
- [ ] Create `tdoc_registry.ml` module
- [ ] Implement in-memory doc storage (hash table)
- [ ] Implement `register_doc : doc_entry -> unit`
- [ ] Implement `lookup_doc : string -> doc_entry option`
- [ ] Implement `save_to_json : string -> unit`
- [ ] Implement `load_from_json : string -> unit`
- [ ] Add package-level indexing
- [ ] Add tag-based search functionality

#### CLI Integration
- [ ] Add `doc` command to `src/repl.ml`
- [ ] Implement `--parse` flag handler
- [ ] Implement directory scanning (recursive)
- [ ] Add progress indicator for parsing
- [ ] Add error reporting for malformed docs
- [ ] Implement `--help` flag for doc command

#### Testing
- [ ] Write unit tests for parser (10+ test cases)
- [ ] Test parsing valid T-Doc blocks
- [ ] Test handling of malformed blocks
- [ ] Test multi-file parsing
- [ ] Test JSON round-trip for all fields
- [ ] Create 3 pilot documented functions:
  - [ ] `mean` in `src/packages/stats/mean.ml`
  - [ ] `filter` in `src/packages/colcraft/filter.ml`
  - [ ] `read_csv` in `src/packages/tables/csv.ml`

**Success Criteria:**
- ✅ Parser successfully extracts all T-Doc tags
- ✅ 100% of pilot functions parse correctly
- ✅ JSON storage/loading works without data loss
- ✅ `t doc --parse src/` completes successfully
- ✅ Unit tests achieve >90% code coverage

**Estimated Time:** 7 days (1.5 weeks)

---

### Phase 2: Markdown Generation (Week 2-3 — 5 days)

**Goal:** Generate human-readable Markdown documentation

**Tasks:**

#### Markdown Generator
- [ ] Create `tdoc_markdown.ml` module
- [ ] Implement function doc template
- [ ] Format function signature nicely
- [ ] Format parameter tables
- [ ] Format return value section
- [ ] Format examples with syntax highlighting markers
- [ ] Generate "See Also" links
- [ ] Generate family grouping
- [ ] Add source location links (GitHub URLs)
- [ ] Add metadata footer (version, package)

#### Index Generation
- [ ] Implement package index generator
- [ ] Create alphabetical function listing
- [ ] Create family-based grouping
- [ ] Create tag-based filtering
- [ ] Generate table of contents
- [ ] Add search-friendly structure

#### File Output
- [ ] Create `docs/reference/` directory structure
- [ ] Implement per-function Markdown file generation
- [ ] Implement package `index.md` generation
- [ ] Add cross-reference link resolution
- [ ] Implement incremental generation (only changed files)

#### CLI Integration
- [ ] Implement `--generate` flag handler
- [ ] Add `--format` flag (markdown/html/json)
- [ ] Add `--output` flag for custom directory
- [ ] Implement combined `--parse --generate` workflow
- [ ] Add dry-run mode (`--dry-run`)

#### Testing
- [ ] Test Markdown output formatting
- [ ] Test cross-reference link generation
- [ ] Test index generation
- [ ] Test incremental updates
- [ ] Validate Markdown syntax with linter
- [ ] Generate docs for pilot functions
- [ ] Manual review of generated docs

**Success Criteria:**
- ✅ Generated Markdown is valid and readable
- ✅ All cross-references resolve correctly
- ✅ Package index lists all functions
- ✅ `t doc --parse --generate` produces complete docs
- ✅ Generated docs render correctly on GitHub

**Estimated Time:** 5 days (1 week)

---

### Phase 3: REPL Integration (Week 3-4 — 7 days)

**Goal:** Interactive help system in T REPL

**Tasks:**

#### Help System Core
- [ ] Create `src/packages/core/help.ml` module
- [ ] Implement `help()` builtin function
- [ ] Load `.tdoc/docs.json` at REPL startup
- [ ] Implement doc lookup by function name
- [ ] Implement graceful handling of undocumented functions
- [ ] Add caching for fast repeated lookups

#### Search Functionality
- [ ] Implement `apropos()` function (keyword search)
- [ ] Search across function names
- [ ] Search across descriptions
- [ ] Search across tags
- [ ] Rank search results by relevance

#### Package Help
- [ ] Implement `package_help()` function
- [ ] Show package overview
- [ ] List all exported functions
- [ ] Show package metadata
- [ ] Display example usage

#### REPL Syntax Sugar
- [ ] Add syntax highlighting for help output
- [ ] Add pagination for long help text
- [ ] Implement "Press Enter to continue" for examples

#### Pretty Printing
- [ ] Format help output for 80-column terminal
- [ ] Use colors/bold for section headers (if TTY)
- [ ] Add horizontal rules between sections
- [ ] Format code examples with indentation
- [ ] Add "See Also" links at bottom

#### CLI Integration
- [ ] Register help functions in `initial_env()`
- [ ] Update REPL welcome message with help tips
- [ ] Add REPL command `.help` as alias
- [ ] Implement `.apropos` REPL command

#### Testing
- [ ] Test `help()` for documented functions
- [ ] Test `help()` for undocumented functions
- [ ] Test `apropos()` search
- [ ] Test `package_help()` display
- [ ] Test output formatting in different terminal sizes
- [ ] Integration test: full REPL workflow

**Success Criteria:**
- ✅ `help("mean")` displays complete documentation
- ✅ `apropos("stats")` returns relevant functions
- ✅ Help loads in <50ms
- ✅ Output fits in standard terminal width
- ✅ Undocumented functions show helpful message

**Estimated Time:** 7 days (1.5 weeks)

---

### Phase 4: Standard Library Documentation (Week 4-6 — 10 days)

**Goal:** Document all functions in T's standard library

**Tasks:**

#### Documentation Audit
- [ ] List all functions in standard library (50+ functions)
- [ ] Categorize by package:
  - [ ] `core` package (10 functions)
  - [ ] `stats` package (8 functions)
  - [ ] `colcraft` package (15 functions)
  - [ ] `tables` package (5 functions)
  - [ ] `plots` package (6 functions)
  - [ ] `strings` package (8 functions)
  - [ ] `pipelines` package (3 functions)
  - [ ] `introspection` package (5 functions)
- [ ] Prioritize by usage frequency (top 20 first)

#### Auto-Stub Generation
- [ ] Implement `--stub` CLI flag
- [ ] Generate stub T-Doc blocks from signatures
- [ ] Infer parameter types from implementation
- [ ] Add TODO comments for manual enhancement
- [ ] Generate stubs for all undocumented functions

#### Manual Documentation (Core Package)
- [ ] Document `print()` with examples
- [ ] Document `assert()` with error handling
- [ ] Document `type()` with all type examples
- [ ] Document `length()` for lists/strings
- [ ] Document `range()` with step examples
- [ ] Document `map()` with lambda examples
- [ ] Document `filter()` with predicate examples
- [ ] Document `reduce()` with accumulator examples
- [ ] Document `zip()` with multiple lists
- [ ] Document `enumerate()` with index examples

#### Manual Documentation (Stats Package)
- [ ] Document `mean()` with NA handling
- [ ] Document `median()` with even/odd cases
- [ ] Document `sd()` with population vs sample
- [ ] Document `quantile()` with percentile examples
- [ ] Document `min()` and `max()` with edge cases
- [ ] Document `sum()` with NA propagation
- [ ] Document `cor()` with correlation types
- [ ] Document `lm()` with formula syntax

#### Manual Documentation (Colcraft Package)
- [ ] Document `filter()` with NSE examples
- [ ] Document `select()` with column syntax
- [ ] Document `mutate()` with transformation examples
- [ ] Document `summarize()` with grouping
- [ ] Document `group_by()` with multiple keys
- [ ] Document `arrange()` with sorting
- [ ] Document `left_join()` with key examples
- [ ] Document `distinct()` with unique rows
- [ ] Document `rename()` with column mapping
- [ ] Document `pivot_longer()` and `pivot_wider()`

#### Manual Documentation (Tables Package)
- [ ] Document `read_csv()` with options
- [ ] Document `write_csv()` with formatting
- [ ] Document `read_parquet()` with Arrow integration
- [ ] Document `write_parquet()` with compression
- [ ] Document `show()` with display options

#### Manual Documentation (Other Packages)
- [ ] Document plotting functions (`plot()`, `ggplot()`)
- [ ] Document string functions (`str_split()`, `str_replace()`)
- [ ] Document pipeline operators (`|>`, `|=>`)
- [ ] Document introspection functions (`explain()`, `packages()`)

#### Package-Level Documentation
- [ ] Write `docs/packages/core.md`
- [ ] Write `docs/packages/stats.md`
- [ ] Write `docs/packages/colcraft.md`
- [ ] Write `docs/packages/tables.md`
- [ ] Write `docs/packages/plots.md`
- [ ] Write `docs/packages/strings.md`
- [ ] Write `docs/packages/pipelines.md`
- [ ] Write `docs/packages/introspection.md`

#### Quality Assurance
- [ ] Review all documentation for clarity
- [ ] Ensure all examples run successfully
- [ ] Check cross-references resolve
- [ ] Verify parameter types are accurate
- [ ] Add intent blocks to top 20 functions
- [ ] Peer review by core team
- [ ] User testing with newcomers (5 people)

#### Coverage Reporting
- [ ] Implement `--coverage` CLI flag
- [ ] Report documented vs total functions
- [ ] Report functions with examples
- [ ] Report functions with intent blocks
- [ ] Generate coverage badge for README

**Success Criteria:**
- ✅ 100% of exported functions have T-Doc blocks
- ✅ 80% of functions have runnable examples
- ✅ 50% of functions have intent blocks
- ✅ All cross-references resolve correctly
- ✅ Coverage report shows >95% documentation
- ✅ User testing shows improved onboarding experience

**Estimated Time:** 10 days (2 weeks)

---

### Phase 5: Advanced Features & Polish (Week 6-8+ — 10+ days)

**Goal:** Production-ready documentation system

**Tasks:**

#### HTML Generation (Optional)
- [ ] Create `tdoc_html.ml` module
- [ ] Design HTML template with CSS
- [ ] Implement static site generation
- [ ] Add client-side search functionality (JavaScript)
- [ ] Generate navigation sidebar
- [ ] Add syntax highlighting for code blocks
- [ ] Support dark/light theme toggle
- [ ] Generate sitemap and RSS feed
- [ ] Implement `--format html` flag

#### Documentation Testing
- [ ] Create `tdoc_test.ml` module
- [ ] Extract examples from T-Doc blocks
- [ ] Run examples as integration tests
- [ ] Verify output matches documented behavior
- [ ] Report test failures with context
- [ ] Add `--test` CLI flag
- [ ] Integrate with CI pipeline

#### LLM Integration
- [ ] Export docs to JSON-LD format
- [ ] Add structured data for LLM training
- [ ] Implement intent block validation
- [ ] Create LLM-friendly API reference
- [ ] Generate few-shot examples for code generation

#### Documentation Website
- [ ] Set up GitHub Pages deployment
- [ ] Create landing page (`docs/index.html`)
- [ ] Add "Getting Started" guide
- [ ] Add "API Reference" section
- [ ] Add search functionality
- [ ] Add version selector (future-proofing)
- [ ] Configure custom domain (if available)

#### CLI Polish
- [ ] Add progress bars for long operations
- [ ] Improve error messages with suggestions
- [ ] Add color output for better UX
- [ ] Implement `--quiet` and `--verbose` flags
- [ ] Add `--watch` mode for live regeneration
- [ ] Add `--serve` mode for local preview

#### CI/CD Integration
- [ ] Add documentation generation to CI
- [ ] Fail CI if docs are out of date
- [ ] Auto-deploy docs on release tags
- [ ] Generate coverage report in CI
- [ ] Add pre-commit hook for doc validation

#### Performance Optimization
- [ ] Profile doc generation speed
- [ ] Implement parallel parsing (if needed)
- [ ] Add caching for incremental builds
- [ ] Optimize JSON serialization
- [ ] Benchmark: parse + generate in <5s for stdlib

#### Community Tools
- [ ] Create documentation contribution guide
- [ ] Add "Edit on GitHub" links in docs
- [ ] Create doc review checklist for PRs
- [ ] Set up automated doc quality checks
- [ ] Create documentation style guide

#### Versioning System (Future)
- [ ] Design version-aware documentation
- [ ] Track documentation changes across versions
- [ ] Generate changelog from doc updates
- [ ] Implement `@since` tag version tracking
- [ ] Add deprecation warnings

**Success Criteria:**
- ✅ HTML docs generated and deployable
- ✅ Example tests pass for all documented functions
- ✅ Documentation website is live
- ✅ CI enforces documentation requirements
- ✅ Parse + generate completes in <5 seconds
- ✅ Community contributors can submit doc PRs

**Estimated Time:** 10+ days (2+ weeks, ongoing)

---

### Phase 6: Maintenance & Future Work (Ongoing)

**Goal:** Keep documentation system healthy and evolving

**Ongoing Tasks:**

#### Documentation Maintenance
- [ ] Review documentation for accuracy (monthly)
- [ ] Update examples when API changes
- [ ] Add documentation for new features
- [ ] Respond to documentation issues/PRs
- [ ] Update package-level docs as packages evolve

#### Community Engagement
- [ ] Respond to documentation questions
- [ ] Mentor new contributors on writing docs
- [ ] Feature high-quality doc contributions
- [ ] Collect feedback on help system UX
- [ ] Run documentation sprints (quarterly)

#### Feature Requests (Backlog)
- [ ] Internationalization support (i18n)
- [ ] Video tutorials integration
- [ ] Interactive code playgrounds
- [ ] Documentation analytics
- [ ] API stability tracking
- [ ] Automated doc quality scoring

#### Performance Monitoring
- [ ] Track doc generation time
- [ ] Monitor help system latency
- [ ] Profile memory usage
- [ ] Optimize bottlenecks
- [ ] Add performance benchmarks to CI

**Success Criteria:**
- ✅ Documentation stays up-to-date with code
- ✅ Community actively contributes docs
- ✅ Doc system scales to 500+ functions
- ✅ Users rate help system as "excellent" (surveys)

---

## Summary Progress Tracker

### Quick Status Overview

**Phase 0: Foundation** ⬜ Not Started / 🟡 In Progress / ✅ Complete
- [ ] Project structure
- [ ] Configuration system  
- [ ] Development environment

**Phase 1: Core Parser** ⬜
- [ ] Data model
- [ ] Parser implementation
- [ ] Registry system
- [ ] CLI integration
- [ ] Testing with pilot functions

**Phase 2: Markdown Generation** ⬜
- [ ] Markdown generator
- [ ] Index generation
- [ ] File output
- [ ] CLI integration
- [ ] Testing

**Phase 3: REPL Integration** ⬜
- [ ] Help system core
- [ ] Search functionality
- [ ] REPL syntax sugar
- [ ] Pretty printing
- [ ] Testing

**Phase 4: Standard Library Docs** ⬜
- [ ] Documentation audit
- [ ] Core package (10 functions)
- [ ] Stats package (8 functions)
- [ ] Colcraft package (15 functions)
- [ ] Other packages (17 functions)
- [ ] Package-level docs
- [ ] Quality assurance
- [ ] Coverage reporting

**Phase 5: Advanced Features** ⬜
- [ ] HTML generation
- [ ] Documentation testing
- [ ] LLM integration
- [ ] Documentation website
- [ ] CI/CD integration
- [ ] Performance optimization
- [ ] Community tools

**Phase 6: Maintenance** ⬜
- [ ] Ongoing documentation updates
- [ ] Community engagement
- [ ] Feature requests (backlog)
- [ ] Performance monitoring

---

### Milestone Checklist

**v0.6.0-alpha (Weeks 1-4):**
- [ ] T-Doc parser complete
- [ ] Markdown generation working
- [ ] REPL help system functional
- [ ] 5 pilot functions documented
- [ ] Documentation for core team review

**v0.6.0-beta (Weeks 5-6):**
- [ ] All standard library functions documented
- [ ] Package-level documentation complete
- [ ] Coverage >95%
- [ ] User testing with 5 external users
- [ ] Feedback incorporated

**v0.7.0 (Weeks 7-8):**
- [ ] HTML documentation generated
- [ ] Documentation website deployed
- [ ] CI integration complete
- [ ] Example testing functional
- [ ] Public announcement ready

**v1.0.0 (Future):**
- [ ] Documentation system stable API
- [ ] 500+ functions documented
- [ ] Community actively contributing
- [ ] Performance benchmarks met
- [ ] Documentation considered feature-complete

---

### Weekly Progress Tracking Template

**Week [N] — [Date Range]**

**Phase:** [Current Phase Name]

**Completed This Week:**
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3

**Blockers:**
- [List any impediments]

**Next Week:**
- [ ] Task 4
- [ ] Task 5
- [ ] Task 6

**Notes:**
[Any important observations or decisions]

---

## Getting Started

To begin implementation:

1. **Create a GitHub project board** with these phases as columns
2. **Convert checkboxes to GitHub issues** for tracking
3. **Assign team members** to specific phases
4. **Set up weekly sync meetings** to review progress
5. **Update this document** as phases are completed

**First Action Item:**
```bash
# Create the project structure
$ mkdir -p src/tdoc .tdoc docs/reference
$ touch src/tdoc/tdoc_types.ml
$ git add src/tdoc .tdoc docs
$ git commit -m "Phase 0: Initialize T documentation system"
```

---

**Document Status:** Ready for Implementation  
**Last Updated:** 2026-02-11  
**Next Review:** After Phase 1 Completion


You're absolutely right! The implementation plan only covers the **documentation system** but completely ignores implementing the **package management system itself** (the `t init package`, `t init project`, `t install` commands, etc.). 

Let me add that missing implementation plan:

---

## Appendix F: Package Management System Implementation Plan

### Overview

This plan covers implementing T's **package management features** (separate from but coordinated with the documentation system). These can be developed in parallel with the documentation system.

**Timeline Summary:**
- **Phase A:** Project/Package Scaffolding (Week 1-2) — 7 days
- **Phase B:** Dependency Management (Week 2-3) — 7 days
- **Phase C:** Package Testing & Validation (Week 3-4) — 5 days
- **Phase D:** Publishing & Release Workflow (Week 4-5) — 5 days
- **Phase E:** Integration & Polish (Week 5-6) — 5 days

---

### Phase A: Project/Package Scaffolding (Week 1-2 — 7 days)

**Goal:** Implement `t init package` and `t init project` commands

**Tasks:**

#### Core Infrastructure
- [ ] Create `src/package_manager/` directory
- [ ] Create `src/package_manager/templates/` for file templates
- [ ] Define package structure types in `package_types.ml`
- [ ] Implement TOML generation utilities
- [ ] Implement Nix flake generation utilities

#### `t init package` Command
- [ ] Add `init` command handler to `src/repl.ml`
- [ ] Implement package name validation (lowercase, hyphens)
- [ ] Create directory structure generator
- [ ] Generate `DESCRIPTION.toml` from template
- [ ] Generate `flake.nix` for packages
- [ ] Generate `README.md` template
- [ ] Generate `LICENSE` file (EUPL-1.2 default)
- [ ] Generate `CHANGELOG.md` template
- [ ] Create `src/`, `tests/`, `examples/`, `docs/` directories
- [ ] Generate `.gitignore` for T packages
- [ ] Initialize git repository (optional flag)
- [ ] Add welcome message with next steps

#### `t init project` Command
- [ ] Implement project name validation
- [ ] Create project directory structure
- [ ] Generate `tproject.toml` from template
- [ ] Generate project `flake.nix` with:
  - [ ] nixpkgs input (date-pinned)
  - [ ] t-lang input
  - [ ] cachix configuration
  - [ ] devShells.default
  - [ ] shellHook with instructions
- [ ] Generate `README.md` for projects
- [ ] Create `src/`, `data/`, `outputs/`, `tests/` directories
- [ ] Generate project-specific `.gitignore`
- [ ] Initialize git repository (optional flag)

#### Template System
- [ ] Create `templates/package/DESCRIPTION.toml.template`
- [ ] Create `templates/package/flake.nix.template`
- [ ] Create `templates/package/README.md.template`
- [ ] Create `templates/package/CHANGELOG.md.template`
- [ ] Create `templates/project/tproject.toml.template`
- [ ] Create `templates/project/flake.nix.template`
- [ ] Create `templates/project/README.md.template`
- [ ] Create `templates/.gitignore.template`
- [ ] Implement template variable substitution (name, date, author)

#### CLI Options
- [ ] Add `--name` flag for package/project name
- [ ] Add `--author` flag for author information
- [ ] Add `--license` flag (default EUPL-1.2)
- [ ] Add `--no-git` flag to skip git init
- [ ] Add `--force` flag to overwrite existing directory
- [ ] Implement interactive mode (prompt for options)

#### Testing
- [ ] Test `t init package my-pkg` creates correct structure
- [ ] Test `t init project my-project` creates correct structure
- [ ] Test template substitution works correctly
- [ ] Test git initialization
- [ ] Test error handling for existing directories
- [ ] Test TOML generation is valid
- [ ] Test Nix flake generation is valid
- [ ] Integration test: init → nix develop succeeds

**Success Criteria:**
- ✅ `t init package foo` creates valid package structure
- ✅ `t init project bar` creates valid project structure
- ✅ Generated flake.nix can be evaluated by Nix
- ✅ Generated DESCRIPTION.toml/tproject.toml are valid
- ✅ `nix develop` works in initialized packages/projects

**Estimated Time:** 7 days (1.5 weeks)

---

### Phase B: Dependency Management (Week 2-3 — 7 days)

**Goal:** Implement `t install` for dependency management

**Tasks:**

#### TOML Parser Integration
- [ ] Add TOML parsing library to T's dependencies
- [ ] Create `toml_parser.ml` module
- [ ] Implement `parse_tproject_toml : string -> project_config`
- [ ] Implement `parse_description_toml : string -> package_config`
- [ ] Add validation for required fields
- [ ] Add validation for dependency format
- [ ] Handle parsing errors gracefully

#### Flake.nix Manipulation
- [ ] Create `nix_generator.ml` module
- [ ] Implement Nix expression AST (simplified)
- [ ] Parse existing flake.nix (extract inputs section)
- [ ] Generate new inputs from tproject.toml dependencies
- [ ] Merge user inputs with generated inputs
- [ ] Update tPackages list in outputs
- [ ] Preserve user modifications in flake.nix
- [ ] Format generated Nix code (indentation, comments)

#### `t install` Command (Basic)
- [ ] Add `install` command handler to `src/repl.ml`
- [ ] Read `tproject.toml` from current directory
- [ ] Extract `[dependencies]` section
- [ ] Validate git URLs and tags
- [ ] Generate flake inputs for each dependency
- [ ] Update `flake.nix` in place (backup original)
- [ ] Print summary of changes
- [ ] Suggest running `nix flake lock`

#### Dependency Resolution
- [ ] Validate git URLs are accessible
- [ ] Check that tags exist on remote
- [ ] Detect circular dependencies (warn)
- [ ] Validate package names are unique
- [ ] Handle transitive dependencies (document, don't resolve)

#### Git Integration
- [ ] Use libgit2 bindings or shell out to git
- [ ] Implement `check_git_tag_exists : url -> tag -> bool`
- [ ] Implement `get_git_remote : unit -> string option`
- [ ] Add `--check` flag to validate dependencies without updating

#### Error Handling
- [ ] Clear error messages for missing tproject.toml
- [ ] Clear error messages for invalid TOML syntax
- [ ] Clear error messages for malformed git URLs
- [ ] Clear error messages for non-existent tags
- [ ] Suggest fixes for common mistakes
- [ ] Add dry-run mode (`--dry-run`)

#### Testing
- [ ] Test parsing valid tproject.toml
- [ ] Test parsing invalid TOML (error handling)
- [ ] Test flake.nix generation
- [ ] Test updating existing flake.nix
- [ ] Test dependency validation
- [ ] Integration test: install → nix develop → package available
- [ ] Test with circular dependencies
- [ ] Test with invalid git URLs

**Success Criteria:**
- ✅ `t install` reads tproject.toml correctly
- ✅ Generated flake.nix includes all dependencies
- ✅ `nix develop` after `t install` loads packages
- ✅ Error messages guide users to fixes
- ✅ Original flake.nix structure preserved

**Estimated Time:** 7 days (1.5 weeks)

---

### Phase C: Package Testing & Validation (Week 3-4 — 5 days)

**Goal:** Implement `t test` and package validation

**Tasks:**

#### Test Discovery
- [ ] Create `test_runner.ml` module
- [ ] Scan `tests/` directory for `test-*.t` or `*_test.t` files
- [ ] Implement test file pattern matching
- [ ] Support recursive directory scanning
- [ ] Add `.tignore` support for excluding files

#### Test Execution
- [ ] Load test files into T runtime
- [ ] Capture test assertions (`assert()`)
- [ ] Track pass/fail status per test
- [ ] Collect error messages and stack traces
- [ ] Support test fixtures (setup/teardown)
- [ ] Implement test isolation (separate environment)

#### `t test` Command
- [ ] Add `test` command handler to `src/repl.ml`
- [ ] Discover all test files
- [ ] Execute tests sequentially
- [ ] Display progress indicator
- [ ] Print test results summary
- [ ] Exit with appropriate code (0 = pass, 1 = fail)

#### Test Output Formatting
- [ ] Implement TAP (Test Anything Protocol) output
- [ ] Add colored output for terminal
- [ ] Show passed tests with ✓
- [ ] Show failed tests with ✗ and error details
- [ ] Display timing information
- [ ] Add verbose mode (`--verbose`)

#### Package Validation
- [ ] Create `package_validator.ml` module
- [ ] Validate DESCRIPTION.toml is present
- [ ] Validate flake.nix is present and valid
- [ ] Check required directories exist (src/, tests/)
- [ ] Validate function exports match documentation
- [ ] Check for common issues (missing LICENSE, etc.)

#### `t doctor` Command
- [ ] Add `doctor` command handler
- [ ] Run package validation checks
- [ ] Check Nix installation
- [ ] Verify git repository is configured
- [ ] Check for uncommitted changes
- [ ] Validate dependencies are fetchable
- [ ] Print actionable suggestions

#### Testing
- [ ] Create example test files
- [ ] Test discovery of multiple test files
- [ ] Test execution with passing tests
- [ ] Test execution with failing tests
- [ ] Test error reporting
- [ ] Test timing and output formatting
- [ ] Integration test: full test suite

**Success Criteria:**
- ✅ `t test` discovers and runs all tests
- ✅ Test output is clear and actionable
- ✅ Failed tests show helpful error messages
- ✅ `t doctor` identifies common issues
- ✅ Test runner integrates with CI

**Estimated Time:** 5 days (1 week)

---

### Phase D: Publishing & Release Workflow (Week 4-5 — 5 days)

**Goal:** Streamline package publishing to git

**Tasks:**

#### Release Validation
- [ ] Create `release_manager.ml` module
- [ ] Validate package structure before release
- [ ] Check all tests pass (`t test`)
- [ ] Check documentation is up-to-date
- [ ] Validate version in DESCRIPTION.toml
- [ ] Check for uncommitted changes
- [ ] Validate CHANGELOG.md has entry for version

#### Git Tag Management
- [ ] Implement git tag creation helper
- [ ] Parse version from DESCRIPTION.toml
- [ ] Generate semantic version tag (e.g., v0.1.0)
- [ ] Add git annotation with changelog excerpt
- [ ] Prevent duplicate tags
- [ ] Support pre-release tags (alpha, beta)

#### `t publish` Command (Basic)
- [ ] Add `publish` command handler
- [ ] Run pre-publish validation
- [ ] Display checklist to user
- [ ] Prompt for confirmation
- [ ] Create git tag
- [ ] Push tag to remote (with confirmation)
- [ ] Display post-publish instructions

#### Release Checklist
- [ ] Generate checklist from validation results
- [ ] Check git remote is configured
- [ ] Check version is incremented from last tag
- [ ] Check CHANGELOG.md is updated
- [ ] Check all tests pass
- [ ] Check documentation coverage
- [ ] Warn about uncommitted changes

#### GitHub Integration (Optional)
- [ ] Generate GitHub release notes from CHANGELOG
- [ ] Add `--github` flag to create GitHub release
- [ ] Use GitHub API to publish release
- [ ] Attach built artifacts (optional)

#### Testing
- [ ] Test tag creation with valid version
- [ ] Test validation catches common issues
- [ ] Test duplicate tag prevention
- [ ] Test dry-run mode
- [ ] Integration test: publish → clone → install

**Success Criteria:**
- ✅ `t publish` validates package thoroughly
- ✅ Git tags are created correctly
- ✅ Release process is documented and clear
- ✅ Users can publish without Nix expertise
- ✅ Published packages are installable

**Estimated Time:** 5 days (1 week)

---

### Phase E: Integration & Polish (Week 5-6 — 5 days)

**Goal:** Connect all components and improve UX

**Tasks:**

#### Command Integration
- [ ] Ensure `t init` → `t install` → `t test` → `t publish` workflow works
- [ ] Add workflow documentation to generated READMEs
- [ ] Create comprehensive CLI help messages
- [ ] Add examples to `t --help` output
- [ ] Implement command aliases (if useful)

#### `t update` Command
- [ ] Add `update` command handler
- [ ] Check for newer tags on git remotes
- [ ] Update tproject.toml with latest versions
- [ ] Run `t install` to update flake.nix
- [ ] Display changelog summaries for updates
- [ ] Add `--package` flag for updating specific dependency

#### `t search` Command (Future)
- [ ] Design package index format
- [ ] Implement basic search by name/description
- [ ] Add `--tag` flag for tag-based filtering
- [ ] Display search results with metadata
- [ ] Link to package repositories

#### Interactive Mode
- [ ] Add `--interactive` flag to `t init`
- [ ] Prompt for package name, author, license
- [ ] Prompt for initial dependencies
- [ ] Validate inputs interactively
- [ ] Show preview before creating files

#### Documentation Generation Integration
- [ ] Ensure `t init package` sets up docs/ structure
- [ ] Update package templates to include doc examples
- [ ] Add `t document` to post-init instructions
- [ ] Integrate documentation coverage with `t doctor`

#### Error Handling Polish
- [ ] Audit all error messages for clarity
- [ ] Add "Did you mean...?" suggestions
- [ ] Provide recovery steps in error messages
- [ ] Add troubleshooting guide to documentation
- [ ] Implement `--debug` flag for verbose output

#### Performance Optimization
- [ ] Profile CLI startup time
- [ ] Cache parsed TOML files
- [ ] Optimize flake.nix parsing
- [ ] Parallelize test execution (if needed)
- [ ] Add progress bars for long operations

#### CI/CD Templates
- [ ] Create GitHub Actions workflow template
- [ ] Add to `t init` generated files
- [ ] Test on push (run `t test`)
- [ ] Validate documentation on PR
- [ ] Auto-deploy docs on release

#### User Guide
- [ ] Write "Creating Your First Package" tutorial
- [ ] Write "Managing Project Dependencies" guide
- [ ] Write "Publishing to GitHub" guide
- [ ] Add troubleshooting section
- [ ] Add FAQ section

#### Testing
- [ ] End-to-end test: init package → develop → test → publish
- [ ] End-to-end test: init project → install deps → run
- [ ] Test on clean system (Docker container)
- [ ] Test with multiple packages/projects
- [ ] User acceptance testing with external users

**Success Criteria:**
- ✅ Complete package workflow works smoothly
- ✅ Error messages guide users effectively
- ✅ CLI performance is snappy (<100ms startup)
- ✅ Documentation is comprehensive
- ✅ External users can create packages without help

**Estimated Time:** 5 days (1 week)

---

## Coordinated Timeline: Package Management + Documentation

Here's how both systems can be developed in parallel:

### Weeks 1-2: Foundations
**Package Management (Phase A):** Scaffolding commands
**Documentation (Phase 0-1):** Parser infrastructure
- Team can split: 2 devs on packages, 1 dev on docs

### Weeks 2-3: Core Features
**Package Management (Phase B):** Dependency management
**Documentation (Phase 2):** Markdown generation
- Integration point: Generated packages include doc structure

### Weeks 3-4: Testing
**Package Management (Phase C):** Test runner
**Documentation (Phase 3):** REPL integration
- Integration point: `t doctor` checks documentation coverage

### Weeks 4-5: Publishing
**Package Management (Phase D):** Release workflow
**Documentation (Phase 4):** Standard library docs
- Integration point: `t publish` validates documentation

### Weeks 5-6: Polish
**Package Management (Phase E):** Integration
**Documentation (Phase 5):** Advanced features
- Integration point: Full workflow validated

### Weeks 6+: Ongoing
**Both systems:** Maintenance and community support

---

## Combined Progress Tracker

### Package Management System ⬜

**Phase A: Scaffolding** ⬜
- [ ] `t init package` command
- [ ] `t init project` command
- [ ] Template system
- [ ] CLI options
- [ ] Testing

**Phase B: Dependencies** ⬜
- [ ] TOML parsing
- [ ] Nix flake manipulation
- [ ] `t install` command
- [ ] Dependency validation
- [ ] Testing

**Phase C: Testing** ⬜
- [ ] Test discovery and execution
- [ ] `t test` command
- [ ] Package validation
- [ ] `t doctor` command
- [ ] Testing

**Phase D: Publishing** ⬜
- [ ] Release validation
- [ ] Git tag management
- [ ] `t publish` command
- [ ] Release checklist
- [ ] Testing

**Phase E: Integration** ⬜
- [ ] Command integration
- [ ] `t update` command
- [ ] Interactive mode
- [ ] Documentation integration
- [ ] CI/CD templates
- [ ] User guide

### Documentation System ⬜

(See Appendix E for full documentation checklist)

---

## First Steps

**To begin package management implementation:**

```bash
# Create the infrastructure
$ mkdir -p src/package_manager/templates
$ touch src/package_manager/package_types.ml
$ touch src/package_manager/templates/package_description.toml.template
$ git add src/package_manager
$ git commit -m "Phase A: Initialize package management system"
```

**Integration with documentation:**
- Generated packages will have `docs/` directory ready for T-Doc
- `t doctor` will check documentation coverage
- `t publish` will validate docs are up-to-date

Would you like me to add more detail to any specific phase?
