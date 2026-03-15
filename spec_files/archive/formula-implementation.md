# Implementation Plan: Formula Interface for T Language

## Overview

Add R-style formula syntax (`y ~ x`) to T and refactor `lm()` to use named arguments with formula interface: `lm(data = df, formula = y ~ x, ...)`.

## Phase 1: Formula Syntax and AST

### 1.1 Lexer Changes (`src/lexer.mll`)

```ocaml
(* Add to operators section *)
| '~' { TILDE }
```

### 1.2 Parser Changes (`src/parser.mly`)

```ocaml
(* Add token *)
%token TILDE

(* Add precedence - formulas are low precedence, between assignment and pipes *)
%left TILDE
%left PIPE MAYBE_PIPE

(* Add formula expression rule *)
formula_expr:
  | e = or_expr { e }
  | left = or_expr TILDE right = or_expr
    { BinOp { op = Formula; left; right } }
  ;

(* Update pipe_expr to use formula_expr *)
pipe_expr:
  | e = formula_expr { e }
  | left = pipe_expr PIPE right = formula_expr
    { BinOp { op = Pipe; left; right } }
  | left = pipe_expr MAYBE_PIPE right = formula_expr
    { BinOp { op = MaybePipe; left; right } }
  ;
```

### 1.3 AST Changes (`src/ast.ml`)

```ocaml
(* Add to binop type *)
and binop = 
  | Plus | Minus | Mul | Div 
  | Eq | NEq | Gt | Lt | GtEq | LtEq 
  | And | Or 
  | Pipe | MaybePipe
  | Formula  (* NEW *)

(* Add formula value type *)
and formula_spec = {
  response: string list;      (* LHS variable names *)
  predictors: string list;    (* RHS variable names *)
  raw_lhs: expr;             (* Original LHS expression *)
  raw_rhs: expr;             (* Original RHS expression *)
}

and value =
  (* ... existing variants ... *)
  | VFormula of formula_spec
```

### 1.4 Utils Extension (`src/ast.ml`)

```ocaml
(* In Utils module *)
let type_name = function
  (* ... existing cases ... *)
  | VFormula _ -> "Formula"

let rec value_to_string = function
  (* ... existing cases ... *)
  | VFormula { response; predictors; _ } ->
      Printf.sprintf "%s ~ %s"
        (String.concat " + " response)
        (String.concat " + " predictors)
```

## Phase 2: Formula Evaluation and Extraction

### 2.1 Formula Parsing Helper (`src/eval.ml`)

```ocaml
(** Extract variable names from a formula expression.
    Supports: x, x + y, x + y + z
    Returns list of variable names *)
let rec extract_formula_vars (expr : expr) : string list =
  match expr with
  | Var s -> [s]
  | BinOp { op = Plus; left; right } ->
      extract_formula_vars left @ extract_formula_vars right
  | Value (VInt 1) -> []  (* Intercept term: y ~ x + 1 *)
  | _ -> []  (* Unsupported formula syntax *)

(** Build a formula spec from LHS and RHS expressions *)
let build_formula_spec (lhs : expr) (rhs : expr) : formula_spec =
  {
    response = extract_formula_vars lhs;
    predictors = extract_formula_vars rhs;
    raw_lhs = lhs;
    raw_rhs = rhs;
  }
```

### 2.2 Eval Changes (`src/eval.ml`)

```ocaml
(* Add to eval_binop *)
and eval_binop env op left right =
  match op with
  | Formula ->
      (* Formulas are not evaluated - they're data structures *)
      let lhs_vars = extract_formula_vars left in
      let rhs_vars = extract_formula_vars right in
      VFormula {
        response = lhs_vars;
        predictors = rhs_vars;
        raw_lhs = left;
        raw_rhs = right;
      }
  | (* ... existing cases ... *)
```

## Phase 3: Named Arguments Support

### 3.1 Argument Extraction Helper (`src/eval.ml`)

