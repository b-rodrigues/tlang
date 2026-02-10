# Troubleshooting Guide

Solutions to common issues when using T.

## Installation Issues

### "command not found: nix"

**Problem**: Nix is not installed or not in PATH.

**Solution**:
```bash
# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# Restart shell or source profile
source ~/.nix-profile/etc/profile.d/nix.sh
```

**Verify**:
```bash
nix --version
# Should output: nix (Nix) 2.x.x
```

---

### "error: experimental feature 'flakes' is disabled"

**Problem**: Flakes not enabled in Nix configuration.

**Solution**:
```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

**For NixOS users**, add to `/etc/nixos/configuration.nix`:
```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

Then rebuild:
```bash
sudo nixos-rebuild switch
```

---

### "nix develop" hangs or takes very long

**Problem**: Nix is building dependencies from source (first time).

**Solution**: Be patient. First build can take 10-30 minutes.

**Monitor progress**:
```bash
nix develop --show-trace
```

**Speed up future builds**: Nix caches everything in `/nix/store/`.

---

### Build fails with "Could not find arrow-glib"

**Problem**: Inside Nix shell, Arrow should be available. If not, flake may be broken.

**Solution**:
```bash
# Ensure you're in Nix shell
nix develop

# Verify Arrow is available
pkg-config --modversion arrow-glib
# Should output version number (e.g., 10.0.0)
```

**If still failing**: Try updating flake:
```bash
nix flake update
nix develop
```

---

## Build Issues

### "dune: command not found"

**Problem**: Not inside Nix development shell.

**Solution**:
```bash
nix develop
# Now dune should be available
```

---

### "Error: Unbound module Ast"

**Problem**: Modules not compiled or dependency issue.

**Solution**:
```bash
dune clean
dune build
```

**If still failing**: Check `dune` file includes necessary modules.

---

### Menhir shift/reduce conflicts

**Problem**: Parser grammar has ambiguities.

**Example output**:
```
Warning: 2 shift/reduce conflicts
```

**Solution** (for contributors):
- Review `parser.mly` for ambiguous rules
- Add precedence directives (`%left`, `%right`)
- Refactor grammar to remove ambiguity

**For users**: Warnings are okay if parser works correctly. Errors must be fixed.

---

## Runtime Errors

### "Error(NameError: 'x' is not defined)"

**Problem**: Variable or function doesn't exist in current scope.

**Solution**:
1. Check spelling: `prnt` → `print`
2. Check if variable was assigned
3. Check if function is in standard library

**Check available functions**:
```t
> type(print)
"Function"

> type(undefined_func)
Error(NameError: ...)
```

---

### "Error(TypeError: Cannot add Int and String)"

**Problem**: Incompatible types in operation.

**Solution**: Explicit conversion (if available):
```t
-- Bad
"Age: " + 25
-- Error: Cannot add String and Int

-- Workaround: Convert manually or use string concatenation with print
-- Note: Alpha does not have a string() conversion function yet
-- Use print for output instead:
print("Age: ")
print(25)
```

---

### "Error(NAError: NA value encountered)"

**Problem**: Operation on NA without explicit handling.

**Solution**: Use `na_rm = true`:
```t
-- Bad
mean([1, 2, NA, 4])

-- Good
mean([1, 2, NA, 4], na_rm = true)
```

---

### "Error(DivisionByZero: Division by zero)"

**Problem**: Dividing by zero.

**Solution**: Guard condition:
```t
-- Bad
x / y

-- Good
if (y == 0) 0.0 else x / y

-- Or use error recovery
(x / y) ?|> \(result) if (is_error(result)) 0.0 else result
```

---

### Segmentation fault (crash)

**Problem**: Usually in Arrow FFI or native code.

**Debugging**:
```bash
# Run with valgrind
valgrind --leak-check=full dune exec src/repl.exe
```

**Workaround**: Avoid Arrow operations, use fallback:
```t
-- May crash with large native DataFrames
df = read_csv("huge.csv")

-- Try smaller data or manual loading
```

**Report**: This is a bug. Please report with minimal reproducible example.

---

## REPL Issues

### REPL doesn't show output

**Problem**: Silent evaluation (no `print`).

**Solution**:
```t
-- Expressions at top-level are printed
> 2 + 3
5

-- But assignments are not
> x = 10
10  -- (value shown but not detailed)

-- Use print for detailed output
> print(x)
10
```

---

### REPL exits on error

**Problem**: Severe error or assertion failure.

**Solution**: Restart REPL. Check what caused the crash and report if reproducible.

---

### REPL hangs on input

