# Brainstorm: `node(runtime = sh)` / shell-backed pipeline nodes

## Goal

Make it possible to define pipeline nodes that execute arbitrary shell/CLI tools
such as `awk`, `sed`, `jq`, `grep`, or custom shell scripts, while still fitting
the existing T pipeline model:

- explicit runtime
- explicit dependencies
- explicit serializers / deserializers
- reproducible node artifacts

This should feel like:

```t
processed = node(
  runtime = sh,
  command = "awk",
  args = list("-F", ",", "NR > 1 { print $1 }", "input.csv"),
  serializer = text,
  deserializer = lines
)
```

or, for full shell syntax:

```t
processed = node(
  runtime = sh,
  command = "awk -F, 'NR > 1 { print $1 }' input.csv | sort | uniq",
  shell = "bash",
  shell_args = list("-lc"),
  serializer = text,
  deserializer = lines
)
```

---

## Why this is useful

There is a big class of pipeline steps that are easier to express as a CLI call
than as native T, R, or Python code:

- quick text munging with `awk` / `sed`
- CSV/TSV reshaping with Unix tools
- invoking domain-specific CLIs
- wrapping existing shell scripts already used in data workflows

The important part is not only “run a command”, but “run a command in a way that
still composes with pipeline inputs, outputs, and caching”.

---

## Desired UX

### 1. Minimal explicit shell node

```t
node(
  runtime = sh,
  command = "awk",
  args = list("-F", ",", "NR > 1 { print $1 }", "input.csv")
)
```

This is the simplest and safest form: command + argv.

### 2. Script-backed shell node

```t
node(
  runtime = sh,
  script = "scripts/clean_data.sh",
  args = list("--input", "input.csv", "--format", "json")
)
```

This matches the existing `script = ...` pattern for R/Python/Quarto and should
probably be supported from day one.

### 3. Full shell command string

```t
node(
  runtime = sh,
  command = "awk -F, 'NR > 1 { print $1 }' input.csv | sort | uniq"
)
```

This is convenient, but it is harder to quote correctly and less safe. It should
likely be treated as an explicit “invoke a shell parser” mode rather than the
default mode.

---

## Recommendation: prefer argv over raw shell strings

If the feature is designed primarily around a single shell string, quoting and
escaping will quickly become painful:

- spaces in paths
- embedded quotes
- `$` expansion
- pipes / redirects / globs
- accidental injection if arguments are interpolated

So the primary API should probably be:

```t
node(
  runtime = sh,
  command = "awk",
  args = list("-F", ",", "NR > 1 { print $1 }", some_path)
)
```

and the shell-string form should be opt-in:

```t
node(
  runtime = sh,
  command = "awk -F, 'NR > 1 { print $1 }' \"$INPUT\" | sort",
  shell = "bash",
  shell_args = list("-lc")
)
```

That gives two clearly different modes:

1. **exec mode**: run a binary directly with argv
2. **shell mode**: run a command string through `sh -c` or `bash -lc`

This distinction matters for both correctness and security.

---

## What should `runtime = sh` mean?

There are a few plausible interpretations:

### Option A — `sh` means “POSIX shell”

- default interpreter: `sh`
- portable, conservative
- discourages Bash-only syntax

### Option B — `sh` means “shell/CLI runtime”

- not necessarily a literal shell
- can execute either:
  - a binary directly (`awk`, `jq`, `csvcut`)
  - a shell command string via configured shell

### Option C — separate runtimes

- `runtime = sh`
- `runtime = bash`

This is more explicit, but may be more surface area than needed.

### My preference

Use **`runtime = sh` as the generic CLI runtime**, and optionally allow:

- `shell = "sh"` (default)
- `shell = "bash"` when shell parsing is needed

That keeps the user-facing API small while still supporting Bash-specific cases.

---

## Arguments: the most important part

The issue here is right to emphasize argument passing, because this is the piece
that makes shell nodes practical instead of fragile.

### Proposed argument model

```t
node(
  runtime = sh,
  command = "awk",
  args = list("-F", ",", "NR > 1 { print $1 }", input_path)
)
```

