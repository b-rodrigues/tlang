# Verification Report: src/lexer.mll

---

## Finding: Float pattern lacks scientific notation support (Original line: 34)

**Actual line**: 35
**Status**: CONFIRMED

**Evidence**: Line 35:
```ocaml
let float = digit+ '.' digit*
```
The review claims line 34, but the actual line is **35** (offset by 1). The pattern does not handle `1.5e10`, `2.997e8`, or `1E-5`. A token like `123.456e10` lexes as `FLOAT(123.456)` + `IDENT("e10")`.

**Verdict**: Issue is real. The line number in the review is off by 1, but the finding is correct.

---

## Finding: `pos_bol` tracking inconsistency (Original lines: 49-58 and 59-63)

**Actual line**: 49-58 and 59-63
**Status**: CONFIRMED

**Evidence**: Two different approaches to newline tracking coexist:
- **Lines 49-58**: `advance_lines_for_lexeme` correctly sets `pos_bol = pos_cnum - chars_since_last_newline` (position right after the last newline in the lexeme)
- **Lines 59-63**: `String.iter (fun c -> if c = '\n' then Lexing.new_line lexbuf) s` sets `pos_bol = pos_cnum` at the end of the entire lexeme for each newline

For the `RBRACE_TRAIL` lexeme `(\n spaces)+ }`, if the next token starts after some whitespace on the last line, the column will be one too large because `pos_bol` points to the byte after `}` instead of the actual start of the line.

**Verdict**: The inconsistency is real. In practice, the column error is usually corrected by a subsequent `NEWLINE` token, but the internal state can be wrong between `RBRACE_TRAIL` and the next `NEWLINE`.

---

## Finding: `Lexing.new_line` called on already-consumed newlines in continuation rules (Original lines: 47-48)

**Actual line**: 47-48
**Status**: CONFIRMED

**Evidence**:
```ocaml
| '\n' [' ' '\t']* "?|>" { Lexing.new_line lexbuf; MAYBE_PIPE }
| '\n' [' ' '\t']* "|>" { Lexing.new_line lexbuf; PIPE }
```
`Lexing.new_line` sets `pos_bol = pos_cnum`, which at this point points past the `}>` or `|>` end of the lexeme. For the next token, column will correctly be 1 (since the next token starts immediately after the lexeme and `pos_cnum - pos_bol + 1 = 1`). The inconsistency is that `pos_bol` doesn't point to the true line start — it points to the character after `|>`.

**Verdict**: Accurate. The behavior happens to be correct for the immediately next token because of the coincidence that `pos_bol` is set to the same offset where the next token starts. Fragile but functional.

---

## Finding: Bare newlines silently accepted inside string literals (Original line: 174)

**Actual line**: 174
**Status**: CONFIRMED

**Evidence**: Line 174:
```ocaml
| [^ '"' '\'' '\\']+ as s { Buffer.add_string buf s; read_string buf delim lexbuf }
```
Newline (`\n`) is not excluded from this character class. Raw newline characters inside string literals are silently captured and added to the string buffer. Most languages either reject these (requiring `\n`) or document explicit multi-line string support.

**Verdict**: Accurate. Whether this is intentional multi-line string support or an oversight cannot be determined from the code alone. Worth documenting either way.

---

## Finding: Unrecognized escape sequences silently produce literal characters (Original line: 176)

**Actual line**: 176
**Status**: CONFIRMED

**Evidence**: Line 176:
```ocaml
| _ as c { Buffer.add_char buf c; read_string buf delim lexbuf }
```
The catch-all in `read_string` matches any character not matched by earlier rules (lines 167-174). When an invalid escape like `\x` is encountered, the `\` is consumed by this catch-all and added as a literal backslash; then `x` is consumed as a normal character. The user silently gets `\x` in their string.

**Verdict**: Accurate. Invalid escape sequences produce no warning or error.

---

## Finding: Catch-all `SyntaxError` on unexpected characters (Original line: 151)

**Actual line**: 151
**Status**: CONFIRMED

**Evidence**: Line 151:
```ocaml
| _ as char { raise (SyntaxError ("Unexpected character: " ^ Char.escaped char)) }
```
This is the correct pattern for handling unrecognized single characters.

**Verdict**: Confirmed as properly handled. The review itself says "No issue, included for completeness."

---

## Finding: `is_ident_char` and lexer regex `identifier` are inconsistent about `$` (Original lines: 7-9 and 38-39)

**Actual line**: 7-9 and 38-39
**Status**: CONFIRMED

**Evidence**:
- **Lines 7-9**: `is_ident_char` matches `'$'`
- **Lines 38-39**: `ident_start` and `ident_char` do NOT include `'$'`

As a result, `$` never appears in an `IDENT` token — it only appears in the dedicated `$identifier` `COLUMN_REF` rule at line 140. The function `is_ident_char` is used in `lsp_server.ml` for syntax-highlighting, where considering `$` as part of an identifier for column references is intentional.

**Verdict**: Accurate. The function name is slightly misleading; the semantics intentionally differ from the lexer's `IDENT` definition. Worth a comment or rename.

---

## Finding: `"` and `'` inside string literals logic is correct (Original line: 167)

**Actual line**: 167
**Status**: CONFIRMED

**Evidence**: Line 167:
```ocaml
| '"' | '\'' as c { if c = delim then STRING (Buffer.contents buf) else (Buffer.add_char buf c; read_string buf delim lexbuf) }
```
When the matched quote character matches the string delimiter, the string terminates. Otherwise, the character is added to the buffer (e.g., `'` inside a `"`-delimited string is kept as a literal `'`). This is correct.

**Verdict**: Confirmed as correct. Note: the review title says `(` and `)` but the description correctly refers to `"` and `'` — the title is a minor typo in the review.
