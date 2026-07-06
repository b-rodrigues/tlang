# Verification Report: src/parser.mly

---

## Finding: Uncaught exception `Mixed_bracket_form` propagates to top level (Original line: 22)

**Actual line**: 22
**Status**: CONFIRMED

**Evidence**: `raise Mixed_bracket_form` at line 22 inside `build_bracket_literal`. The exception is defined at line 7 but never caught in the parser, `eval.ml`, or `repl.ml`. A user writing `[a: 1, 2]` will crash the REPL/script runner with an unhandled OCaml exception.

**Verdict**: The finding is accurate. The exception is uncaught in all production code paths.

---

## Finding: Uncaught exception `Invalid_match_pattern` propagates to top level (Original line: 449-453)

**Actual line**: 449-453
**Status**: CONFIRMED

**Evidence**: Lines 449-453 contain:
```ocaml
raise
  (Invalid_match_pattern
     (Printf.sprintf
        "Invalid pattern constructor `%s`. ..."
        ctor))
```
The exception is defined at line 8 but never caught. Any user writing a match pattern with a non-`Error` constructor in `{ ... }` crashes the parser.

**Verdict**: Accurate. Both critical exceptions from this file share the same root cause — they are raised in semantic actions but never caught.

---

## Finding: `if_expr` branches restricted to `primary_expr` (Original lines: 422-425)

**Actual line**: 422-425
**Status**: CONFIRMED

**Evidence**: Both productions use `primary_expr`:
```
| IF LPAREN cond = expr RPAREN then_ = primary_expr %prec IF_WITHOUT_ELSE
| IF LPAREN cond = expr RPAREN then_ = primary_expr ELSE else_ = primary_expr
```
`if (cond) 1 + 2 else 3` will fail; users must write `if (cond) (1 + 2) else 3`.

**Verdict**: Correctly identified. This is a real syntactic limitation.

---

## Finding: `max 1` clamps column calculation (Original line: 48)

**Actual line**: 48
**Status**: CONFIRMED

**Evidence**:
```ocaml
column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1);
```
The `max 1` silently clamps negatives to 1. If `pos_cnum < pos_bol`, the error is hidden.

**Verdict**: Accurate observation. Low-severity, but real.

---

## Finding: Inner match on `e.node` uses catch-all `_` (Original lines: 26-30)

**Actual line**: 26-31
**Status**: CONFIRMED

**Evidence**: Lines 26-31:
```ocaml
(match e.node with
 | UnquoteSplice _ -> ...
 | _ ->
     loop true saw_pair dict_rev ((None, e) :: list_rev) rest)
```
The catch-all handles the other ~18 `expr_node` variants uniformly (treating them as list elements). If a new variant needs `UnquoteSplice`-like behavior, it would silently fall through to the catch-all.

**Verdict**: Accurately described. The review line numbers were slightly off (extends to line 31, not 30) but the finding is correct.

---

## Finding: Exception definitions without catch coverage (Original lines: 7-8)

**Actual line**: 7-8
**Status**: CONFIRMED

**Evidence**:
```ocaml
exception Mixed_bracket_form
exception Invalid_match_pattern of string
```
Neither exception is caught in `eval.ml`, `repl.ml`, or the parser itself.

**Verdict**: This is a summary of the two CRITICAL findings above. Accurate.

---

## Finding: Empty comment blocks (Original lines: 84-85, 97-100)

**Actual line**: 84-85, 97-99
**Status**: FALSE_POSITIVE

**Evidence**:
- Line 84: `/* ... */` — contains `...` text, not empty
- Line 97: `/* ... PRECEDENCE ... */` — contains descriptive text `... PRECEDENCE ...`
- Lines 85, 98-99: blank lines for visual separation

The review claims these are "standalone `/* ... */` blocks with only spaces and newlines inside." They actually contain meaningful separator text and follow the file's established convention for section dividers (there are multiple `/* ... */` blocks throughout, all using `...` as separator content).

**Verdict**: The comments are not empty — they contain `...` and `... PRECEDENCE ...` respectively, which are consistent visual separators used elsewhere in the file. No fix needed.

---

## Finding: `%nonassoc LOWEST` used as virtual base precedence (Original line: 106)

**Actual line**: 106
**Status**: CONFIRMED

**Evidence**: `%nonassoc LOWEST` at line 106, referenced via `%prec LOWEST` on several rules (lines 187, 207, 213, 219, 225, 241, 258, 276). This is a standard Menhir pattern to anchor a virtual bottom-level precedence.

**Verdict**: Accurate identification. The review itself says "No change strictly needed." This is a harmless idiom.