```ocaml
(** Extract named and positional arguments from call args *)
let partition_args (args : (string option * expr) list) 
    : (string * value) list * value list =
  let named = ref [] in
  let positional = ref [] in
  List.iter (fun (name_opt, e) ->
    let v = eval_expr env e in
    match name_opt with
    | Some name -> named := (name, v) :: !named
    | None -> positional := v :: !positional
  ) args;
  (List.rev !named, List.rev !positional)

(** Get a named argument, or return default *)
let get_named_arg (named : (string * value) list) (key : string) 
    (default : value option) : value option =
  match List.assoc_opt key named with
  | Some v -> Some v
  | None -> default

(** Get a required named argument, or return error *)
let get_required_named (named : (string * value) list) (key : string) 
    (fn_name : string) : (value, value) result =
  match List.assoc_opt key named with
  | Some v -> Ok v
  | None -> 
      Error (make_error ArityError 
        (Printf.sprintf "%s() missing required argument '%s'" fn_name key))
```

## Phase 4: Refactored `lm()` Implementation

### 4.1 New `lm()` (`src/packages/stats/lm.ml`)

```ocaml
open Ast

(** Extract single variable name from formula side *)
let extract_single_var (vars : string list) (side : string) (fn : string) 
    : (string, value) result =
  match vars with
  | [v] -> Ok v
  | [] -> Error (make_error ValueError 
      (Printf.sprintf "%s() %s side of formula is empty" fn side))
  | _ -> Error (make_error ValueError 
      (Printf.sprintf "%s() only supports single-variable formulas, got: %s" 
        fn (String.concat " + " vars)))

let register env =
  Env.add "lm"
    (make_builtin ~variadic:true 0 (fun args env ->
      (* Parse arguments - expect named: data, formula *)
      let eval_arg (name_opt, e) = 
        let v = Eval.eval_expr env e in
        (name_opt, v)
      in
      let evaluated = List.map eval_arg args in
      
      let named = List.filter_map (fun (n, v) -> 
        match n with Some name -> Some (name, v) | None -> None
      ) evaluated in
      let positional = List.filter_map (fun (n, v) -> 
        match n with None -> Some v | Some _ -> None
      ) evaluated in
      
      (* Get required arguments *)
      let get_req key = 
        match List.assoc_opt key named with
        | Some v -> Ok v
        | None -> Error (make_error ArityError 
            (Printf.sprintf "lm() missing required argument '%s'" key))
      in
      
      match (get_req "data", get_req "formula") with
      | (Error e, _) | (_, Error e) -> e
      | (Ok data_val, Ok formula_val) ->
        match (data_val, formula_val) with
        | (VDataFrame df, VFormula { response; predictors; _ }) ->
          (* Extract single response and predictor *)
          (match (extract_single_var response "left" "lm",
                  extract_single_var predictors "right" "lm") with
           | (Error e, _) | (_, Error e) -> e
           | (Ok y_col, Ok x_col) ->
             (* Check columns exist *)
             (match (Arrow_table.get_column df.arrow_table y_col, 
                     Arrow_table.get_column df.arrow_table x_col) with
              | (None, _) -> 
                  make_error KeyError 
                    (Printf.sprintf "Column '%s' not found in DataFrame" y_col)
              | (_, None) -> 
                  make_error KeyError 
                    (Printf.sprintf "Column '%s' not found in DataFrame" x_col)
              | (Some _, Some _) ->
                let nrows = Arrow_table.num_rows df.arrow_table in
                if nrows < 2 then
                  make_error ValueError "lm() requires at least 2 observations"
                else
                  (* Use Arrow-Owl bridge for numeric column extraction *)
                  match (Arrow_owl_bridge.numeric_column_to_owl df.arrow_table y_col,
                         Arrow_owl_bridge.numeric_column_to_owl df.arrow_table x_col) with
                  | (None, _) | (_, None) ->
                    make_error TypeError 
                      "lm() requires numeric columns without NA values"
                  | (Some y_view, Some x_view) ->
                    let ys = y_view.arr in
                    let xs = x_view.arr in
                    (* Delegate computation to Arrow_owl_bridge *)
                    (match Arrow_owl_bridge.linreg xs ys with
                     | None ->
                       make_error ValueError 
                         "lm() cannot fit model: predictor has zero variance"
                     | Some (intercept, slope, r_squared) ->
                       let resid = Arrow_owl_bridge.residuals xs ys intercept slope in
                       let n = Array.length xs in
                       VDict [
                         ("formula", formula_val);
                         ("intercept", VFloat intercept);
                         ("slope", VFloat slope);
                         ("r_squared", VFloat r_squared);
                         ("residuals", VVector (Array.map (fun r -> VFloat r) resid));
                         ("n", VInt n);
                         ("response", VString y_col);
                         ("predictor", VString x_col);
                       ])))
        | (VDataFrame _, _) -> 
            make_error TypeError "lm() 'formula' must be a Formula (use ~ operator)"
        | (_, _) -> 
            make_error TypeError "lm() 'data' must be a DataFrame"
    ))
    env
```

