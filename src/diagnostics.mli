(* src/diagnostics.mli *)
(* Interface for diagnostics module, enforcing private constructors on suggested_fix *)

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
  | Contract_violation
  | Contract_unverifiable
  | Invalid_expect_placement

val error_class_to_string : error_class -> string
val error_class_of_string : string -> error_class
val severity_to_string : severity -> string
val phase_to_string : diagnostic_phase -> string

(** Confidence level for a suggested fix, indicating how deterministic it is.
    - [High]: highly deterministic — safe to apply automatically (e.g., Cast with intact schema chain, Rename at edit distance 1 with unique match)
    - [Medium]: heuristic — verify before applying (e.g., Add_node_arg, Cast with broken chain, Rename at edit distance 2)
    - [Low]: informational — check manually (e.g., Run_command, Suggest_identifier at distance 3+)
    Confidence is computed dynamically from diagnostic context, not static per fix kind. *)
type confidence = High | Medium | Low

val confidence_to_string : confidence -> string
val confidence_of_string : string -> confidence

type suggested_fix = private
  | Cast of { column: string; cast_to: string; target_node: string option; file: string option; line: int option; chain_broken: bool; confidence: confidence }
  | Rename_column of { old_name: string; new_name: string; target_node: string option; file: string option; line: int option; edit_distance: int; is_unique: bool; confidence: confidence }
  | Add_node_arg of { node: string; arg: string; target_node: string option; file: string option; line: int option; confidence: confidence }
  | Suggest_identifier of { name: string; suggestion: string; target_node: string option; file: string option; line: int option; edit_distance: int; is_unique: bool; confidence: confidence }
  | Run_command of { command: string; description: string; target_node: string option; file: string option; line: int option; confidence: confidence }
  | NoFix

(** Smart constructors for suggested_fix. These are the only way to build
    suggested_fix values — the type is private to enforce this constraint.
    Each constructor computes confidence automatically from its inputs. *)

(** Cast: inserts a type coercion. Confidence is [High] when [chain_broken]
    is false (schema propagates through the pipeline), [Medium] otherwise. *)
val make_cast_fix : column:string -> cast_to:string -> chain_broken:bool -> ?target_node:string -> ?file:string -> ?line:int -> unit -> suggested_fix

(** Rename_column: replaces column references. Confidence computed from edit
    distance and uniqueness unless explicitly overridden via [?confidence]. *)
val make_rename_column_fix : old_name:string -> new_name:string -> edit_distance:int -> is_unique:bool -> ?confidence:confidence -> ?target_node:string -> ?file:string -> ?line:int -> unit -> suggested_fix

(** Suggest_identifier: spelling correction. Confidence scales with edit
    distance and uniqueness: [High] at distance 1 with unique match, down to
    [Low] at distance 3+. *)
val make_suggest_identifier_fix : name:string -> suggestion:string -> edit_distance:int -> is_unique:bool -> ?target_node:string -> ?file:string -> ?line:int -> unit -> suggested_fix

(** Add_node_arg: adds a missing argument to a node. Always [Medium]. *)
val make_add_node_arg_fix : node:string -> arg:string -> ?target_node:string -> ?file:string -> ?line:int -> unit -> suggested_fix

(** Run_command: suggests a shell command. Always [Low]. *)
val make_run_command_fix : command:string -> description:string -> ?target_node:string -> ?file:string -> ?line:int -> unit -> suggested_fix

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

val gen_id : unit -> string
val suggested_fix_to_yojson : suggested_fix -> Yojson.Safe.t
val suggested_fix_of_yojson : Yojson.Safe.t -> suggested_fix
val diagnostic_to_yojson : diagnostic -> Yojson.Safe.t
val check_result_to_yojson : check_result -> Yojson.Safe.t
val error_code_to_phase : Ast.error_code -> diagnostic_phase
val error_code_to_error_class : Ast.error_code -> error_class
val extract_node_name_from_message : string -> string option
val extract_cycle_nodes : string -> string list
val extract_cross_runtime_info : string -> (string * string) option
val no_fix : suggested_fix
val extract_caused_by_from_context : (string * Ast.value) list -> string list
val of_verror : ?file:string -> Ast.error_info -> diagnostic
val of_pipeline_result : ?file:string -> Ast.pipeline_result -> diagnostic list
val exit_code_of_diagnostics : diagnostic list -> int
val worst_phase : diagnostic list -> diagnostic_phase
val worst_tier : diagnostic list -> int
val diagnostic_phase : diagnostic -> diagnostic_phase
val diagnostic_severity : diagnostic -> severity
val diagnostic_error_class : diagnostic -> error_class
val diagnostic_message : diagnostic -> string
val check_result_entries : check_result -> diagnostic list
val make_result : tier:int -> phase:diagnostic_phase -> diagnostic list -> check_result
val extract_name_and_suggestion : string -> (string * (string * int * bool) option)
