# Implementation Plan: Non-Standard Evaluation (NSE) for T Language

## Overview

This document outlines the implementation plan for Non-Standard Evaluation (NSE) in T, using the dollar-prefix syntax (`$column_name`) for column references. This approach provides clean, concise syntax while avoiding any ambiguity with existing language features.

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

### Proposed Syntax (Dollar-Prefix NSE)

```t
-- Load data
df = read_csv("data.csv", clean_colnames = true)

-- Data manipulation pipeline
result = df
  |> filter($age > 30)
  |> select($name, $age, $salary)
  |> arrange($age, "desc")
```

### Benefits

1. **More Readable**: Cleaner syntax without quotes and lambda boilerplate
2. **Less Typing**: Only one extra character (`$`) for column references
3. **Clear Intent**: Dollar sign immediately signals a column reference
4. **R-Familiar**: Similar to R's `df$column` syntax
5. **No Ambiguity**: No conflict with existing dot accessor or other syntax
6. **Simple Implementation**: Clean lexer pattern with no disambiguation needed

## Design Decision: Dollar-Prefix Only

After considering multiple approaches (bare names, col.name, .name, $name), the decision has been made to focus **exclusively on the dollar-prefix syntax** (`$column_name`).

### Why Dollar-Prefix is the Final Choice

**No Ambiguity**:
- No conflict with existing dot accessor (`row.field`)
- No conflict with floating point numbers (`.5`)
- Dollar sign is not used elsewhere in T's syntax
- Clear, unambiguous column reference marker

**Very Concise**:
- Only 1 character prefix: `$`
- `$name` (5 chars) vs `"name"` (6 chars including quotes)
- Much shorter than alternatives like `col.name` (8 chars)

**R Familiarity**:
- R users already know `df$column` for column access
- Natural transition for R → T migration
- Intuitive for the target audience

**Simple Implementation**:
- Single lexer pattern: `'$'` + identifier
- No complex disambiguation logic needed
- Straightforward parser changes
- Clean AST representation

**Universal Context**:
- Works in any context where a DataFrame is referenced
- No need for special scoping rules
- Consistent across all data manipulation functions

## Dot Accessor vs. Dollar Accessor: Key Differences

It's important to understand the distinction between T's two accessor syntaxes:

### Dot Accessor (`.`) - Field Access on Objects

The dot accessor is used for accessing fields/properties on **specific objects** or **row instances**:

```t
-- Accessing fields on a row object (in lambda context)
df |> filter(\(row) row.age > 30)
--                  ^^^ dot accesses the 'age' field of the 'row' object

-- Accessing properties on any object
pipeline.result
model.r_squared
dict.field_name
```

**Characteristics**:
- Requires an explicit object/variable on the left side
- Used in traditional lambda-based row operations
- Accesses a specific instance's field
- Always requires context: `<object>.<field>`

### Dollar Accessor (`$`) - Column Reference in DataFrame Context

The dollar accessor is used for referencing **columns** in a DataFrame when the DataFrame is **contextually implied**:

```t
-- Referencing columns when df is in context (via pipe)
df |> filter($age > 30)
--           ^^^ dollar references the 'age' column of the contextual DataFrame

df |> select($name, $age, $salary)
--           ^^^^  ^^^^  ^^^^^^^ column references without object prefix
```

**Characteristics**:
- No explicit object needed - references the DataFrame in context
- Used in NSE (Non-Standard Evaluation) contexts
- References an entire column, not a single field
- Standalone: just `$column_name`

### Side-by-Side Comparison

```t
-- OLD SYNTAX: Using dot accessor with lambda
df |> filter(\(row) row.age > 30 && row.dept == "sales")
--                  ^^^^^^^^         ^^^^^^^^^^ 
--                  explicit row object required

-- NEW SYNTAX: Using dollar accessor with NSE
df |> filter($age > 30 && $dept == "sales")
--           ^^^^         ^^^^^ 
--           column references - no row object needed

-- BOTH are valid, but dollar syntax is more concise
```

### When to Use Which

**Use Dot Accessor (`.`)** when:
- You have an explicit object/variable to access
- Working with non-DataFrame objects (dictionaries, models, etc.)
- You need to access nested properties: `pipeline.data.field`
- Inside traditional lambdas that receive a row parameter

**Use Dollar Accessor (`$`)** when:
- Working with DataFrame operations (select, filter, arrange, etc.)
- The DataFrame is contextually clear (e.g., in a pipe chain)
- You want concise column references without lambda boilerplate
- Performing data manipulation with data verbs

### Migration Example

```t
-- Before (String-based with lambda):
customers 
  |> filter(\(row) row.age > 25 && row.status == "active")
  |> select("name", "email", "purchase_total")
  |> arrange("purchase_total", "desc")

-- After (Dollar-accessor NSE):
customers
  |> filter($age > 25 && $status == "active")
  |> select($name, $email, $purchase_total)
  |> arrange($purchase_total, "desc")

-- Key difference:
-- - Dot (.) requires explicit 'row' object in lambda
-- - Dollar ($) directly references columns in DataFrame context
```

### Technical Implementation Note

