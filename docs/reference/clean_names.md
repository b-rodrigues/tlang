# clean_names

Clean Column Names

Normalizes a list of strings to be safe, consistent column names. Converts symbols (like €) to text, strips diacritics, lowers the case, replaces non-alphanumeric characters with underscores, and resolves duplicates.

## Parameters

- **names** (`Vector[String]`): The column names to clean.

## Returns:

Returns: The cleaned column names.

