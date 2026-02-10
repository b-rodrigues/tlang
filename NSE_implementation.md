# Implementation Plan: Non-Standard Evaluation (NSE) for T Language

## Overview

This document outlines the implementation plan for Non-Standard Evaluation (NSE) in T, inspired by R's tidyverse. NSE will allow users to reference DataFrame column names as bare identifiers instead of strings, making data manipulation code more concise and readable.

## Motivation

### Current Syntax (String-Based)

```t
-- Load data
df = read_csv("data.csv", clean_colnames = true)

-- Data manipulation pipeline
result = df
  |> filter(\(row) row.age > 30)
  |> select("name", "age", "salary")
  |> arrange("age", "desc")
```

### Proposed Syntax (NSE with Bare Names)

```t
-- Load data
df = read_csv("data.csv", clean_colnames = true)

-- Data manipulation pipeline
result = df
  |> filter(age > 30)
  |> select(name, age, salary)
  |> arrange(age, "desc")
```

### Benefits

1. **More Readable**: Cleaner syntax without quotes and lambda boilerplate
2. **Less Typing**: Reduces cognitive load and code verbosity
3. **Tidyverse-Like**: Familiar to R users transitioning to T
4. **Less Error-Prone**: Fewer string quotes to manage
5. **Better IDE Support**: Potential for column name autocomplete

## Design Considerations

### Three Approaches to NSE

#### Approach 1: Bare Names (Tidyverse Style)
**Syntax**: `select(name, age, salary)`

**Pros**:
- Most concise and readable
- Exactly like R tidyverse
- Least typing required

**Cons**:
- Requires sophisticated scoping rules
- May conflict with existing variables in scope
- More complex to implement
- Potential ambiguity between column names and variables

**Implementation Complexity**: High

#### Approach 2: Symbol/Accessor Syntax (Polars Style)
**Syntax**: `select(col.name, col.age, col.salary)` or `select($name, $age, $salary)`

**Pros**:
- Clear distinction between columns and variables
- Easier to implement than bare names
- No scoping ambiguity
- Familiar to Polars/Spark users

**Cons**:
- Still requires some boilerplate
- Less concise than bare names
- Not as clean as tidyverse

**Implementation Complexity**: Medium

#### Approach 3: Hybrid Approach
**Syntax**: Allow both string and bare names: `select(name, "age", salary)`

**Pros**:
- Flexible - users choose their style
- Gradual migration path from strings
- Backward compatible

**Cons**:
- Multiple ways to do the same thing
- May be confusing for newcomers
- Harder to maintain consistency

**Implementation Complexity**: Medium-High

### Recommended Approach: Start with Symbol Syntax, Evolve to Bare Names

Given T's current alpha stage and the need for rapid iteration, we recommend:

**Phase 1 (Beta)**: Implement **Symbol/Accessor Syntax** (`col.name` or `$name`)
- Lower implementation complexity
- Clear semantics
- No backward compatibility concerns

**Phase 2 (Future)**: Add **Bare Names** support
- Build on Phase 1 infrastructure
- Add sophisticated scoping resolution
- Maintain symbol syntax as alternative for disambiguating cases

This staged approach allows us to:
1. Deliver value quickly
2. Learn from user feedback
3. Avoid premature complexity
4. Keep the door open for the ideal bare names syntax

## Phase 1: Symbol/Accessor Syntax Implementation

### Option 1A: `col.name` Syntax (Recommended)

#### Example Usage
```t
df |> select(col.name, col.age, col.salary)
df |> filter(col.age > 30)
df |> mutate(col.bonus, \(row) row.salary * 0.1)  -- Keep lambda for complex expressions
df |> arrange(col.age, "desc")
```

#### Advantages
- Natural dot notation
- Consistent with existing `row.field` syntax in lambdas
- Easy to understand for users already familiar with `row.age`

### Option 1B: `$name` Syntax (Alternative)

#### Example Usage
```t
df |> select($name, $age, $salary)
df |> filter($age > 30)
df |> mutate($bonus, \(row) row.salary * 0.1)
df |> arrange($age, "desc")
```

#### Advantages
- Short and concise
- Clear marker that this is a column reference
- Familiar to R users (`$` is used for column access in R)
- Distinct from any other syntax in T

