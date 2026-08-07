# with_seed

Run a thunk with a scoped random seed

Sets the global random number generator to `seed` for the duration of the thunk evaluation, then restores the previous RNG state. This scopes determinism to a single expression: any random draws outside the thunk are unaffected. Useful for reproducible property tests and sampling.  The thunk is a one-parameter lambda (the argument is ignored) so that it binds lazily, mirroring prop_for_all's predicate convention:  with_seed(42, \(x) sample([1, 2, 3, 4, 5], n = 3))

## Parameters

- **seed** (`Int`): The seed value to scope the RNG to.

- **thunk** (`Function`): A one-parameter lambda whose body is run under `seed`.


## Returns

The result of evaluating `thunk`.

## Examples

```t
with_seed(42, \(x) sample([1, 2, 3, 4, 5], n = 3))
```

## See Also

[prop_for_all](prop_for_all.html), [slice_sample](slice_sample.html), [sample](sample.html), [set_seed](set_seed.html)

