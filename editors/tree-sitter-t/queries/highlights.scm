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
  (#match? @function.builtin "^(abs|add_diagnostics|all_of|anova|anti_join|any_of|apropos|args|arrange|to_date|to_datetime|to_factor|asin|assert|assert_dir_exists|assert_file_exists|assert_non_empty_file|assert_size_of_file|atan|add_diagnostics|bind_cols|bind_rows|body|build_pipeline|case_when|casewhen|cat|ceiling|clean_colnames|clean_names|coef|colnames|complete|conf_int|contains|cor|count|cov|crossing|cume_dist|cummax|cummin|cumsum|cv|day|dense_rank|deserialize|deviance|df_residual|diag|dir_exists|distinct|drop_na|ends_with|env|error|error_code|error_message|everything|exit|expand|explain|explain_json|expr|fill|filter|fit_stats|fivenum|floor|full_join|get|getwd|glimpse|group_by|head|help|huber_loss|identical|ifelse|inner_join|inspect_node|inspect_pipeline|inv|iqr|is_error|is_na|jl_node|join|kurtosis|lag|lead|left_join|length|list_files|list_logs|lm|log|make_date|make_datetime|map|matmul|max|mdy|mean|median|min|mutate|n|n_distinct|ncol|nest|nesting|node|nobs|normalize|now|nrow|ntile|path_abs|path_basename|path_dirname|path_ext|path_join|path_stem|pchisq|percent_rank|pf|pivot_longer|pivot_wider|pnorm|poly|populate_pipeline|pipeline_ci|pow|predict|pretty_print|print|pt|pull|pyn|qn|quantile|range|read_arrow|read_csv|read_file|read_node|read_parquet|read_pipeline|rebuild_node|relocate|rename|replace_na|reshape|residuals|rn|round|row_number|run|scale|score|sd|select|semi_join|separate|seq|serialize|shn|sigma|sin|skewness|slice|slice_max|slice_min|sort|source|split|sqrt|standardize|starts_with|str_detect|str_extract|str_join|str_nchar|str_replace|str_split|summarize|summary|sum|suppress_warnings|t_read_json|t_read_onnx|t_read_pmml|t_write_json|tail|today|to_float|to_integer|trace_nodes|trimmed_mean|type|uncount|ungroup|unite|unnest|var|vcov|wald_test|where|winsorize|write_arrow|write_csv|write_text|ymd|ymd_hms)$"))

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
