(* src/packages/core/packages.ml *)
(* Phase 7: Standard package registry *)
(* Defines the standard packages that are loaded by default *)

open Ast

(** Package metadata *)
type package_info = {
  name : string;
  description : string;
  functions : string list;
}

let docs_loaded : unit Lazy.t =
  lazy (
    let docs_paths = ["help/docs.json"; "docs.json"] in
    let loaded_paths =
      List.filter_map (fun path ->
        if Sys.file_exists path then begin
          try
            Tdoc_registry.load_from_json path;
            Some path
          with _ ->
            prerr_endline (Printf.sprintf "Documentation: failed to parse %s" path);
            None
        end else
          None
      ) docs_paths
    in
    match loaded_paths with
    | [] ->
        prerr_endline "Documentation: no docs.json found in help/docs.json or docs.json; proceeding without documentation."
    | _paths ->
        ()
  )

let ensure_docs_loaded () =
  Lazy.force docs_loaded

let package_families = function
  | "core" -> ["core"; "boolean"; "repl"; "package_manager"; "tdoc"]
  | "strcraft" -> ["strcraft"; "string"]
  | "stats" -> ["stats"; "descriptive-statistics"]
  | "base" -> ["base"; "json"; "serialization"]
  | "math" | "colcraft" | "dataframe" | "pipeline" | "explain" | "chrono" as pkg -> [pkg]
  | _ -> []

let dedup_sort_strings xs =
  xs
  |> List.sort_uniq String.compare

let documented_functions_for_package pkg_name =
  ensure_docs_loaded ();
  let families = package_families pkg_name in
  Tdoc_registry.get_all ()
  |> List.filter (fun (doc : Tdoc_types.doc_entry) ->
    match doc.family with
    | Some family -> List.mem family families && doc.is_export
    | None -> false)
  |> List.map (fun (doc : Tdoc_types.doc_entry) -> doc.name)
  |> dedup_sort_strings

let package_functions pkg =
  let documented = documented_functions_for_package pkg.name in
  dedup_sort_strings (documented @ pkg.functions)

(** Standard package definitions *)
let core_package = {
  name = "core";
  description = "Core utilities: printing, type inspection, data structures";
  functions = ["print"; "type"; "args"; "length"; "head"; "tail"; "is_error"; "seq"; "map"; "sum"; "pretty_print"; "get";
               "ifelse"; "case_when"; "run"; "t_run"; "t_test"; "t_doc"; "eval"; "expr"; "exprs"; "enquo"; "enquos"; "body"; "source"; "cat"; "to_integer"; "to_float"; "to_numeric"; "exit"; "getwd"; "file_exists"; "dir_exists"; "read_file"; "list_files"; "env";
               "path_join"; "path_basename"; "path_dirname"; "path_ext"; "path_stem"; "path_abs"];
}

let strcraft_package = {
  name = "strcraft";
  description = "String inspection, transformation, and formatting";
  functions = ["str_nchar"; "is_empty"; "str_substring"; "slice"; "char_at"; "index_of"; "last_index_of"; "contains"; "starts_with"; "ends_with";
               "str_replace"; "replace_first"; "to_lower"; "to_upper"; "str_trim"; "trim_start"; "trim_end"; "str_lines"; "str_words"; "str_repeat";
               "str_format"; "str_extract"; "str_extract_all"; "str_detect"; "str_pad"; "str_trunc"; "str_flatten"; "str_count";
               "str_sprintf"; "str_join"; "str_string"; "str_split"];
}

let stats_package = {
  name = "stats";
  description = "Statistical summaries and models";
  functions = ["mean"; "sd"; "quantile"; "cor"; "lm"; "predict"; "summary"; "fit_stats"; "add_diagnostics"; "min"; "max"; "coef"; "conf_int"; 
               "nobs"; "df_residual"; "sigma"; "dispersion"; "vcov"; "compare"; "residuals"; "augment"; "score";
               "pnorm"; "pt"; "pf"; "pchisq"; "anova"; "wald_test"; "cut"; "poly"];
}

