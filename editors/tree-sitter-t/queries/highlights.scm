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

; Core builtins — alphabetically sorted for maintainability.
; This list covers the most important functions from all standard packages.
((identifier) @function.builtin
  (#match? @function.builtin "^(abs|anti_join|arrange|assert|assert_dir_exists|assert_file_exists|assert_non_empty_file|assert_size_of_file|bind_cols|bind_rows|build_pipeline|cat|case_when|clean_colnames|coef|complete|conf_int|contains|cor|count|cov|crossing|cummax|cummin|cumsum|dataframe|dense_rank|deserialize|distinct|drop_na|ends_with|error|error_code|error_message|everything|exit|expand|explain|explain_json|expr|factor|fill|filter|floor|full_join|glimpse|group_by|head|help|identical|ifelse|inner_join|inspect_node|inspect_pipeline|is_error|is_na|join|lag|lead|left_join|length|list_files|list_logs|lm|map|max|mean|median|min|mutate|n|n_distinct|ncol|nesting|node|normalize|nobs|nrow|pivot_longer|pivot_wider|populate_pipeline|predict|pretty_print|print|pull|pyn|qn|quantile|range|read_arrow|read_csv|read_file|read_node|read_parquet|read_pipeline|rebuild_node|relocate|rename|replace_na|rn|round|sd|select|semi_join|seq|serialize|shn|slice|slice_max|slice_min|sort|split|sqrt|standardize|starts_with|str_detect|str_extract|str_join|str_nchar|str_replace|str_split|summarize|summary|sum|suppress_warnings|t_read_onnx|t_read_pmml|t_write_json|t_read_json|tail|today|trace_nodes|type|uncount|ungroup|unnest|var|where|write_arrow|write_csv|write_text|ymd|ymd_hms)$"))

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