Internally, when you write `filter($age > 30)`, the T compiler transforms it to `filter(\(row) row.age > 30)`. The dollar syntax is syntactic sugar that:
1. Detects column references (`$column_name`)
2. Automatically wraps the expression in a lambda
3. Transforms `$column` to `row.column` references

This means both syntaxes ultimately use the same underlying mechanism, but the dollar accessor provides a cleaner, more readable surface syntax.

## Implementation: Dollar-Prefix Syntax

### Dollar-Prefix Syntax: `$name`

#### Example Usage
```t
df |> select($name, $age, $salary)
df |> filter($age > 30)
df |> mutate($bonus, \(row) row.salary * 0.1)  -- Keep lambda for complex expressions
df |> arrange($age, "desc")
```

#### Advantages
- Very concise - only one extra character (`$`)
- Clear marker that this is a column reference
- Familiar to R users (`df$column` in R)
- No ambiguity with existing dot accessor
- No ambiguity with floating point numbers
- Clean and minimal syntax
- Simple lexer implementation

### Implementation Details for `$name` Syntax

#### 1. Lexer Changes (`src/lexer.mll`)

Add support for dollar-prefixed identifiers:

```ocaml
(* Add to identifier/operator section *)
| '$' (lower (letter | digit | '_')*) as s {
    COLUMN_REF (String.sub s 1 (String.length s - 1))
  }
```

**Note**: This is much simpler than dot-prefix because:
- No ambiguity with field access (`.` operator)
- No ambiguity with floating point numbers (`.5`)
- Dollar sign is not used elsewhere in T's syntax
- Clean, unambiguous pattern

#### 2. Parser Changes (`src/parser.mly`)

Add token and parsing rule:

```ocaml
%token <string> COLUMN_REF

atom:
  | (* ... existing rules ... *)
  | col = COLUMN_REF { ColumnRef col }
```

#### 3. AST Changes (`src/ast.ml`)

Add a new expression variant for column references:

```ocaml
and expr =
  (* ... existing variants ... *)
  | ColumnRef of string  (* NEW: $name syntax *)

(** Check if an expression is a column reference *)
let is_column_ref expr =
  match expr with
  | ColumnRef field -> Some field
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
            (* NSE: $field pattern *)
            | _ when (match Ast.is_column_ref expr with Some _ -> true | None -> false) ->
                (match Ast.is_column_ref expr with
                 | Some field -> Ok field
                 | None -> Error (make_error ValueError "Unexpected column ref"))
            (* Error: not a column reference *)
            | _ -> Error (make_error TypeError 
                    "select() expects column references using $field syntax")
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

(** Transform an NSE expression like ($age > 30) into \(row) row.age > 30 *)
let rec desugar_nse_expr expr =
  match expr with
  | ColumnRef field ->
      (* $field → row.field *)
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
  | _ -> expr  (* Literals, variables, etc. remain unchanged *)

(** Check if an expression uses NSE (contains $field) *)
let rec uses_nse expr =
  match expr with
  | ColumnRef _ -> true
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
                 (* Transform $field → row.field and wrap in lambda *)
                 let desugared_body = desugar_nse_expr pred_expr in
                 VLambda {
                   params = ["row"];
                   body = desugared_body;
                   closure_env = env;
                   is_variadic = false;
                 }
               else
                 (* Traditional lambda expression *)
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

Similar to `select()`, needs to handle `$field` syntax:

```ocaml
(* Extract column names, supporting $field syntax *)
let col_names = List.map (fun (name_opt, expr) ->
  let v = eval_expr env expr in
  match v with
  | _ when (match Ast.is_column_ref expr with Some _ -> true | None -> false) ->
      (match Ast.is_column_ref expr with
       | Some field -> Ok field
       | None -> Error (make_error ValueError "Unexpected column ref"))
  | _ -> Error (make_error TypeError 
          "arrange() expects column references using $field syntax")
) sort_cols in
```

#### 5. Changes to `mutate()`, `group_by()`, `summarize()`

Each of these functions needs similar updates:

- **`mutate()`**: First argument (new column name) supports NSE
- **`group_by()`**: Column names support NSE
- **`summarize()`**: Column names support NSE

## Migration Strategy

### Breaking Change Accepted

Since backward compatibility is not required, the migration is straightforward:

1. **Remove string syntax**: Strings will no longer be accepted for column references
2. **Update all existing code**: All T code using strings must be updated to `$name` syntax
3. **Provide migration script**: Automated tool to convert `select("name")` → `select($name)`

### Gradual Rollout

**Beta 0.2 (Initial Release)**:
- Implement `$name` syntax
- Support in: `select()`, `arrange()`, `group_by()`
- Simple NSE for `filter()` (e.g., `$age > 30`)

**Beta 0.3 (Enhanced Support)**:
- NSE for `mutate()` (column name uses `$name`, value expression can use NSE)
- NSE for `summarize()` (column name uses `$name`, aggregation can use NSE)
- Complex filter predicates with NSE

**Stable 1.0 (Production Ready)**:
- Full NSE support across all data verbs
- Comprehensive error messages with suggestions
- Performance optimizations
- Complete documentation

## Testing Strategy

### Unit Tests

1. **NSE column references**: Test `$name` parsing and evaluation
2. **Error messages**: Verify helpful errors for invalid column refs
3. **Edge cases**: Test columns with underscores, numbers, special names

### Golden Tests

Create golden test comparisons against R dplyr:

```t
-- T code
df |> select($name, $age)

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
select(df, $col1, $col2, ...)
```

### Arguments

- `df`: DataFrame to select from
- `$col1, $col2, ...`: Column names using dollar-prefix syntax

### Examples

```t
-- Using NSE (dollar-prefix)
df |> select($name, $age)

