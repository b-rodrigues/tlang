#!/bin/bash
# Revert OCaml type names that were incorrectly refactored.
# We want to keep to_dataframe and to_expression as function names in T-Lang,
# but revert them to dataframe and expr in OCaml types.

# 1. Revert Ast.to_expression to Ast.expr
find src -name "*.ml" -o -name "*.mli" -o -name "*.mly" | xargs sed -i 's/Ast\.to_expression/Ast.expr/g'
find src -name "*.ml" -o -name "*.mli" -o -name "*.mly" | xargs sed -i 's/to_expression list/expr list/g'

# 2. Revert to_dataframe (type) to dataframe (type)
# This is tricky because to_dataframe is also a function.
# Usually in OCaml, types in function signatures look like (df : to_dataframe) or (_ : to_dataframe)
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/: to_dataframe/: dataframe/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/of to_dataframe/of dataframe/g'

# 3. Revert record fields in Ast.stmt_node
# Assignment { name; to_expression; _ } -> Assignment { name; expr; _ }
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/Assignment { \(.*\); to_expression; \(.*\) }/Assignment { \1; expr; \2 }/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/Reassignment { \(.*\); to_expression; \(.*\) }/Reassignment { \1; expr; \2 }/g'
# And just the fields
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/to_expression =/expr =/g'

# 5. Fix Call record fields if they were broken (Call has fn and args)
# No change needed for Call? Call had 'fn' and 'args' which were both to_expression types.
# Wait, I refactored fn and args to to_expression types in ast.ml already.

# 6. Any other places where to_expression was used as a TYPE name.
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/: to_expression/: expr/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/-> to_expression/-> expr/g'

echo "Reversion complete."
