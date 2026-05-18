#!/bin/bash
# Revert variable names to 'expr' where they were incorrectly changed to 'to_expression'.
# Version 2: More thorough.

# 1. match to_expression -> match expr
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/match to_expression /match expr /g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/match to_expression\./match expr\./g'

# 2. unparse_expr to_expression -> unparse_expr expr
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/unparse_expr to_expression/unparse_expr expr/g'

# 3. | Expression to_expression -> | Expression expr
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/| Expression to_expression/| Expression expr/g'

# 4. let ... to_expression = -> let ... expr =
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/let \(.*\) to_expression =/let \1 expr =/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/fun \(.*\) to_expression ->/fun \1 expr ->/g'

# 5. Fix field accesses: to_expression.node -> expr.node
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/to_expression\.node/expr.node/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/to_expression\.loc/expr.loc/g'

# 6. Function calls with to_expression argument
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/(\(.*\)) to_expression/(\1) expr/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/ \(.*\) to_expression/ \1 expr/g'
# Careful with above, it might be too broad. Let's refine.
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/analyze_expr_for_pipeline_call to_expression/analyze_expr_for_pipeline_call expr/g'

# 7. Record fields in match patterns
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/Reassignment { \(.*\); to_expression }/Reassignment { \1; expr }/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/Assignment { \(.*\); to_expression; \(.*\) }/Assignment { \1; expr; \2 }/g'

# 8. Some to_expression -> Some expr
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/Some to_expression/Some expr/g'

echo "Variable name reversion (v2) complete."
