# Your First Pipeline

> A quick, end-to-end tutorial for declaring R, Python, and Julia dependencies,
> syncing the reproducible environment, and running a small polyglot pipeline.

This guide takes you from a bare machine to a working polyglot pipeline. T itself is
never installed — you install Nix, then bootstrap a project that pins its own copy of
the T toolchain. If you already have a T project created with `t init --project`, skip
straight to [section 1](#enter-the-project-environment).

## 0. Bootstrap a project

T is distributed exclusively via Nix. Follow the [Nix Installation Guide](nix-installation.md)
to install Nix and configure the `rstats-on-nix` binary cache. Then:

```bash
# 1. Start a temporary shell that provides the `t` executable
nix shell --accept-flake-config github:b-rodrigues/tlang

# 2. Scaffold a new project (still inside the temporary shell)
t init --project my_analysis

# 3. Leave the temporary shell and enter the project environment
exit
cd my_analysis
nix develop
```

You are now inside a reproducible development shell with the `t` command and the
project-specific runtimes on `PATH`. All commands below should be run inside that
shell.

## 1. Enter the project environment

From the project root, enter the reproducible development shell:

```bash
nix develop
```

All commands below should be run inside that shell. This ensures `t`, the
project-specific runtimes, and the dependency guards are all on `PATH`.

## 2. Declare runtime packages in `tproject.toml`

T projects are explicit: R, Python, and Julia packages belong in
`tproject.toml`, not in ad hoc `install.packages()`, `pip install`, or
`Pkg.add()` calls. Open `tproject.toml` and make sure the runtime dependency
sections contain the packages you plan to use:

```toml
[r-dependencies]
packages = ["stringr"]

[py-dependencies]
version = "python313"
packages = ["numpy"]

[jl-dependencies]
version = "lts"
packages = ["DataFrames"]
```

A few rules of thumb:

- Add R packages under `[r-dependencies].packages`.
- Add Python packages under `[py-dependencies].packages` and keep the Python
  version explicit.
- Add Julia packages under `[jl-dependencies].packages`; `version = "lts"` is
  the recommended default unless you need a specific Julia release.
- If your project was scaffolded with empty lists already present, edit those
  lists instead of creating duplicate sections.

## 3. Sync the project after editing dependencies

After changing `tproject.toml`, regenerate the project environment:

```bash
t update
```

Then re-enter the development shell so the updated package set is active:

```bash
exit
nix develop
```

If T reports that a package used by a pipeline node is missing, add it to the
matching dependency section, run `t update`, and enter `nix develop` again.

## 4. Write a hello-world polyglot pipeline

Replace `src/pipeline.t` with this small pipeline:

```t
p = pipeline {
  r_hello = rn(
    command = <{
      library(stringr)
      str_to_upper("hello from R")
    }>,
    serializer = ^text
  )

  python_hello = pyn(
    command = <{
import numpy as np
f"hello from Python; numpy sum = {np.array([1, 2, 3]).sum()}"
    }>,
    serializer = ^text
  )

  julia_hello = jln(
    command = <{
      using DataFrames
      df = DataFrame(language = ["Julia"], nodes = [1])
      "hello from $(df.language[1]); rows = $(nrow(df))"
    }>,
    serializer = ^text
  )
}

build_pipeline(p, verbose = 1)

print(read_node(p.r_hello))
print(read_node(p.python_hello))
print(read_node(p.julia_hello))
```

This file defines three independent nodes:

- `r_hello` runs in R via `rn()` and uses the declared `stringr` package.
- `python_hello` runs in Python via `pyn()` and uses the declared `numpy`
  package.
- `julia_hello` runs in Julia via `jln()` and uses the declared `DataFrames`
  package.

Each node uses `serializer = ^text`, which is enough for a first hello-world
pipeline because every node returns a string.

## 5. Run the pipeline

From the project root, run:

```bash
t run src/pipeline.t
```

T will materialize the pipeline under `_pipeline/`, build each node in a
Nix-managed sandbox, and write a timestamped build log. The first run may take
longer because Nix may need to fetch or build packages; later runs are cached.

## 6. Inspect the result

The final three lines in `src/pipeline.t` read the built artifacts back through
T and print them:

```t
print(read_node(p.r_hello))
print(read_node(p.python_hello))
print(read_node(p.julia_hello))
```

Use `read_node(p.node_name)` when you want the value materialized for a specific
pipeline node — it re-reads the serialized artifact from the Nix store. By contrast,
`p.node_name` (direct dot access) returns the cached in-memory value. For this
hello-world pipeline, they produce the same result because the node outputs are
simple strings. You should see the text values produced by the three runtimes.

## 7. What to read next

Once this quick pipeline works, continue in this order:

1. [Configure Editors](editors.md) — Set up syntax highlighting, LSP support,
   and formatting conveniences.
2. [Data I/O & Formats](data-formats.md) — Read CSV, Parquet, and Arrow IPC files;
   download data from URLs; understand NA handling.
3. [Language Overview](language_overview.md) — Learn T expressions, data types,
   functions, and pipes.
4. [Pipeline Tutorial](pipeline_tutorial.md) — Go deeper into dependency graphs,
   serializers, materialization, error handling, and larger DAGs.
5. [Project Development](project_development.md) — Learn more about
   `tproject.toml`, Nix environments, tests, and project structure.
