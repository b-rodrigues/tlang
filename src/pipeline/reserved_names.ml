(* src/pipeline/reserved_names.ml *)
(* Canonical list of names that cannot be used as pipeline node names.

   A node name is reserved when it collides with something bound in the
   evaluation environment ([Packages.init_env]) — either a registered builtin
   function or a [known_symbols] runtime/serializer symbol.  Such a name can
   never be resolved as a cross-pipeline dependency at construction time,
   because free-variable dependency inference treats any env-bound name as
   "already known" and therefore refuses to chain the node (see eval.ml).
   Allowing the collision would silently break pipeline blocks that reference
   the node (e.g. [n] shadows the [n] builtin in { z = n + 1 }).

   Each name carries a kind so error messages can name the collision
   precisely ("builtin function" vs "runtime symbol").  The list is checked
   against the live environment (both membership and kind) by
   tests/pipeline/test_reserved_names.ml, so a builtin added to the
   environment without updating this list fails CI.  This module must NOT
   depend on Packages (Packages -> pipeline_inspect2 -> Pipeline_validation ->
   Reserved_names would be a module cycle); it is intentionally a static list. *)

type node_name_kind =
  | BuiltinFunction
  | RuntimeSymbol

let runtime_symbols =
  [ "R"; "Python"; "T"; "Julia"; "Quarto"; "sh"; "default"; "write_rds";
    "read_rds"; "write_pkl"; "read_pkl"; "write_json"; "read_json"; "pmml";
    "bin" ]

