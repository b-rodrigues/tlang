---
name: t-package
description: Use this skill when working inside a T (tlang) package — a directory with DESCRIPTION.toml, src/*.t, and a tests/ folder meant to be imported by other T projects rather than run as an analysis. Trigger for writing exported functions, adding T-Doc (--#) comments, writing unit tests, running t doc or t test, or deciding whether something belongs in this package versus a one-off project. Trigger even without the word "package" if the directory has DESCRIPTION.toml and no tproject.toml.
---

# T Package Quickstart

Companion to `AGENTS.md` and `T-LANGUAGE-REFERENCE.md` in this package's root — read both first.
This skill covers the mechanics of adding something to the package correctly.

## Mental model

A package is a library, not an analysis. The test that should guide every decision here: **would
this function still make sense if someone imported it into a project you've never seen?** If it
assumes a `data/` directory, a specific column name, or a specific project's shape, it belongs in
a project's pipeline, not in this package.

## Worked example: adding an exported function

```t
--# Winsorize a numeric column at the given percentile tails.
--#
--# Values below the lower quantile are clipped to it, and likewise for the upper.
--# Returns the input unchanged if all values are NA.
--#
--# @name winsorize
--# @param x :: Vector[Float] The values to clip.
--# @param probs :: Vector[Float] = [0.01, 0.99] Lower/upper quantile cutoffs.
--# @return :: Vector[Float] The clipped values.
--# @export
winsorize = \(x, probs = [0.01, 0.99]) {
  bounds = quantile(x, probs, na_rm = true)
  x |> map(\(v) clamp(v, bounds[0], bounds[1]))
}
```

Then, matching test in `tests/`:

```t
test("winsorize clips values outside the given quantiles", {
  x = [1, 2, 3, 100, -50]
  result = winsorize(x, probs = [0.1, 0.9])
  assert(max(result) < 100, "upper tail should be clipped")
  assert(min(result) > -50, "lower tail should be clipped")
})
```

## The T-Doc block is not optional decoration

Every public function needs one, and `t doc --generate` will catch it if you skip a field. Keep
the tags in this order: `@name`, `@param` (one per parameter, in call order), `@return`,
`@family` (if grouping with related functions), `@export` or `@private`.

`@private` is how you hide a helper from the package's public namespace — use it liberally for
anything that isn't meant to be called directly by consumers of the package.

## Data-first, always

The data argument is the *first* positional parameter, full stop — even if the function reads
more naturally with it elsewhere. This is what makes `df |> winsorize(probs = [0.05, 0.95])` work.
If you're about to write a function where data isn't first, that's a sign it should be structured
differently, not an exception to make.

## Error handling

No placeholders, no silent `null`-like fallbacks. On invalid input, return
`error("PackageName", "specific message")` and let the caller decide what to do with it via
`is_error()` / `?|>`. A function that prints a warning and returns a best-guess value is hiding a
bug from whoever calls it next.

## Before calling a task done

- `t test` passes, and the new/changed function has at least one test exercising it.
- `t doc --parse . && t doc --generate` runs clean — this is the fastest way to catch a malformed
  T-Doc block before a human notices.
- If you added a dependency, it's declared in `DESCRIPTION.toml` and you ran `t update`.
- Naming follows snake_case / tidyverse-style conventions already used elsewhere in `src/` — check
  a neighboring function rather than guessing.