let colcraft_package = {
  name = "colcraft";
  description = "DataFrame manipulation verbs and window functions";
  functions = ["select"; "filter"; "mutate"; "arrange"; "group_by"; "ungroup"; "summarize";
               "n"; "n_distinct";
               "ntile"; "dense_rank"; "row_number"; "min_rank"; "cume_dist"; "percent_rank";
               "lag"; "lead"; "cumany"; "cumall"; "cummax"; "cummin"; "cummean"; "cumsum";
               "pivot_longer"; "pivot_wider"; "complete"; "fill"; "separate"; "unite"; "drop_na"; "replace_na"; "expand"; "crossing"; "nesting"; "factor"; "as_factor"; "fct"; "fct_infreq"; "fct_reorder"; "fct_relevel"; "fct_rev"; "fct_recode"; "fct_collapse"; "fct_lump_n"; "fct_lump_min"; "fct_lump_prop"; "fct_other"; "fct_drop"; "fct_expand"; "fct_c"; "levels"; "ordered";
               "rename"; "relocate"; "starts_with"; "ends_with"; "contains"; "everything"; "where"; "matches"; "all_of"; "any_of"; "is_numeric"; "is_character"; "is_logical"; "is_factor"; "distinct"; "slice"; "slice_max"; "slice_min"; "count";
               "left_join"; "inner_join"; "full_join"; "semi_join"; "anti_join"; "bind_rows"; "bind_cols";
               "nest"; "unnest"; "separate_rows"; "uncount"];
}

let math_package = {
  name = "math";
  description = "Pure numerical primitives";
  functions = ["sqrt"; "abs"; "log"; "exp"; "pow"; "ndarray"; "shape"; "reshape"; "matmul"; "diag"; "inv"; "kron"; "transpose"; "cbind"; "iota"];
}

let base_package = {
  name = "base";
  description = "Assertions, NA handling, and error utilities";
  functions = ["assert"; "is_na"; "na"; "na_int"; "na_float"; "na_bool"; "na_string"; "error"; "error_code"; "error_message"; "error_context"; "serialize"; "deserialize"; "t_write_json"; "t_read_json"];
}

let chrono_package = {
  name = "chrono";
  description = "Date and datetime parsing, extraction, and arithmetic";
  functions = [
    "ymd"; "mdy"; "dmy"; "ydm";
    "ymd_h"; "ymd_hm"; "ymd_hms"; "mdy_hms"; "dmy_hms";
    "parse_date"; "parse_datetime"; "today"; "now";
    "year"; "month"; "day"; "mday"; "yday"; "wday"; "week"; "isoweek"; "isoyear"; "quarter"; "semester";
    "hour"; "minute"; "second"; "tz";
    "years"; "months"; "weeks"; "days"; "hours"; "minutes"; "seconds"; "milliseconds"; "microseconds"; "nanoseconds";
    "make_period"; "period_years"; "period_months"; "period_days"; "period_hours"; "period_minutes"; "period_seconds";
    "format_date"; "format_datetime"; "as_date"; "as_datetime"; "interval";
    "is_date"; "is_datetime"; "is_period"; "is_duration"; "is_interval";
    "floor_date"; "ceiling_date"; "round_date"; "with_tz"; "force_tz"; "%within%"; "is_leap_year"; "days_in_month";
  ];
}

let dataframe_package = {
  name = "dataframe";
  description = "DataFrame creation and introspection";
  functions = ["dataframe"; "read_csv"; "read_parquet"; "write_csv"; "colnames"; "nrow"; "ncol"; "clean_colnames"; "glimpse"; "pull"; "to_array"; "read_arrow"; "write_arrow"];
}

let pipeline_package = {
  name = "pipeline";
  description = "Pipeline definition and introspection";
  functions = ["pipeline_nodes"; "pipeline_deps"; "pipeline_node"; "pipeline_run"; "build_pipeline"; "populate_pipeline"; "inspect_pipeline"; "list_logs"; "read_node"; "pipeline_copy"; "trace_nodes";
               "pipeline_to_frame"; "filter_node"; "mutate_node"; "rename_node"; "select_node"; "arrange_node";
               "union"; "difference"; "intersect"; "patch";
               "swap"; "rewire"; "prune"; "upstream_of"; "downstream_of"; "subgraph";
               "chain"; "parallel";
               "pipeline_edges"; "pipeline_roots"; "pipeline_leaves"; "pipeline_depth";
               "pipeline_cycles"; "pipeline_summary"; "pipeline_validate"; "pipeline_assert";
               "pipeline_print"; "pipeline_dot"];
}

