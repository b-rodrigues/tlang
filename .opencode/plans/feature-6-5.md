# Feature 6.5: `Add_node_arg` and `Pin_package_version` Fix Application

## Context

Features 6.1–6.4 implemented the `suggested_fix` type, serialization, and `Cast`/`Rename_column` fix application. Two variants remain stubs in `apply_fix`:
- `Add_node_arg _ -> false` (fix.ml:91)
- `Pin_package_version _ -> false` (fix.ml:92)

Neither variant is currently **generated** as a diagnostic anywhere — the spec asks to implement the mechanical application (the `apply_fix` side), not the diagnostic generation. This is plumbing so that when diagnostics are eventually generated with these fix kinds, `t fix` can apply them.

## Implementation Plan

### Step 1: `apply_add_node_arg` in `src/fix.ml`

**Goal:** Given a `.t` file, a node name, and an argument string (e.g., `"na_rm = true"`), find the node definition and insert the argument.

**Algorithm (regex-based, matching existing `apply_cast`/`apply_rename_column` style):**
1. Read the file content.
2. Find the node definition: search for `<node_name> = <function_call>(` where function_call is one of `node`, `pyn`, `rn`, `jln`, `qn`, `shn`.
3. From the opening `(`, find the matching closing `)` (handling nested parens in `command = <{ ... }>` blocks — but the closing `)` of the node call is always at indent level ≤ the opening `(`).
4. Insert `, <arg>` just before the closing `)`, on a new line with matching indentation.
5. Write the file back.

**Simpler approach (matching `apply_cast` style — line-based):**
1. Read lines from the file.
2. Find the line containing `<node_name> = ` followed by a node function call.
3. Scan forward to find the closing `)` of that call (counting open/close parens, resetting on `<{` ... `}>`).
4. Insert a new line before the `)` line with the argument, indented to match.
5. Write lines back.

**Signature:**
```ocaml
val apply_add_node_arg : file:string -> node:string -> arg:string -> unit
```

### Step 2: `apply_pin_package_version` in `src/fix.ml`

**Goal:** Given a `tproject.toml` file, a package name, and a version string, update the version constraint for that package.

**Challenge:** The current TOML format stores packages as flat string lists (e.g., `packages = ["dplyr", "readr"]`) with no per-package version info. There's no existing version-per-package mechanism.

**Approach — regex-based string replacement in the TOML file:**
1. Read the file content.
2. Search for the package name as a quoted string in the TOML: `"dplyr"`.
3. Replace it with a versioned form. Two options:
   - **Option A:** `"dplyr@1.0.0"` — simple string convention, parsed by downstream tooling.
   - **Option B:** Replace the flat string with a table: `dplyr = { version = "1.0.0" }` — but this changes the TOML structure and breaks the parser which expects `packages = ["string", ...]`.

**Recommended: Option A** — append `@version` to the package string. This is a non-breaking change to the TOML format: the string `"dplyr@1.0.0"` is still a valid TOML string in the array. Downstream Nix tooling would need to strip the version suffix, but that's a separate concern.

**Alternative (if Option A is rejected):** Use text-based replacement to find the `[r-dependencies]` (or `[py-dependencies]` / `[jl-dependencies]`) section, find the `packages = [...]` line, and replace just the target package entry. This keeps the existing parser happy but the format still needs a convention for versioning.

**Signature:**
```ocaml
val apply_pin_package_version : file:string -> pkg:string -> version:string -> unit
```

### Step 3: Update `apply_fix` dispatch

In `fix.ml:83-93`, replace the stubs:

```ocaml
| Add_node_arg { node; arg; file = _; line = _; target_node = _ } ->
    (match file with
     | Some f -> apply_add_node_arg ~file:f ~node ~arg; true
     | None -> false)
| Pin_package_version { pkg; version; file } ->
    (match file with
     | Some f -> apply_pin_package_version ~file:f ~pkg ~version; true
     | None -> false)
```

Also update `apply_fixes` dry-run logic (line 117-120) to recognize these as applicable.

### Step 4: Tests in `tests/test_fix.ml`

**`test_apply_add_node_arg`:**
- Create temp `.t` file with a node definition (multi-line, with `command` block).
- Call `apply_add_node_arg ~file ~node:"raw_data" ~arg:"na_rm = true"`.
- Read file back, verify the argument was inserted before the closing `)`.
- Verify the node's other arguments are unchanged.

**`test_apply_pin_package_version`:**
- Create temp `tproject.toml` with `packages = ["dplyr", "readr"]`.
- Call `apply_pin_package_version ~file ~pkg:"dplyr" ~version:"1.0.0"`.
- Read file back, verify `"dplyr"` was replaced with the versioned form.
- Verify `"readr"` is unchanged.

**Update `apply_fix` dispatch test:**
- Change the existing test that asserts `apply_fix returns false for Add_node_arg` to now assert it returns `true` (with a valid temp file).

**Update dry-run tests:**
- Add `Add_node_arg` and `Pin_package_version` to the dry-run counting test.

### Step 5: Documentation

- `docs/api-reference.md`: Update `t fix` section — all fix kinds now supported.
- `docs/changelog.md`: Add entry under 0.54.1.

## Files to Change

| File | Change |
|------|--------|
| `src/fix.ml` | Add `apply_add_node_arg`, `apply_pin_package_version`; update `apply_fix` dispatch and dry-run logic |
| `tests/test_fix.ml` | Add tests for both new fixes; update existing stub test |
| `docs/api-reference.md` | Update `t fix` section |
| `docs/changelog.md` | Add changelog entry |

## Verification

1. `nix develop --command bash -c 'eval "$shellHook" && dune build'`
2. `nix develop --command bash -c 'eval "$shellHook" && dune exec tests/test_runner.exe'`
3. All existing tests pass + new tests pass

## Open Questions

1. **`Pin_package_version` format:** The `@version` convention changes the semantics of the package string. Is this acceptable, or should we use a different approach (e.g., a separate `[package-versions]` section in TOML)?
2. **`Add_node_arg` for `<{ ... }>` blocks:** Node commands can span multiple lines inside `<{ ... }>`. The closing `)` of the node call is always outside the command block, so the paren-counting approach should work — but worth testing with complex nested expressions.
