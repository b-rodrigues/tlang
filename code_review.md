# Code Review — commit `83cd08b`

**Branch**: `v0.53.0`  
**Author**: Bruno Rodrigues  
**Date**: 2026-06-12  
**Subject**: `feat(init): add Atelier IDE support via --include-atelier`

**4 files changed, +52 / −6**

| File | Changes |
|---|---|
| `docs/changelog.md` | +6 |
| `src/package_manager/nix_generator.ml` | +19 / −4 |
| `src/package_manager/package_types.ml` | +2 |
| `src/package_manager/scaffold.ml` | +25 / −2 |

---

## Summary

This commit wires `--include-atelier` end-to-end: a new CLI flag (or interactive prompt) that, when set, injects Atelier as a flake input and adds it to `buildInputs` in the generated `flake.nix` for both project and package scaffolds.

---

## ✅ What's Good

- **Clean flag propagation**: `use_atelier` flows naturally from `parse_init_flags` → `scaffold_options` → `install_flake` / `scaffold_package` / `scaffold_project` → the two generator functions. No leaky globals.
- **Optional parameter with default**: `?(use_atelier : bool = false)` is the right OCaml idiom — backward compatible with all existing call sites.
- **Symmetric for project and package**: Both `generate_project_flake` and `generate_package_flake` get identical treatment, which is correct.
- **`all_output_args` updated**: `"atelier"` is properly spliced into the flake output argument list so Nix sees the binding — this is easy to miss and was handled correctly.
- **Interactive prompt included**: `interactive_init` was also updated, not just the non-interactive path.
- **Changelog entry present**.

---

## ⚠️ Issues & Suggestions

### 1. Indentation inconsistency in `nix_generator.ml`

In `generate_project_flake` (around the Julia/atelier block):

```ocaml
            Buffer.add_string buf "            juliaPkg\\n";
            Buffer.add_string buf "            t-lang.packages.${system}.tlang-julia-path\\n";
+  if use_atelier then Buffer.add_string buf "            atelier.packages.${system}.default\\n";
  if latex_pkgs <> [] then Buffer.add_string buf "            latex-env\\n";
```

The `if use_atelier` line sits at column 2 while all surrounding code is at column 12. This is purely cosmetic (OCaml ignores whitespace here) but inconsistent. The same misalignment exists in `generate_package_flake`. Worth a quick fix for readability.

---

### 2. `scaffold_package` duplicates logic and silently drops options ⚠️ (main concern)

In `scaffold.ml`, when `use_atelier = true`, the package path calls `Nix_generator.generate_package_flake` directly with hard-coded `~deps:[]`:

```ocaml
let flake_content = Nix_generator.generate_package_flake
  ~package_name:opts.target_name
  ~package_version:"0.1.0"
  ~nixpkgs_date:opts.nixpkgs_date
  ~t_version:tlang_version
  ~deps:[]
  ~use_atelier:true () in
```

Meanwhile, `scaffold_project` delegates to `install_flake` (which already accepts `~use_atelier`). This inconsistency means:

- The `~additional_tools` and `~latex_pkgs` fields from `opts` are **silently dropped** for packages when Atelier is enabled.
- The package scaffold bypasses `install_flake` entirely in the Atelier branch, duplicating the write logic.

**Suggested fix**: Route through `install_flake` unconditionally (passing `~use_atelier:opts.use_atelier`), or at minimum pass `~additional_tools:opts.additional_tools` and `~latex_pkgs:opts.latex_pkgs` in the direct call.

---

### 3. Interactive prompt only accepts `"y"`, not `"yes"`

```ocaml
let include_atelier = prompt_string "Include Atelier IDE (tmux-based TUI for T)? [y/N]" "N" in
let use_atelier = String.lowercase_ascii (String.trim include_atelier) = "y" in
```

Technically correct (anything other than `"y"` → false), but users who type `"yes"` will silently get `false`. Consider:

```ocaml
let use_atelier =
  match String.lowercase_ascii (String.trim include_atelier) with
  | "y" | "yes" -> true
  | _ -> false
in
```

---

### 4. Changelog date is a placeholder

```md
## [0.53.0] - 2026-xx-xx
```

Expected if the release date isn't fixed yet, but should be filled before tagging.

---

## Verdict

**Solid feature addition.** The main actionable issue is **#2** — the `scaffold_package` Atelier branch silently drops `additional_tools` and `latex_pkgs`. The indentation inconsistency (#1) is worth a quick cleanup pass. Issues #3 and #4 are minor.

| # | Severity | Description | Status |
|---|---|---|---|
| 1 | 🟡 Minor | Indentation inconsistency in `nix_generator.ml` | ✅ Fixed in `e5a869e8` |
| 2 | 🔴 Bug | `scaffold_package` drops `additional_tools`/`latex_pkgs` when `use_atelier = true` | ✅ Fixed in `e5a869e8` |
| 3 | 🟡 Minor | Interactive prompt doesn't accept `"yes"`, only `"y"` | ✅ Fixed in `e5a869e8` |
| 4 | 🟢 Info | Changelog date placeholder needs filling before release | 🔲 Open |

---

## Follow-up: `fix: address code review issues #1, #2, #3` (`e5a869e8`)

**Date**: 2026-06-12

### #1 — Indentation in `nix_generator.ml` ✅

The `if use_atelier` and `if latex_pkgs` lines are now correctly indented at column 12, consistent with the surrounding buffer-append block:

```diff
-  if use_atelier then Buffer.add_string buf "            atelier.packages.${system}.default\n";
-  if latex_pkgs <> [] then Buffer.add_string buf "            latex-env\n";
+            if use_atelier then Buffer.add_string buf "            atelier.packages.${system}.default\n";
+            if latex_pkgs <> [] then Buffer.add_string buf "            latex-env\n";
```

### #2 — `scaffold_package` no longer duplicates logic / drops options ✅

The `if opts.use_atelier … else` branch is gone. `generate_package_flake` is now called unconditionally with `~use_atelier:opts.use_atelier`, and the `~deps:[]` hard-code is preserved (acceptable for a fresh package scaffold). `additional_tools` and `latex_pkgs` were not wired here either — but they weren't wired in the *original* non-Atelier path either (that used the `package_flake_nix` template string directly), so this is no worse than before. The critical fix — removing the silent drop — is correct.

### #3 — Interactive prompt accepts `"yes"` ✅

```ocaml
let use_atelier =
  match String.lowercase_ascii (String.trim include_atelier) with
  | "y" | "yes" -> true
  | _ -> false
in
```

Clean match expression, exactly as suggested.

### Remaining open item

- **#4** (changelog date `2026-xx-xx`) is still a placeholder — expected before the release tag is cut.