**Problem**: Waiting for multiline completion or invalid syntax.

**Solution**:
- Press Ctrl+C to cancel
- Check for unclosed `(`, `{`, `[`

---

## Data Loading Issues

### "Error: File not found"

**Problem**: CSV file doesn't exist or wrong path.

**Solution**:
```t
-- Bad (relative to unknown location)
df = read_csv("data.csv")

-- Good (absolute or known relative path)
df = read_csv("/home/user/project/data.csv")

-- Or check file exists first
ls data.csv  # In shell
```

---

### CSV loads with wrong types

**Problem**: Arrow infers types from first rows.

**Solution**: Ensure data is consistent:
- No mixed types in columns
- Missing values represented as empty strings (inferred as NA)
- Numeric columns don't have text

**Workaround**: Preprocess CSV externally or load as strings and convert.

---

### Column names have special characters

**Problem**: Column names like `"Growth%"` not accessible.

**Solution**: Use `clean_colnames = true`:
```t
df = read_csv("data.csv", clean_colnames = true)
-- "Growth%" becomes "growth_percent"
```

---

## Performance Issues

### Operations are very slow

**Problem**: Alpha interpreter is slow, especially for large data.

**Solutions**:
1. **Reduce data size**: Filter early in pipeline
2. **Use native Arrow operations** when available
3. **Chunk processing**: Split large files

**Example**:
```t
-- Slow: Load everything then filter
df = read_csv("huge.csv")
small = df |> filter(\(row) row.year == 2023)

-- Better: Filter during load (if supported) or filter immediately
df = read_csv("huge.csv")
small = df |> filter(\(row) row.year == 2023)  -- Filter early
```

---

### Out of memory

**Problem**: Loading large datasets exhausts RAM.

**Solutions**:
1. **Use streaming** (not yet available)
2. **Process in chunks** (manually split CSV)
3. **Reduce data** before loading:
   ```bash
   # In shell, filter before loading
   grep "2023" huge.csv > subset.csv
   ```

---

## Testing Issues

### Tests fail with floating-point differences

**Problem**: Precision differences across platforms.

**Example**:
```
Expected: 2.333333333
Got:      2.333333334
```

**Solution**: This is acceptable if difference < 1e-6. Update test to allow tolerance.

---

### Golden tests fail (T vs R output differs)

**Possible causes**:
1. Floating-point precision
2. NA handling differences
3. Sorting order for ties

**Solution**: Check if differences are significant or just numerical noise.

---

## Platform-Specific Issues

### macOS: "library not found for -larrow"

**Problem**: Arrow libraries not in library path.

**Solution**: Use Nix shell (this shouldn't happen):
```bash
nix develop
```

If Nix fails, check `flake.nix` for macOS-specific configuration.

---

### WSL2: "Permission denied"

**Problem**: File on Windows mount (`/mnt/c/...`) instead of Linux filesystem.

**Solution**: Clone repository to Linux filesystem:
```bash
# Bad (Windows mount)
cd /mnt/c/Users/username/tlang

# Good (Linux filesystem)
cd ~/tlang
```

---

## Advanced Troubleshooting

### Enable debug logging

**Modify `eval.ml`** (for contributors):
```ocaml
let debug = ref true

let eval env expr =
  if !debug then
    Printf.eprintf "DEBUG: eval %s\n" (show_expr expr);
  (* ... *)
```

---

### Inspect Nix build

**See what Nix is building**:
```bash
nix develop --show-trace
```

**Check Nix store**:
```bash
ls /nix/store/ | grep arrow
ls /nix/store/ | grep ocaml
```

---

### Clean rebuild

**Nuclear option** (removes all build artifacts):
```bash
dune clean
rm -rf _build
nix develop --command dune build
```

---

## Getting More Help

### Before asking for help

1. **Check this guide**
2. **Search [GitHub Issues](https://github.com/b-rodrigues/tlang/issues)**
3. **Try minimal reproducible example**

### When asking for help

Include:
- **Exact error message**
- **Minimal code to reproduce**
- **Your environment**:
  ```bash
  uname -a
  nix --version
  # Inside nix develop:
  ocaml --version
  dune --version
  pkg-config --modversion arrow-glib
  ```

### Where to ask

- **Bugs**: [GitHub Issues](https://github.com/b-rodrigues/tlang/issues)
- **Questions**: [GitHub Discussions](https://github.com/b-rodrigues/tlang/discussions)
- **Documentation improvements**: Pull requests

---

**Still stuck?** Create a [GitHub Issue](https://github.com/b-rodrigues/tlang/issues/new) with details!
