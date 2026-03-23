# Collection and Block Syntax Specification

## Status

This document defines the **authoritative parsing and semantic rules** for:

* Dictionary literals
* List literals
* Block statements

These rules are fundamental language guarantees and must not be changed implicitly by tooling, refactoring systems, transpilers, or LLM-generated code.

---

# 1. Overview

The language defines three distinct syntactic constructs:

| Syntax              | Meaning            |
| ------------------- | ------------------ |
| `[a, b, c]`         | List literal       |
| `[key: value, ...]` | Dictionary literal |
| `{ ... }`           | Block statement    |

These constructs are **mutually exclusive** and must never overlap semantically.

---

# 2. Block Statements

## Syntax

```
{
    statement1
    statement2
}
```

## Semantics

* `{}` defines a block.
* Blocks contain statements.
* Blocks are used in control flow constructs (`if`, `while`, etc.).
* `{}` never represents a dictionary.
* `{}` never represents a collection.

## Rule

> `{}` is reserved exclusively for block statements.

There are no exceptions.

---

# 3. List Literals

## Syntax

```
[expr1, expr2, expr3]
```

Example:

```
["alice", 12]
[1, 2, 3]
[]
```

## Semantics

* Ordered collection
* Indexed by position
* May contain heterogeneous elements (unless restricted by type system)
* Evaluates each element expression left-to-right

## Empty List

```
[]
```

This is always a list.

---

# 4. Dictionary Literals

## Syntax

```
[key1: value1, key2: value2, ...]
```

Example:

```
[name: "alice", age: 32]
```

## Semantics

* Mapping from keys to values
* Keys are expressions
* Values are expressions
* Insertion order preserved (if language defines ordered maps)

---

# 5. Parsing Rule (Authoritative)

The parser must apply the following deterministic rule:

### When encountering `[`:

1. Parse top-level elements separated by commas.

2. If **any top-level element contains a colon (`:`)** of the form:

   ```
   key_expression : value_expression
   ```

   then:

   → The entire literal is parsed as a **dictionary**.

3. Otherwise:

   → The literal is parsed as a **list**.

---

## Examples

### Dictionary

```
[name: "alice", age: 32]
```

Parsed as:

```
Dict(
  key="name", value="alice",
  key="age",  value=32
)
```

---

### List

```
["alice", 12]
```

Parsed as:

```
List("alice", 12)
```

---

### Nested Example

```
[
  name: "alice",
  scores: [10, 20, 30]
]
```

Still a dictionary because top-level `:` exists.

---

# 6. Disallowed Forms

The following must produce syntax errors:

## Mixed Forms

```
[name: "alice", 12]
```

Reason: mixture of key-value pair and standalone expression.

Rule:

> A bracket literal must be entirely key-value pairs or entirely expressions.

---

## Colon Without Value

```
[name:]
```

Syntax error.

---

## Ambiguous Block Usage

```
{ name: "alice" }
```

This is a block.
Not a dictionary.
Always.

If used in expression position where a value is required, it is a syntax error unless blocks are expressions in the language.

---

# 7. Formal Grammar Sketch

```
block        ::= "{" statement* "}"

list_literal ::= "[" expression_list? "]"

dict_literal ::= "[" key_value_list "]"

expression_list ::= expression ("," expression)*

key_value_list ::= key_value ("," key_value)*

key_value ::= expression ":" expression
```

Parser decision rule:

```
if top-level ':' detected inside '[' ']'
    parse as dict_literal
else
    parse as list_literal
```

This must be implemented at the AST construction stage.

---

# 8. AST Distinction

The AST must distinguish explicitly:

```
ListLiteral(elements: Expr[])
DictLiteral(entries: (Expr, Expr)[])
Block(statements: Stmt[])
```

These nodes are never interchangeable.

---

# 9. Type Semantics

| Construct | Type                       |
| --------- | -------------------------- |
| `[1,2]`   | List                       |
| `[a:1]`   | Dict                       |
| `{ ... }` | Block (no collection type) |

Blocks are not values unless the language explicitly defines block expressions.

---

# 10. Rationale

## 1. Avoid `{}` Ambiguity

Many languages overload `{}` for both blocks and maps.

This language deliberately avoids that ambiguity.

This improves:

* Parser simplicity
* Tooling reliability
* LLM code generation stability
* Readability

---

## 2. Deterministic Parsing

The presence of `:` at top level inside `[]` is a simple and robust discriminator.

No lookahead complexity.
No contextual guessing.

---

## 3. Structural Clarity

Visual meaning:

* `[]` → data
* `{}` → control flow

Never overlap.

---

# 11. Guidance for Tooling and LLMs

### DO NOT:

* Generate `{ key: value }` for dictionaries.
* Rewrite dictionary literals into blocks.
* Mix list and dictionary syntax.
* Infer dictionary from runtime context.

### ALWAYS:

* Use `[key: value]` for dictionaries.
* Use `[a, b, c]` for lists.
* Use `{}` only for blocks.

---

# 12. Invariants (Must Never Change)

1. `{}` is block-only.
2. `[]` is collection-only.
3. Colon at top-level inside `[]` means dictionary.
4. No implicit conversions between list and dict.
5. Mixed list/dict bracket forms are illegal.

These are core language guarantees.

---

# Summary

| Syntax                     | Meaning    | Example         |
| -------------------------- | ---------- | --------------- |
| `[1, 2]`                   | List       | `["alice", 12]` |
| `[name: "alice", age: 32]` | Dictionary | mapping         |
| `{ ... }`                  | Block      | control flow    |

This separation is strict, deliberate, and foundational to the language design.
