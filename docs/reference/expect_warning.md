# expect_warning

Assert that a pipeline node produced a warning diagnostic

Passes if the node's diagnostics contain at least one warning. Optionally filters by warning `kind` string and/or regex on the warning `message`.  This only checks pipeline node warning diagnostics (stored in `nd_warnings` on `NodeResult`/`ComputedNode`). It does not capture runtime warnings or print output.  `ComputedNode` values must already have been evaluated (e.g. via `build_pipeline` or `run_pipeline`); otherwise the expectation fails.  The `message` pattern uses OCaml's standard `Str` regular expression syntax (not PCRE). Matching is substring-based (searches anywhere in the message). Empty string values for `kind` or `message` are treated as omitted filters (match any).

## Parameters

- **node** (`NodeResult`): | ComputedNode The computed node to inspect.

- **kind** (`String`): = "" Optional warning kind to match exactly (e.g. "NAExcluded").

- **message** (`String`): = "" Optional regex pattern to match against the warning message.


## Returns

Pass if warnings are present and match any provided filters.

## Examples

```t
assert(expect_warning(read_node(p.my_node)))
assert(expect_warning(read_node(p.my_node), kind = "NAExcluded"))
assert(expect_warning(read_node(p.my_node), message = "excluded"))
```

## See Also

[expect_error](expect_error.html)