let explain_package = {
  name = "explain";
  description = "Value introspection and intent blocks";
  functions = ["explain"; "explain_json"; "intent_fields"; "intent_get"];
}

(** All standard packages *)
let all_packages = [
  core_package;
  strcraft_package;
  base_package;
  chrono_package;
  math_package;
  stats_package;
  dataframe_package;
  colcraft_package;
  pipeline_package;
  explain_package;
]

(** Convert a package to a T value *)
let package_to_value pkg =
  VDict [
    ("name", VString pkg.name);
    ("description", VString pkg.description);
    ("functions", VList (List.map (fun f -> (None, VString f)) (package_functions pkg)));
  ]

(** Register the packages() builtin *)
(*
--# List available packages
--#
--# Returns a list of all standard packages available in the environment.
--#
--# @name packages
--# @return :: List[Dict] List of package metadata.
--# @example
--#   packages()
--# @family core
--# @seealso package_info
--# @export
*)
let register env =
  let env = Env.add "packages"
    (make_builtin ~name:"packages" 0 (fun _args _env ->
      VList (List.map (fun pkg -> (None, package_to_value pkg)) all_packages)
    ))
    env
  in
(*
--# Get package information
--#
--# Returns metadata for a specific package, including its description and functions.
--#
--# @name package_info
--# @param name :: String The name of the package.
--# @return :: Dict Package metadata.
--# @example
--#   package_info("stats")
--# @family core
--# @seealso packages
--# @export
*)
  let env = Env.add "package_info"
    (make_builtin ~name:"package_info" 1 (fun args _env ->
      match args with
      | [VString name] ->
          (match List.find_opt (fun p -> p.name = name) all_packages with
          | Some pkg -> package_to_value pkg
          | None -> Error.make_error KeyError (Printf.sprintf "Package `%s` not found." name))
      | _ -> Error.type_error "Function `package_info` expects a string argument."
    ))
    env
  in

(*
--# Exit the interpreter
--#
--# Terminates the current T process and accepts an optional numeric exit status.
--#
--# @name exit
--# @family core
--# @export
*)

  let env = Env.add "exit"
    (make_builtin ~name:"exit" ~variadic:true 0 (fun args _env ->
      let code = match args with
        | [VInt n] -> n
        | [] -> 0
        | _ -> 1
      in
      Stdlib.exit code
    ))
    env
  in
  
  (* Helper to keep named args *)
  let make_builtin_named ?name ?(variadic=false) arity func =
    VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
               b_func = (fun named_args env_ref -> func named_args !env_ref) }
  in

  (* Register Boolean functions *)
(*
--# Vectorized if-else
--#
--# Vectorized conditional selection. Returns values from `true_val` or `false_val`
--# depending on whether `condition` is true or false.
--#
--# @name ifelse
--# @param condition :: Bool | Vector[Bool] The condition to check.
--# @param true_val :: Any | Vector[Any] Value to return if condition is true.
--# @param false_val :: Any | Vector[Any] Value to return if condition is false.
--# @param missing :: Any (Optional) Value to return if condition is NA. Defaults to NA.
--# @param out_type :: String (Optional) Force-cast output values to Int, Float, String, or Bool.
--# @return :: Any | Vector[Any] A scalar when `condition` is scalar, otherwise a vector aligned to `condition`.
--# @example
--#   ifelse(x > 5, "High", "Low")
--#   ifelse(x % 2 == 0, x, 0)
--# @family boolean
--# @export
*)
  let env = Env.add "ifelse" (make_builtin_named ~name:"ifelse" ~variadic:true 3 T_boolean.ifelse) env in

(*
--# Vectorized case-when
--#
--# Evaluates a series of `condition ~ value` formulas sequentially.
--# Returns the value corresponding to the first true condition for each element.
--#
--# @name casewhen
--# @param ... :: Formula One or more formulas of the form `condition ~ value`.
--# @param .default :: Any (Optional) Value to return if no condition matches. Defaults to NA.
--# @return :: Vector[Any] A vector of the matched values.
--# @example
--#   casewhen(
--#     x > 0 ~ "Positive",
--#     x < 0 ~ "Negative",
--#     .default = "Zero"
--#   )
--# @family boolean
--# @export
*)
  let env = Env.add "casewhen" (make_builtin_named ~name:"casewhen" ~variadic:true 0 (T_boolean.casewhen Eval.eval_expr_immutable)) env in

