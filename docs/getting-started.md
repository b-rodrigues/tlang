# Getting Started with T

Welcome to T! This guide will help you install T, create your first project, and understand the basic layout of a T workspace.

## Prerequisites

T requires the **Nix package manager** with flakes enabled. Nix ensures that your T environment is perfectly reproducible across Linux and macOS.

We strongly recommend installing Nix using the [Determinate Systems Nix Installer](https://install.determinate.systems/nix). For detailed, platform-specific steps, please see our:

👉 **[Nix Installation Guide](nix-installation.md)**

## Running T

As a user, you don't need to clone the repository or build the compiler from source! You can run the T shell directly from GitHub using Nix:

```bash
nix shell github:b-rodrigues/tlang
```

This command will download the T executable, fetch all required dependencies, and drop you into a temporary shell where the `t` command is available, for as long as you stay in that shell.

## Starting a New Workspace

T provides a built-in scaffolding tool to initialize your workspaces. There are two types of workspaces in T:
- **Projects**: Designed for data analysis, scripts, and reproducible pipelines.
- **Packages**: Designed for creating reusable functions and libraries to share with others.

### Creating a Project

To start a new data analysis project, navigate to your desired folder and run (while in the temporary shell you dropped in before):

```bash
t init --project my_analysis
```

The scaffolding tool will generate a reproducible workspace with the following layout:

```text
my_analysis/
├── tproject.toml       # Project configuration and dependencies
├── flake.nix           # Reproducible environment definition
├── README.md           # Project overview
├── AGENTS.md           # Onboarding guide for AI Agents
├── T-LANGUAGE-REFERENCE.md # Tiered language reference for LLMs (git-ignored)
├── src/
│   └── pipeline.t      # Your main analysis script
├── data/               # Place your raw data files here
├── outputs/            # Output directory for results
└── tests/              # Unit tests for your analysis
```

### AI Agent Onboarding

T is designed to be highly compatible with AI-assisted development. When you run `t init`, the tool will prompt you for an **Agent Context Level**:

- **small**: Core syntax and top 20 functions.
- **medium**: (Default) Exhaustive standard library index.
- **full**: Full language manual and detailed examples.
- **huge**: Concatenated documentation of the entire T ecosystem.

This selection generates two files in your project root:
1. **`AGENTS.md`**: A project-specific guide that tells LLMs how to work within your project's architecture.
2. **`T-LANGUAGE-REFERENCE.md`**: A technical reference file for the AI to read.

By providing these files, you ensure that any AI agent you use has immediate access to the exact technical context it needs.

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

Now that you’ve bootstrapped your project or package, you can leave the temporary Nix shell using `exit`.
Move into the project’s directory (if not there already), and type `nix develop` to drop into the development environment of the project.
You may be prompted to make the `flake.nix` discoverable, you can copy and paste the suggested command or
simply run `git add .` to stage the whole project. Try `nix develop` again to drop into the development
environment. You should see the following:

```bash
==================================================
T Project: start_t
==================================================

Available commands:
  t repl              - Start T REPL
  t run <file>        - Run a T file
  t test              - Run tests

To add dependencies:
  * Add them to tproject.toml
  * Run 't update' to sync flake.nix

```

Inside your project or package directory, you can start the interactive REPL to explore your data:

```bash
t repl
```

(or simply `t`).

To execute a script from end-to-end, use:

```bash
t run scripts/main.t
```

## Next Steps

Now that you have your first project set up and understand the folder structure, you are ready to explore the language features and build reproducible data pipelines!

1. **[Configure Editors](editors.md)** — Configure your editor to play well with T.
2. **[Language Overview](language_overview.md)** — Explore T's syntax, types, and standard library functions.
3. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how to build reproducible, DAG-based data analysis workflows (the core feature of T).
4. **[Project Development](project_development.md)** — Dive deeper into managing your `tproject.toml` and Nix environments.
