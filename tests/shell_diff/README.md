# Shell differential fixtures

Each `case_NN_*.sh` is a minimal shell snippet exercising one settled
persistence rule of T's shell dependency scanner. The matching
`case_NN_*.json` is that snippet parsed by a real shell parser
(`shfmt --to-json`, version in `SHFMT_VERSION`), checked in so the
test stays hermetic: no parser binary is needed at test time.

`tests/test_shell_diff.ml` collects persistent bindings twice — once
with T's scanner, once by walking the shfmt AST — and requires exact
agreement. The shfmt-side rules below mirror POSIX/bash persistence
and were verified against real bash where subtle:

- A bare `Assign` statement binds (arrays included). Values are never
  walked: command substitutions are subshells.
- `CallExpr` binds its `Assigns` only with zero `Args` (pure
  assignment: chains, redirects, empty values). With arguments the
  assigns are env-prefixes and bind nothing.
- `Stmt.Background` (lone `&`) and `BinaryCmd` pipe elements run in
  subshells: nothing inside persists. `&&` (op 11) and `||` (op 12)
  run in place and persist; `|` is op 13 (shfmt 3.13 encoding).
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
`case_16_export_prefix` documents shell truth; the test skips it
until the behavior is decided. See the 0.55.5 review thread.
