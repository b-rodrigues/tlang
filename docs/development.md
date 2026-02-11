# Development Guide

Comprehensive guide for T language development, building, testing, and debugging.

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Building T](#building-t)
- [Testing](#testing)
- [Debugging](#debugging)
- [Development Workflow](#development-workflow)
- [Performance Profiling](#performance-profiling)
- [Common Tasks](#common-tasks)

---

## Development Environment Setup

### Prerequisites

1. **Nix** with flakes enabled (see [Installation Guide](installation.md))
2. **Git** for version control
3. **Editor** with OCaml support (VS Code, Emacs, Vim)

### Initial Setup

```bash
# Clone repository
git clone https://github.com/b-rodrigues/tlang.git
cd tlang

# Enter Nix development shell
nix develop

# Build
dune build

# Verify installation
dune exec src/repl.exe
```

### Editor Setup

#### VS Code

Install extensions:
- **OCaml Platform** (`ocamllabs.ocaml-platform`)
- **Dune** (syntax highlighting for `dune` files)

**`.vscode/settings.json`**:
```json
{
  "ocaml.sandbox": {
    "kind": "custom",
    "template": "nix develop --command $prog $args"
  }
}
```

#### Emacs

Use **Tuareg** mode and **Merlin**:

```elisp
;; In .emacs or init.el
(require 'tuareg)
(require 'merlin)
(add-hook 'tuareg-mode-hook #'merlin-mode)
```

#### Vim/Neovim

Use **Merlin** and **ALE** or **coc-ocaml**:

```vim
" In .vimrc
Plug 'ocaml/merlin'
Plug 'dense-analysis/ale'
```

---

## Building T

### Dune Build System

T uses [Dune](https://dune.build/) for building.

**Key Commands**:
```bash
# Build everything
dune build

# Build specific target
dune build src/repl.exe

# Clean build artifacts
dune clean

# Watch mode (rebuild on file changes)
dune build --watch
```

### Build Artifacts

Compiled outputs are in `_build/default/`:
- `src/repl.exe` — REPL executable
- `src/*.cmo`, `src/*.cmi` — Compiled modules
- `tests/*.exe` — Test executables

### Build Configuration

**`dune-project`**: Project metadata
```sexp
(lang dune 3.0)
(name t_lang)
(using menhir 2.1)
```

**`src/dune`**: Build rules for source
```sexp
(executable
 (name repl)
 (libraries arrow-glib))

(menhir
 (modules parser))

(ocamllex lexer)
```

### Dependencies

Managed by Nix (in `flake.nix`):
- **OCaml** 4.14+
- **Dune** 3.0+
- **Menhir** (parser generator)
- **Arrow GLib** (Arrow bindings)
- **GLib** (C library)

Update dependencies:
```bash
nix flake update
nix develop
```

---

## Testing

### Test Structure

```
tests/
├── unit/              # OCaml unit tests
│   ├── test_mean.ml
│   ├── test_filter.ml
│   └── dune
├── golden/            # T vs R golden tests
│   ├── mean.t
│   ├── mean.R
│   └── run_golden.sh
└── examples/          # End-to-end examples
    ├── pipeline_example.t
    └── dune
```

### Running Tests

**All tests**:
```bash
dune runtest
```

**Specific test file**:
```bash
dune runtest tests/unit/test_mean.ml
```

**Verbose output**:
```bash
dune runtest --verbose
```

**Watch mode** (re-run on changes):
```bash
dune runtest --watch
```

### Writing Unit Tests

**`tests/unit/test_example.ml`**:
```ocaml
open Ast
open Eval

let test_addition () =
  let env = Environment.create () in
  let expr = BinOp (Add, Int 2, Int 3) in
  let result = eval env expr in
  assert (result = VInt 5)

let test_mean_basic () =
  let values = [VInt 1; VInt 2; VInt 3] in
  let result = Stats.mean values false in
  assert (result = VFloat 2.0)

let tests = [
  ("addition", test_addition);
  ("mean_basic", test_mean_basic);
]

let () =
  List.iter (fun (name, test) ->
    try
      test ();
      Printf.printf "✓ %s\n" name
    with e ->
      Printf.printf "✗ %s: %s\n" name (Printexc.to_string e)
  ) tests
```

**`tests/unit/dune`**:
```sexp
(test
 (name test_example)
 (libraries t_lang))
```

### Golden Tests

Compare T output against R:

**T program** (`tests/golden/mean.t`):
```t
print(mean([1, 2, 3, 4, 5]))
```

**R script** (`tests/golden/mean.R`):
```r
cat(mean(c(1, 2, 3, 4, 5)), "\n")
```

**Run comparison**:
```bash
# Generate T output
dune exec src/repl.exe < tests/golden/mean.t > /tmp/t_output.txt

# Generate R output
Rscript tests/golden/mean.R > /tmp/r_output.txt

# Compare
diff /tmp/t_output.txt /tmp/r_output.txt
```

**Automated golden test script** (`tests/golden/run_golden.sh`):
```bash
#!/usr/bin/env bash
set -e

for t_file in tests/golden/*.t; do
  base=$(basename "$t_file" .t)
  r_file="tests/golden/${base}.R"
  
  if [ ! -f "$r_file" ]; then
    echo "⚠ Skipping $base (no R script)"
    continue
  fi
  
  dune exec src/repl.exe < "$t_file" > /tmp/t_${base}.txt
  Rscript "$r_file" > /tmp/r_${base}.txt
  
  if diff /tmp/t_${base}.txt /tmp/r_${base}.txt > /dev/null; then
    echo "✓ $base"
  else
    echo "✗ $base (output differs)"
    diff /tmp/t_${base}.txt /tmp/r_${base}.txt
  fi
done
```

---

## Debugging

### REPL Debugging

**Interactive exploration**:
```bash
dune exec src/repl.exe
```

```t
> x = 42
42
> type(x)
"Int"
> x + 10
52
```

**Load script into REPL**:
```bash
cat examples/analysis.t | dune exec src/repl.exe
```

### OCaml Debugger

**Compile with debug symbols**:
```bash
dune build --profile dev
```

**Run with ocamldebug**:
```bash
ocamldebug _build/default/src/repl.exe
```

**Debug commands**:
```
(ocd) break Eval.eval
(ocd) run
(ocd) step
(ocd) print env
(ocd) backtrace
```

### Print Debugging

**In OCaml code**:
```ocaml
let eval env expr =
  Printf.eprintf "DEBUG: evaluating %s\n" (show_expr expr);
  match expr with
  | Int n ->
      Printf.eprintf "DEBUG: int value %d\n" n;
      VInt n
  | _ -> (* ... *)
```

**In T code**:
```t
x = 10
print("DEBUG: x = " + string(x))
result = x * 2
print("DEBUG: result = " + string(result))
```

### Trace Execution

**Enable tracing** (modify `eval.ml`):
```ocaml
let trace = ref false

let eval env expr =
  if !trace then
    Printf.eprintf "TRACE: %s\n" (show_expr expr);
  (* ... *)
```

**Run with trace**:
```bash
TRACE=1 dune exec src/repl.exe
```

### Error Diagnosis

**Type errors**:
```t
> 1 + "hello"
Error(TypeError: Cannot add Int and String)
```

Check:
- Value types (use `type()`)
- Function signatures
- Conversion functions available

**Name errors**:
```t
> undefined_var
Error(NameError: 'undefined_var' is not defined)
```

Check:
- Variable spelling
- Scope (is it in current environment?)
- Package loaded correctly

**Arrow FFI errors**:
```
Error: Undefined symbol: caml_arrow_read_csv
```

Check:
- You're in Nix shell (`nix develop`)
- Arrow GLib is available: `pkg-config --modversion arrow-glib`
- FFI stubs compiled correctly

---

## Development Workflow

### Typical Development Cycle

1. **Write code** (OCaml or T)
2. **Build**:
   ```bash
   dune build
   ```
3. **Test** (unit + manual):
   ```bash
   dune runtest
   dune exec src/repl.exe
   ```
4. **Debug** (if tests fail):
   - Add print statements
   - Use OCaml debugger
   - Inspect intermediate values
5. **Commit**:
   ```bash
   git add .
   git commit -m "feat: add feature"
   ```
6. **Push and open PR**

### Watch Mode (Fast Iteration)

**Terminal 1** (build on save):
```bash
dune build --watch
```

**Terminal 2** (REPL for testing):
```bash
dune exec src/repl.exe
```

Edit code → save → `dune build` auto-runs → restart REPL → test.

### Working on Standard Library

**Add new function** (`src/packages/stats/median.ml`):
```ocaml
let median values na_rm =
  Stats.quantile values 0.5 na_rm
```

**Register in loader** (if not auto-discovered):
Edit `src/packages/stats/loader.ml` or equivalent.

**Test**:
```bash
dune build
dune exec src/repl.exe
```

```t
> median([1, 2, 3, 4, 5])
3.0
```

**Add unit test** (`tests/unit/test_median.ml`):
```ocaml
let test_median () =
  let result = Stats.median [VInt 1; VInt 2; VInt 3] false in
  assert (result = VFloat 2.0)
```

---

## Performance Profiling

### Timing Execution

**In T**:
```t
start = time()  -- If time() function exists
-- ... computation ...
end = time()
print("Elapsed: " + string(end - start))
```

**In OCaml**:
```ocaml
let start_time = Unix.gettimeofday () in
let result = expensive_function () in
let end_time = Unix.gettimeofday () in
Printf.printf "Time: %.3f s\n" (end_time -. start_time);
result
```

### OCaml Profiling

**Compile with profiling**:
```bash
dune build --profile release
```

**Run with `perf` (Linux)**:
```bash
perf record dune exec src/repl.exe < benchmark.t
perf report
```

**Run with `gprof`**:
```bash
# Requires special build flags (modify dune config)
ocamlfind ocamlopt -p -o repl.native src/repl.ml
./repl.native < benchmark.t
gprof repl.native gmon.out
```

### Benchmarking

**Benchmarking script** (`scripts/benchmark.sh`):
```bash
#!/usr/bin/env bash
echo "Benchmarking T operations..."

time dune exec src/repl.exe <<EOF
df = read_csv("large_data.csv")
result = df |> filter($age > 30) |> summarize($count = nrow($age))
print(result)
EOF
```

---

## Common Tasks

### Adding a New Data Type

1. **Update AST** (`src/ast.ml`):
   ```ocaml
   type value =
     | (* ... existing types ... *)
     | VMyNewType of my_new_type_data
   ```

2. **Add constructors and accessors**:
   ```ocaml
   let make_my_type data = VMyNewType data
   ```

3. **Update evaluator** (`src/eval.ml`):
   ```ocaml
   match expr with
   | MyNewTypeExpr data -> VMyNewType (construct data)
   ```

4. **Add pretty-printer**:
   ```ocaml
   let string_of_value = function
     | VMyNewType data -> "MyNewType(...)"
   ```

### Adding a New Operator

1. **Update lexer** (`src/lexer.mll`):
   ```ocaml
   | "@@" { DOUBLE_AT }
   ```

2. **Update parser** (`src/parser.mly`):
   ```ocaml
   %token DOUBLE_AT
   
   expr:
     | expr DOUBLE_AT expr { BinOp (MyOp, $1, $3) }
   ```

3. **Update evaluator** (`src/eval.ml`):
   ```ocaml
   let eval_binop op left right =
     match op with
     | MyOp -> (* implementation *)
   ```

### Adding a New Package

1. **Create directory**:
   ```bash
   mkdir src/packages/mypackage
   ```

2. **Add functions** (one per file):
   ```bash
   # src/packages/mypackage/my_func.ml
   let my_func arg1 arg2 =
     (* implementation *)
   ```

3. **Create loader** (`src/packages/mypackage/loader.ml`):
   ```ocaml
   let load env =
     Environment.add env "my_func" (VNativeFunction my_func)
   ```

4. **Register in main loader** (if needed)

5. **Update documentation**:
   - `docs/api-reference.md`
   - Add examples

### Updating Parser Grammar

1. **Edit** `src/parser.mly`
2. **Rebuild**:
   ```bash
   dune build
   ```
3. **Check for conflicts**:
   ```
   Warning: 2 shift/reduce conflicts
   ```
   
   Fix by:
   - Adjusting precedence (`%left`, `%right`, `%nonassoc`)
   - Refactoring grammar rules
   - Making syntax unambiguous

4. **Test** with examples covering new syntax

### Arrow FFI Development

1. **Write C stub** (`src/arrow/arrow_stubs.c`):
   ```c
   CAMLprim value caml_my_arrow_function(value v_arg) {
     // ... Arrow C GLib calls ...
     return Val_unit;
   }
   ```

2. **Declare in OCaml** (`src/arrow/arrow_ffi.ml`):
   ```ocaml
   external my_arrow_function : arg_type -> return_type = "caml_my_arrow_function"
   ```

3. **Build** (Nix handles linking):
   ```bash
   dune build
   ```

4. **Test**:
   ```t
   > df = read_csv("data.csv")
   > my_new_operation(df)
   ```

---

## Troubleshooting

### Build Fails

**"Command not found: dune"**
- Ensure you're in `nix develop` shell

**"Unbound module"**
- Check `dune` file includes necessary libraries
- Verify module name matches filename

**Menhir conflicts**
- Review parser grammar for ambiguities
- Add `%prec` directives
- Simplify conflicting rules

### Tests Fail

**Unit test assertion fails**
- Add debug prints to see actual vs expected
- Check input data matches test assumptions
- Verify function signature

**Golden test differs**
- Floating-point precision differences (acceptable if small)
- Platform-specific behavior (check on both Linux/macOS)
- R package version mismatch

### Runtime Errors

**Segfault in Arrow FFI**
- Check C stub memory management
- Ensure Arrow objects are not freed prematurely
- Use `valgrind` for memory debugging:
  ```bash
  valgrind --leak-check=full dune exec src/repl.exe
  ```

**"Type error" at runtime**
- Use `type()` to inspect values
- Check function expects correct types
- Verify conversions are explicit

---

## Advanced Topics

### Custom Build Profiles

**`dune-workspace`**:
```sexp
(lang dune 3.0)

(context
 (default
  (name release)
  (flags (:standard -O3))))

(context
 (default
  (name dev)
  (flags (:standard -g))))
```

Build with profile:
```bash
dune build --profile release
dune build --profile dev
```

### Cross-Compilation

Nix supports cross-compilation:

```bash
# For ARM64
nix build .#tlang-arm64

# For macOS from Linux (requires macOS SDK)
nix build .#tlang-darwin
```

### Continuous Integration

See `.github/workflows/` for CI configuration.

**Local CI simulation**:
```bash
# Run same checks as CI
dune build
dune runtest
dune build @fmt --auto-promote  # Format check
```

---

**Next Steps**: [Contributing Guide](contributing.md) | [Architecture](architecture.md)
