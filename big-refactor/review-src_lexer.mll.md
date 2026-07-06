# Review: src/lexer.mll

**Lines**: 176
**Severity summary**: 1 critical, 1 warning, 6 info

---

## CRITICAL: Float pattern lacks scientific notation support

- **Line 34**: `let float = digit+ '.' digit*` — This regex does NOT handle scientific notation (e.g., `1.5e10`, `2.997e8`, `1E-5`). The token `123.456e10` will silently parse as `FLOAT(123.456)` followed by `IDENT("e10")`, which is almost certainly not what the user intended and produces a confusing downstream type error.

  **Fix**: Extend the float pattern to handle optional exponent suffixes:
  ```ocaml
  let float = digit+ '.' digit* (['e' 'E'] ['+' '-']? digit+)?
  ```
  Note that `int_of_string` / `float_of_string` in OCaml natively handle scientific notation, so no conversion code change is needed.

## WARNING: `pos_bol` tracking inconsistency between newline-counting approaches

- **Lines 49-58**: `advance_lines_for_lexeme` is used to correctly update `pos_lnum` and compute `pos_bol = pos_cnum - chars_since_last_newline`.
- **Lines 59-63**: `String.iter (fun c -> if c = '\n' then Lexing.new_line lexbuf) s` is used instead — this calls `Lexing.new_line` which sets `pos_bol = pos_cnum` (the absolute end of the entire lexeme), rather than the position right after the last newline. For the lexeme `\n  }` (newline, spaces, brace), `advance_lines_for_lexeme` would set `pos_bol` to the position after the `\n`, while the `String.iter` approach sets `pos_bol` to the position after `}`. Both produce functionally correct column values for the *next* token (column 1), but inconsistent internal state can cause subtle bugs in error reporting if any code inspects `pos_bol` directly or computes intermediate positions.

  **Fix**: Replace the `String.iter` approach on lines 61-62 with a call to `advance_lines_for_lexeme` for consistency:
  ```ocaml
  let s = Lexing.lexeme lexbuf in
  advance_lines_for_lexeme lexbuf s;
  RBRACE_TRAIL
  ```

## INFO: `Lexing.new_line` called on already-consumed newlines in continuation rules

- **Lines 47-48**: `'\n' [' ' '\t']* "?|>"` / `"|>"` — The action calls `Lexing.new_line lexbuf` after the entire lexeme has been consumed. At this point `pos_cnum` points past the `>` that ends the lexeme, so `pos_bol` is set to the end of the lexeme rather than the position after the `\n`. This works for the immediate next token (which starts right after the lexeme), but `pos_bol` no longer reflects the true start of the lexical line.

  **Fix**: For single-newline cases, `Lexing.new_line` is acceptable since the next token starts immediately after the lexeme and column will correctly be 1. Consider using `advance_lines_for_lexeme` for consistency if maintenance burden is low.

## INFO: Bare newlines silently accepted inside string literals

- **Line 174**: `[^ '"' '\'' '\\']+ as s` — This regex matches any sequence of characters that are not `"`, `'`, or `\`. Since `\n` is not in this exclusion set, raw newlines inside string literals are silently captured and added to the buffer. Most languages reject bare newlines in strings (requiring `\n` instead). Whether this is intentional (multi-line string support) or an oversight is unclear from the code alone.

  **Fix**: If multi-line strings are desired, document the behavior. If not, add a rule that raises a clear syntax error on bare newlines inside strings.

## INFO: Unrecognized escape sequences in strings silently produce literal characters

- **Line 176**: `| _ as c { Buffer.add_char buf c; read_string buf delim lexbuf }` — This catch-all in `read_string` handles any character not matched by earlier rules. When an invalid escape like `\x` is encountered, the `\` is caught by this rule and added to the buffer as a literal backslash; the next call handles `x` as a normal character. The user gets `\x` in their string with no warning.

  **Fix**: Add a specific rule to handle unknown escape sequences and produce a `SyntaxError`:
  ```ocaml
  | '\\' _ as s { raise (SyntaxError ("Unknown escape sequence: " ^ s)) }
  ```

## INFO: Catch-all `SyntaxError` on unexpected characters properly handled

- **Line 151**: `| _ as char { raise (SyntaxError ("Unexpected character: " ^ Char.escaped char)) }` — Unrecognized single characters raise a structured `SyntaxError`. This is correct and the exception IS caught at all entry points (`eval.ml`, `repl.ml`, `package_loader.ml`, `lsp_server.ml`, etc.). No issue, included for completeness.

## INFO: `is_ident_char` and lexer regex `identifier` are inconsistent about `$`

- **Line 7-9**: `is_ident_char` includes `'$'` as a valid identifier character.
- **Line 38-39**: The lexer regex `ident_start` and `ident_char` do NOT include `$`, so `$` is never part of an `IDENT` token — it only appears in the special `$identifier` column-reference rule (line 140). The function `is_ident_char` is used externally in `lsp_server.ml:127` for syntax-highlighting purposes and may intentionally consider `$` an identifier character for column reference highlighting. The inconsistency is that the function name implies a direct correspondence with the lexer's `IDENT` token, but the semantics differ.

  **Fix**: Either rename `is_ident_char` to something more descriptive like `is_ident_or_column_char`, or add a comment explaining the difference.

## INFO: `(` and `)` inside string literals leave narrow edge case

- **Line 167**: `'"' | '\'' as c { if c = delim then STRING ... else ... }` — This rule matches both `"` and `'`, checking if the matched quote equals the string delimiter. For a `"`-delimited string, hitting `'` adds `'` to the buffer (correct). For a `'`-delimited string, hitting `"` adds `"` to the buffer (correct). However, this means a `'`-delimited string that contains `'` followed by a "normal" character will not terminate at the first `'` — it terminates when the character matches the delimiter exactly. This is correct.

  **Fix**: No change needed — the logic is correct. Included for audit completeness.
