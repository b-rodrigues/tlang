(* src/diagnostics.ml *)
(* Structured diagnostic types and JSON serialization for t check (§2 of spec) *)

type diagnostic_phase = Parse | Wire | Schema | Env | Build | Exec

type severity = Error | Warning

type suggested_fix =
  | Cast of { column: string; cast_to: string }
  | Rename_column of { old_name: string; new_name: string }
  | Add_node_arg of { node: string; arg: string }
  | Pin_package_version of { pkg: string; version: string }
  | NoFix

type diagnostic = {
  diag_id : string;
  diag_error_class : string;
  diag_severity : severity;
  diag_phase : diagnostic_phase;
  diag_node_id : string option;
  diag_node_lang : string option;
  diag_file : string option;
  diag_line : int option;
  diag_column : int option;
  diag_message : string;
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

let suggested_fix_to_yojson = function
  | Cast { column; cast_to } ->
      `Assoc [
        ("kind", `String "cast");
        ("column", `String column);
        ("cast_to", `String cast_to);
      ]
  | Rename_column { old_name; new_name } ->
      `Assoc [
        ("kind", `String "rename_column");
        ("old_name", `String old_name);
        ("new_name", `String new_name);
      ]
  | Add_node_arg { node; arg } ->
      `Assoc [
        ("kind", `String "add_node_arg");
        ("node", `String node);
        ("arg", `String arg);
      ]
  | Pin_package_version { pkg; version } ->
      `Assoc [
        ("kind", `String "pin_package_version");
        ("pkg", `String pkg);
        ("version", `String version);
      ]
  | NoFix -> `Null

let diagnostic_to_yojson d =
  `Assoc [
    ("id", `String d.diag_id);
    ("error_class", `String d.diag_error_class);
    ("severity", severity_to_yojson d.diag_severity);
    ("phase", phase_to_yojson d.diag_phase);
    ("node", (match d.diag_node_id with
      | Some n -> `Assoc [
          ("id", `String n);
          ("lang", (match d.diag_node_lang with Some l -> `String l | None -> `Null));
        ]
      | None -> `Null));
    ("file", (match d.diag_file with Some f -> `String f | None -> `Null));
    ("span", (match d.diag_line with
      | Some l -> `Assoc [
          ("start", `List [`Int l; `Int (Option.value ~default:1 d.diag_column)]);
        ]
      | None -> `Null));
    ("message", `String d.diag_message);
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
  | Ast.StructuralError -> "structural_error"
  | Ast.NameError -> "name_error"
  | Ast.ArityError -> "arity_error"
  | Ast.TypeError -> "type_error"
  | Ast.SyntaxError -> "parse_error"
  | Ast.FileError -> "file_error"
  | Ast.KeyError -> "key_error"
  | Ast.IndexError -> "index_error"
  | Ast.ValueError -> "value_error"
  | Ast.RuntimeError -> "runtime_error"
  | Ast.DivisionByZero -> "division_by_zero"
  | Ast.AssertionError -> "assertion_error"
  | Ast.MatchError -> "match_error"
  | Ast.ShellError -> "shell_error"
  | Ast.AggregationError -> "aggregation_error"
  | Ast.NAPredicateError -> "na_predicate_error"
  | Ast.MissingArtifactError -> "missing_artifact"
  | Ast.GenericError -> "generic_error"

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

let of_verror ?file (err : Ast.error_info) : diagnostic =
  let diag_phase = error_code_to_phase err.code in
  let node_name = extract_node_name_from_message err.message in
  let caused_by = match extract_caused_by_from_context err.context with
    | name :: _ -> [name]
    | [] -> extract_cycle_nodes err.message
  in
  let suggested_fix = match err.code with
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
    diag_message = err.message;
    diag_caused_by = caused_by;
    diag_suggested_fix = suggested_fix;
  }

let of_pipeline_result ?file (p : Ast.pipeline_result) : diagnostic list =
  List.concat (List.map (fun (name, nd) ->
    let errors = match nd.Ast.nd_error with
      | Some ne ->
          [{
            diag_id = gen_id ();
            diag_error_class = ne.Ast.ne_kind;
            diag_severity = Error;
            diag_phase = Exec;
            diag_node_id = Some name;
            diag_node_lang = None;
            diag_file = file;
            diag_line = None;
            diag_column = None;
            diag_message = ne.Ast.ne_message;
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
          | "invalid_expect_placement" -> nw.Ast.nw_kind, Wire
          | "NAExcluded" -> "na_warning", Exec
          | other -> other, Exec
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
          diag_message = nw.Ast.nw_message;
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