let builtin_functions =
  [
    "abs"; "acos"; "acosh"; "add_diagnostics"; "all_of"; "am";
    "anova"; "anti_join"; "any_of"; "apropos"; "args"; "arrange";
    "arrange_node"; "asin"; "asinh"; "assert"; "assert_dir_exists"; "assert_file_exists";
    "assert_non_empty_file"; "assert_size_of_file"; "atan"; "atan2"; "atanh"; "bind_cols";
    "bind_rows"; "body"; "build_log"; "build_log_history"; "build_log_to_frame"; "build_pipeline";
    "case_when"; "cat"; "cbind"; "ceiling"; "ceiling_date"; "chain";
    "char_at"; "check"; "clean_colnames"; "coef"; "collect_exceptions"; "col_lens";
    "colnames"; "compare"; "compare_native_vs_pmml_scores"; "complete"; "compose"; "conf_int";
    "contains"; "cor"; "cos"; "cosh"; "count"; "cov";
    "crossing"; "cross_pattern"; "cumall"; "cumany"; "cume_dist"; "cummax";
    "cummean"; "cummin"; "cumsum"; "cut"; "cv"; "day";
    "days"; "days_in_month"; "debug_node"; "dense_rank"; "deserialize"; "deviance";
    "df_residual"; "diag"; "difference"; "diff_summary"; "dir_exists"; "dispersion";
    "distinct"; "dmy"; "dmy_hms"; "downstream_of"; "drop_na"; "ends_with";
    "enquo"; "enquos"; "env"; "env_var_lens"; "error"; "error_chain";
    "error_code"; "error_context"; "errored_nodes"; "error_msg"; "eval"; "everything";
    "exit"; "exp"; "expand"; "expand_pipeline"; "expect_between"; "expect_colnames";
    "expect_column_types"; "expect_computed"; "expect_dependency"; "expect_deserializer"; "expect_empty"; "expect_equal";
    "expect_error"; "expect_fail"; "expect_false"; "expect_falsy"; "expect_fields"; "expect_gt";
    "expect_gte"; "expect_has_colnames"; "expect_has_pattern"; "expect_in"; "expect_length"; "expect_lt";
    "expect_lte"; "expect_match"; "expect_msg"; "expect_ncol"; "expect_nodes"; "expect_no_na";
    "expect_noop"; "expect_nrow"; "expect_pass"; "expect_pipeline"; "expect_range"; "expect_runtime";
    "expect_serializer"; "expect_set_equal"; "expect_str_contains"; "expect_summary"; "expect_table_equal"; "expect_true";
    "expect_truthy"; "expect_type"; "expect_unique"; "expect_values"; "expect_warning"; "explain";
    "explain_json"; "export_artifacts"; "fct_c"; "fct_collapse"; "fct_drop"; "fct_expand";
    "fct_infreq"; "fct_lump_min"; "fct_lump_n"; "fct_lump_prop"; "fct_other"; "fct_recode";
    "fct_relevel"; "fct_reorder"; "fct_rev"; "fetchurl"; "file_exists"; "fill";
    "filter"; "filter_lens"; "filter_node"; "fit_stats"; "fivenum"; "float_seq";
    "floor"; "floor_date"; "force_tz"; "format_date"; "format_datetime"; "full_join";
    "get"; "getwd"; "glimpse"; "group_by"; "head"; "head_pattern";
    "help"; "hour"; "hours"; "huber_loss"; "identical"; "idx_lens";
    "ifelse"; "import_artifacts"; "index_of"; "inner_join"; "inspect_artifacts"; "inspect_log";
    "inspect_node"; "inspect_pipeline"; "intent_fields"; "intent_get"; "intersect"; "interval";
    "inv"; "iota"; "iqr"; "is_character"; "is_date"; "is_datetime";
    "is_duration"; "is_empty"; "is_error"; "is_factor"; "is_interval"; "is_leap_year";
    "is_logical"; "is_na"; "is_numeric"; "isoweek"; "isoyear"; "is_period";
    "kron"; "kurtosis"; "lag"; "last_index_of"; "lead"; "left_join";
    "length"; "levels"; "list_files"; "list_logs"; "lm"; "log";
    "mad"; "make_date"; "make_datetime"; "make_period"; "map"; "map_pattern";
    "matches"; "matmul"; "max"; "mdy"; "mdy_hms"; "mean";
    "median"; "meta_flatten"; "microseconds"; "milliseconds"; "min"; "min_rank";
    "minute"; "minutes"; "mode"; "modify"; "month"; "months";
    "mutate"; "mutate_node"; "n"; "na"; "na_bool"; "na_float";
    "na_int"; "nanoseconds"; "na_string"; "ncol"; "ndarray"; "ndarray_data";
    "n_distinct"; "nest"; "nesting"; "nobs"; "node_diff"; "node_fork";
    "node_lens"; "node_meta_lens"; "node_when"; "normalize"; "now"; "nrow";
    "ntile"; "ordered"; "over"; "package_info"; "packages"; "parallel";
    "parse_date"; "parse_datetime"; "patch"; "path_abs"; "path_basename"; "path_dirname";
    "path_ext"; "path_join"; "path_stem"; "pchisq"; "percent_rank"; "period_days";
    "period_hours"; "period_minutes"; "period_months"; "period_seconds"; "period_years"; "pf";
    "pipeline_assert"; "pipeline_cache_status"; "pipeline_config_to_frame"; "pipeline_copy"; "pipeline_cycles"; "pipeline_deps";
    "pipeline_depth"; "pipeline_diff"; "pipeline_edges"; "pipeline_gc"; "pipeline_leaves"; "pipeline_node";
    "pipeline_node_options"; "pipeline_nodes"; "pipeline_print"; "pipeline_report"; "pipeline_roots"; "pipeline_run";
    "pipeline_to_dot"; "pipeline_to_drv"; "pipeline_to_frame"; "pipeline_to_ga"; "pipeline_to_mermaid"; "pipeline_to_store";
    "pipeline_validate"; "pivot_longer"; "pivot_wider"; "pm"; "pnorm"; "poly";
    "populate_pipeline"; "pow"; "predict"; "prefetch"; "pretty_print"; "print";
    "prop_for_all"; "prop_gen_between"; "prop_gen_bool"; "prop_gen_choice"; "prop_gen_date_range"; "prop_gen_df";
    "prop_gen_df_from"; "prop_gen_dict"; "prop_gen_factor"; "prop_gen_float_range"; "prop_gen_fn"; "prop_gen_frequency";
    "prop_gen_int"; "prop_gen_int_range"; "prop_gen_list"; "prop_gen_one_of"; "prop_gen_string_from"; "prop_gen_vector";
    "prop_gen_ymd"; "prop_map_gen"; "prop_named"; "prop_resize"; "prop_show_spec"; "prop_stats";
    "prop_such_that"; "prop_test"; "prune"; "pt"; "pull"; "qchisq";
    "qf"; "qnorm"; "qt"; "quantile"; "quarter"; "quo";
    "quos"; "range"; "read_csv"; "read_file"; "read_ipc"; "read_log";
    "read_node"; "read_parquet"; "read_past_node"; "read_pipeline"; "rebuild_node"; "relocate";
    "rename"; "rename_node"; "replace_first"; "replace_na"; "reshape"; "residuals";
    "rewire"; "rm"; "round"; "round_date"; "row_lens"; "row_number";
    "run"; "sample"; "sample_pattern"; "scale"; "score"; "sd";
    "second"; "seconds"; "select"; "select_node"; "semester"; "semi_join";
    "separate"; "separate_rows"; "seq"; "serialize"; "set"; "set_nix_defaults";
    "set_pipeline_global_options"; "set_seed"; "shape"; "show_plot"; "sigma"; "sign";
    "signif"; "sin"; "sinh"; "skewness"; "slice"; "slice_max";
    "slice_min"; "slice_pattern"; "slice_sample"; "source"; "sqrt"; "standardize";
    "starts_with"; "str_count"; "str_detect"; "str_extract"; "str_extract_all"; "str_flatten";
    "str_format"; "str_join"; "str_lines"; "str_nchar"; "str_pad"; "str_repeat";
    "str_replace"; "str_split"; "str_sprintf"; "str_substring"; "str_trim"; "str_trunc";
    "str_words"; "subgraph"; "sum"; "summarize"; "summary"; "suppress_warnings";
    "swap"; "tail"; "tail_pattern"; "tan"; "tanh"; "t_check";
    "t_diff"; "t_fix"; "t_gc"; "t_make"; "to_array"; "to_bool";
    "to_dataframe"; "to_date"; "to_datetime"; "today"; "to_expr"; "to_exprs";
    "to_factor"; "to_float"; "to_integer"; "to_lower"; "to_string"; "to_symbol";
    "to_upper"; "trace_nodes"; "transpose"; "t_read_json"; "t_read_onnx"; "t_read_pmml";
    "trim_end"; "trimmed_mean"; "trim_start"; "trunc"; "t_score_pmml"; "t_write_json";
    "t_write_onnx"; "t_write_pmml"; "type"; "tz"; "uncount"; "ungroup";
    "union"; "unite"; "unnest"; "upstream_of"; "var"; "vcov";
    "wald_test"; "warning_msg"; "wday"; "week"; "weeks"; "where";
    "which_nodes"; "winsorize"; "with_seed"; "with_tz"; "write_csv"; "write_ipc";
    "write_parquet"; "write_text"; "yday"; "ydm"; "year"; "years";
    "ymd"; "ymd_h"; "ymd_hm"; "ymd_hms";
  ]

