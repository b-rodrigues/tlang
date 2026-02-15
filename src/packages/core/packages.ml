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
  functions = ["print"; "type"; "length"; "head"; "tail"; "is_error"; "seq"; "map"; "sum"; "pretty_print"; "join"; "string"; "get";
               "is_empty"; "substring"; "slice"; "char_at"; "index_of"; "last_index_of"; "contains"; "starts_with"; "ends_with"; "replace"; "replace_first"; "to_lower"; "to_upper"];
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
  env
