# t_fix

Mechanically Apply Suggested Fixes

Runs `t check --schema` on a file, extracts diagnostics with suggested_fix, and applies them (e.g., renaming columns, adding missing node arguments). Uses bottom-up line order to avoid line-number drift.

## Parameters

- **file** (`String`): The path to the .t file to fix.

- **dry_run** (`Bool`): = false Show what would be fixed without modifying the file.


## Returns

Summary of fixes applied (or would be applied).