Where:

- `command` = executable name or absolute path
- `args` = ordered list of arguments

This should map directly to an argv array, not to a string join.

### Why this matters

Passing arguments as a list:

- preserves spaces safely
- avoids quoting bugs
- makes generated build commands deterministic
- is much easier to serialize into Nix derivations

### Named arguments?

I do **not** think the CLI argv itself should become a Dict/named-args layer.
Shell tools are positional by nature. T should preserve that.

However, T could still support a small amount of shell-node metadata:

- `args`
- `env`
- `cwd`
- `shell`
- `shell_args`

---

## Serialization / deserialization should stay first-class

This is the part that makes shell nodes fit the existing node abstraction.

The shell node should not invent a completely separate “stdout is the result”
model unless the serializer explicitly says so. Instead, it should reuse the
existing node artifact contract:

- upstream values get materialized for the node
- the node writes its result artifact
- T deserializes the artifact back into a native value

### Good mental model

Shell nodes are not special. They are just another runtime that happens to
execute a CLI process.

### Built-in serializer/deserializer formats worth supporting

At minimum:

- `default` — whatever T already does for native nodes
- `json` — useful for structured scalar/list/dict results
- `text` — raw UTF-8 text
- `lines` — newline-delimited text to `List[String]`
- `arrow` — tabular data
- `file` / `binary` — opaque artifact passthrough

The most common shell-node use cases would likely be:

| Use case | Serializer | Deserializer |
| --- | --- | --- |
| `awk` / `sed` text output | `text` | `text` or `lines` |
| `jq` structured output | `text` or `json` | `json` |
| CSV/TSV processing | `file` or `text` | loader-specific |
| Arrow-aware CLI tool | `arrow` | `arrow` |

### Important design point

For shell nodes, serializers may be needed in **two directions**:

1. **Input side**: how upstream T values are exposed to the CLI
2. **Output side**: how the CLI result is read back into T

Today `serializer` / `deserializer` mostly describe the node output artifact. For
shell nodes, we may eventually want a slightly richer model:

- output serializer/deserializer (existing concept)
- input materialization helpers for dependencies

That said, for a first version we should avoid overcomplicating things.

---

## How should inputs reach the shell command?

This is probably more important than whether the runtime is called `sh` or
`bash`.

### Option 1 — environment variables with artifact paths

This is closest to the current pipeline design:

- `T_NODE_raw_data=/nix/store/.../raw_data/artifact`
- `T_NODE_model=/nix/store/.../model/artifact`

Then the shell command reads those paths.

Pros:

- consistent with existing node execution model
- works well with files and Nix store artifacts

Cons:

- CLI code still needs to know how to consume the artifact format

### Option 2 — explicit helper variables for common paths

For example:

- `T_INPUT_<dep>`
- `T_OUTPUT`
- `T_OUTPUT_DIR`

Then shell code can be written very simply:

```sh
awk -F, 'NR > 1 { print $1 }' "$T_INPUT_raw_data" > "$T_OUTPUT"
```

This feels like a strong option because it makes the shell contract easy to
understand.

### Option 3 — positional injection into `args`

T could allow helpers like:

```t
node(
  runtime = sh,
  command = "awk",
  args = list("-F", ",", "NR > 1 { print $1 }", input("raw_data"))
)
```

This would be nice ergonomically, but it requires extra language/API design.

### My preference

For a first version:

- expose dependency artifact paths as environment variables
- always expose an output artifact path
- let `args` stay plain strings

That is simple, explicit, and close to how build tools already work.

---

## A concrete execution contract

Something like this seems reasonable:

### Inputs exposed by T

- `T_NODE_<name>` = artifact path for each upstream dependency
- `T_OUTPUT` = path where the node must write its main artifact
- `T_OUTPUT_DIR` = directory for auxiliary files
- `T_RUNTIME_SERIALIZER`
- `T_RUNTIME_DESERIALIZER`

### Node obligation

The shell process must:

1. exit with code `0` on success
2. write its main result to `T_OUTPUT`
3. write any secondary files under `T_OUTPUT_DIR`

### T obligation

T must:

1. prepare the sandbox
2. expose dependency artifacts
3. invoke the CLI
4. fail cleanly on non-zero exit
5. deserialize `T_OUTPUT` using the declared deserializer

This keeps shell nodes aligned with R/Python nodes: produce an artifact, do not
just print a best-effort result to stdout.

---

## Should stdout/stderr still matter?

Yes, but mainly for observability:

- stdout can be logged
- stderr should be captured for error reporting
- exit code must remain authoritative

It may still be useful to support a convenience mode where:

- if `deserializer = text`, T can treat stdout as the output artifact

But I would keep that as optional sugar, not the core contract. Artifact-first
fits the rest of the pipeline system better.

---

## Suggested examples

### 1. `awk` text pipeline

```t
names = node(
  runtime = sh,
  command = "awk -F, 'NR > 1 { print $1 }' \"$T_NODE_raw_csv\" > \"$T_OUTPUT\"",
  shell = "bash",
  shell_args = list("-lc"),
  serializer = text,
  deserializer = lines
)
```

This is a good example of why shell-string mode is still useful: redirection into
`T_OUTPUT` is simple and obvious.

### 2. `jq` returning JSON

```t
summary = node(
  runtime = sh,
  command = "jq '{rows: length}' \"$T_NODE_records\" > \"$T_OUTPUT\"",
  shell = "sh",
  shell_args = list("-c"),
  serializer = json,
  deserializer = json
)
```

### 3. existing shell script

```t
cleaned = node(
  runtime = sh,
  script = "scripts/clean_data.sh",
  args = list("$T_NODE_raw_data", "$T_OUTPUT"),
  serializer = text,
  deserializer = text
)
```

---

## Naming thoughts

The user suggestion of `node(runtime = "sh")` or similar feels right. A few
possible spellings:

- `runtime = sh`
- `runtime = Shell`
- `runtime = Bash`

I would avoid making `bash` the only spelling, because many useful commands
don’t need Bash semantics at all. The broader idea is “CLI/shell node”, not just
“Bash script node”.

So my preference is:

- `runtime = sh`
- optional `shell = "bash"` when Bash features are needed

---

## Open questions

### 1. Should `command` accept both String and List[String]?

Possible, but maybe confusing. I would keep:

- `command` = String
- `args` = List[String]

### 2. Should raw shell strings be allowed without an explicit `shell` field?

Probably not. Requiring `shell = "sh"` or `shell = "bash"` makes the parsing
boundary explicit.

### 3. How many built-in deserializers do we need initially?

Probably just:

- `text`
- `json`
- `arrow`

`lines` would still be very nice because it is such a common shell pattern.

### 4. Should dependencies be auto-deserialized before the shell node runs?

Probably no. A shell runtime is file-oriented by nature. It should work with
paths/artifacts, not in-memory values.

---

## Pragmatic first version

If the goal is to ship this without too much complexity, I would scope v1 as:

1. `runtime = sh`
2. `command` + optional `args`
3. `script = "..."` support for `.sh`
4. expose dependency artifact paths via env vars
5. require writing the main result to `T_OUTPUT`
6. support `text`, `json`, and `arrow` deserializers
7. treat direct shell-string execution as opt-in via `shell = "sh"` or `shell = "bash"`

That would already unlock:

- `awk`
- `sed`
- `grep`
- `jq`
- existing shell scripts
- many small CLI wrappers

without forcing a large redesign of the pipeline system.

---

## Short conclusion

The most important design decision is to treat shell nodes as **artifact-producing
pipeline nodes**, not as ad hoc subprocess calls.

If that is preserved, then `node(runtime = sh)` becomes a very natural addition:

- `command` and `args` define the executable invocation
- serializers/deserializers define the T boundary
- env vars provide dependency artifact paths
- shell parsing is available, but opt-in

That seems like the cleanest path to making `awk`-style nodes useful without
making pipeline execution brittle.
