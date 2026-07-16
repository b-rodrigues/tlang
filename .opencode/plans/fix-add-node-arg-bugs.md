# Fix: apply_add_node_arg correctness bugs

## Context

Feature 6.5 (commit `91b216cb`) introduced `apply_add_node_arg` and cross-runtime deserializer generation. Code review identified five bugs that would produce broken pipeline files or silent failures.

## Bug 1: Missing comma (Critical — produces syntax errors)

**Location:** `src/fix.ml:145-154`

When inserting `serializer = ^csv` before the closing `)`, the previous line (`runtime = T`) has no trailing comma. Result:
```
runtime = T
serializer = ^csv
)
```
This is a parse error — T arguments are comma-separated.

**Fix:** Before inserting the new arg line, check if the last collected line (the line just before closing `)`) ends with `,` or `)`. If not, append `,` to it in the `lines` list.

```ocaml
(* Before inserting the new arg, ensure previous line has a trailing comma *)
let prev_line = List.hd !lines in
let trimmed_prev = String.trim prev_line in
let last_char = trimmed_prev.[String.length trimmed_prev - 1] in
if last_char <> ',' && last_char <> '(' then begin
  lines := (prev_line ^ ",") :: List.tl !lines
end;
lines := l :: Printf.sprintf "%s%s" pad arg :: !lines
```

## Bug 2: `apply_add_node_arg` doesn't report failure (Medium)

**Location:** `src/fix.ml:83,166-175`

`apply_add_node_arg` returns `unit` and `apply_fix` hardcodes `true`. If the node name is `""` (from `None` in `of_verror`) or the node isn't found, the file is rewritten unchanged but the caller thinks it succeeded.

**Fix:**
- Change `apply_add_node_arg` to return `bool` — `true` if `found` was set, `false` otherwise.
- In `apply_fix`, propagate the return value: `apply_add_node_arg ~file ~node ~arg`.

## Bug 3: Indentation from wrong line (Low — cosmetic but malformed)

**Location:** `src/fix.ml:147-152`

The new arg's indent is taken from the closing `)` line (column 0) instead of sibling arguments (column 2). Result: the new arg is unindented.

**Fix:** Track the indentation of the last argument line seen while scanning. Use that for the new arg's indent instead of the closing paren's indent.

Add a ref `last_arg_indent = ref 0` before the while loop. In the `found` branch (inside the node call), after each line that isn't the closing paren, update:
```ocaml
let trimmed_l = String.trim l in
if trimmed_l <> "" then
  last_arg_indent := let rec count s n = if n < String.length s && s.[n] = ' ' then count s (n+1) else n in count l 0
```

Then use `!last_arg_indent` instead of `count l 0` for the pad.

## Bug 4: Hardcoded `^csv` regardless of dep runtime (Medium)

**Location:** `src/diagnostics.ml:375-389`

The error message contains the dependency's runtime in parens: `` `rn` (R) ``. The fix always suggests `deserializer = ^csv` even for Julia→R dependencies where `^arrow` would be more appropriate.

**Fix:** Extract the dependency runtime from the error message with a single combined regex. Map runtime → appropriate serializer:

```ocaml
(* Single regex: "depends on `name` (Runtime)" *)
let re = Str.regexp "depends on `\\([^`]+\\)` (\\([^)]+\\))" in
try
  ignore (Str.search_forward re err.message 0);
  let dep_runtime = Str.matched_group 2 err.message in
  let serializer = match dep_runtime with
    | "Julia" -> "^arrow"
    | _ -> "^csv"  (* R, Python, and unknown all default to CSV *)
  in
  Some (dep_runtime, serializer)
with Not_found -> None
```

This replaces both `extract_dep_name_from_cross_runtime_error` and the guard regex — one pass extracts everything.

## Bug 5: Redundant regex (Minor — cleanup)

**Location:** `src/diagnostics.ml:375-389`

The guard clause runs a regex to check "is this a cross-runtime message", then the match body runs `extract_dep_name_from_cross_runtime_error` with a different regex over the same string. The `None` branch is dead code.

**Fix:** Merge into a single `extract_cross_runtime_info` function that returns `Some (node, dep_name, dep_runtime, serializer)` or `None`. Use it once in the match arm.

## Files to change

| File | Change |
|------|--------|
| `src/fix.ml` | Fix comma insertion, return bool, track arg indentation |
| `src/diagnostics.ml` | Replace two regex helpers with one; map runtime→serializer; use dep info |
| `tests/test_fix.ml` | Strengthen tests: verify comma presence, check return value for not-found case, verify indentation |
| `tests/test_check.ml` | Update generation test to verify serializer mapping (Julia→^arrow, R→^csv) |

## New/updated tests

1. **Comma test:** After `apply_add_node_arg`, verify the line before the inserted arg ends with `,`.
2. **Roundtrip test:** After `apply_add_node_arg`, re-parse the file with `Parser.program Lexer.token` and verify no parse error.
3. **Not-found test:** Call `apply_add_node_arg` with a node name that doesn't exist in the file, verify it returns `false` and file is unchanged.
4. **Indentation test:** Verify the inserted arg has the same indent as sibling args.
5. **Runtime→serializer test:** `of_verror` with Julia dep message → `^arrow`; with R dep message → `^csv`.
6. **Update dispatch test:** `apply_fix` with `Add_node_arg` for non-existent node → returns `false`.

## Verification

```bash
nix develop --command bash -c 'eval "$shellHook" && dune build && dune exec tests/test_runner.exe'
```
