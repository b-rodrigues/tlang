# Getting Started with T

Welcome to T! This guide will help you bootstrap a T project, create your first
workspace, and understand the basic layout of a T workspace.

## Prerequisites

T requires the **Nix package manager** with flakes enabled. Nix ensures that
your T environment is perfectly reproducible across Linux and macOS.

We strongly recommend installing Nix using the [Determinate Systems Nix
Installer](https://install.determinate.systems/nix). For detailed,
platform-specific steps, please see our:

👉 **[Nix Installation Guide](nix-installation.md)**

## Running T

As a user, you don't need to clone the repository or build the compiler from
source! You can run the T shell directly from GitHub using Nix:

```bash
nix shell --accept-flake-config github:b-rodrigues/tlang
```

This command will download the T executable, fetch all required dependencies,
and drop you into a temporary shell where the `t` command is available, for as
long as you stay in that shell.

## Starting a New Workspace

T provides a built-in scaffolding tool to initialize your workspaces. There are
two types of workspaces in T:

- **Projects**: Designed for data analysis, scripts, and reproducible pipelines.
- **Packages**: Designed for creating reusable packages to share with others.

### Creating a Project

To start a new data analysis project, navigate to your desired folder and run
(while in the temporary shell you dropped in before):

```bash
t init --project my_analysis
```

```bash
t init --project my_analysis
```

This scaffolds a complete, reproducible analysis project. By default, it sets up:
- A runnable `src/pipeline.t` template demonstrating polyglot pipeline nodes.
- A declarative `tproject.toml` tracking your language packages and runtimes.
- A hermetic `flake.nix` that locks dependencies across Linux and macOS.
- Built-in AI agent context files (`AGENTS.md` and `T-LANGUAGE-REFERENCE.md`) so coding assistants like Claude Code, Cursor, and Copilot understand T syntax immediately.

#### Workspace Layout

The generated project has the following directory structure:

```text
my_analysis/
├── tproject.toml           # Project configuration and package dependencies
├── flake.nix               # Pinned Nix environment definition
├── README.md               # Project documentation
├── AGENTS.md               # Context and rules for AI coding assistants
├── T-LANGUAGE-REFERENCE.md # Language reference guide (git-ignored)
├── src/
│   └── pipeline.t          # Your main analysis pipeline
├── data/                   # Place raw input datasets here
└── tests/                  # Pipeline and unit assertions
```

### Creating a Package

If you want to create a reusable library of T functions, initialize a package instead:

```bash
t init --package my_package
```

The tree layout for a package is structured for development and testing:

```text
my_package/
├── DESCRIPTION.toml    # Package metadata (name, version, exports)
├── flake.nix           # Reproducible environment definition
├── README.md           # Package overview
├── AGENTS.md           # Onboarding guide for AI Agents
├── T-LANGUAGE-REFERENCE.md # Tiered language reference for LLMs (git-ignored)
├── src/
│   └── main.t          # Package source code
├── tests/
│   └── test-my_package.t  # Unit tests for your package
├── examples/           # Usage examples
└── docs/               # Documentation
```

## Running Your Code

Now that you’ve bootstrapped your project or package, you can leave the
temporary Nix shell using `exit`. Move into the project’s directory (if not
there already), and type `nix develop` to drop into the development environment
of the project. You may be prompted to make the `flake.nix` discoverable, you
can copy and paste the suggested command or simply run `git add .` to stage the
whole project. Try `nix develop` again to drop into the development environment.
You should see the following:

```bash
==================================================
T Project: my_analysis
==================================================

Available commands:
  t repl              - Start T REPL
  t run <file>        - Run a T file
  t test              - Run tests

To add dependencies:
  * Add them to tproject.toml
  * Run 't update' to sync flake.nix

```

Inside your project or package directory, you can start the interactive REPL to
explore your data:

```bash
t repl
```

(or simply `t`).

To execute a script from end-to-end, use:

```bash
t run src/pipeline.t
```

## Next Steps

Now that you have your first project set up and understand the folder structure, the best next step is to run a tiny reproducible pipeline before configuring editor integrations or reading the deeper reference material.

1. **[Your First Pipeline](first-pipeline.md)** — Add R, Python, and Julia packages to `tproject.toml`, run `t update`, and build a small hello-world polyglot pipeline.
2. **[Data I/O & Formats](data-formats.md)** — Read CSV, Parquet, and Arrow files; download data from URLs; understand NA handling.
3. **[Configure Editors](editors.md)** — Configure your editor to play well with T.
4. **[Language Overview](language_overview.md)** — Explore T's syntax, types, and standard library functions.
5. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how to build reproducible, DAG-based data analysis workflows (the core feature of T).
6. **[Project Development](project_development.md)** — Dive deeper into managing your `tproject.toml` and Nix environments.
