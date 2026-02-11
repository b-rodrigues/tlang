# Contributing to T

Thank you for your interest in contributing to T! This guide will help you get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Submitting Changes](#submitting-changes)
- [Review Process](#review-process)

---

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive environment for all contributors, regardless of background or identity.

### Expected Behavior

- Be respectful and considerate
- Welcome newcomers and help them get started
- Focus on constructive criticism
- Accept responsibility for mistakes
- Prioritize the community's well-being

### Unacceptable Behavior

- Harassment, discrimination, or exclusionary language
- Personal attacks or insults
- Trolling or inflammatory comments
- Publishing others' private information

### Enforcement

Violations can be reported to the project maintainers. All complaints will be reviewed and investigated.

---

## How Can I Contribute?

### Reporting Bugs

**Before submitting**, check if the issue already exists in [GitHub Issues](https://github.com/b-rodrigues/tlang/issues).

**When submitting**:
1. Use a clear, descriptive title
2. Describe the exact steps to reproduce
3. Provide sample code and data (if applicable)
4. Include your environment (OS, Nix version, OCaml version)
5. Attach error messages and stack traces

**Example**:
```markdown
**Bug**: `mean()` returns incorrect result for large floats

**Steps**:
1. Start REPL
2. Run: `mean([1e10, 1e10, 1e10])`
3. Expected: `1e10`, Got: `9.99999e9`

**Environment**:
- OS: Ubuntu 22.04
- Nix: 2.13.3
- OCaml: 4.14.1
```

### Suggesting Features

**Before suggesting**, consider:
- Is it aligned with T's design goals (reproducibility, explicitness, data analysis)?
- Is it too broad or general-purpose?
- Could it be a library instead of core language feature?

**When suggesting**:
1. Clearly describe the problem it solves
2. Provide concrete examples
3. Discuss alternatives

### Contributing Code

We welcome:
- Bug fixes
- New standard library functions
- Performance improvements
- Documentation improvements
- Test coverage expansion

**Good first issues** are tagged with `good-first-issue` in GitHub.

### Improving Documentation

Documentation contributions are highly valued:
- Fix typos and grammatical errors
- Add examples to existing docs
- Write tutorials for common workflows
- Improve API reference clarity

---

## Development Setup

See the [Development Guide](development.md) for detailed setup instructions.

**Quick Start**:
```bash
git clone https://github.com/b-rodrigues/tlang.git
cd tlang
nix develop
dune build
dune runtest
```

---

## Project Structure

```
tlang/
├── src/
│   ├── ast.ml              # AST definition
│   ├── lexer.mll           # Lexer (ocamllex)
│   ├── parser.mly          # Parser (Menhir)
│   ├── eval.ml             # Evaluator
│   ├── repl.ml             # REPL implementation
│   ├── arrow/              # Arrow FFI bindings
│   │   ├── arrow_ffi.ml
│   │   └── arrow_stubs.c
│   ├── ffi/                # Other FFI utilities
│   └── packages/           # Standard library
│       ├── base/           # Errors, NA, assertions
│       ├── core/           # Functional utilities
│       ├── math/           # Math functions
│       ├── stats/          # Statistics
│       ├── dataframe/      # DataFrame operations
│       ├── colcraft/       # Data verbs
│       ├── pipeline/       # Pipeline introspection
│       └── explain/        # Debugging tools
├── tests/                  # Test suite
│   ├── unit/               # Unit tests
│   ├── golden/             # Golden tests (T vs R)
│   └── examples/           # Example programs
├── docs/                   # Documentation
├── examples/               # Example T programs
├── scripts/                # Development scripts
├── flake.nix               # Nix flake configuration
├── dune-project            # Dune configuration
└── Makefile                # Convenience targets
```

---

## Coding Standards

### OCaml Style

Follow standard OCaml conventions:

**Naming**:
- `snake_case` for functions and variables
- `PascalCase` for modules and types
- `SCREAMING_CASE` for constants

**Formatting**:
```ocaml
(* Use ocamlformat for automatic formatting *)
let eval env expr =
  match expr with
  | Int n -> VInt n
  | Float f -> VFloat f
  | Ident name -> Environment.lookup env name
  | BinOp (op, left, right) ->
      let v_left = eval env left in
      let v_right = eval env right in
      eval_binop op v_left v_right
  | _ -> failwith "Not implemented"
```

**Comments**:
- Use `(* OCaml comments *)` for implementation notes
- Document complex logic
- Explain "why" not "what"

**Pattern Matching**:
- Exhaustively match all cases
- Use `_` for catch-all only when intentional
- Avoid deeply nested matches (extract functions)

### T Language Style

**Example programs** should demonstrate best practices:

```t
-- Good: Clear variable names, explicit NA handling
customers = read_csv("data.csv", clean_colnames = true)
avg_age = mean(customers.age, na_rm = true)

-- Bad: Cryptic names, implicit NA behavior
c = read_csv("data.csv")
a = mean(c.age)  -- Errors if NA present
```

**Documentation**:
- Include docstrings for new functions
- Provide usage examples
- Document parameters and return values

---

## Testing Requirements

### Unit Tests

Located in `tests/unit/`.

**Example** (`tests/unit/test_mean.ml`):
```ocaml
let test_mean_basic () =
  let result = Stats.mean [VInt 1; VInt 2; VInt 3] false in
  assert (result = VFloat 2.0)

let test_mean_with_na () =
  let result = Stats.mean [VInt 1; VNA NAInt; VInt 3] true in
  assert (result = VFloat 2.0)

let tests = [
  ("mean_basic", test_mean_basic);
  ("mean_with_na", test_mean_with_na);
]
```

### Golden Tests

Located in `tests/golden/`.

Compare T output against R:

**T Program** (`tests/golden/mean.t`):
```t
print(mean([1, 2, 3, 4, 5]))
```

**R Script** (`tests/golden/mean.R`):
```r
cat(mean(c(1, 2, 3, 4, 5)), "\n")
```

**Run**:
```bash
dune exec src/repl.exe < tests/golden/mean.t > t_output.txt
Rscript tests/golden/mean.R > r_output.txt
diff t_output.txt r_output.txt
```

### Test Coverage

**Required**:
- All new functions must have unit tests
- Bug fixes must include regression tests
- Performance claims must include benchmarks

**Recommended**:
- Test edge cases (empty lists, NA values, errors)
- Test cross-platform behavior (Linux, macOS)
- Test integration with existing features

### Running Tests

```bash
# All tests
dune runtest

# Specific test
dune runtest tests/unit/test_mean.ml

# Verbose output
dune runtest --verbose

# Watch mode (re-run on changes)
dune runtest --watch
```

---

## Submitting Changes

### Workflow

1. **Fork** the repository
2. **Clone** your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/tlang.git
   ```
3. **Create a branch**:
   ```bash
   git checkout -b feature/my-feature
   ```
4. **Make changes**:
   - Write code
   - Add tests
   - Update documentation
5. **Test**:
   ```bash
   dune build
   dune runtest
   ```
6. **Commit**:
   ```bash
   git add .
   git commit -m "Add feature: description"
   ```
7. **Push**:
   ```bash
   git push origin feature/my-feature
   ```
8. **Open a Pull Request** on GitHub

### Commit Messages

Follow conventional commit format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, no code change
- `refactor`: Code refactor
- `test`: Add or fix tests
- `chore`: Build, CI, tooling

**Examples**:
```
feat(stats): Add median function

Implements median via quantile(0.5). Supports na_rm parameter.

Closes #42
```

```
fix(eval): Fix closure environment capture

Closures were capturing global env instead of local env.
This caused incorrect behavior in nested functions.
```

### Pull Request Guidelines

**Title**: Clear and descriptive
```
Add median function to stats package
```

**Description**: Include:
- What changed and why
- Related issue numbers (`Fixes #42`, `Closes #17`)
- Testing done
- Screenshots (for UI/output changes)

**Example**:
```markdown
## Summary
Adds `median()` function to stats package.

## Changes
- Implement median as `quantile(data, 0.5)`
- Add unit tests
- Update API reference documentation

## Testing
- Unit tests pass
- Golden test against R's `median()`
- Tested with NA values (na_rm parameter)

Fixes #42
```

**Checklist**:
- [ ] Code follows style guidelines
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] All tests pass
- [ ] Commit messages are clear

---

## Review Process

### What Reviewers Look For

1. **Correctness**: Does it work as intended?
2. **Testing**: Are changes adequately tested?
3. **Style**: Does it follow project conventions?
4. **Documentation**: Are changes documented?
5. **Scope**: Is the change focused and minimal?
6. **Backward Compatibility**: Does it break existing code?

### Addressing Feedback

- Be responsive to comments
- Don't take criticism personally
- Ask questions if feedback is unclear
- Make requested changes promptly
- Mark conversations as resolved when addressed

### Approval and Merge

- **1 approval required** for most changes
- **2 approvals required** for breaking changes or core features
- Maintainers will merge once approved
- Squash-merge is used to keep history clean

---

## Adding New Standard Library Functions

### Process

1. **Choose a package**: `base`, `core`, `math`, `stats`, `dataframe`, `colcraft`, `pipeline`, or `explain`
2. **Create function file**: `src/packages/<package>/<function_name>.ml` or `.t`
3. **Implement function**:
   ```ocaml
   (* src/packages/stats/median.ml *)
   let median values na_rm =
     Stats.quantile values 0.5 na_rm
   ```
4. **Register in package loader** (if needed)
5. **Add tests**: `tests/unit/test_median.ml`
6. **Update docs**: `docs/api-reference.md`
7. **Add example**: `examples/median_example.t`

### Function Signature Guidelines

**Parameters**:
- Required parameters first
- Optional parameters (e.g., `na_rm`) last
- Use named arguments for clarity

**Return values**:
- Return values, not side effects (when possible)
- Use `VError` for errors, not OCaml exceptions
- Document return type in comments

**Error handling**:
```ocaml
(* Good: Return VError *)
if List.length values = 0 then
  VError { code = "ValueError"; message = "Empty list"; ... }
else
  (* Compute result *)

(* Bad: Raise exception *)
if List.length values = 0 then
  failwith "Empty list"
```

---

## Getting Help

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions, ideas, show-and-tell
- **Pull Requests**: Code review and technical discussion

### Asking Good Questions

Include:
- What you're trying to do
- What you've tried
- Specific error messages
- Minimal reproducible example
- Your environment (OS, versions)

**Example**:
```markdown
I'm trying to add a new window function `row_min()` but getting a type error:

Error: This expression has type 'a list but an expression was expected of type Vector.t

Code:
```ocaml
let row_min values =
  (* ... *)
```

I've looked at `row_number.ml` but can't figure out where the conversion happens.

Environment: Ubuntu 22.04, OCaml 4.14.1
```

---

## Recognition

Contributors are recognized in:
- GitHub contributor graph
- Release notes for significant contributions
- `CONTRIBUTORS.md` file (coming soon)

---

## License

By contributing, you agree that your contributions will be licensed under the [EUPL v1.2](../LICENSE).

---

**Ready to contribute?** Check out [good first issues](https://github.com/b-rodrigues/tlang/labels/good-first-issue) or dive into the [Development Guide](development.md)!
