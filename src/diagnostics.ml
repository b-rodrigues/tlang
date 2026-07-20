(* src/diagnostics.ml *)
(* Structured diagnostic types and JSON serialization for t check (§2 of spec) *)

type diagnostic_phase = Parse | Wire | Schema | Env | Build | Exec

type severity = Error | Warning

type error_class =
  | Structural_error
  | Name_error
  | Arity_error
  | Type_error
  | Parse_error
  | File_error
  | Key_error
  | Index_error
  | Value_error
  | Runtime_error
  | Division_by_zero
  | Assertion_error
  | Match_error
  | Shell_error
  | Aggregation_error
  | Na_predicate_error
  | Missing_artifact
  | Generic_error
  | Schema_mismatch
  | Missing_tproject
  | Missing_package
  | Missing_from_lockfile
  | Nix_generation_error
  | Nix_eval_error
  | Na_warning
  | Nix_error
  | Unknown_error

let error_class_to_string = function
  | Structural_error -> "structural_error"
  | Name_error -> "name_error"
  | Arity_error -> "arity_error"
  | Type_error -> "type_error"
  | Parse_error -> "parse_error"
  | File_error -> "file_error"
  | Key_error -> "key_error"
  | Index_error -> "index_error"
  | Value_error -> "value_error"
  | Runtime_error -> "runtime_error"
  | Division_by_zero -> "division_by_zero"
  | Assertion_error -> "assertion_error"
  | Match_error -> "match_error"
  | Shell_error -> "shell_error"
  | Aggregation_error -> "aggregation_error"
  | Na_predicate_error -> "na_predicate_error"
  | Missing_artifact -> "missing_artifact"
  | Generic_error -> "generic_error"
  | Schema_mismatch -> "schema_mismatch"
  | Missing_tproject -> "missing_tproject"
  | Missing_package -> "missing_package"
  | Missing_from_lockfile -> "missing_from_lockfile"
  | Nix_generation_error -> "nix_generation_error"
  | Nix_eval_error -> "nix_eval_error"
  | Na_warning -> "na_warning"
  | Nix_error -> "nix_error"
  | Unknown_error -> "unknown_error"

let error_class_of_string = function
  | "structural_error" | "StructuralError" -> Structural_error
  | "name_error" | "NameError" -> Name_error
  | "arity_error" | "ArityError" -> Arity_error
  | "type_error" | "TypeError" -> Type_error
  | "parse_error" | "SyntaxError" -> Parse_error
  | "file_error" | "FileError" -> File_error
  | "key_error" | "KeyError" -> Key_error
  | "index_error" | "IndexError" -> Index_error
  | "value_error" | "ValueError" -> Value_error
  | "runtime_error" | "RuntimeError" -> Runtime_error
  | "division_by_zero" | "DivisionByZero" -> Division_by_zero
  | "assertion_error" | "AssertionError" -> Assertion_error
  | "match_error" | "MatchError" -> Match_error
  | "shell_error" | "ShellError" -> Shell_error
  | "aggregation_error" | "AggregationError" -> Aggregation_error
  | "na_predicate_error" | "NAPredicateError" -> Na_predicate_error
  | "missing_artifact" | "MissingArtifactError" -> Missing_artifact
  | "generic_error" | "GenericError" -> Generic_error
  | "schema_mismatch" -> Schema_mismatch
  | "missing_tproject" -> Missing_tproject
  | "missing_package" -> Missing_package
  | "missing_from_lockfile" -> Missing_from_lockfile
  | "nix_generation_error" -> Nix_generation_error
  | "nix_eval_error" -> Nix_eval_error
  | "Na_warning" | "na_warning" -> Na_warning
  | "nix_error" | "NixError" -> Nix_error
  | _ -> Unknown_error

type confidence = High | Medium | Low

let confidence_to_string = function
  | High -> "high"
  | Medium -> "medium"
  | Low -> "low"

let confidence_of_string = function
  | "high" -> High
  | "medium" -> Medium
  | "low" | _ -> Low

type suggested_fix =
  | Rename_column of { old_name: string; new_name: string; target_node: string option; file: string option; line: int option; edit_distance: int; is_unique: bool; confidence: confidence }
  | Add_node_arg of { node: string; arg: string; target_node: string option; file: string option; line: int option; confidence: confidence }
  | Suggest_identifier of { name: string; suggestion: string; target_node: string option; file: string option; line: int option; edit_distance: int; is_unique: bool; confidence: confidence }
  | Run_command of { command: string; description: string; target_node: string option; file: string option; line: int option; confidence: confidence }
  | NoFix
