# Review: src/parser.mly

**Lines**: 584
**Severity summary**: 2 critical, 1 warning, 4 info

---

## CRITICAL: Uncaught exception `Mixed_bracket_form` propagates to top level

- **Line 22**: `raise Mixed_bracket_form` is triggered by user input (`[a: 1, 2]` — mixing list and dict syntax in a bracket literal). The exception is never caught in production code — `eval.ml` and `repl.ml` only catch `Lexer.SyntaxError` and `Parser.Error` around calls to `Parser.program`. The test file `tests/core/test_lists.ml:6` merely expects the raw exception string, confirming there is no runtime handler. A user writing `[a: 1, 2]` will crash the REPL or script runner with an unhandled OCaml exception instead of receiving a structured `VError`.

  **Fix**: Catch `Mixed_bracket_form` in the `build_bracket_literal` function itself and return a `VError` (or restructure `build_bracket_literal` to return a `(expr_node, string) result` that the call site in the `bracket_lit` rule can inspect, producing an error expression instead of raising).

## CRITICAL: Uncaught exception `Invalid_match_pattern` propagates to top level

- **Line 449-453**: `raise (Invalid_match_pattern ...)` is raised when a user writes a match pattern like `match x { Foo { y } => y }` — i.e., any constructor name other than `Error` inside a `{ ... }` pattern. As with `Mixed_bracket_form`, this exception is never caught in production code. Any user input that triggers this branch crashes the parser rather than returning a descriptive error.

  **Fix**: Replace `raise (Invalid_match_pattern ...)` with a `VError` return. Since `match_pattern` is embedded inside semantic actions, this likely requires changing the return type of the relevant rule (or propagating an error expression node like `with_loc (Value (VError ...))` at the grammar action level).

## WARNING: `if_expr` branches restricted to `primary_expr`

- **Lines 422-425**: Both the `then_` and `else_` branches of `if_expr` are constrained to `primary_expr` rather than `expr`. This means expressions like `if (cond) 1 + 2 else 3` will fail to parse (they require parentheses: `if (cond) (1 + 2) else 3`). While this may be an intentional syntactic limitation, it is inconsistent with most languages and will surprise users. This also interacts with the dangling-else resolution (`%prec IF_WITHOUT_ELSE`), which depends on `primary_expr` consuming only non-IF expressions.

  **Fix**: Widen `then_` and `else_` to `expr` and fix the dangling-else ambiguity through a different mechanism (e.g., a mid-rule action or a dedicated `if_body` non-terminal that excludes `if_expr` from the first position).

## INFO: `max 1` clamps column calculation, could mask lexer bugs

- **Line 48**: `column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1)` — the `max 1` guards against negative column values that should never occur in a correctly functioning lexer. If `pos_cnum < pos_bol` (e.g., due to an `advance_lines_for_lexeme` bug), the column is silently set to 1 instead of surfacing the underlying issue.

  **Fix**: Remove the `max 1` guard, or replace it with an assertion during development.

## INFO: Inner match on `e.node` uses catch-all `_` with implicit exhaustiveness

- **Line 26-30**: The pattern `match e.node with | UnquoteSplice _ -> ... | _ -> ...` relies on a catch-all to handle the other ~18 `expr_node` variants. This is safe because the catch-all's behavior (treating the expression as a normal list element) applies uniformly. However, if a new `expr_node` variant is later added that should also behave like `UnquoteSplice` (e.g., `Unquote`), the catch-all will silently treat it as a normal expression rather than forcing list semantics.

  **Fix**: Make the distinction explicit — either list the specific variants that behave as "normal" elements, or document in a comment that the catch-all is intentional and list which variants (if any) in the future should also receive `UnquoteSplice`-like treatment.

## INFO: Exception definitions without `try/with` coverage

- **Line 7-8**: `Mixed_bracket_form` and `Invalid_match_pattern` are defined here but never caught in production code (see CRITICAL findings above). The `Parser.Error` exception (raised by Menhir on standard parse failures) IS handled at every call site.

  **Fix**: Either catch these exceptions at call sites in `eval.ml`/`repl.ml`, or — preferably — eliminate the `raise` in favor of `VError` returns as described above.

## INFO: Empty comment blocks

- **Lines 84-85, 97-100**: Standalone `/* ... */` blocks with only spaces and newlines inside. These appear to be visual separators but carry no semantic content and are not consistent with the rest of the file's commenting style. While harmless, they add noise.

  **Fix**: Remove the empty comment blocks; use consistent section-comment conventions if visual separation is desired.

## INFO: `%nonassoc LOWEST` used as virtual base precedence but never in conflict

- **Line 106**: `%nonassoc LOWEST` is declared but only used as a virtual low-precedence sentinel (`%prec LOWEST` on several rules). This is a common and harmless pattern, but the same effect could be achieved by simply omitting `%prec` on the lowest-level rules.

  **Fix**: No change strictly needed, but consider removing `LOWEST` and the corresponding `%prec LOWEST` annotations for clarity, since Menhir's default precedence assignment already handles these rules correctly.