### Implementation Details for `col.name` Syntax

#### 1. Lexer Changes (`src/lexer.mll`)

No changes needed - `col` is already a valid identifier, and `.` is already tokenized.

#### 2. Parser Changes (`src/parser.mly`)

No changes needed - `col.name` is already parsed as `DotAccess { target = Var "col"; field = "name" }`.

#### 3. AST Changes (`src/ast.ml`)

Add a new special identifier detection:

```ocaml
(** Check if an expression is a column reference pattern: col.field *)
let is_column_ref expr =
  match expr with
  | DotAccess { target = Var "col"; field } -> Some field
  | _ -> None
```

#### 4. Evaluation Changes for Data Verbs

Each data verb that supports NSE needs to be updated to detect and handle column references.

**Example: `select()` in `src/packages/colcraft/t_select.ml`**

```ocaml
open Ast

let register ~eval_expr env =
  Env.add "select"
    (make_builtin ~variadic:true 1 (fun args env ->
      match args with
      | VDataFrame df :: col_args ->
          (* Convert arguments to column names *)
          let col_names = List.map (fun (name_opt, expr) ->
            (* Evaluate the expression first *)
            let v = eval_expr env expr in
            match v with
            (* NSE: col.field pattern *)
            | _ when (match Ast.is_column_ref expr with Some _ -> true | None -> false) ->
                (match Ast.is_column_ref expr with
                 | Some field -> Ok field
                 | None -> Error (make_error ValueError "Unexpected column ref"))
            (* Traditional: string literal *)
            | VString s -> Ok s
            (* Error: neither NSE nor string *)
            | _ -> Error (make_error TypeError 
                    "select() expects column names as strings or col.field syntax")
          ) col_args in
          
          (match List.find_opt Result.is_error col_names with
           | Some (Error e) -> e
           | _ ->
             let names = List.map (fun r -> match r with Ok s -> s | _ -> "") col_names in
             let missing = List.filter (fun n -> not (Arrow_table.has_column df.arrow_table n)) names in
             if missing <> [] then
               make_error KeyError (Printf.sprintf "Column(s) not found: %s" (String.concat ", " missing))
             else
               let new_table = Arrow_compute.project df.arrow_table names in
               let remaining_keys = List.filter (fun k -> List.mem k names) df.group_keys in
               VDataFrame { arrow_table = new_table; group_keys = remaining_keys })
      | _ :: _ -> make_error TypeError "select() expects a DataFrame as first argument"
      | _ -> make_error ArityError "select() requires a DataFrame and at least one column name"
    ))
    env
```

**Example: `filter()` in `src/packages/colcraft/t_filter.ml`**

For `filter()`, we need to transform NSE expressions into the traditional lambda form:

