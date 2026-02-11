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
- **REPL-accessible help system** (`?function_name`)
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
| ?function | REPL help | `?function` or `help(function)` |
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
│  │         REPL Integration (help(), ?)                  │  │
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
T> ?mean
-- Shows full documentation for mean()

T> help("mean")
-- Same as ?mean

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

**Modified REPL:**

```ocaml
(* src/repl.ml *)
let handle_help_query query env =
  if String.starts_with ~prefix:"?" query then
    let func_name = String.sub query 1 (String.length query - 1) in
    display_help func_name env
  else
    parse_and_eval env query
```

**Deliverables:**
- ✅ `help()` builtin function
- ✅ `?` prefix syntax in REPL
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
T> ?mean
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
- [ ] Add `?` syntax to REPL
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

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0-draft | 2026-02-11 | Initial specification |