(*
--# Evaluate a quoted expression
--#
--# Evaluates Expr values in the current environment and returns plain values unchanged.
--#
--# @name eval
--# @family core
--# @export
*)

  let env = Env.add "eval"
    (make_builtin ~name:"eval" 1 (fun args env ->
      match args with
      | [VExpr quoted] -> Eval.eval_expr_immutable env quoted
      | [v] -> v
      | _ -> Error.arity_error_named "eval" 1 (List.length args)
    ))
    env
  in

(*
--# Capture an expression
--#
--# Captures the provided expression as an Expr object without evaluating it.
--# Useful for metaprogramming, quotation, and custom evaluation.
--#
--# @name expr
--# @param x :: Any The expression to capture.
--# @return :: Expr The captured expression object.
--# @example
--#   e = expr(1 + 2)
--#   eval(e)
--# @family core
--# @export
*)
  let env = Env.add "expr"
    (make_builtin ~name:"expr" 1 (fun args _env ->
      match args with
      | [v] -> VExpr (Ast.mk_expr (Value v))
      | _ -> Error.arity_error_named "expr" 1 (List.length args)
    ))
    env
  in

(*
--# Capture multiple expressions
--#
--# Captures one or more expressions as a List of Expr values.
--# Useful for metaprogramming and non-standard evaluation.
--#
--# @name exprs
--# @param ... :: Any One or more expressions to capture.
--# @return :: List[Expr] A list of captured expressions.
--# @example
--#   exprs(1 + 1, x = 2 * 2)
--# @family core
--# @export
*)
  let env = Env.add "exprs"
    (make_builtin_named ~name:"exprs" ~variadic:true 0 (fun args _env ->
      VList (List.map (fun (name, v) -> (name, VExpr (Ast.mk_expr (Value v)))) args)
    ))
    env
  in

(*
--# Capture a function argument's expression (non-standard evaluation)
--#
--# Must be called inside a function body. Captures the unevaluated expression
--# that the caller passed as the named parameter, returning it as an Expr.
--# Accepts exactly one argument: a bare symbol naming one of the function's parameters.
--#
--# @name enquo
--# @param param :: Symbol The name of the parameter whose expression to capture.
--# @return :: Expr The captured expression object.
--# @example
--#   my_select = \(df: DataFrame, col: Any -> DataFrame) {
--#     col_expr = enquo(col)
--#     eval(expr(df |> select(!!col_expr)))
--#   }
--#   my_select(iris, $Sepal.Length)
--# @family core
--# @export
*)

(*
--# Capture variadic argument expressions (non-standard evaluation)
--#
--# Must be called inside a function body. Captures the unevaluated expressions
--# passed through the variadic `...` parameter as a named List of Expr values.
--# Call with `...` or with no arguments.
--#
--# @name enquos
--# @param ... :: Any The variadic parameter to capture.
--# @return :: List[Expr] A list of captured expressions, preserving argument names.
--# @example
--#   my_summarize = \(df: DataFrame, ... -> DataFrame) {
--#     cols = enquos(...)
--#     eval(expr(df |> summarize(!!!cols)))
--#   }
--#   my_summarize(iris, mean_sep = mean($Sepal.Length))
--# @family core
--# @export
*)

(*
--# Get function body
--#
--# Returns the implementation body of a function.
--# For T functions, it returns the body as an Expr object.
--# For built-ins, it returns metadata about the OCaml implementation.
--#
--# @name body
--# @param fn :: Function The function to inspect.
--# @return :: Expr | String The function body or implementation info.
--# @example
--#   f = \(x) (x + 1)
--#   body(f)
--# @family core
--# @export
*)
  let env = Env.add "body"
    (make_builtin ~name:"body" 1 (fun args _env ->
      match args with
      | [VLambda l] -> VExpr l.body
      | [VBuiltin { b_name = Some name; _ }] ->
          (match Tdoc_registry.lookup name with
           | Some doc -> VString (Printf.sprintf "Built-in function implemented in %s:%d" doc.source_path doc.line_number)
           | None -> VNA NAGeneric)
      | [v] -> Error.type_error (Printf.sprintf "body: expected a Function, got %s." (Utils.type_name v))
      | _ -> Error.arity_error_named "body" 1 (List.length args)
    ))
    env
  in

