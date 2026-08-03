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
  (#match? @function.builtin "^(abs|add_diagnostics|all_of|anova|anti_join|any_of|apropos|args|arrange|arrange_node|asin|assert|assert_dir_exists|assert_file_exists|assert_non_empty_file|assert_size_of_file|atan|bind_cols|bind_rows|body|build_log|build_log_history|build_log_to_frame|build_pipeline|case_when|casewhen|cat|ceiling|chain|clean_colnames|clean_names|coef|collect_exceptions|colnames|complete|conf_int|contains|cor|count|cov|crossing|cume_dist|cummax|cummin|cumsum|cv|day|debug_node|dense_rank|deserialize|deviance|df_residual|diag|diff_summary|difference|dir_exists|distinct|downstream_of|drop_na|ends_with|env|error|error_code|error_message|errored_nodes|everything|exit|expand|expand_pipeline|explain|explain_json|export_artifacts|expr|fetchurl|fill|filter|filter_node|fit_stats|fivenum|floor|full_join|get|getwd|glimpse|group_by|head|help|huber_loss|identical|ifelse|import_artifacts|inner_join|inspect_artifacts|inspect_log|inspect_node|inspect_pipeline|intersect|inv|iqr|is_error|is_na|jl_node|join|kurtosis|lag|lead|left_join|length|list_files|list_logs|lm|log|make_date|make_datetime|map|matmul|max|mdy|mean|median|meta_flatten|min|mutate|mutate_node|n|n_distinct|ncol|nest|nesting|nobs|node|node_diff|node_fork|node_when|normalize|now|nrow|ntile|parallel|patch|path_abs|path_basename|path_dirname|path_ext|path_join|path_stem|pchisq|percent_rank|pf|pipeline_assert|pipeline_cache_status|pipeline_copy|pipeline_cycles|pipeline_deps|pipeline_depth|pipeline_diff|pipeline_edges|pipeline_gc|pipeline_leaves|pipeline_node|pipeline_node_options|pipeline_nodes|pipeline_print|pipeline_report|pipeline_roots|pipeline_run|pipeline_to_dot|pipeline_to_drv|pipeline_to_frame|pipeline_to_ga|pipeline_to_mermaid|pipeline_to_store|pipeline_validate|pivot_longer|pivot_wider|pnorm|poly|populate_pipeline|pow|predict|prefetch|pretty_print|print|prop_for_all|prop_gen_bool|prop_gen_choice|prop_gen_date_range|prop_gen_df|prop_gen_df_from|prop_gen_factor|prop_gen_float_range|prop_gen_frequency|prop_gen_fn|prop_gen_int|prop_gen_int_range|prop_gen_list|prop_gen_one_of|prop_gen_string_from|prop_gen_vector|prop_map_gen|prop_resize|prop_stats|prop_such_that|prune|pt|pull|pyn|qchisq|qf|qn|qnorm|qt|quantile|range|read_arrow|read_csv|read_file|read_log|read_node|read_parquet|read_past_node|read_pipeline|rebuild_node|relocate|rename|rename_node|replace_na|reshape|residuals|rewire|rn|round|row_number|run|sample|scale|score|sd|select|select_node|semi_join|separate|seq|serialize|set_nix_defaults|set_pipeline_global_options|set_seed|shn|sigma|sin|skewness|slice|slice_max|slice_min|slice_sample|sort|source|split|sqrt|standardize|starts_with|str_detect|str_extract|str_join|str_nchar|str_replace|str_split|subgraph|sum|summarize|summary|suppress_warnings|swap|t_check|t_diff|t_fix|t_gc|t_make|t_read_json|t_read_onnx|t_read_pmml|t_write_json|tail|to_date|to_datetime|to_factor|to_float|to_integer|today|trace_nodes|trimmed_mean|type|uncount|ungroup|union|unite|unnest|upstream_of|var|vcov|wald_test|where|which_nodes|winsorize|with_seed|write_arrow|write_csv|write_text|ymd|ymd_hms)$"))

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