```ocaml
open Ast

(** Transform an NSE expression like (col.age > 30) into \(row) row.age > 30 *)
let rec desugar_nse_expr expr =
  match expr with
  | DotAccess { target = Var "col"; field } ->
      (* col.field → row.field *)
      DotAccess { target = Var "row"; field }
  | BinOp { op; left; right } ->
      (* Recursively transform both sides *)
      BinOp { op; left = desugar_nse_expr left; right = desugar_nse_expr right }
  | UnaryOp { op; operand } ->
      UnaryOp { op; operand = desugar_nse_expr operand }
  | Call { func; args } ->
      Call { func = desugar_nse_expr func; 
             args = List.map (fun (n, e) -> (n, desugar_nse_expr e)) args }
  | IfThenElse { condition; then_branch; else_branch } ->
      IfThenElse { 
        condition = desugar_nse_expr condition;
        then_branch = desugar_nse_expr then_branch;
        else_branch = desugar_nse_expr else_branch 
      }
  | ListExpr exprs ->
      ListExpr (List.map desugar_nse_expr exprs)
  | _ -> expr  (* Literals, variables (except col), etc. remain unchanged *)

(** Check if an expression uses NSE (contains col.field) *)
let rec uses_nse expr =
  match expr with
  | DotAccess { target = Var "col"; _ } -> true
  | BinOp { left; right; _ } -> uses_nse left || uses_nse right
  | UnaryOp { operand; _ } -> uses_nse operand
  | Call { func; args } -> uses_nse func || List.exists (fun (_, e) -> uses_nse e) args
  | IfThenElse { condition; then_branch; else_branch } ->
      uses_nse condition || uses_nse then_branch || uses_nse else_branch
  | ListExpr exprs -> List.exists uses_nse exprs
  | _ -> false

let register ~eval_expr ~eval_call env =
  Env.add "filter"
    (make_builtin ~variadic:true 1 (fun args env ->
      match args with
      | (None, df_expr) :: (None, pred_expr) :: rest when rest = [] ->
          let df_val = eval_expr env df_expr in
          (match df_val with
           | VDataFrame df ->
               (* Check if predicate uses NSE *)
               let pred_fn = if uses_nse pred_expr then
                 (* Transform col.field → row.field and wrap in lambda *)
                 let desugared_body = desugar_nse_expr pred_expr in
                 VLambda {
                   params = ["row"];
                   body = desugared_body;
                   closure_env = env;
                   is_variadic = false;
                 }
               else
                 (* Traditional lambda or expression *)
                 eval_expr env pred_expr
               in
               
               (* Now proceed with existing filter logic *)
               (match try_vectorize_filter df.arrow_table pred_fn with
                | Some keep ->
                  let new_table = Arrow_compute.filter df.arrow_table keep in
                  VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
                | None ->
                  (* Fall back to row-by-row evaluation *)
                  let nrows = Arrow_table.num_rows df.arrow_table in
                  let keep = Array.make nrows false in
                  let had_error = ref None in
                  for i = 0 to nrows - 1 do
                    if !had_error = None then begin
                      let row_dict = VDict (Arrow_bridge.row_to_dict df.arrow_table i) in
                      let result = eval_call env pred_fn [(None, Value row_dict)] in
                      match result with
                      | VBool true -> keep.(i) <- true
                      | VBool false -> ()
                      | VError _ as e -> had_error := Some e
                      | _ -> had_error := Some (make_error TypeError "filter() predicate must return a Bool")
                    end
                  done;
                  (match !had_error with
                   | Some e -> e
                   | None ->
                     let new_table = Arrow_compute.filter df.arrow_table keep in
                     VDataFrame { arrow_table = new_table; group_keys = df.group_keys }))
           | _ -> make_error TypeError "filter() expects a DataFrame as first argument")
      | _ -> make_error ArityError "filter() takes exactly 2 arguments"
    ))
    env
```

**Example: `arrange()` in `src/packages/colcraft/arrange.ml`**

Similar to `select()`, needs to handle both strings and `col.field`:

```ocaml
(* Extract column names, supporting both strings and col.field syntax *)
let col_names = List.map (fun (name_opt, expr) ->
  let v = eval_expr env expr in
  match v with
  | _ when (match Ast.is_column_ref expr with Some _ -> true | None -> false) ->
      (match Ast.is_column_ref expr with
       | Some field -> Ok field
       | None -> Error (make_error ValueError "Unexpected column ref"))
  | VString s -> Ok s
  | _ -> Error (make_error TypeError 
          "arrange() expects column names as strings or col.field syntax")
) sort_cols in
```

#### 5. Changes to `mutate()`, `group_by()`, `summarize()`

Each of these functions needs similar updates:

- **`mutate()`**: First argument (new column name) supports NSE
- **`group_by()`**: Column names support NSE
- **`summarize()`**: Column names support NSE

### Implementation Details for `$name` Syntax

If we choose `$name` instead of `col.name`:

#### 1. Lexer Changes (`src/lexer.mll`)

Add dollar prefix for identifiers:

```ocaml
| '$' (lower (letter | digit | '_')*) as s {
    COLUMN_REF (String.sub s 1 (String.length s - 1))
  }
```

#### 2. Parser Changes (`src/parser.mly`)

```ocaml
%token <string> COLUMN_REF

atom:
  | (* ... existing rules ... *)
  | col = COLUMN_REF { ColumnRef col }
```

#### 3. AST Changes (`src/ast.ml`)

```ocaml
and expr =
  (* ... existing variants ... *)
  | ColumnRef of string  (* NEW: $name syntax *)
```

#### 4. Evaluation Changes

Similar to `col.name` approach, but checking for `ColumnRef` pattern instead of `DotAccess { target = Var "col"; field }`.

