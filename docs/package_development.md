# T Package Development Guide

This guide walks you through creating, developing, and publishing a package for the T language.

## 1. Creating a Package

You can create a new package interactively using the `t init package` command.

```bash
$ t init package
Initializing new T package/project...
Name [my_package]: advanced-stats
Author [User]: Alice
License [EUPL-1.2]: EUPL-1.2

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

After modifying dependencies, run `t update` to sync your `flake.nix` and lock file:

```bash
$ t update
Syncing 1 dependency(ies) from DESCRIPTION.toml → flake.nix...
Running nix flake update...
```

This regenerates `flake.nix` so new dependencies appear as proper flake inputs, then locks them. After updating, re-enter the development shell:

```bash
$ nix develop
```

## 3. Writing Code

Write your T code in `src/`. For example, `src/stats_helpers.t`:

```t
-- src/stats_helpers.t

-- Public by default — importers can use this
weighted_mean = \(x, w) sum(x .* w) / sum(w)

--# Internal helper, not for public use.
--# @private
_validate_weights = \(w) {
  assert(length(w) > 0)
}
```

All top-level bindings in your package are **public by default**. To hide an internal helper, add `@private` to its T-Doc block.

You can test your code interactively in the REPL:

```bash
$ t repl
T> import "src/stats_helpers.t"
T> weighted_mean([1, 2, 3], [0.5, 0.3, 0.2])
1.7
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
- `@family <name>`: Group related functions together.
- `@private`: Mark the function as private — it will not be visible to importers.
- `@export`: Explicitly mark as public (this is the default, so usually not needed).

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

## 8. How Others Import Your Package

Once published, other packages or projects can depend on yours by adding it to their `DESCRIPTION.toml` or `tproject.toml`:

```toml
[dependencies]
advanced-stats = { git = "https://github.com/user/advanced-stats", tag = "v0.1.0" }
```

Then in their T code, they can import your package:

```t
-- Import everything (all public functions)
import advanced_stats

-- Import only specific functions
import advanced_stats[weighted_mean]

-- Import with aliases
import advanced_stats[wmean=weighted_mean]
```

Functions marked with `@private` in your package are not visible to importers.