let reserved : (string * node_name_kind) list =
  List.map (fun n -> (n, BuiltinFunction)) builtin_functions
  @ List.map (fun n -> (n, RuntimeSymbol)) runtime_symbols

module StringMap = Map.Make(String)
module StringSet = Set.Make(String)

let kind_map : node_name_kind StringMap.t =
  List.fold_left (fun m (n, k) -> StringMap.add n k m) StringMap.empty reserved

let reserved_set : StringSet.t =
  StringSet.of_list (List.map fst reserved)

(** Whether [name] may not be used as a pipeline node name. *)
let is_reserved_node_name (name : string) : bool =
  StringSet.mem name reserved_set

(** The kind of collision if [name] is reserved, else [None]. *)
let reserved_node_kind (name : string) : node_name_kind option =
  StringMap.find_opt name kind_map

(** Error message shared by every enforcement point (t check / construction /
    rename_node) so users always see identical wording. *)
let reserved_error_message (name : string) : string =
  let what =
    match reserved_node_kind name with
    | Some BuiltinFunction -> "a builtin function"
    | Some RuntimeSymbol -> "a runtime symbol"
    | None -> "a builtin function or runtime symbol"
  in
  Printf.sprintf
    "Node `%s` is reserved: `%s` is %s. Node names cannot collide with builtin functions or runtime symbols. Choose a different node name."
    name name what