## Phase 2: Bare Names Support (Future)

### Challenge: Scoping Resolution

The main challenge with bare names is distinguishing between:
- DataFrame column names
- Variables in scope
- Built-in functions

### Example Ambiguity

```t
age = 25  -- Local variable

df = read_csv("data.csv")

-- Does this filter by column 'age' or variable 'age'?
result = df |> filter(age > 30)
```

### Solution: Context-Aware Resolution

1. **Within data verb context**: Bare names refer to columns by default
2. **Explicit variable reference**: Use special syntax (e.g., `var.age` or `^age`)
3. **Scoping priority**:
   - First check if name is a column in the active DataFrame
   - Then check if name is a variable in current scope
   - Finally check if name is a built-in function

### Implementation Sketch

```ocaml
(** Resolve a bare name in data verb context *)
let resolve_bare_name (df : dataframe) (name : string) (env : environment) : resolution =
  if Arrow_table.has_column df.arrow_table name then
    ColumnRef name
  else if Env.mem name env then
    VarRef name
  else
    Error (Printf.sprintf "Name '%s' not found in DataFrame columns or environment" name)
```

### Transformation for `filter()`

```t
-- User writes:
df |> filter(age > 30 && status == active_status)

-- Transformer resolves to:
df |> filter(\(row) row.age > 30 && row.status == active_status)
--                     ^^^                ^^^^^^        ^^^^^^^^^^^^^^
--                     column             column        variable (from env)
```

### Parser Context Tracking

The parser needs to track when it's inside a data verb to enable bare name resolution:

```ocaml
(** Parser state to track data verb context *)
type parse_context = {
  in_data_verb: bool;
  current_dataframe: dataframe option;
}

(** During parsing of data verbs, set context *)
let parse_filter env df_expr pred_expr =
  let df = eval_expr env df_expr in
  (* Enter data verb context *)
  let ctx = { in_data_verb = true; current_dataframe = Some df } in
  let pred = parse_expr_with_context ctx pred_expr in
  ...
```

## Migration Strategy

### Backward Compatibility

To ensure smooth migration:

1. **Keep string syntax**: Continue to support `select("name", "age")`
2. **Add NSE incrementally**: Roll out `col.name` or `$name` in phases
3. **Provide migration guide**: Document how to convert old code
4. **Linter/Formatter**: Optionally auto-convert strings to NSE

### Gradual Rollout

**Phase 1.1 (Immediate - Beta 0.2)**:
- Implement `col.name` or `$name` syntax
- Support in: `select()`, `arrange()`, `group_by()`
- Keep lambda syntax for `filter()` and `mutate()` (complex expressions)

**Phase 1.2 (Beta 0.3)**:
- NSE for `filter()` (simple predicates only)
- NSE for `mutate()` (column name, still lambda for value)
- NSE for `summarize()` (column name, still lambda for aggregation)

**Phase 2.1 (Stable 1.0)**:
- Bare names support
- Advanced scoping resolution
- Full NSE for all data verbs

## Testing Strategy

### Unit Tests

1. **NSE column references**: Test `col.name` parsing and evaluation
2. **String fallback**: Ensure strings still work
3. **Mixed usage**: Test combining NSE and strings in same call
4. **Error messages**: Verify helpful errors for invalid column refs

### Golden Tests

Create golden test comparisons against R dplyr:

```t
-- T code
df |> select(col.name, col.age)

-- Equivalent R
df %>% select(name, age)

-- Both should produce identical output
```

### Integration Tests

1. **End-to-end pipelines**: Complex multi-step transformations with NSE
2. **Edge cases**: Empty DataFrames, missing columns, special characters in names
3. **Performance**: Ensure NSE doesn't introduce overhead

## Documentation Updates

### User Documentation

1. **Language overview**: Add NSE section explaining the feature
2. **Migration guide**: How to convert from string-based to NSE
3. **Examples**: Update all examples to use NSE
4. **Best practices**: When to use NSE vs. strings vs. lambdas

### API Reference

Update documentation for each data verb:

```markdown
## select()

Select columns from a DataFrame.

### Syntax

```t
select(df, col1, col2, ...)
```

### Arguments

- `df`: DataFrame to select from
- `col1, col2, ...`: Column names (strings or col.field syntax)

### Examples

```t
-- Using strings
df |> select("name", "age")

