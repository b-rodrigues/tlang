(comment) @comment

[
  "if"
  "else"
  "import"
  "function"
  "pipeline"
  "intent"
  "match"
  "in"
] @keyword

[
  "true"
  "false"
] @boolean

(number) @number
(string) @string
(na) @constant.builtin
(ellipsis) @constant.builtin
(serializer_id) @attribute
(column_ref) @variable.member
(backtick_identifier) @variable
(raw_code_block) @embedded
(shell_command_block) @embedded

(assignment name: (identifier) @variable)
(assignment name: (backtick_identifier) @variable)
(reassignment name: (identifier) @variable)
(reassignment name: (backtick_identifier) @variable)
(parameter name: (identifier) @parameter)
(parameter name: (backtick_identifier) @parameter)
(parameter name: (column_ref) @parameter)
(pipeline_node name: (identifier) @variable)
(intent_field name: (identifier) @property)
(dict_entry key: (identifier) @property)
(dict_entry key: (backtick_identifier) @property)
(import_binding alias: (identifier) @variable)
(import_binding name: (identifier) @namespace)
(import_statement package: (identifier) @namespace)
(error_pattern field: (identifier) @property)
(list_rest_pattern name: (identifier) @variable)
(member_expression property: (identifier) @property)
(call_expression function: (identifier) @function.call)
(call_expression function: (member_expression property: (identifier) @function.method))
(identifier) @variable

((identifier) @function.builtin
  (#match? @function.builtin "^(build_pipeline|clean_colnames|filter|glimpse|group_by|head|join|mean|mutate|ncol|node|nrow|predict|print|pyn|read_csv|rn|select|slice|split|sqrt|summarize|t_read_pmml|tail)$"))

[
  "="
  ":="
  ":"
  "->"
  "=>"
  "|>"
  "?|>"
  "~"
  "+"
  "-"
  "*"
  "/"
  "%"
  ".+"
  ".-"
  ".*"
  "./"
  ".%"
  "=="
  "!="
  "<"
  ">"
  "<="
  ">="
  ".=="
  ".!="
  ".<"
  ".>"
  ".<="
  ".>="
  "&&"
  "||"
  "&"
  "|"
  ".&"
  ".|"
  "!"
  "!!"
  "!!!"
  "."
] @operator

[
  "(" ")"
  "[" "]"
  "{" "}"
] @punctuation.bracket

[
  ","
  ";"
] @punctuation.delimiter