let no_fix = NoFix

(** Compute confidence for typo-based fixes (Rename_column, Suggest_identifier).
    Scales with edit distance and match uniqueness:
    - distance 1 + unique = [High]
    - distance 2 + unique, or distance 1 + ambiguous = [Medium]
    - everything else = [Low] *)
let confidence_for_typo ~edit_distance ~is_unique =
  if edit_distance = 1 && is_unique then High
  else if edit_distance = 2 && is_unique then Medium
  else if edit_distance = 1 then Medium
  else Low

let make_rename_column_fix ~old_name ~new_name ~edit_distance ~is_unique ?confidence ?target_node ?file ?line () =
  let confidence = match confidence with
    | Some c -> c
    | None -> confidence_for_typo ~edit_distance ~is_unique
  in
  Rename_column { old_name; new_name; target_node; file; line; edit_distance; is_unique; confidence }

let make_suggest_identifier_fix ~name ~suggestion ~edit_distance ~is_unique ?target_node ?file ?line () =
  let confidence = confidence_for_typo ~edit_distance ~is_unique in
  Suggest_identifier { name; suggestion; target_node; file; line; edit_distance; is_unique; confidence }

let make_add_node_arg_fix ~node ~arg ?target_node ?file ?line () =
  Add_node_arg { node; arg; target_node; file; line; confidence = Medium }

let make_run_command_fix ~command ~description ?target_node ?file ?line () =
  Run_command { command; description; target_node; file; line; confidence = Low }

type diagnostic = {
  diag_id : string;
  diag_error_class : error_class;
  diag_severity : severity;
  diag_phase : diagnostic_phase;
  diag_node_id : string option;
  diag_node_lang : string option;
  diag_file : string option;
  diag_line : int option;
  diag_column : int option;
  diag_end_line : int option;
  diag_end_column : int option;
  diag_message : string;
  diag_expected : string option;
  diag_actual : string option;
  diag_caused_by : string list;
  diag_suggested_fix : suggested_fix;
}

type check_result = {
  cr_schema_version : string;
  cr_status : string;
  cr_phase : diagnostic_phase;
  cr_tier : int;
  cr_diagnostics : diagnostic list;
}

let next_id = ref 1000

let gen_id () =
  incr next_id;
  Printf.sprintf "T%04d" !next_id

let phase_to_string = function
  | Parse -> "parse"
  | Wire -> "wire"
  | Schema -> "schema"
  | Env -> "env"
  | Build -> "build"
  | Exec -> "exec"

let severity_to_string = function
  | Error -> "error"
  | Warning -> "warning"

let phase_to_yojson p = `String (phase_to_string p)
let severity_to_yojson s = `String (severity_to_string s)

let opt_string_to_yojson = function
  | Some s -> `String s
  | None -> `Null

let opt_int_to_yojson = function
  | Some i -> `Int i
  | None -> `Null

