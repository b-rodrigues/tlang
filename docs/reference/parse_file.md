# parse_file

Parse T-Doc Comments

Scans a source file and extracts all T-Doc documentation blocks (lines starting with `--#`). Parses the tags (`@name`, `@param`, `@return`, etc.) into structured documentation entries.

## Parameters

- **filename** (`String`): The path to the source file to parse.

## Returns

A list of parsed documentation entries.

