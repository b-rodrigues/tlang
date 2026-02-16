# 1. Design Goals

### 1.1 Philosophy

T should feel:

* Lightweight and fluid in REPL exploration
* Strict, safe, and explicit in scripts and packages
* Functional and composable
* Column-type aware for tabular work

Typing must:

* Be mandatory in scripts and packages
* Be optional in REPL exploration
* Support generics
* Support ad-hoc polymorphism (like numeric operations over multiple types)
* Support typed tabular data

---

# 2. Execution Modes

Introduce two compiler modes:

### Mode A — REPL (interactive)

* Type inference enabled
* Missing type annotations allowed
* Types inferred where possible
* Warnings instead of hard failures (configurable)

### Mode B — Script / Package

* Type annotations required on all top-level functions
* Strict checking
* No implicit `Any`
* All generics must be explicitly declared

Implementation:

Add a compiler flag:

```
--mode repl
--mode strict
```

The parser is the same.
The typechecker behavior changes based on mode.

---

# 3. Core Type System

## 3.1 Base Types

```
Int
Float
Bool
String
Null
```

## 3.2 Composite Types

```
List[T]
Dict[K, V]
Tuple[T1, T2, ...]
DataFrame[Schema]
```

## 3.3 Function Type

```
(T1, T2) -> R
```

---

# 4. Lambda Syntax (Only Syntax)

T only supports:

```
f = \(x, y) x + y
```

Typed lambdas:

```
f = \(x: Int, y: Int) -> Int x + y
```

Grammar addition:

```
lambda :=
  "\" "(" param_list ")" ("->" type)? expression
```

---

# 5. Type Annotations

## 5.1 Required in Strict Mode

All top-level functions must declare:

* Parameter types
* Return type

Valid:

```
add = \(x: Int, y: Int) -> Int x + y
```

Invalid in strict mode:

```
add = \(x, y) x + y
```

---

# 6. Type Inference (REPL Only)

Use Hindley–Milner style inference:

* Infer types for unannotated lambdas
* Allow polymorphic inference
* Default numeric literals to Int unless promoted

In strict mode:

* Inference allowed internally
* But public functions must be annotated

---

# 7. Parametric Polymorphism

Allow generic type variables:

```
id = \(x: T) -> T x
```

Internally:

* Represent `T` as type variable
* Unify at call site

Multiple type parameters:

```
pair = \(x: A, y: B) -> Tuple[A, B] (x, y)
```

---

# 8. Typeclasses (Ad-hoc Polymorphism)

T needs generic numeric operations and generic joins.

Introduce typeclasses:

```
typeclass Addable[T] {
  add: (T, T) -> T
}
```

Register implementations:

```
instance Addable[Int] {
  add = \(x: Int, y: Int) -> Int x + y
}
```

Then:

```
sum = \(x: T, y: T) -> T where Addable[T]
  add(x, y)
```

Implementation Plan:

1. Add constraint field to function type
2. During type resolution:

   * Gather constraints
   * Resolve instance dictionary
3. Pass resolved instance at runtime

This allows:

* Numeric operators
* String join
* DataFrame merge generics

---

# 9. Built-in vs Optional String Layer

Built-in (minimal, primitive):

```
length(String) -> Int
slice(String, Int, Int) -> String
trim(String) -> String
split(String, String) -> List[String]
join(String, List[String]) -> String
replace(String, String, String) -> String
contains(String, String) -> Bool
starts_with(String, String) -> Bool
ends_with(String, String) -> Bool
```

Optional package: `lexis`

Higher-level:

```
pad_left
pad_right
center
extract_regex
replace_regex
count_regex
normalize_unicode
slugify
wrap
indent
```

Built-ins must remain minimal and low-level.

---

# 10. DataFrame with Typed Columns

## 10.1 Schema Type

Define schema as type-level mapping:

```
DataFrame[
  {
    name: String,
    age: Int,
    salary: Float
  }
]
```

Internally:

```
type schema =
  (string * ttype) list
```

---

## 10.2 Column Access

```
df$name
```

Typechecker verifies:

* Column exists
* Returns correct type

---

## 10.3 Grouping

Grouped DataFrame type:

```
GroupedDataFrame[
  BaseSchema,
  GroupKeys
]
```

Where:

* BaseSchema is full schema
* GroupKeys is subset

---

## 10.4 merge (DataFrame)

You decided:

* `join` → strings
* `merge` → data frames

Type of merge:

```
merge :
  (
    DataFrame[A],
    DataFrame[B],
    on: List[String]
  ) -> DataFrame[A ∪ B]
```

Typechecker:

* Ensure `on` columns exist in both
* Ensure compatible types
* Compute merged schema

---

# 11. Strictness Rules

In strict mode:

* No implicit numeric promotion
* No undeclared generics
* No missing return types
* No unresolved typeclass constraints
* DataFrame schema must be fully known

In REPL:

* Allow partial schemas
* Allow inference
* Allow implicit promotion (optional warning)

---

# 12. Compiler Pipeline Changes

Current pipeline likely:

```
Parse → AST → Eval
```

New pipeline:

```
Parse
→ Desugar
→ Type inference / checking
→ Constraint resolution
→ Typed AST
→ Eval
```

Add new modules:

* type.ml
* infer.ml
* unify.ml
* constraints.ml
* dataframe_schema.ml

---

# 13. Migration Strategy (Incremental Implementation)

## Phase 1 — Core Type Infrastructure

* Define type AST
* Add type annotation parsing
* Implement simple type equality checking
* Enforce strict mode annotations

No generics yet.

---

## Phase 2 — Hindley–Milner Inference

* Add type variables
* Add unification
* Add inference for lambdas
* Enable REPL relaxed mode

---

## Phase 3 — Parametric Generics

* Support explicit type variables
* Add type parameter scope
* Allow polymorphic functions

---

## Phase 4 — Typeclasses

* Add constraint system
* Add instance registration
* Add resolution pass
* Replace built-in numeric operators with typeclass-based ones

---

## Phase 5 — Typed DataFrame

* Implement schema type
* Implement column lookup typing
* Implement merge schema composition
* Implement grouped type

---

# 14. Next Concrete Steps (Practical)

Given your current stage (interpreter + packages + pipe):

### Step 1

Add:

* Type representation
* Type annotation parsing
* Strict mode flag

### Step 2

Make strict mode require:

```
\(x: T) -> R
```

### Step 3

Implement simple typechecking for:

* literals
* arithmetic
* function application

### Step 4

Add inference engine

### Step 5

Refactor numeric operators into a typeclass

### Step 6

Add DataFrame schema type

# Unit tests

Add unit tests.
