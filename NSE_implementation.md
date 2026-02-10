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

#### Approach 2: Dollar-Prefix Syntax
**Syntax**: `select($name, $age, $salary)`

**Pros**:
- Clear distinction between columns and variables
- Very concise - minimal boilerplate (just `$`)
- No scoping ambiguity
- No conflict with existing dot accessor
- Familiar to R users (`$` is used for column access in R)
- Easier to implement than bare names
- Simpler lexer (no ambiguity with `.5` floats or `row.field`)

**Cons**:
- Requires lexer changes to support dollar prefix
- Not as common as dot notation in other languages

**Implementation Complexity**: Low-Medium

#### Approach 3: Dot-Prefix Syntax (Alternative)
**Syntax**: `select(.name, .age, .salary)`

**Pros**:
- Clear distinction between columns and variables
- Very concise

**Cons**:
- Conflicts with existing dot accessor (ambiguity issues)
- Conflicts with floating point syntax (`.5`)
- More complex lexer disambiguation needed

**Implementation Complexity**: Medium

### Recommended Approach: Start with Dollar-Prefix Syntax, Evolve to Bare Names

Given T's current alpha stage and the need for rapid iteration, we recommend:

**Phase 1 (Beta)**: Implement **Dollar-Prefix Syntax** (`$name`)
- Lower implementation complexity than bare names
- Very concise and clean
- Clear semantics with no scoping ambiguity
- No conflict with existing dot accessor
- No backward compatibility needed (breaking change accepted)

**Phase 2 (Future)**: Add **Bare Names** support
- Build on Phase 1 infrastructure
- Add sophisticated scoping resolution
- Maintain dollar-prefix syntax as alternative for disambiguating cases

This staged approach allows us to:
1. Deliver immediate value with clean syntax
2. Learn from user feedback
3. Avoid premature complexity
4. Keep the door open for the ideal bare names syntax

## Phase 1: Dollar-Prefix Syntax Implementation

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
2. **Explicit variable reference**: Use special syntax (e.g., `var.name` or `^name`)
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

Note: With Phase 1 `$name` syntax already in place, the transformation is simpler as `$age` is already explicitly a column reference.

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

### Breaking Change Accepted

Since backward compatibility is not required, the migration is straightforward:

1. **Remove string syntax**: Strings will no longer be accepted for column references
2. **Update all existing code**: All T code using strings must be updated to `$name` syntax
3. **Provide migration script**: Automated tool to convert `select("name")` → `select($name)`

### Gradual Rollout

**Phase 1.1 (Immediate - Beta 0.2)**:
- Implement `$name` syntax
- Support in: `select()`, `arrange()`, `group_by()`
- Simple NSE for `filter()` (e.g., `$age > 30`)

**Phase 1.2 (Beta 0.3)**:
- NSE for `mutate()` (column name uses `$name`, value expression can use NSE)
- NSE for `summarize()` (column name uses `$name`, aggregation can use NSE)
- Complex filter predicates with NSE

**Phase 2.1 (Stable 1.0)**:
- Bare names support
- Advanced scoping resolution
- Full NSE for all data verbs
- Ability to use `$name` for disambiguation when needed

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

### T's Proposed NSE (Phase 1) - Dollar-Prefix

```t
-- $field syntax
df |> select($name, $age)
df |> filter($age > 30)
```

### T's Ultimate Goal (Phase 2)

```t
-- Bare names (tidyverse-style)
df |> select(name, age)
df |> filter(age > 30)
```

## Conclusion

Non-Standard Evaluation is a crucial feature for making T competitive with modern data manipulation languages. By implementing it in phases—starting with dollar-prefix syntax (`$name`) and evolving to bare names—we can:

1. Deliver immediate value to users with clean, concise syntax
2. Maintain code clarity and avoid scoping issues
3. Learn from user feedback before committing to complex bare name resolution
4. Make a clean break from string-based syntax without backward compatibility concerns

The recommended approach is to implement **`$name` syntax** in Phase 1, as it:
- Very concise - only one extra character (`$`)
- Clear semantics with no ambiguity
- Distinctive visual marker for column references
- No conflict with existing dot accessor (avoids parser complexity)
- Familiar to R users (`df$column` in R)
- Simple, clean lexer implementation
- Provides foundation for eventual bare name support

This positions T as a modern, user-friendly language for data analysis while maintaining the technical rigor and reproducibility that are core to the project's mission. The breaking change is acceptable given the alpha status and allows for a cleaner, more elegant syntax from the start.
