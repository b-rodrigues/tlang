# Arrow Native Path Audit

Audit of `values_to_column` type inference, native write-path routing, and
round-trip fidelity for all column types.

---

## 1. `values_to_column` — Type Detection

**File:** `src/arrow/arrow_bridge.ml:83-188`

### Algorithm

Scan the value array once, setting type flags (`has_int`, `has_float`, …) and
`all_na`. Then route via priority chain:

```
all_na?               → NAColumn          [line 122]
has_dataframe?        → ListColumn        [line 124]
has_factor?           → DictionaryColumn  [line 133]
has_datetime?         → DatetimeColumn    [line 140]
has_date?             → DateColumn        [line 154]
has_string? OR
  factor_inconsistent → StringColumn      [line 160]
has_float?            → FloatColumn       [line 168]
has_int?              → IntColumn         [line 175]
has_bool?             → BoolColumn        [line 181]
else                  → NAColumn          [line 187]
```

### Type flags set by each value variant

| Value variant | Flags set | `all_na` affected? |
|---|---|---|
| `VInt _` | `has_int := true` | `all_na := false` |
| `VFloat _` | `has_float := true` | `all_na := false` |
| `VBool _` | `has_bool := true` | `all_na := false` |
| `VString _` | `has_string := true` | `all_na := false` |
| `VDate _` | `has_date := true` | `all_na := false` |
| `VDatetime _` | `has_datetime := true` | `all_na := false` |
| `VDataFrame _` | `has_dataframe := true` | `all_na := false` |
| `VFactor (_, l, o)` | `has_factor, factor_levels, factor_ordered` | `all_na := false` |
| `VNA _` | (none) | (none — `all_na` stays) |
| any other (fallback) | `has_string := true` | `all_na := false` |

### Guard conditions for each route

| Route | Guard (must be true) | Guard (must be false) |
|---|---|---|
| `ListColumn` | `has_dataframe` | no mixed scalar types |
| `DictionaryColumn` | `has_factor` | `factor_inconsistent` |
| `DatetimeColumn` | `has_datetime` | `has_int \|\| has_float \|\| has_bool \|\| has_string \|\| has_date \|\| has_factor` |
| `DateColumn` | `has_date` | `has_int \|\| has_float \|\| has_bool \|\| has_string \|\| has_datetime \|\| has_factor` |
| `StringColumn` | `has_string \|\| factor_inconsistent` | (none) |
| `FloatColumn` | `has_float` | (fallen through from earlier) |
| `IntColumn` | `has_int` | (fallen through from earlier) |
| `BoolColumn` | `has_bool` | (fallen through from earlier) |

### Key observation: priority means types are **lossy** when mixed

If a column has `[VInt 1; VString "a"]`, the String route fires (line 160) and
VInt is stringified. This is by design — Arrow columns are homogeneous.

---

## 2. Native Materialization Support

**File:** `src/arrow/arrow_table.ml:512-519`

```ocaml
let is_arrow_table_new_supported = function
  | IntColumn _ | FloatColumn _ | BoolColumn _ | StringColumn _
  | DateColumn _ | NAColumn _ | DictionaryColumn _ -> true
  | ListColumn a -> is_supported_list_column a
  | DatetimeColumn _ -> true
```

**All column types** are supported for native materialization:

| Column type | Native write support | Notes |
|---|---|---|
| `IntColumn` | ✅ | Tag 0 in C FFI |
| `FloatColumn` | ✅ | Tag 1 |
| `BoolColumn` | ✅ | Tag 2 |
| `StringColumn` | ✅ | Tag 3 |
| `DictionaryColumn` | ✅ | Tag 4 — empty level list handled |
| `ListColumn` | ✅ (conditional) | Tag 5 — needs all-primitive struct fields |
| `NAColumn` | ✅ | Tag 6 — all-null bitmap |
| `DateColumn` | ✅ | Tag 7 |
| `DatetimeColumn` | ✅ | Tag 8 — with optional timezone |

**No column type is rejected by `materialize`.** If `arrow_table_new` fails at
the C level (e.g. empty dictionary), the table silently falls back to OCaml
storage with a warning. The OCaml storage path is always functional.

**Implication:** routing is the only gate. If `values_to_column` produces the
correct `column_data` variant, materialization will attempt native write.

---

## 3. All Callers of `values_to_column`

Every call site that produces a column from T values and thus depends on
correct type inference.

### `src/packages/colcraft/mutate.ml` — 6 call sites

