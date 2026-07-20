# expect() Contract System — Removed in v0.54.x

**Status:** Removed  
**Removed in:** v0.54.x (commit series)  
**Author:** b-rodrigues  

## What It Was

`expect()` was a static schema contract annotation for pipeline nodes. It was a **no-op at runtime** — the function simply returned its input unchanged. Its entire purpose was static analysis via `t check --schema`.

## Syntax

```t
clean = raw
  |> read_csv("data.csv")
  |> filter($status == "complete")
  |> mutate($score = as.numeric($score))
  |> expect(columns = ["id", "name", "score"])
```

Mixed contracts:

```t
clean = raw
  |> expect(columns = ["id", "amount", "region"],
             amount ~ double(),
             null_rate("amount") < 0.02)
```

## Three Contract Types

1. **Column presence** (`columns = [...]`) — verified statically; missing columns produced `contract_violation` errors
2. **Type contract** (`col ~ type()`) — verified statically when column type was known (e.g. from CSV headers); mismatches produced `contract_violation` warnings with a `Cast` suggested fix
3. **Null-rate contract** (`null_rate("col") < threshold`) — could not be verified statically; always emitted `contract_unverifiable` warnings

## Architecture

### Files involved

| File | Role |
|------|------|
| `src/packages/pipeline/expect.ml` | Registered `expect` as a no-op builtin (pass-through) |
| `src/ast.ml` | Defined `expect_contract` type: `Contract_columns`, `Contract_type`, `Contract_null_rate` |
| `src/schema_check.ml` | Core engine: `Expect` verb classification, `extract_contracts`, `validate_contracts`, placement validation loop |
| `src/diagnostics.ml` | Error classes: `Contract_violation`, `Contract_unverifiable`, `Invalid_expect_placement`; `Cast` fix variant and `make_cast_fix` helper |
| `src/fix.ml` | `apply_cast` function — inserted `mutate($col = as.type($col))` before expect() node |
| `src/packages/pipeline/t_fix.ml` | REPL-callable `t fix` — always ran with `schema:true` to trigger contract validation |
| `src/packages/core/packages.ml` | Registered `Expect.register` and listed `"expect"` in `known_symbols` |

### Data flow

1. User writes `|> expect(columns = [...], col ~ type(), null_rate("col") < n)` in a `.t` file
2. `expect.ml` registers `expect` as a builtin that is a no-op pass-through at runtime
3. `ast.ml` defines `expect_contract` type with three variants
4. `schema_check.ml` is the core engine:
   - `classify_verb` maps `"expect"` to the `Expect` variant
   - `infer_output_schema` passes schema through unchanged for `Expect`
   - `extract_contracts` parses expect() args into contract types
   - `validate_contracts` checks contracts against the inferred schema
   - The main validation loop checks placement (last vs mid-chain) and triggers extraction/validation
5. `diagnostics.ml` defines `Contract_violation`, `Contract_unverifiable`, and `Invalid_expect_placement` error classes
6. `fix.ml` applies mechanical `Cast` fixes for type contract violations

### Diagnostic error classes removed

- `Contract_violation` — column missing or type mismatch
- `Contract_unverifiable` — contract cannot be verified statically (e.g. null-rate)
- `Invalid_expect_placement` — expect() not in last position of pipe chain

### Suggested fix type removed

- `Cast` — inserted `|> mutate($col = as.type($col))` before the expect() node when a type contract violation was detected

## Why It Was Removed

The user decided to remove `expect()` completely in favor of adding more precise features in a future release. Key reasons:

1. **Null-rate contracts were unverifiable** — they always emitted warnings without actionable information
2. **Type contracts were limited** — only worked when column types were known from CSV headers
3. **The feature added complexity** (~250 lines of implementation + ~120 lines of tests) for limited practical value
4. **Future alternatives** may provide more precise validation mechanisms

## What Was Kept

- The `diag_expected` field in diagnostics — used by many other error classes (type mismatches, missing packages, etc.)
- The `confidence` system in suggested_fix — used by other fix types (Rename_column, Suggest_identifier, etc.)
- Schema validation infrastructure in `schema_check.ml` — column reference checking, schema propagation, type inference all remain

## What Was Deleted

### Implementation (~250 lines)
- `src/packages/pipeline/expect.ml` (entire file)
- `src/ast.ml`: `expect_contract` type and its three variants
- `src/diagnostics.ml`: `Contract_violation`, `Contract_unverifiable`, `Invalid_expect_placement` error classes; `Cast` fix variant; `make_cast_fix`; `confidence_for_cast`
- `src/fix.ml`: `apply_cast` function and Cast handling in `apply_fix`
- `src/schema_check.ml`: `Expect` verb variant; `extract_contracts`; `validate_contracts`; expect() placement validation loop
- `src/packages/core/packages.ml`: `Expect.register` call and `"expect"` from `known_symbols`

### Tests (~120 lines)
- `tests/test_fix.ml`: Cast fix tests and expect()-using fixtures
- `tests/test_check.ml`: schema_cast confidence tests
- `tests/golden/t_scripts/schema_cast_broken.t` and `schema_cast_unbroken.t`

### Documentation
- `docs/api-reference.md`: Full `expect()` section, `cast` row in suggested_fix table, contract error classes
- `summary.md`: Shape Contracts section
- `AGENTS.md`: expect() workflow steps and shape contracts section
- `docs/changelog.md`: expect() entries
- `agents/t-reference-huge.md`: expect() documentation

## Potential Future Reintroduction

If reintroduced, consider:
- Runtime-verifiable contracts (not just static)
- Integration with `NA` handling rather than separate null-rate checks
- Stronger type propagation that works across R/Python/Julia nodes
- Contract syntax that doesn't require being the last node in a pipe chain