(*
--# Get function source code
--#
--# Returns the source code of a function as a string.
--# For built-in functions, it attempts to read the underlying OCaml source file.
--#
--# @name source
--# @param fn :: Function The function to inspect.
--# @return :: String The source code of the function.
--# @example
--#   source(print)
--# @family core
--# @export
*)
  let env = Env.add "source"
    (make_builtin ~name:"source" 1 (fun args _env ->
      match args with
      | [VLambda l] -> VString (Utils.unparse_expr l.body)
      | [VBuiltin { b_name = Some name; _ }] ->
          (match Tdoc_registry.lookup name with
           | Some doc ->
               let path = doc.source_path in
               if path = "" || not (Sys.file_exists path) then
                 VString (Printf.sprintf "OCaml source not found at `%s`" path)
               else
                 let lines = ref [] in
                 let chan = open_in path in
                 (try
                   for _ = 1 to doc.line_number - 1 do
                     ignore (input_line chan)
                   done;
                   (* Read until end of file or a reasonable limit *)
                   for _ = 1 to 50 do
                     lines := input_line chan :: !lines
                   done;
                   close_in chan;
                   VString (String.concat "\n" (List.rev !lines))
                 with End_of_file ->
                   close_in chan;
                   VString (String.concat "\n" (List.rev !lines)))
           | None -> VString (Printf.sprintf "No source metadata for `%s`" name))
      | [v] -> Error.type_error (Printf.sprintf "source: expected a Function, got %s." (Utils.type_name v))
      | _ -> Error.arity_error_named "source" 1 (List.length args)
    ))
    env
  in

(*
--# Run a shell command
--#
--# Executes a shell command and returns its stdout as a string.
--# Raises a ShellError if the command fails (non-zero exit code).
--#
--# @name run
--# @param cmd :: String The shell command to execute.
--# @return :: String The stdout of the command.
--# @example
--#   branch = run("git rev-parse --abbrev-ref HEAD")
--#   print(branch)
--# @family core
--# @export
*)
  let env = Env.add "run"
    (make_builtin_named ~name:"run" 1 (fun args env ->
      match args with
      | [(_, VString cmd)] | [(_, VSymbol cmd)] ->
          (match Eval.eval_shell_expr (ref env) cmd with
           | VShellResult { sr_exit_code = 0; sr_stdout; _ } ->
               VString sr_stdout
           | VShellResult { sr_exit_code; sr_stderr; _ } ->
               let msg =
                 if sr_stderr <> "" then
                   Printf.sprintf "Command failed (exit %d): %s" sr_exit_code sr_stderr
                 else
                   Printf.sprintf "Command failed (exit %d)" sr_exit_code
               in
               Error.make_error ShellError msg
           | VError _ as e -> e
           | _ -> Error.make_error GenericError "eval_shell_expr returned unexpected value")
      | [(_, other)] ->
          Error.make_error TypeError
            (Printf.sprintf "run() expects a String command, got %s" (Utils.type_name other))
      | [] -> Error.make_error ArityError "run() requires a command argument"
      | _  -> Error.make_error ArityError "run() takes exactly one argument"
    ))
    env
  in

  env

(** Initialize the environment with all standard packages *)
let init_env () =
  let env = Env.empty in
  (* Core package *)
  let env = T_print.register env in
  let env = T_type.register env in
  let env = Args.register env in
  let env = Head.register env in
  let env = Tail.register env in
  let env = Is_error.register env in
  let env = T_seq.register env in
  let env = T_map.register ~eval_call:Eval.eval_call_immutable env in
  let env = Sum.register env in
  let env = T_get.register env in
  let env = Help.register env in
  let env = T_write_text.register env in
  let env = Converters.register env in
  let env = File_ops.register env in
  let env = Path_ops.register env in
  (* Strcraft package *)
  let env = String_ops.register env in
  (* Base package *)
  let env = T_assert.register env in
  let env = Is_na.register env in
  let env = Na.register env in
  let env = Error_mod.register env in
  let env = Error_utils.register env in
  let env = Serialize.register env in
  let env = Deserialize.register env in
  let env = T_json.register env in
  (* Chrono package *)
  let env = Chrono.register env in
  (* Dataframe package *)
  let env = T_dataframe.register env in
  let env = T_read_csv.register env in
  let env = T_read_parquet.register env in
  let env = T_write_csv.register ~write_csv_fn:(fun ~sep table path -> Arrow_io.write_csv ~sep table path) env in
  let env = T_read_arrow.register env in
  let env = T_write_arrow.register env in
  let env = Colnames.register env in
  let env = Nrow.register env in
  let env = Ncol.register env in
  let env = Glimpse.register env in