| Line | Context | Type risk |
|---|---|---|
| 266 | Grouped mutate fallback: `new_col` built per-group then `values_to_column` | All-NA per-group result → NAColumn |
| 284 | Ungrouped mutate: `VVector vec` from `eval_call` | **PRIMARY PATH** — `to_factor`, `to_date`, etc. all flow here |
| 289 | Ungrouped mutate: `VList items` converted to vec | Same risk |
| 294 | Ungrouped mutate: scalar broadcast `Array.make nrows res` | Single value broadcast — always typed |
| 310 | Per-row eval fallback: `new_col` built row-by-row | All-NA eval results → NAColumn |
| 322 | `apply_vector_mutation`: direct vector assignment | **SECONDARY PATH** — user provides typed vector |

### `src/packages/lens/lens.ml` — 7 call sites

| Line(s) | Context | Type risk |
|---|---|---|
| 45, 48, 51 | `col_lens_set_impl`: set column to a value/vector | Scalar broadcast or recycling — always typed |
| 190 | `row_lens_set_impl`: update single cell in column | Single cell mutation — column already has type |
| 200 | `row_lens_set_impl`: add new column from row dict | Single cell — remaining entries VNA → all-NA column → NAColumn |
| 407, 423 | `filter_lens_set`: update matched rows | Replacement values may be all-NA |

### `src/arrow/arrow_compute.ml` — 2 call sites

| Line | Context | Type risk |
|---|---|---|
| 669 | `apply_unary_math_column`: sqrt, log, exp, abs on column | Numeric output — float, never all-NA unless all input NA |
| 710 | `pow_column`: raise column to power | Same as above |

### `src/arrow/arrow_bridge.ml` — 1 call site

| Line | Context | Type risk |
|---|---|---|
| 239 | `table_from_value_columns`: build Arrow table from column arrays | Multi-column table build — hits all-NA if any column is all-NA |

### `src/packages/colcraft/separate_rows.ml` — 1 call site

| Line | Context | Type risk |
|---|---|---|
| 53 | `separate_rows`: split cell values into rows | Typed by source column — low risk |

### `src/packages/colcraft/nest.ml` — 1 call site

| Line | Context | Type risk |
|---|---|---|
| 127 | `nest`: key columns from grouped data | Key values are always present (non-NA) — no risk |

---

## 4. The All-NA Gap

### Root cause

`values_to_column` line 122-123:
```ocaml
if !all_na then
  Arrow_table.NAColumn (Array.length values)
```

When every element in the value array is `VNA _`, no type flag is set, `all_na`
remains `true`, and the column becomes `NAColumn`. All type information is lost.

### Types affected (pre-0.53.1)

| Intended type | Value variant for non-NA | NA representation | Status |
|---|---|---|---|
| IntColumn | `VInt _` | `VNA NAInt` | ❌ all-NA → NAColumn |
| FloatColumn | `VFloat _` | `VNA NAFloat` | ❌ all-NA → NAColumn |
| BoolColumn | `VBool _` | `VNA NABool` | ❌ all-NA → NAColumn |
| StringColumn | `VString _` | `VNA NAString` | ❌ all-NA → NAColumn |
| DateColumn | `VDate _` | `VNA NADate` | ❌ all-NA → NAColumn |
| DatetimeColumn | `VDatetime _` | `VNA NADate` (note: not NADatetime) | ❌ all-NA → NAColumn |
| DictionaryColumn | `VFactor _` | `VNA NAGeneric` | ✅ **fixed** in 0.53.1 via sentinel |
| ListColumn | `VDataFrame _` | `VNA NAGeneric` | ❌ all-NA → NAColumn |

### Practical severity

| Type | Likelihood of all-NA in practice | Severity |
|---|---|---|
| **DictionaryColumn** | High — `to_factor` with NA input before categories arrive | **Fixed** |
| DatetimeColumn | Medium — date parsing on NA column | Medium |
| DateColumn | Medium — same | Medium |
| IntColumn | Low — ints are typically present | Low |
| FloatColumn | Low — same | Low |
| BoolColumn | Low | Low |
| StringColumn | Low | Low |
| ListColumn | Very low — list columns from nesting always have data | Low |

### The `NAFactor` sentinel pattern (applied in 0.53.1)

The fix for Factor was: inject one `VFactor (-1, levels, ordered)` into the
value array so `has_factor` fires, but guard the DictionaryColumn builder with
`when i >= 0` so negative-index VFactor produces `None` (null) in the Arrow
bitmap. This could be generalized to other types.

### Generalization approaches

**Approach A – `NAFactor`-style sentinel per type:** For each type, inject a
sentinel value variant with a flag that means "null" (e.g. `VDate(-1)` with
negative day number, `VDatetime(-1L, tz)` with negative micros, etc.). The
column builder guards against the sentinel value. *Downside: sentinel values
may collide with real values.*

