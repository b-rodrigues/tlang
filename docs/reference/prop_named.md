# prop_named

Name a reusable property

Bundles a property function under a `name` into an immutable named property Dict. Named properties are plain values (no global registry): pass the result to prop_test to run it against a generator. Failure reports are prefixed with the property's name.

## Parameters

- **name** (`String`): The property's display name.

- **property** (`Function`): A function from a generated value to Bool or Expect.


## Returns

{ name, property }.

## Examples

```t
monotone = prop_named("monotone", \(x) x <= 100)
assert(prop_test(monotone, prop_gen_between(0, 200)))
```

## See Also

[prop_for_all](prop_for_all.html), [prop_test](prop_test.html)