## Phase 5: Testing Updates

### 5.1 Formula Parsing Tests

```t
-- Test formula creation
f = y ~ x
print(type(f))  -- Should print "Formula"
print(f)        -- Should print "y ~ x"

-- Test multi-variable formulas
f2 = mpg ~ hp + wt
print(f2)       -- Should print "mpg ~ hp + wt"
```

### 5.2 `lm()` Tests

```t
-- Update existing tests to use new interface
data = read_csv("data.csv")

-- Simple regression
model = lm(data = data, formula = mpg ~ hp)
print(model.slope)
print(model.intercept)
print(model.r_squared)

-- Test error handling
model_err = lm(data = data, formula = missing ~ hp)  -- Should error: column not found
model_err2 = lm(formula = mpg ~ hp)  -- Should error: missing 'data' argument
model_err3 = lm(data = data)  -- Should error: missing 'formula' argument
```

### 5.3 Golden Test Updates

Update `tests/golden/test_lm.t` to use new syntax:

```t
data = read_csv("iris.csv")
model = lm(data = data, formula = Sepal.Length ~ Sepal.Width)
pretty_print(model)
```

## Phase 6: Documentation

### 6.1 Add Formula Documentation (`docs/formulas.md`)

```markdown
# Formulas in T

Formulas provide a declarative way to specify statistical models, inspired by R.

## Syntax

```t
response ~ predictor
```

The `~` operator creates a Formula object that can be passed to modeling functions.

## Examples

```t
-- Simple linear regression
model = lm(data = df, formula = y ~ x)

-- Future: Multiple regression
model = lm(data = df, formula = y ~ x1 + x2 + x3)
```

## Supported Functions

- `lm()` - Linear regression

## Future Extensions

- Intercept control: `y ~ x + 1` vs `y ~ x - 1`
- Interactions: `y ~ x1 * x2`
- Transformations: `y ~ log(x)`
```

### 6.2 Update `lm()` Documentation

```markdown
# lm() - Linear Regression

Fit a linear model using least squares.

## Signature

```t
lm(data: DataFrame, formula: Formula, ...) -> Dict
```

## Arguments

- `data`: DataFrame containing the variables
- `formula`: Formula specifying the model (e.g., `y ~ x`)
- `...`: Reserved for future options (e.g., `weights`, `subset`)

## Returns

Dictionary containing:
- `formula`: The model formula
- `intercept`: Estimated intercept
- `slope`: Estimated slope (coefficient)
- `r_squared`: R² statistic
- `residuals`: Vector of residuals
- `n`: Number of observations
- `response`: Name of response variable
- `predictor`: Name of predictor variable

## Examples

```t
data = read_csv("mtcars.csv")
model = lm(data = data, formula = mpg ~ hp)
print(model.r_squared)
```


Very important: no need to keep backward compatibility with old interface!

## Summary

This implementation plan:

1. ✅ Adds formula syntax with `~` operator
2. ✅ Provides named argument support in builtins
3. ✅ Refactors `lm()` to use `lm(data = df, formula = y ~ x, ...)`
4. ✅ Maintains extensibility for future model options via `...`
5. ✅ Includes comprehensive tests and documentation

The design is extensible for future enhancements like multiple regression, interactions, and model options.