-- Column names with underscores
df |> select($first_name, $last_name)
```
```

## Benefits Summary

### For Users

1. **Less Typing**: Only one extra character (`$`) for column references
2. **Better Readability**: Code looks cleaner without quotes or verbose prefixes
3. **Clear Semantics**: Dollar prefix clearly indicates column references
4. **Easier Migration**: Simple pattern to convert from strings
5. **Familiar to R Users**: R uses `$` for column access (`df$column`)

### For the Language

1. **Modern Syntax**: Clean, distinctive column reference syntax
2. **Differentiation**: Unique positioning vs. Python/Julia
3. **Extensibility**: Foundation for future features (e.g., column expressions)
4. **No Ambiguity**: Clear distinction from variables and field access
5. **Simple Implementation**: No conflicts with existing operators

## Open Questions

1. **Dynamic column names**:
   - NSE won't work for computed column names
   - Recommendation: **Provide escape hatch** - perhaps `select(col_from_var(var_name))`
   - Example: When column name is in a variable

2. **Error messages**?
   - When a column isn't found, should we suggest:
     - Similar column names?
     - Variables in scope that might have been intended?
   - Recommendation: **Yes, provide "Did you mean?" suggestions**

3. **Reserved symbols**?
   - Should `$` be reserved only for column references?
   - Or allow other uses in the future?
   - Recommendation: **Reserve `$` prefix for NSE** to avoid future conflicts

## Implementation Timeline

### Week 1: Foundation & Lexer
- [ ] Implement lexer changes for `.name` syntax
- [ ] Handle disambiguation: `.name` vs `.5` vs `.`
- [ ] Add `COLUMN_REF` token
- [ ] Write lexer tests

### Week 2: Parser & AST
- [ ] Add `ColumnRef` expression variant to AST
- [ ] Update parser to recognize `COLUMN_REF` token
- [ ] Add helper functions (`is_column_ref`)
- [ ] Write parser tests

### Week 3: Data Verbs - Basic
- [ ] Update `select()` with NSE support
- [ ] Update `arrange()` with NSE support
- [ ] Update `group_by()` with NSE support
- [ ] Add unit tests for each verb

### Week 4: Data Verbs - Advanced
- [ ] Update `filter()` with NSE desugaring
- [ ] Update `mutate()` with NSE for column names
- [ ] Update `summarize()` with NSE for column names
- [ ] Add golden tests for each verb

### Week 5: Migration & Tooling
- [ ] Create migration script (string → `.name`)
- [ ] Update all examples in repo
- [ ] Update all tests to use `.name`
- [ ] Create migration guide

### Week 6: Documentation & Polish
- [ ] Update all user documentation
- [ ] Update API reference
- [ ] Comprehensive integration testing
- [ ] Performance testing
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
# Pandas uses strings
df[["name", "age"]]
df[df["age"] > 30]
```

### T's Current Approach

```t
-- Strings + lambdas
df |> select("name", "age")
df |> filter(\(row) row.age > 30)
```

### T's New Approach - Dollar-Prefix NSE

```t
-- $field syntax - final design
df |> select($name, $age)
df |> filter($age > 30)
```

## Conclusion

Non-Standard Evaluation using the dollar-prefix syntax (`$column_name`) is a crucial feature for making T competitive with modern data manipulation languages while maintaining clarity and simplicity.

The dollar-prefix approach provides:

1. **Immediate value** with clean, concise syntax
2. **Clear semantics** with no ambiguity between column references and other language features
3. **Universal applicability** - works in any DataFrame context without special scoping rules
4. **R familiarity** - intuitive for the target audience already using `df$column` in R
5. **Simple implementation** - clean lexer pattern with straightforward parser changes

The **`$name` syntax** is the final design choice because it:
- Very concise - only one extra character (`$`)
- Clear semantics with no ambiguity
- Distinctive visual marker for column references
- No conflict with existing dot accessor (which remains for field access on objects)
- Familiar to R users (`df$column` in R)
- Simple, clean lexer implementation
- Works universally in any context where a DataFrame is referenced

This positions T as a modern, user-friendly language for data analysis while maintaining the technical rigor and reproducibility that are core to the project's mission. The breaking change is acceptable given the alpha status and allows for a cleaner, more elegant syntax from the start.

### Key Distinction

Remember: 
- **Dot (`.`)** = field access on an **explicit object** (`row.field`, `obj.property`)
- **Dollar (`$`)** = column reference in **contextual DataFrame** (`$column_name`)

Both serve different purposes and complement each other in T's syntax design.