let suggested_fix_to_yojson = function
  | Rename_column { old_name; new_name; target_node; file; line; edit_distance = _; is_unique = _; confidence } ->
      `Assoc [
        ("kind", `String "rename_column");
        ("old_name", `String old_name);
        ("new_name", `String new_name);
        ("target_node", opt_string_to_yojson target_node);
        ("file", opt_string_to_yojson file);
        ("line", opt_int_to_yojson line);
        ("confidence", `String (confidence_to_string confidence));
      ]
  | Add_node_arg { node; arg; target_node; file; line; confidence } ->
      `Assoc [
        ("kind", `String "add_node_arg");
        ("node", `String node);
        ("arg", `String arg);
        ("target_node", opt_string_to_yojson target_node);
        ("file", opt_string_to_yojson file);
        ("line", opt_int_to_yojson line);
        ("confidence", `String (confidence_to_string confidence));
      ]
  | Suggest_identifier { name; suggestion; target_node; file; line; edit_distance = _; is_unique = _; confidence } ->
      `Assoc [
        ("kind", `String "suggest_identifier");
        ("name", `String name);
        ("suggestion", `String suggestion);
        ("target_node", opt_string_to_yojson target_node);
        ("file", opt_string_to_yojson file);
        ("line", opt_int_to_yojson line);
        ("confidence", `String (confidence_to_string confidence));
      ]
  | Run_command { command; description; target_node; file; line; confidence } ->
      `Assoc [
        ("kind", `String "run_command");
        ("command", `String command);
        ("description", `String description);
        ("target_node", opt_string_to_yojson target_node);
        ("file", opt_string_to_yojson file);
        ("line", opt_int_to_yojson line);
        ("confidence", `String (confidence_to_string confidence));
      ]
  | NoFix -> `Null

let opt_string_of_yojson json =
  match json with
  | `String s -> Some s
  | `Null -> None
  | _ -> None

let opt_int_of_yojson json =
  match json with
  | `Int i -> Some i
  | `Null -> None
  | _ -> None

let suggested_fix_of_yojson json =
  let open Yojson.Safe.Util in
  match json with
  | `Null -> NoFix
  | _ ->
      let kind = json |> member "kind" |> to_string in
      let file = json |> member "file" |> opt_string_of_yojson in
      let line = json |> member "line" |> opt_int_of_yojson in
      let target_node = json |> member "target_node" |> opt_string_of_yojson in
      let confidence =
        match json |> member "confidence" |> opt_string_of_yojson with
        | Some c -> confidence_of_string c
        | None -> Low
      in
      match kind with
      | "rename_column" ->
          Rename_column {
            old_name = json |> member "old_name" |> to_string;
            new_name = json |> member "new_name" |> to_string;
            target_node;
            file; line;
            (* Signal fields are not recoverable from JSON; safe defaults are assigned *)
            edit_distance = 0;
            is_unique = true;
            confidence;
          }
      | "add_node_arg" ->
          Add_node_arg {
            node = json |> member "node" |> to_string;
            arg = json |> member "arg" |> to_string;
            target_node;
            file; line;
            confidence;
          }
      | "suggest_identifier" ->
          Suggest_identifier {
            name = json |> member "name" |> to_string;
            suggestion = json |> member "suggestion" |> to_string;
            target_node;
            file; line;
            (* Signal fields are not recoverable from JSON; safe defaults are assigned *)
            edit_distance = 0;
            is_unique = true;
            confidence;
          }
      | "run_command" ->
          Run_command {
            command = json |> member "command" |> to_string;
            description = json |> member "description" |> to_string;
            target_node;
            file; line;
            confidence;
          }
      | _ -> NoFix

let diagnostic_to_yojson d =
  `Assoc [
    ("id", `String d.diag_id);
    ("error_class", `String (error_class_to_string d.diag_error_class));
    ("severity", severity_to_yojson d.diag_severity);
    ("phase", phase_to_yojson d.diag_phase);
    ("node", `Assoc [
        ("id", (match d.diag_node_id with Some n -> `String n | None -> `Null));
        ("lang", (match d.diag_node_lang with Some l -> `String l | None -> `Null));
        ("file", (match d.diag_file with Some f -> `String f | None -> `Null));
        ("span", (match d.diag_line with
          | Some l -> `Assoc [
              ("start", `List [`Int l; `Int (Option.value ~default:1 d.diag_column)]);
              ("end", (match d.diag_end_line with
                | Some el -> `List [`Int el; `Int (Option.value ~default:1 d.diag_end_column)]
                | None -> `Null));
            ]
          | None -> `Null));
      ]);
    ("message", `String d.diag_message);
    ("expected", (match d.diag_expected with
      | Some v -> `Assoc [("kind", `String "arrow_type"); ("value", `String v)]
      | None -> `Null));
    ("actual", (match d.diag_actual with
      | Some v -> `Assoc [("kind", `String "arrow_type"); ("value", `String v)]
      | None -> `Null));
    ("caused_by", `List (List.map (fun s -> `String s) d.diag_caused_by));
    ("suggested_fix", suggested_fix_to_yojson d.diag_suggested_fix);
  ]

