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

(** Standard package definitions *)
let core_package = {
  name = "core";
  description = "Core utilities: printing, type inspection, data structures, strings";
  functions = ["print"; "type"; "length"; "nchar"; "head"; "tail"; "is_error"; "seq"; "map"; "sum"; "pretty_print"; "join"; "string"; "get";
               "is_empty"; "substring"; "slice"; "char_at"; "index_of"; "last_index_of"; "contains"; "starts_with"; "ends_with"; "replace"; "replace_first"; "to_lower"; "to_upper"; 
               "ifelse"; "case_when"];
}

let stats_package = {
  name = "stats";
  description = "Statistical summaries and models";
  functions = ["mean"; "sd"; "quantile"; "cor"; "lm"; "summary"; "fit_stats"; "add_diagnostics"; "min"; "max"];
}

let colcraft_package = {
  name = "colcraft";
  description = "DataFrame manipulation verbs";
  functions = ["select"; "filter"; "mutate"; "arrange"; "group_by"; "ungroup"; "summarize"];
}

let math_package = {
  name = "math";
  description = "Pure numerical primitives";
  functions = ["sqrt"; "abs"; "log"; "exp"; "pow"; "ndarray"; "shape"; "reshape"; "matmul"; "diag"; "inv"; "kron"; "transpose"; "cbind"; "iota"];
}

let base_package = {
  name = "base";
  description = "Assertions, NA handling, and error utilities";
  functions = ["assert"; "is_na"; "na"; "na_int"; "na_float"; "na_bool"; "na_string"; "error"; "error_code"; "error_message"; "error_context"];
}

let dataframe_package = {
  name = "dataframe";
  description = "DataFrame creation and introspection";
  functions = ["dataframe"; "read_csv"; "write_csv"; "colnames"; "nrow"; "ncol"; "clean_colnames"; "glimpse"; "pull"; "to_array"];
}

let pipeline_package = {
  name = "pipeline";
  description = "Pipeline definition and introspection";
  functions = ["pipeline_nodes"; "pipeline_deps"; "pipeline_node"; "pipeline_run"];
}

let explain_package = {
  name = "explain";
  description = "Value introspection and intent blocks";
  functions = ["explain"; "explain_json"; "intent_fields"; "intent_get"];
}

(** All standard packages *)
let all_packages = [
  core_package;
  base_package;
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
    ("functions", VList (List.map (fun f -> (None, VString f)) pkg.functions));
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
    (make_builtin 0 (fun _args _env ->
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
    (make_builtin 1 (fun args _env ->
      match args with
      | [VString name] ->
          (match List.find_opt (fun p -> p.name = name) all_packages with
          | Some pkg -> package_to_value pkg
          | None -> Error.make_error KeyError (Printf.sprintf "Package `%s` not found." name))
      | _ -> Error.type_error "Function `package_info` expects a string argument."
    ))
    env
  in
  
  (* Register Boolean functions *)
  let env = Env.add "ifelse" (make_builtin ~variadic:true 3 T_boolean.ifelse) env in
  let env = Env.add "case_when" (make_builtin_named ~variadic:true 0 (T_boolean.case_when Eval.eval_expr)) env in

  env

(** Initialize the environment with all standard packages *)
let init_env () =
  let env = Env.empty in
  (* Core package *)
  let env = T_print.register env in
  let env = T_type.register env in
  let env = Head.register env in
  let env = Tail.register env in
  let env = Is_error.register env in
  let env = T_seq.register env in
  let env = T_map.register ~eval_call:Eval.eval_call env in
  let env = Sum.register env in
  let env = T_get.register env in
  let env = T_string.register env in
  let env = Help.register env in
  let env = String_ops.register env in
  (* Base package *)
  let env = T_assert.register env in
  let env = Is_na.register env in
  let env = Na.register env in
  let env = Error_mod.register env in
  let env = Error_utils.register env in
  (* Dataframe package *)
  let env = T_dataframe.register env in
  let env = T_read_csv.register env in
  let env = T_write_csv.register ~write_csv_fn:(fun ~sep table path -> Arrow_io.write_csv ~sep table path) env in
  let env = Colnames.register env in
  let env = Nrow.register env in
  let env = Ncol.register env in
  let env = Glimpse.register env in
  (* clean_colnames as a standalone function on DataFrames *)
  let env = Env.add "clean_colnames"
    (make_builtin 1 (fun args _env ->
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
      | _ -> Error.arity_error_named "clean_colnames" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (* Pipeline package *)
  let env = Pipeline_nodes.register env in
  let env = Pipeline_deps.register env in
  let env = Pipeline_node.register env in
  let env = Pipeline_run.register ~rerun_pipeline:Eval.rerun_pipeline env in
  (* Colcraft package *)
  let env = T_select.register env in
  let env = T_filter.register ~eval_call:Eval.eval_call ~eval_expr:Eval.eval_expr ~uses_nse:Eval.uses_nse ~desugar_nse_expr:Eval.desugar_nse_expr env in
  let env = Mutate.register ~eval_call:Eval.eval_call ~eval_expr:Eval.eval_expr ~uses_nse:Eval.uses_nse ~desugar_nse_expr:Eval.desugar_nse_expr env in
  let env = Arrange.register env in
  let env = Group_by.register env in
  let env = Ungroup.register env in
  let env = Summarize.register ~eval_call:Eval.eval_call ~eval_expr:Eval.eval_expr ~uses_nse:Eval.uses_nse ~desugar_nse_expr:Eval.desugar_nse_expr env in
  let env = Window_rank.register env in
  let env = Window_offset.register env in
  let env = Window_cumulative.register env in
  (* Math package *)
  let env = T_sqrt.register env in
  let env = T_abs.register env in
  let env = T_log.register env in
  let env = T_exp.register env in
  let env = Pow.register env in
  let env = T_iota.register env in
  let env = Ndarray.register env in
  (* Stats package *)
  let env = Mean.register env in
  let env = Sd.register env in
  let env = Quantile.register env in
  let env = Cor.register env in
  let env = Lm.register env in
  let env = Fit_stats.register env in
  let env = Add_diagnostics.register env in
  let env = Summary.register env in
  let env = Min.register env in
  let env = Max.register env in
  (* Explain package *)
  let env = Intent_fields.register env in
  let env = Intent_get.register env in
  let env = T_explain.register env in
  let env = Explain_json.register ~eval_call:Eval.eval_call env in
  (* Phase 7: Pretty-print and packages *)
  (* Using Pretty_print.register fully qualified *)
  let env = Pretty_print.register env in
  let env = register env in (* Defined above in this file *)
  env