**Approach B – `~type_hint` parameter on `values_to_column`:** Add an optional
type hint so callers can specify the intended column type. When `all_na` and
type hint is provided, use the hinted column type. *Downside: requires threading
hints through all callers.*

**Approach C – NA type tags:** The `na_type` variant already carries type info
(`NAInt`, `NAFloat`, etc.). `values_to_column` already sees `VNA NAInt` but
currently ignores it (`VNA _ -> ()`). Could set `has_int := true` on `VNA NAInt`
and produce `IntColumn` with all-null entries. *Cleanest — no new API, no
sentinel values. The metadata is already in the NA tag.*

---

## 5. Round-Trip Fidelity

### `column_to_values` → `values_to_column` round-trip

| Column type | `column_to_values` output | `values_to_column` re-route | Fidelity |
|---|---|---|---|
| `IntColumn` | `VInt` / `VNA NAInt` | `IntColumn` | ✅ Exact |
| `FloatColumn` | `VFloat` / `VNA NAFloat` | `FloatColumn` | ✅ Exact |
| `BoolColumn` | `VBool` / `VNA NABool` | `BoolColumn` | ✅ Exact |
| `StringColumn` | `VString` / `VNA NAString` | `StringColumn` | ✅ Exact |
| `DateColumn` | `VDate` / `VNA NADate` | `DateColumn` | ✅ Exact |
| `DatetimeColumn` | `VDatetime` / `VNA NADate` | `DatetimeColumn` | ✅ Exact (tz preserved) |
| `NAColumn` | `VNA NAGeneric` | `NAColumn` | ✅ Exact |
| `DictionaryColumn` | `VFactor` / `VNA NAGeneric` | `DictionaryColumn` | ✅ Exact |
| `ListColumn` | `VDataFrame` / `VNA NAGeneric` | `ListColumn` | ✅ Exact |

### Fidelity by operation path

**`mutate` with non-NA typed output:** ✅ Works. `eval_call` returns
`VVector` of typed values → `values_to_column` infers type correctly →
`add_column` + `materialize` → native Arrow.

**`mutate` with all-NA typed output for Factor:** ✅ Fixed in 0.53.1.
Sentinel `VFactor (-1, levels, ordered)` preserves `DictionaryColumn` type.

**`mutate` with all-NA typed output for other types:** ❌ Currently `NAColumn`.
Native path breaks.

**CSV read → mutate → filter → collect:** ✅ Full native path works for
standard types. `explain(df).native_path_active` stays `true`.

**ListColumn (nested DataFrame) round-trip:** ✅ `column_to_values` produces
`VDataFrame` from `ListColumn`; `values_to_column` re-routes to `ListColumn`.
Struct schema must be consistent across rows for native materialization.

---

## 6. Summary of Gaps

| # | Gap | Affected | Priority |
|---|---|---|---|
| 1 | All-NA type erasure → `NAColumn` for all non-Factor types | `mutate` with `to_date`, `as.integer` etc. on all-NA input | Medium |
| 2 | Per-row eval fallback in `mutate` (line 310) also hits all-NA gap | Any grouped/per-row eval producing all-NA | Low |
| 3 | `lens.ml` row_lens / filter_lens can produce all-NA columns | Lens operations adding new columns from all-NA data | Low |
| 4 | `table_from_value_columns` (aggregation path) | `group_aggregate_ocaml` producing all-NA group results | Low |

### Recommendations

1. **Generalize fix via NA type tags (Approach C):** In `values_to_column`,
   change the `VNA _ -> ()` arm to set the corresponding type flag based on
   the NA tag:
   ```
   VNA NAInt → has_int := true
   VNA NAFloat → has_float := true
   VNA NABool → has_bool := true
   VNA NAString → has_string := true
   VNA NADate → has_date := true
   VNA NAGeneric → ()  (keep as-is — ambiguous)
   ```
   `VDatetime` NA uses `VNA NADate` (see line 26), so datetime needs separate
   handling — could add a `NADatetime` variant or detect datetime NAs via the
   sentinel pattern.

   This is a one-line change per type, requires no threading of hints, and
   uses information already present in the value representation.

2. **Consider `VNA NADatetime` variant:** Currently datetime NAs reuse
   `VNA NADate`. Adding `NADatetime` would let `values_to_column`
   distinguish date vs datetime NA columns naturally.

3. **Add end-to-end test:** `mutate(df, $col = to_factor(all_NA)) |> filter(...)`
   with `explain()` asserting `native_path_active = true`.