let check_result_to_yojson r =
  `Assoc [
    ("schema_version", `String r.cr_schema_version);
    ("status", `String r.cr_status);
    ("phase", phase_to_yojson r.cr_phase);
    ("tier", `Int r.cr_tier);
    ("diagnostics", `List (List.map diagnostic_to_yojson r.cr_diagnostics));
  ]

let error_code_to_phase code =
  match code with
  | Ast.SyntaxError -> Parse
  | Ast.StructuralError -> Wire
  | Ast.NameError -> Wire
  | Ast.ArityError -> Wire
  | Ast.TypeError -> Schema
  | Ast.FileError -> Env
  | Ast.MissingArtifactError -> Env
  | _ -> Exec

let error_code_to_error_class code =
  match code with
  | Ast.StructuralError -> Structural_error
  | Ast.NameError -> Name_error
  | Ast.ArityError -> Arity_error
  | Ast.TypeError -> Type_error
  | Ast.SyntaxError -> Parse_error
  | Ast.FileError -> File_error
  | Ast.KeyError -> Key_error
  | Ast.IndexError -> Index_error
  | Ast.ValueError -> Value_error
  | Ast.RuntimeError -> Runtime_error
  | Ast.DivisionByZero -> Division_by_zero
  | Ast.AssertionError -> Assertion_error
  | Ast.MatchError -> Match_error
  | Ast.ShellError -> Shell_error
  | Ast.AggregationError -> Aggregation_error
  | Ast.NAPredicateError -> Na_predicate_error
  | Ast.MissingArtifactError -> Missing_artifact
  | Ast.GenericError -> Generic_error

let extract_node_name_from_message msg =
  let patterns = [
    (Str.regexp "Node `\\([^`]+\\)`", 1);
    (Str.regexp "node `\\([^`]+\\)`", 1);
    (Str.regexp "node '\"'\\([^\"']+\\)\"'", 1);
  ] in
  let rec try_patterns = function
    | [] -> None
    | (re, group) :: rest ->
      (try
        ignore (Str.search_forward re msg 0);
        Some (Str.matched_group group msg)
      with Not_found -> try_patterns rest)
  in
  try_patterns patterns

let extract_cycle_nodes msg =
  let re = Str.regexp "dependency cycle involving node `\\([^`]+\\)`" in
  try
    ignore (Str.search_forward re msg 0);
    [Str.matched_group 1 msg]
  with Not_found -> []

(** Extract cross-runtime deserializer info from an error message.
    e.g. "Node `pyn` (Python) depends on `rn` (R) but has no explicit deserializer."
    returns Some ("R", "^csv") — the dep's runtime and the appropriate serializer format. *)
let extract_cross_runtime_info msg =
  let re = Str.regexp "depends on `\\([^`]+\\)` (\\([^)]+\\))" in
  try
    ignore (Str.search_forward re msg 0);
    let dep_runtime = Str.matched_group 2 msg in
    let serializer = match dep_runtime with
      | "Julia" -> "^arrow"
      | _ -> "^csv"
    in
    Some (dep_runtime, serializer)
  with Not_found -> None

let extract_caused_by_from_context context =
  List.filter_map (fun (k, v) ->
    match k, v with
    | "node_name", Ast.VString name -> Some name
    | "caused_by", Ast.VList items ->
        let names = List.filter_map (fun (_, item) ->
          match item with Ast.VString s -> Some s | _ -> None
        ) items in
        if names = [] then None else Some (String.concat "," names)
    | _ -> None
  ) context

let known_identifiers = [
  "summary"; "mean"; "sd"; "var"; "median"; "sum"; "min"; "max"; "length";
  "nrow"; "ncol"; "read_csv"; "write_csv"; "print"; "paste"; "paste0";
  "toupper"; "tolower"; "nchar"; "substr"; "grep"; "gsub"; "strsplit";
  "is.na"; "is.numeric"; "is.character"; "is.logical"; "as.numeric";
  "as.character"; "as.logical"; "seq"; "rep"; "c"; "list"; "data.frame";
  "filter"; "mutate"; "select"; "arrange"; "group_by"; "ungroup";
  "summarise"; "summarize"; "pivot_longer"; "pivot_wider"; "rename";
  "slice"; "head"; "tail"; "distinct"; "count"; "tally"; "pull";
  "left_join"; "right_join"; "inner_join"; "full_join"; "anti_join";
  "bind_rows"; "bind_cols"; "do.call"; "apply"; "lapply"; "sapply";
  "vapply"; "tapply"; "mapply"; "Reduce"; "Map";
  "which"; "ifelse"; "case_when"; "between"; "near";
  "row_number"; "rank"; "dense_rank"; "lag"; "lead";
  "cumsum"; "cumprod"; "cummax"; "cummin";
  "table"; "prop.table"; "addmargins"; "margin.table";
  "class"; "typeof"; "str"; "names"; "colnames"; "rownames";
  "dim"; "nlevels"; "levels"; "attributes"; "attr";
  "list.files"; "dir.exists"; "file.exists"; "readLines";
  "writeLines"; "cat"; "message"; "warning"; "stop";
  "tryCatch"; "withCallingHandlers"; "suppressWarnings";
  "suppressMessages"; "system"; "system.time"; "proc.time";
  "Sys.time"; "Sys.sleep"; "date"; "Sys.Date";
  "library"; "require"; "install.packages"; "available.packages";
  "optim"; "nlm"; "uniroot"; "integrate"; "deriv";
  "solve"; "qr"; "svd"; "eigen"; "chol"; "det"; "norm";
  "crossprod"; "tcrossprod"; "outer"; "inner"; "%*%";
  "which.min"; "which.max"; "pmax"; "pmin"; "pmax.int"; "pmin.int";
  "xor"; "all"; "any"; "identical"; "equal"; "setdiff";
  "union"; "intersect"; "match"; "%in%";
  "Rev"; "sort"; "order"; "duplicated"; "unique";
  "tabulate"; "findInterval"; "cut"; "find";
  "grepl"; "regexpr"; "gregexpr"; "regmatches";
  "sprintf"; "format"; "formatC"; "prettyNum"; "pretty";
  "hcl.colors"; "rainbow"; "heat.colors"; "terrain.colors";
  "topo.colors"; "cm.colors"; "colorRampPalette";
  "par"; "plot"; "points"; "lines"; "abline"; "curve";
  "hist"; "barplot"; "boxplot"; "pie"; "stripchart";
  "text"; "legend"; "title"; "axis"; "mtext"; "grid";
  "polygon"; "rect"; "segments"; "arrows";
  "locator"; "identify"; "dev.new"; "dev.off"; "pdf"; "png"; "jpeg"
]

let known_identifiers_lower_table =
  let tbl = Hashtbl.create (List.length known_identifiers) in
  List.iter (fun k ->
    Hashtbl.replace tbl (String.lowercase_ascii k) k
  ) known_identifiers;
  tbl

(** Extract the variable name and an optional correction from an error message.
    Returns (name, (suggestion * edit_distance * is_unique) option). *)
let extract_name_and_suggestion msg =
  let re_var = Str.regexp "Variable '\\([^']+\\)' is not defined" in
  let re_name = Str.regexp "Name `\\([^`]+\\)` is not defined" in
  try
    let name =
      if (try ignore (Str.search_forward re_var msg 0); true with Not_found -> false) then
        Str.matched_group 1 msg
      else if (try ignore (Str.search_forward re_name msg 0); true with Not_found -> false) then
        Str.matched_group 1 msg
      else
        raise Not_found
    in
    let lower_name = String.lowercase_ascii name in
    let candidates = Hashtbl.fold (fun lk _ acc -> lk :: acc) known_identifiers_lower_table [] in
    match Ast.suggest_names_with_scores lower_name candidates with
    | (best_match, dist) :: runner_up :: _ ->
        let suggestion = Hashtbl.find known_identifiers_lower_table best_match in
        let is_unique = snd runner_up > dist in
        (name, Some (suggestion, dist, is_unique))
    | [(best_match, dist)] ->
        let suggestion = Hashtbl.find known_identifiers_lower_table best_match in
        (name, Some (suggestion, dist, true))
    | [] -> (name, None)
  with Not_found -> ("", None)

let of_verror ?file (err : Ast.error_info) : diagnostic =
  let diag_phase = error_code_to_phase err.code in
  let node_name = extract_node_name_from_message err.message in
  let caused_by = match extract_caused_by_from_context err.context with
    | name :: _ -> [name]
    | [] -> extract_cycle_nodes err.message
  in
  let suggested_fix = match err.code with
    | StructuralError ->
        (match extract_cross_runtime_info err.message with
         | Some (_dep_runtime, serializer) ->
             let arg = "deserializer = " ^ serializer in
             let node = match node_name with Some n -> n | None -> "" in
             make_add_node_arg_fix ~node ~arg ?target_node:node_name ?file ()
         | None -> NoFix)
    | NameError ->
        let (name, suggestion_info) = extract_name_and_suggestion err.message in
        (match suggestion_info with
         | Some (s, edit_distance, is_unique) ->
             make_suggest_identifier_fix ~name ~suggestion:s ~edit_distance ~is_unique ?target_node:node_name ?file ()
         | None -> NoFix)
    | _ -> NoFix
  in
  {
    diag_id = gen_id ();
    diag_error_class = error_code_to_error_class err.code;
    diag_severity = Error;
    diag_phase;
    diag_node_id = node_name;
    diag_node_lang = None;
    diag_file = file;
    diag_line = (match err.location with Some l -> Some l.Ast.line | None -> None);
    diag_column = (match err.location with Some l -> Some l.Ast.column | None -> None);
    diag_end_line = None;
    diag_end_column = None;
    diag_message = err.message;
    diag_expected = None;
    diag_actual = None;
    diag_caused_by = caused_by;
    diag_suggested_fix = suggested_fix;
  }

let of_pipeline_result ?file (p : Ast.pipeline_result) : diagnostic list =
  List.concat (List.map (fun (name, nd) ->
    let errors = match nd.Ast.nd_error with
      | Some ne ->
          [{
            diag_id = gen_id ();
            diag_error_class = error_class_of_string ne.Ast.ne_kind;
            diag_severity = Error;
            diag_phase = Exec;
            diag_node_id = Some name;
            diag_node_lang = None;
            diag_file = file;
            diag_line = None;
            diag_column = None;
            diag_end_line = None;
            diag_end_column = None;
            diag_message = ne.Ast.ne_message;
            diag_expected = None;
            diag_actual = None;
            diag_caused_by = nd.Ast.nd_upstream_errors;
            diag_suggested_fix = NoFix;
          }]
      | None -> []
    in
    (* NA-exclusion warnings with na_count=0 mean no rows were affected —
       nothing to report.  All other warning kinds (e.g. invalid_expect_placement)
       are surfaced unconditionally. *)
    let warnings = List.filter_map (fun nw ->
      if nw.Ast.nw_kind = "NAExcluded" && nw.Ast.nw_na_count = 0 then None
      else
        let diag_error_class, diag_phase =
          match nw.Ast.nw_kind with
          | "NAExcluded" -> Na_warning, Exec
          | other -> error_class_of_string other, Exec
        in
        Some ({
          diag_id = gen_id ();
          diag_error_class;
          diag_severity = Warning;
          diag_phase;
          diag_node_id = Some name;
          diag_node_lang = None;
          diag_file = file;
          diag_line = None;
          diag_column = None;
          diag_end_line = None;
          diag_end_column = None;
          diag_message = nw.Ast.nw_message;
          diag_expected = None;
          diag_actual = None;
          diag_caused_by = (match nw.Ast.nw_source with
            | Ast.WarningUpstream upstream -> [upstream]
            | Ast.WarningOwn -> []);
          diag_suggested_fix = NoFix;
        } : diagnostic)
    ) nd.Ast.nd_warnings in
    errors @ warnings
  ) p.Ast.p_node_diagnostics)

let exit_code_of_diagnostics entries =
  if entries = [] then 0
  else
    let has_schema = List.exists (fun d -> d.diag_phase = Schema) entries in
    let has_env = List.exists (fun d -> d.diag_phase = Env) entries in
    if has_env then 3
    else if has_schema then 2
    else 1

let phase_rank = function
  | Parse -> 0
  | Wire -> 1
  | Schema -> 2
  | Env -> 3
  | Build -> 4
  | Exec -> 5

let worst_phase entries =
  match entries with
  | [] -> Wire
  | d :: rest ->
      List.fold_left (fun acc e ->
        if phase_rank e.diag_phase > phase_rank acc
        then e.diag_phase else acc
      ) d.diag_phase rest

let worst_tier entries =
  match entries with
  | [] -> 1
  | d :: rest ->
      match List.fold_left (fun acc e ->
        if phase_rank e.diag_phase > phase_rank acc
        then e.diag_phase else acc
      ) d.diag_phase rest with
      | Parse | Wire -> 1
      | Schema -> 2
      | Env | Build | Exec -> 3

let diagnostic_phase d = d.diag_phase
let diagnostic_severity d = d.diag_severity
let diagnostic_error_class d = d.diag_error_class
let diagnostic_message d = d.diag_message
let check_result_entries r = r.cr_diagnostics

let make_result ~tier ~phase entries =
  let status = if entries = [] then "ok" else "error" in
  {
    cr_schema_version = "1";
    cr_status = status;
    cr_phase = phase;
    cr_tier = tier;
    cr_diagnostics = entries;
  }
