# Your First Pipeline

> A quick, end-to-end tutorial for declaring R, Python, and Julia dependencies,
> syncing the reproducible environment, and running a small polyglot pipeline.

This guide assumes you have already completed the [Getting Started](getting-started.md)
setup and are inside a T project created with `t init --project`.

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
2. [Language Overview](language_overview.md) — Learn T expressions, data types,
   functions, and pipes.
3. [Pipeline Tutorial](pipeline_tutorial.md) — Go deeper into dependency graphs,
   serializers, materialization, error handling, and larger DAGs.
4. [Project Development](project_development.md) — Learn more about
   `tproject.toml`, Nix environments, tests, and project structure.