-- Using NSE (col.field)
df |> select(col.name, col.age)

-- Mixed (both work)
df |> select(col.name, "age")
```
```

## Benefits Summary

### For Users

1. **Less Typing**: No quotes needed for simple column references
2. **Better Readability**: Code looks cleaner, more like natural language
3. **Familiar**: Similar to R tidyverse, easier for R users
4. **Flexible**: Can still use strings when needed (e.g., programmatic column names)

### For the Language

1. **Modern Syntax**: Competitive with other data languages
2. **Differentiation**: Unique positioning vs. Python/Julia
3. **Extensibility**: Foundation for future features (e.g., column expressions)

## Open Questions

1. **Which syntax to choose**?
   - `col.name` (familiar, consistent with `row.field`)
   - `$name` (concise, R-like)
   - Vote: **`col.name`** (more explicit, no new syntax)

2. **Should we support bare names in Phase 1**?
   - Pro: Match tidyverse exactly
   - Con: Higher implementation complexity, scoping ambiguities
   - Decision: **No, wait for Phase 2** to get experience with symbol syntax first

3. **How to handle dynamic column names**?
   - NSE won't work for computed column names
   - Recommendation: **Keep string syntax for dynamic cases**
   - Example: `select(df, columns[i])` still uses strings

4. **Error messages**?
   - When a bare name isn't found, should we suggest:
     - Similar column names?
     - Variables in scope?
   - Recommendation: **Yes, provide "Did you mean?" suggestions**

## Implementation Timeline

### Week 1-2: Foundation
- [ ] Decide on syntax (`col.name` vs `$name`)
- [ ] Implement AST helper functions
- [ ] Add lexer/parser support if needed ($name)
- [ ] Write comprehensive unit tests

### Week 3-4: Data Verbs
- [ ] Update `select()` with NSE support
- [ ] Update `arrange()` with NSE support
- [ ] Update `group_by()` with NSE support
- [ ] Add golden tests for each verb

### Week 5-6: Advanced Features
- [ ] Update `filter()` with NSE desugaring
- [ ] Update `mutate()` with NSE for column names
- [ ] Update `summarize()` with NSE for column names
- [ ] Performance testing and optimization

### Week 7-8: Polish
- [ ] Update all documentation
- [ ] Create migration guide
- [ ] Update all examples in repo
- [ ] Comprehensive integration testing
- [ ] Release Beta 0.2 with NSE support

## References

### R tidyverse NSE

```r
# R allows bare names
df %>% select(name, age, salary)
df %>% filter(age > 30)
df %>% arrange(desc(age))
```

### Polars (Python) column syntax

```python
# Polars uses col() for column references
df.select(pl.col("name"), pl.col("age"))
df.filter(pl.col("age") > 30)
```

### Pandas (Python) string-based

```python
# Pandas uses strings (like current T)
df[["name", "age"]]
df[df["age"] > 30]
```

### T's Current Approach

```t
-- Strings + lambdas
df |> select("name", "age")
df |> filter(\(row) row.age > 30)
```

### T's Proposed NSE (Phase 1)

```t
-- col.field syntax
df |> select(col.name, col.age)
df |> filter(col.age > 30)
```

### T's Ultimate Goal (Phase 2)

```t
-- Bare names (tidyverse-style)
df |> select(name, age)
df |> filter(age > 30)
```

## Conclusion

Non-Standard Evaluation is a crucial feature for making T competitive with modern data manipulation languages. By implementing it in phases—starting with explicit symbol syntax (`col.name` or `$name`) and evolving to bare names—we can:

1. Deliver immediate value to users
2. Maintain code clarity and avoid scoping issues
3. Learn from user feedback before committing to complex bare name resolution
4. Preserve backward compatibility during the transition

The recommended approach is to implement **`col.name` syntax** in Phase 1, as it:
- Requires minimal changes to lexer/parser
- Is consistent with existing `row.field` syntax
- Provides clear semantics with no ambiguity
- Can be easily extended to bare names later

This positions T as a modern, user-friendly language for data analysis while maintaining the technical rigor and reproducibility that are core to the project's mission.
