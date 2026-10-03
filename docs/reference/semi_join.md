# semi_join

Filter rows using matches in another table

Keeps rows from the left DataFrame that have a matching key in the right DataFrame.

## Parameters

- **x** (`DataFrame`): Left DataFrame.

- **y** (`DataFrame`): Right DataFrame.

- **by** (`String | Symbol | List | Vector`): [Optional] Key columns. Defaults to shared columns.


## Returns

Filtered left DataFrame.