(*
--# Clean DataFrame Column Names
--#
--# Standardizes column names using a snake_case convention. Removes special
--# characters and handles duplicates.
--#
--# @name clean_colnames
--# @param x :: DataFrame | List[String] The object with names to clean.
--# @return :: DataFrame | List[String] The object with cleaned names.
--# @family dataframe
--# @seealso colnames
--# @export
*)
  let env = Env.add "clean_colnames"
    (make_builtin ~name:"clean_colnames" 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; group_keys }] ->
          let old_names = Arrow_table.column_names arrow_table in
          let new_names = Clean_colnames.clean_names old_names in
          let columns = List.map2 (fun old_name new_name ->
            match Arrow_table.get_column arrow_table old_name with
            | Some col -> (new_name, col)
            | None -> (new_name, Arrow_table.NullColumn (Arrow_table.num_rows arrow_table))
          ) old_names new_names in
          let nrows = Arrow_table.num_rows arrow_table in
          let new_table = Arrow_table.create columns nrows in
          VDataFrame { arrow_table = new_table; group_keys }
      | [VList items] ->
          let strs = List.map (fun (_, v) ->
            match v with VString s -> s | _ -> Ast.Utils.value_to_string v
          ) items in
          let cleaned = Clean_colnames.clean_names strs in
          VList (List.map (fun s -> (None, VString s)) cleaned)
      | [VNA _] -> Error.type_error "Function `clean_colnames` expects a DataFrame or List.\nReceived NA."
      | [_] -> Error.type_error "Function `clean_colnames` expects a DataFrame or List of strings."
      | _ -> Error.arity_error_named "clean_colnames" 1 (List.length args)
    ))
    env
  in
  (* Pipeline package *)
  let env = Pipeline_nodes.register env in
  let env = Pipeline_deps.register env in
  let env = Pipeline_node.register env in
  let env = Pipeline_run.register ~rerun_pipeline:(fun env prev -> Eval.rerun_pipeline (ref env) prev) env in
  let env = Build_pipeline.register env in
  let env = Populate_pipeline.register env in
  let env = Inspect_pipeline.register env in
  let env = Read_node.register env in
  let env = Pipeline_copy.register env in
  let env = Trace_nodes.register env in
  let env = Pipeline_to_frame.register env in
  let env = Filter_node.register ~eval_call:Eval.eval_call_immutable env in
  let env = Mutate_node.register ~eval_call:Eval.eval_call_immutable env in
  let env = Rename_node.register env in
  let env = Select_node.register env in
  let env = Arrange_node.register env in
  (* Phase 3 — Set operations & DAG-aware transformations *)
  let env = Pipeline_set_ops.register env in
  let env = Pipeline_dag_ops.register env in
  (* Phase 4 — Composition & inspection utilities *)
  let env = Pipeline_composition.register env in
  let env = Pipeline_inspect2.register env in
  (* Colcraft package *)
  let env = T_select.register env in
  let env = T_filter.register ~eval_call:Eval.eval_call_immutable ~eval_expr:Eval.eval_expr_immutable ~uses_nse:Eval.uses_nse ~desugar_nse_expr:Eval.desugar_nse_expr env in
  let env = Mutate.register ~eval_call:Eval.eval_call_immutable ~eval_expr:Eval.eval_expr_immutable ~uses_nse:Eval.uses_nse ~desugar_nse_expr:Eval.desugar_nse_expr env in
  let env = Arrange.register env in
  let env = Group_by.register env in
  let env = Ungroup.register env in
  let env = Summarize.register ~eval_call:Eval.eval_call_immutable ~eval_expr:Eval.eval_expr_immutable ~uses_nse:Eval.uses_nse ~desugar_nse_expr:Eval.desugar_nse_expr env in
  let env = N.register env in
  let env = N_distinct.register env in
  let env = Window_rank.register env in
  let env = Window_offset.register env in
  let env = Window_cumulative.register env in
  let env = Pivot_longer.register env in
  let env = Pivot_wider.register env in
  let env = T_complete.register env in
  let env = Fill.register env in
  let env = Separate.register env in
  let env = Unite.register env in
  let env = Drop_na.register env in
  let env = Replace_na.register env in
  let env = Expand.register env in
  let env = Factors.register env in
  let env = Rename.register env in
  let env = Relocate.register env in
  let env = Selection_helpers.register env in
  let env = Joins.register env in
  let env = Distinct.register env in
  let env = Slice.register env in
  let env = Count.register env in
  let env = Slice_min_max.register env in
  let env = Nest.register env in
  let env = Unnest.register env in
  let env = Separate_rows.register env in
  let env = Uncount.register env in
  (* Math package *)
  let env = T_sqrt.register env in
  let env = T_abs.register env in
  let env = T_log.register env in
  let env = T_exp.register env in
  let env = Pow.register env in
  let env = T_iota.register env in
  let env = Round.register env in
  let env = Floor.register env in
  let env = Ceiling.register env in
  let env = Ceil.register env in
  let env = Trunc.register env in
  let env = Sign.register env in
  let env = Signif.register env in
  let env = Sin.register env in
  let env = Cos.register env in
  let env = Tan.register env in
  let env = Asin.register env in
  let env = Acos.register env in
  let env = Atan.register env in
  let env = Atan2.register env in
  let env = Sinh.register env in
  let env = Cosh.register env in
  let env = Tanh.register env in
  let env = Asinh.register env in
  let env = Acosh.register env in
  let env = Atanh.register env in
  let env = Ndarray.register env in
  (* Stats package *)
  let env = Distributions.register env in
  let env = Mean.register env in
  let env = Sd.register env in
  let env = Quantile.register env in
  let env = Cor.register env in
  let env = Lm.register env in
  let env = Predict.register env in
  let env = T_read_pmml.register env in
  let env = Fit_stats.register env in
  let env = Add_diagnostics.register env in
  let env = Summary.register env in
  let env = Min.register env in
  let env = Max.register env in
  let env = Median.register env in
  let env = Var.register env in
  let env = Cov.register env in
  let env = Range.register env in
  let env = Iqr.register env in
  let env = Scale.register env in
  let env = Standardize.register env in
  let env = Normalize.register env in
  let env = Mad.register env in
  let env = Skewness.register env in
  let env = Kurtosis.register env in
  let env = Mode.register env in
  let env = Cv.register env in
  let env = Fivenum.register env in
  let env = Trimmed_mean.register env in
  let env = Winsorize.register env in
  let env = Huber_loss.register env in
  let env = Coef.register env in
  let env = Conf_int.register env in
  let env = Nobs.register env in
  let env = Df_residual.register env in
  let env = Sigma.register env in
  let env = Dispersion.register env in
  let env = Vcov.register env in
  let env = Compare.register env in
  let env = Residuals.register env in
  let env = Augment.register env in
  let env = Score.register env in
  let env = Anova.register env in
  let env = Basis.register env in
  let env = Wald_test.register env in
  (* Explain package *)
  let env = Intent_fields.register env in
  let env = Intent_get.register env in
  let env = T_explain.register env in
  let env = Explain_json.register ~eval_call:Eval.eval_call_immutable env in
  (* Phase 7: Pretty-print and packages *)
  (* Using Pretty_print.register fully qualified *)
  let env = Pretty_print.register env in
  let env = register env in
  (* Known symbols: bare words that should resolve to VSymbol rather than
     NameError.  These are used as keyword-style arguments in node() and
     related calls (e.g. `runtime = R`, `serializer = write_rds`).
     Add new runtimes or serializer names here as they are introduced. *)
  let known_symbols = [
    (* Runtimes *)
    "R"; "Python"; "T"; "Julia"; "Quarto"; "sh";
    (* Serialization defaults *)
    "default";
    (* R serializers *)
    "write_rds"; "read_rds";
    (* Python serializers *)
    "write_pkl"; "read_pkl";
    (* Arrow serializers *)
    (* JSON serializers *)
    "write_json"; "read_json";
    (* PMML *)
    "pmml";
  ] in
  let env = List.fold_left (fun acc name ->
    Env.add name (VSymbol name) acc
  ) env known_symbols in
  Import_registry.mark_builtin_bindings env
