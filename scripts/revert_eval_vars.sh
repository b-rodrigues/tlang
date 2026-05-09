#!/bin/bash
# Fix remaining to_expression references in eval.ml and other files

find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/(to_expression : Ast.expr)/(expr : Ast.expr)/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/{ name; typ; to_expression }/{ name; typ; expr }/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/{ to_expression; _ }/{ expr; _ }/g'
find src -name "*.ml" -o -name "*.mli" | xargs sed -i 's/\[to_expression\]/\[expr\]/g'

echo "Done"
