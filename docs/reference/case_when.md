# case_when

Vectorized Case-When

Evaluates multiple conditions and returns the corresponding value for the first true condition. Similar to SQL's CASE WHEN. Conditions are provided as formulas `condition ~ value`.

## Parameters

- **.default** (`Any`): (Optional) Default value if no condition is met.
- **...** (`Formula`): Conditions and their corresponding return values.

## Returns

A vector of the resulting values.

