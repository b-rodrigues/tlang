# T Package Development Guide

This guide walks you through creating, developing, and publishing a package for the T language.

## 1. Creating a Package

You can create a new package interactively using the `t init package` command.

```bash
$ t init package
Initializing new T package/project...
Name [my-pkg]: advanced-stats
Author [User]: Alice
License [MIT]: EUPL-1.2

✓ Package 'advanced-stats' created successfully!
```

This creates a standard directory structure:

- **DESCRIPTION.toml**: Package metadata and dependencies.
- **flake.nix**: Reproducible development environment definition.
- **src/**: Source code (e.g., `main.t`).
- **tests/**: Test files (e.g., `test-advanced-stats.t`).
- **docs/**: Documentation (e.g., `index.md`).

## 2. Managing Dependencies

Dependencies are declared in `DESCRIPTION.toml`. To add a dependency on another T package (e.g., `math` or a git repository):

```toml
[dependencies]
# Example: depend on a git repository
my-lib = { git = "https://github.com/user/my-lib", tag = "v1.0.0" }
```

After modifying dependencies, run `t update` to refresh your environment:

```bash
$ t update
```

Then re-enter the development shell:

```bash
$ nix develop
```

## 3. Writing Code

Write your T code in `src/`. For example, `src/stats.t`:

```t
# src/stats.t
export fn mean(x) {
  sum(x) / length(x)
}
```

You can test your code interactively in the REPL:

```bash
$ t repl
T> import "src/stats.t"
T> stats.mean([1, 2, 3])
2.0
```

## 4. Testing

T has a built-in test runner. Tests are `.t` files in the `tests/` directory.

Example `tests/test-mean.t`:

```t
import "src/stats.t"

assert(stats.mean([1, 2, 3]) == 2.0)
assert(stats.mean([-1, -1]) == -1.0)
```

Run all tests with:

```bash
$ t test
```

## 5. Documentation

T packages use **T-Doc**, a comment-based documentation system. Documentation lives in source files close to the code and is generated into Markdown.

### Writing Documentation

Use `--#` comments above your functions to document them.

```t
--# Calculate the square of a number.
--#
--# @param x :: Integer
--#   The input number.
--#
--# @return :: Integer
--#   The squared result.
--#
--# @example
--#   square(4)
--#   -- 16
--#
--# @export
fn square(x) {
  x * x
}
```

**Supported Tags:**
- `@param <name> :: <type> <description>`: Document a parameter.
- `@return :: <type> <description>`: Document the return value.
- `@example`: Start a code example block.
- `@seealso <func1>, <func2>`: Link to related functions.
- `@export`: Mark the function as public (only exported functions appear in docs).

### Generating Documentation

To generate the documentation files in `docs/reference/`:

```bash
$ t doc --parse --generate
```

This will:
1.  Scan your `src/` directory for `--#` blocks.
2.  Generate Markdown files for each function in `docs/reference/`.
3.  Generate a `docs/reference/index.md` listing all exported functions.

### Viewing Documentation

You can view your documentation locally using:

```bash
$ t docs
```
This opens `docs/index.md` (or `README.md`) in your system viewer. You can link to your reference documentation from there.

## 6. Quality Control

Before publishing, run `t doctor` to check your package for common issues:

```bash
$ t doctor
✓ Everything looks good!
```

It checks for:
- Required files (`DESCRIPTION.toml`, `flake.nix`).
- Valid directory structure.
- Documentation existence.
- Nix installation.

## 7. Publishing

When you are ready to release a version:

1.  Ensure `DESCRIPTION.toml` has the correct `version`.
2.  Update `CHANGELOG.md` with release notes for that version.
3.  Commit all changes to git.
4.  Run `t publish`.

```bash
$ t publish
Preparing to publish version 0.1.0...

✓ Validation complete.
Proceed to tag and push v0.1.0? [y/N] y
✓ Tag v0.1.0 pushed to remote.
```

This will run your tests, verify the changelog, and push a git tag to your repository.
