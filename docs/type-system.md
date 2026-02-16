# Type System

T currently has an **alpha-stage, mode-aware type system**. The implementation focuses on typed lambda signatures and strict validation for top-level functions, with broader static typing features planned for later phases.

## Why this exists

The typing design in `spec_files/typing_system.md` sets a dual goal:

- keep REPL exploration lightweight,
- while making scripts and packages more explicit and safer.

PRs #83 and #84 introduced the first concrete implementation of that plan: typed lambda syntax, generic parameter declarations, and strict-mode validation behavior.

## Execution modes

Two checker modes are available:

- `repl`
- `strict`

### Current behavior

- `t repl` defaults to `repl` mode.
- `t run <file.t>` defaults to `strict` mode.
- `--mode repl|strict` can be used to override defaults.

In `strict` mode, only **top-level lambda assignments** are validated today.

## Lambda syntax

T supports both untyped and typed lambda forms.

### Untyped lambda

Body is any expression.

```t
add = \(x, y) x + y
```

### Typed lambda

Return type annotation is included inside the parameter parentheses.

```t
add_int = \(x: Int, y: Int -> Int) (x + y)
```

### Generic typed lambda

Generic type variables must be declared explicitly with `<...>`.

```t
id = \<T>(x: T -> T) x
pair = \<A, B>(x: A, y: B -> Tuple[A, B]) [x, y]
```

## Type annotation forms currently parsed

### Base types

- `Int`
- `Float`
- `Bool`
- `String`
- `Null`

### Composite forms

- `List[T]`
- `Dict[K, V]`
- `Tuple[T1, T2, ...]`
- `DataFrame[SchemaLikeType]` (parsed as a type argument shape, not yet enforced semantically)

### Generic variables

Single uppercase identifiers are interpreted as type variables (for example `T`, `A`, `B`).

## What strict mode validates today

In `strict` mode, for top-level lambdas assigned with `name = \(...) ...`, T validates:

1. all parameters have type annotations,
2. return type is annotated,
3. if type variables are used, generic parameters are declared,
4. all used type variables are declared.

If any rule fails, evaluation is blocked with a type error.

## What is **not** implemented yet

The current implementation is intentionally narrow. The following items from the spec are still future work:

- full expression-level type inference (HM-style),
- end-to-end static typing of function application and operators,
- typeclass/constraint resolution,
- fully typed DataFrame schemas and column-level checks,
- typed AST pipeline stages beyond signature validation.

In other words, this is a **signature validation layer**, not yet a full static typechecker.

## Practical guidance

- Use `repl` mode for exploratory work.
- Use `strict` mode (default in `run`) for scripts and packages.
- Prefer explicit signatures on exported/top-level functions to make behavior auditable and future-proof as stricter checks are added.

## References

- Typing spec: `spec_files/typing_system.md`
- Initial implementation context: PR #83 and PR #84
