# Shell differential fixtures

Each `case_NN_*.sh` is a minimal shell snippet exercising one settled
persistence rule of T's shell dependency scanner. The matching
`case_NN_*.json` is that snippet parsed by a real shell parser
(`shfmt --to-json`, version in `SHFMT_VERSION`), checked in so the
test stays hermetic: no parser binary is needed at test time.

`tests/test_shell_diff.ml` checks two dimensions:

- Bindings: T must not bind more than the shell does
  (`T binds ⊆ truth`). Over-binding drops a later read and loses an
  edge. Under-binding only keeps extra edges and passes, except in
  the `exact_cases` list where precision matters and equality holds.
- Reads: every `$x` / `${x}` variable read in the shfmt AST
  (`ParamExp`) must stay visible to T's identifier scan. Extra T
  names (command words like `echo`) are fine.

The shfmt-side rules below mirror POSIX/bash persistence
and were verified against real bash where subtle:

- A bare `Assign` statement binds (arrays included). Values are never
  walked: command substitutions are subshells.
- `CallExpr` binds its `Assigns` only with zero `Args` (pure
  assignment: chains, redirects, empty values). With arguments the
  assigns are env-prefixes and bind nothing.
- `Stmt.Background` (lone `&`) and `BinaryCmd` pipe elements run in
  subshells: nothing inside persists. `&&` (op 11) and `||` (op 12)
  run in place but only the left side persists; the right side is
  conditional and never persists outward (T treats it as unbound);
  `|` is op 13 (shfmt 3.13 encoding).
- Brace groups run in the current shell and persist.
- `Subshell` bodies, function bodies, and `if`/`while`/`for` bodies
  never persist outward. `for` loop variables bind at loop level
  (`ForClause.Loop.Name`).
- `DeclClause` (`export`/`declare`/`readonly`/`local`) binds
  assignment args, never bare words.

Regenerate the JSON after editing any `.sh` file:

```
scripts/regen_shell_diff.sh
```

## Known divergence: `export FOO=1 cmd`

Real bash binds `FOO` here (verified: the variable persists and the
command never runs), and the same holds for `declare`/`readonly`.
T's scanner treats it as an assignment prefix and binds nothing
(`check_bind "sh export prefix binds nothing"`). The fixture
`case_16_export_prefix` documents shell truth; the test keeps it
subset-only (not in `exact_cases`) so it passes while the divergence
stands. See the 0.55.5 review thread.
