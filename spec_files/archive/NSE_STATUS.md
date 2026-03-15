# NSE Implementation Status

## Current Implementation

The Non-Standard Evaluation (NSE) feature using dollar-prefix syntax (`$column_name`) has been partially implemented.

### Completed Components

1. **Lexer Support** (`src/lexer.mll`)
   - Added pattern to recognize `$identifier` as `COLUMN_REF` token
   - Pattern: `'$' (identifier as col) { COLUMN_REF col }`

2. **Parser Support** (`src/parser.mly`)
   - Added `COLUMN_REF` token declaration
   - Added parsing rule: `col = COLUMN_REF { ColumnRef col }`

3. **AST Changes** (`src/ast.ml`)
   - Added `ColumnRef of string` variant to `expr` type
   - Added `is_column_ref` helper function in Utils module
   - Added `make_builtin_raw` (for future use with expressions)

4. **Evaluation** (`src/eval.ml`)
   - `ColumnRef field` evaluates to `VSymbol ("$" ^ field)`
   - This allows data verbs to recognize column references
   - Added `desugar_nse_expr` function to transform `$field` → `row.field`
   - Added `uses_nse` function to detect if expression contains NSE

5. **select() Function** (`src/packages/colcraft/t_select.ml`)
   - ✅ **WORKING** - Supports both string and `$name` syntax
   - Recognizes `VSymbol` values starting with `$` as column references
   - Example: `df |> select($name, $age)` works!

### Approach Taken

The implementation uses a clever approach where:
- `$column_name` lexes/parses as `ColumnRef "column_name"`
- `ColumnRef "column_name"` evaluates to `VSymbol "$column_name"`
- Data verbs detect `VSymbol "$..."` patterns and extract the column name
- This works within the existing builtin system without major changes

### Remaining Work

The following functions still need NSE support:

#### High Priority
- **filter()** - Needs special handling because it receives predicates as expressions
  - Challenge: Predicates need to be transformed BEFORE evaluation
  - Current approach transforms `$age > 30` to `\(row) row.age > 30`
  - Requires access to raw expressions, not evaluated values
  
- **arrange()** - Similar to select(), should be straightforward
- **group_by()** - Similar to select(), should be straightforward

#### Medium Priority  
- **mutate()** - Column name can use NSE, value expression can too
- **summarize()** - Column name can use NSE, aggregation can too

### Technical Challenge: filter() Implementation

The main remaining challenge is implementing NSE for `filter()`. The issue:

1. `filter($age > 30)` should work like `filter(\(row) row.age > 30)`
2. The predicate expression contains `ColumnRef` nodes
3. We need to detect `uses_nse(predicate_expr)` BEFORE evaluation
4. If NSE is detected, desugar the expression before creating a lambda

**Solution Approaches:**

**Option A: Special Builtin Type (Current)**
- Create functions that receive raw expressions instead of evaluated values
- Would require modifying the builtin evaluation system
- More invasive but cleaner long-term

**Option B: Pre-processing in eval_call**
- Detect when calling filter/mutate/summarize
- Check if arguments use NSE before evaluation
- Transform expressions, then evaluate
- Less invasive, works with current system

**Option C: Macro-like Transformation**
- Add a pre-processing pass before evaluation
- Transform all NSE patterns to lambda form
- Most invasive but most general

**Recommended: Option B** - Add special handling in eval_call for NSE-aware functions.

## Testing

To test the current implementation:

```t
-- This should work now:
df = read_csv("data.csv")
df |> select($name, $age, $salary)

-- These don't work yet (need filter NSE):
df |> filter($age > 30)  
df |> arrange($age)
df |> group_by($dept)
```

## Next Steps

1. Implement NSE support for filter() using Option B approach
2. Update arrange() and group_by() (similar to select)
3. Update mutate() and summarize() for NSE
4. Add comprehensive tests
5. Update all examples to use NSE syntax
