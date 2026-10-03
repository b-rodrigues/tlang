(* src/ast.ml *)
(* Phase 1: Values, Types, and Errors for the T language alpha. *)
(* Extends Phase 0 with explicit missingness, structured errors, *)
(* and placeholder types for vectors and DataFrames. *)

(** Environment module — immutable string map *)
module Env = Map.Make(String)
module String_set = Set.Make(String)

exception TLangSyntaxError of string
exception Mixed_bracket_form
exception Invalid_match_pattern of string
exception Invalid_type_declaration of string

type symbol = string


(** NA type tags — missingness is explicit and typed *)
type na_type =
  | NABool
  | NAInt
  | NAFloat
  | NAString
  | NADate
  | NADatetime
  | NAGeneric

(** Symbolic error codes *)
type error_code =
  | TypeError
  | AggregationError
  | ArityError
  | NameError
  | DivisionByZero
  | KeyError
  | IndexError
  | AssertionError
  | FileError
  | ValueError
  | MatchError
  | SyntaxError
  | ShellError
  | RuntimeError
  | GenericError
  | NAPredicateError
  | MissingArtifactError
  | StructuralError

(** Structured source location *)
type source_location = {
  file : string option;
  line : int;
  column : int;
}

(** Generic located wrapper *)
type 'a located = {
  node : 'a;
  loc : source_location option;
}

type pattern_expr =
  | PatternMap of string list         (* map(dep1, dep2, ...) *)
  | PatternCross of pattern_expr list  (* cross(map(...), map(...), ...) *)
  | PatternSlice of string * int list  (* slice(dep, [3, 4]) *)
  | PatternHead of string * int        (* head(dep, n) *)
  | PatternTail of string * int        (* tail(dep, n) *)
  | PatternSample of string * int      (* sample(dep, n) *)

(** Structured error information *)
type error_info = {
  code : error_code;
  message : string;
  context : (string * value) list;
  location : source_location option;
  na_count : int;
}

(** DataFrame type — Arrow-backed columnar storage *)
and dataframe = {
  arrow_table : Arrow_table.t;
  group_keys : string list;
}

and ndarray = {
  shape : int array;
  data : float array;
}

(** Phase 6: Intent block — structured metadata for LLM-native workflows *)
and intent_block = {
  intent_fields : (string * string) list;  (* Key-value pairs of metadata *)
}

(** testcraft: outcome of an expect_* comparison *)
and expect_kind =
  | Expect_pass
  | Expect_stop of string
  | Expect_hold of string

and node_warning_source =
  | WarningOwn
  | WarningUpstream of string

and node_warning = {
  nw_kind : string;
  nw_fn : string;
  nw_na_count : int;
  nw_na_indices : int list;
  nw_message : string;
  nw_source : node_warning_source;
}

and node_error = {
  ne_kind : string;
  ne_fn : string;
  ne_message : string;
  ne_na_count : int;
}

and node_diagnostics = {
  nd_warnings : node_warning list;
  nd_error : node_error option;
  nd_warnings_suppressed : bool;
  nd_recovered : bool;
  nd_upstream_errors : string list;
}

(** Phase 3: Pipeline result with cached values and dependency info *)
and pipeline_result = {
  p_nodes : (string * value) list;           (* Cached node results *)
  p_exprs : (string * expr) list;            (* Original expressions *)
  p_deps  : (string * string list) list;     (* Dependency graph *)
  p_imports : stmt list;                     (* Import statements to propagate *)
  p_runtimes : (string * string) list;       (* Map node name -> runtime *)
  p_serializers : (string * expr) list;      (* Map node name -> serializer expr *)
  p_deserializers : (string * expr) list;    (* Map node name -> deserializer expr *)
  p_env_vars : (string * (string * value) list) list;  (* Map node name -> build env vars *)
  p_args : (string * (string * value) list) list;      (* Map node name -> runtime/tool args *)
  p_shells : (string * string option) list;          (* Map node name -> shell interpreter name *)
  p_shell_args : (string * expr list) list;          (* Map node name -> shell interpreter args *)
  p_functions : (string * expr list) list;   (* Map node name -> function files *)
  p_includes : (string * expr list) list;    (* Map node name -> included files *)
  p_noops : (string * bool) list;            (* Map node name -> noop flag *)
  p_scripts : (string * string option) list; (* Map node name -> optional script path *)
  p_explicit_deps : (string * string list option) list; (* Map node name -> explicit dependencies *)
  p_node_diagnostics : (string * node_diagnostics) list; (* Map node name -> diagnostics *)
  p_has_patterns : bool;                      (* true if any node has a pattern *)
  p_patterns     : (string * pattern_expr) list; (* Map node name -> pattern *)
  p_iterations   : (string * string) list;       (* Map node name -> iteration type *)
  p_flakes       : (string * string option) list; (* Map node name -> optional flake path *)
  p_provenance   : (string * option_provenance) list; (* Map node name -> per-option source provenance *)
}

(** Provenance of a resolved option value: declared in the node()
    constructor, or injected globally via set_pipeline_global_options. *)
and option_source =
  | Source_global
  | Source_node

and option_provenance = {
  prov_functions     : (expr * option_source) list; (* parallel to p_functions entries *)
  prov_includes      : (expr * option_source) list; (* parallel to p_includes entries *)
  prov_env_vars      : (string * option_source) list; (* parallel to p_env_vars keys *)
  prov_args          : (string * option_source) list; (* parallel to p_args keys *)
  prov_shell_args    : (expr * option_source) list; (* parallel to p_shell_args entries *)
  prov_explicit_deps : (string * option_source) list; (* parallel to explicit deps *)
  prov_serializer    : option_source option; (* None = unset (default used) *)
  prov_deserializer  : option_source option; (* None = unset (default used) *)
  prov_shell         : option_source option; (* None = unset *)
  prov_flake         : option_source option; (* None = unset *)
  prov_noop          : option_source option; (* None = not forced *)
}

and meta_pipeline = {
  mp_pipelines : (string * value) list;      (* Map sub-pipeline name -> pipeline value (VPipeline) *)
}


(** Formula specification — captures LHS/RHS of ~ expressions *)
and formula_spec = {
  response: string list;
  predictors: string list;
  raw_lhs: expr;
  raw_rhs: expr;
}

(** Metadata for a node built via Nix that points to a filesystem artifact *)
and computed_node = {
  cn_name : string;
  cn_runtime : string;
  cn_path : string;
  cn_serializer : string;
  cn_class : string;
  cn_dependencies : string list;
  cn_p_exprs : ((string * expr) list) option;  (* Pipeline identity for scoped cache lookups *)
  cn_flake : string option;                    (* Optional path to a dedicated Nix flake *)
  cn_config : node_config option;              (* Resolved per-node config snapshot (provenance) *)
}

(** Resolved per-node configuration snapshot attached to computed nodes for
    introspection (e.g. explain).  Carries both the resolved values and the
    source of each value.  It has no back-reference to the pipeline, so it can
    be embedded in a computed node without creating structural equality
    cycles.  Nodes restored from build logs carry None. *)
and node_config = {
  nc_runtime       : string;
  nc_functions     : (expr * option_source) list;
  nc_includes      : (expr * option_source) list;
  nc_env_vars      : (string * value * option_source) list;
  nc_args          : (string * value * option_source) list;
  nc_shell         : (string * option_source) option;
  nc_shell_args    : (expr * option_source) list;
  nc_flake         : (string * option_source) option;
  nc_noop          : (bool * option_source) option;
  nc_serializer    : (expr * option_source) option;
  nc_deserializer  : (expr * option_source) option;
  nc_deps          : (string * option_source) list;
}

(** Metadata for an unbuilt node (first-class value from node() function) *)
and unbuilt_node = {
  un_command : expr;
  un_script : string option;  (* Path to an external script file (.R or .py) *)
  un_runtime : string;
  un_serializer : expr;
  un_deserializer : expr;
  un_env_vars : (string * value) list;
  un_args : (string * value) list;
  un_shell : string option;
  un_shell_args : expr list;
  un_functions : expr list;
  un_includes : expr list;
  un_noop : bool;
  un_dependencies : string list option;
  un_pattern : pattern_expr option;     (* None = no dynamic branching *)
  un_iteration : string;                (* "vector" | "list" *)
  un_flake : string option;             (* Optional path to a dedicated Nix flake *)
}

(** Result of a ?<{...}> shell escape — carries stdout, stderr, and exit code.
    Displays as a raw string (stdout) when printed, but exposes .stderr and
    .exit_code as dot-access fields. *)
and shell_result = {
  sr_stdout    : string;
  sr_stderr    : string;
  sr_exit_code : int;
}

and period = {
  p_years : int;
  p_months : int;
  p_days : int;
  p_hours : int;
  p_minutes : int;
  p_seconds : int;
  p_micros : int;
}

and interval = {
  iv_start : int64;
  iv_end : int64;
  iv_tz : string option;
}

and serializer = {
  s_format : string;
  s_writer : value; (* VLambda or VBuiltin *)
  s_reader : value; (* VLambda or VBuiltin *)
  s_r_writer : string option;
  s_r_reader : string option;
  s_py_writer : string option;
  s_py_reader : string option;
  s_julia_writer : string option;
  s_julia_reader : string option;
}

and lens =
  | ColLens of string
  | IdxLens of int
  | RowLens of int
  | NodeLens of string
  | NodeMetaLens of string * string
  | EnvVarLens of string * string
  | CompositeLens of lens * lens
  | FilterLens of value

and build_log = {
  bl_nodes : value list;
  bl_duration : float;
  bl_failed_nodes : string list;
  bl_out_path : string option;
}

(** Runtime values *)
and value =
  | VBuildLog of build_log
  (* Scalar Types *)
  | VInt of int
  | VFloat of float
  | VBool of bool
  | VString of string
  | VRawCode of string
  | VSymbol of symbol
  | VDate of int
  | VDatetime of int64 * string option
  (* General-Purpose Containers *)
  | VList of (string option * value) list
  | VDict of (string * value) list
  (* User-defined union value: nominal (the type name is identity) with an
     explicit case tag and positional payload. *)
  | VUnion of { un_type : string; un_case : string; un_payload : value list }
  | VVector of value array
  | VNDArray of ndarray
  | VDataFrame of dataframe
  | VPipeline of pipeline_result
  | VMetaPipeline of meta_pipeline
  (* User-defined record value: nominal (the type name is identity) and
     closed (exactly the declared fields, no more, no fewer). *)
  | VRecord of { rec_type : string; rec_fields : (string * value) list }
  (* User-defined type declaration as a first-class value, so type names
     follow normal scoping and `Point(...)` construction is just a call. *)
  | VTypeDef of { td_name : string; td_def : type_def }

  | VLens of lens
  (* Functional Types *)
  | VLambda of lambda
  | VBuiltin of builtin
  (* Special Values *)
  | VNA of na_type
  | VError of error_info
  | VFactor of int * string list * bool
  | VPeriod of period
  | VDuration of float
  | VInterval of interval
  (* Phase 6: Intent block value *)
  | VIntent of intent_block
  (* Formula value *)
  | VFormula of formula_spec
  | VComputedNode of computed_node
  | VNode of unbuilt_node
  | VNullNode
  | VPattern of pattern_expr
  | VExpr of expr
  (* Quosure: expression captured with its lexical environment (like rlang::quo) *)
  | VQuo of { q_expr: expr; q_env: value Env.t }
  (* Shell escape result *)
  | VShellResult of shell_result
  (* Metaprogramming intermediate values *)
  | VUnquote of value
  | VUnquoteSplice of value
  | VDynamicArg of string * value
  (* Internal: environment as a first-class value, used by __q_caller_env__ *)
  | VEnv of value Env.t
  | VSerializer of serializer
  | VNodeResult of {
      v : value;
      node_name : string;
      diagnostics : node_diagnostics;
    }
  (* testcraft: result of an expect_* comparison *)
  | VExpect of expect_kind



and builtin = {
  b_name: string option;
  b_arity: int;
  b_variadic: bool;
  b_func: ((string option * value) list -> value Env.t ref -> value);
}

and lambda = {
  params : symbol list;
  autoquote_params : bool list;
  param_types : typ option list;
  return_type : typ option;
  generic_params : string list;
  variadic : bool;
  body : expr;
  env : value Env.t option;
}

and match_pattern =
  | PWildcard
  | PVar of symbol
  | PNA
  | PList of match_pattern list * symbol option
  | PError of symbol option
  (* Union case arm: the case name plus one sub-pattern per payload
     position. Nullary cases still use call syntax (`Missing()`), so a
     bare name always means a binding, never a case test. *)
  | PUnion of { pu_case : string; pu_args : match_pattern list }

(** User-defined type definitions: nominal closed records, and tagged
    unions whose cases carry positional payloads. *)
and type_def =
  | RecordDef of { rd_fields : (string * typ) list }
  | UnionDef of { ud_cases : (string * typ list) list }

and expr = expr_node located

and expr_node =
  | Value of value
  | Var of symbol
  | ColumnRef of string  (* NSE: $column_name references *)
  | Call of { fn : expr; args : (string option * expr) list }
  | Lambda of lambda
  | IfElse of { cond : expr; then_ : expr; else_ : expr }
  | Match of { scrutinee : expr; cases : (match_pattern * expr) list }
  | ListLit of (string option * expr) list
  | DictLit of (string * expr) list
  | BinOp of { op : binop; left : expr; right : expr }
  | UnOp of { op : unop; operand : expr }
  | DotAccess of { target : expr; field : string }
  | RawCode of { raw_text : string; raw_identifiers : string list }  (* Foreign code block <{ ... }> *)
  | BroadcastOp of { op : binop; left : expr; right : expr }
  | PipelineDef of (string * expr) list
  | PipelineOfDef of (string * expr) list

  | IntentDef of (string * expr) list
  | Unquote of expr
  | UnquoteSplice of expr
  | ShellExpr of string
  | Block of stmt list

and stmt = stmt_node located

and stmt_node =
  | Expression of expr
  | Assignment of { name : symbol; typ : typ option; expr : expr }
  | Reassignment of { name : symbol; expr : expr }
  | TypeDecl of { tname : symbol; tdef : type_def }
  | Import of string
  | ImportPackage of string
  | ImportFrom of { package: string; names: import_spec list }
  | ImportFileFrom of { filename: string; names: import_spec list }

and import_spec = {
  import_name: string;
  import_alias: string option;
}

and binop = Plus | Minus | Mul | Div | Mod | Eq | NEq | Gt | Lt | GtEq | LtEq | And | Or | BitAnd | BitOr
  | In (* New: membership check *) | Pipe | MaybePipe | Formula | FatArrow
and unop = Not | Neg
and typ =
  | TInt
  | TFloat
  | TBool
  | TString
  | TList of typ option
  | TDict of typ option * typ option
  | TTuple of typ list
  | TUnion of typ list
  | TDataFrame of typ option
  | TVar of string
  | TCustom of string
  | TComputedNode
  | TSerializer
  | TExpr
  | TArrow of typ list * typ
  | TUnknown

type program = stmt list
(* Immediate child expressions of an expression node, in source order.
    Single place covering every constructor: a new AST variant without an
    arm here is a compile-time match warning, not a silent traversal gap.
    Whole-tree walkers ([sites_in_expr], [generic_lambdas_in_expr],
    [expr_mentions_any] in check_utils.ml) build on this instead of
    repeating the traversal. *)
let rec children_of_expr (e : expr) : expr list =
  match e.node with
  | Value _ | Var _ | ColumnRef _ | RawCode _ | ShellExpr _ -> []
  | Call { fn; args } -> fn :: List.map snd args
  | Lambda l -> [l.body]
  | IfElse { cond; then_; else_ } -> [cond; then_; else_]
  | Match { scrutinee; cases } -> scrutinee :: List.map snd cases
  | ListLit items -> List.map snd items
  | DictLit pairs -> List.map snd pairs
  | BinOp { left; right; _ } | BroadcastOp { left; right; _ } -> [left; right]
  | UnOp { operand; _ } -> [operand]
  | DotAccess { target; _ } -> [target]
  | PipelineDef nodes | PipelineOfDef nodes | IntentDef nodes -> List.map snd nodes
  | Unquote x | UnquoteSplice x -> [x]
  | Block stmts -> List.concat_map children_of_stmt stmts

and children_of_stmt (s : stmt) : expr list =
  match s.node with
  | Expression e -> [e]
  | Assignment { expr = e; _ } -> [e]
  | Reassignment { expr = e; _ } -> [e]
  | TypeDecl _ -> []
  | Import _ | ImportPackage _ | ImportFrom _ | ImportFileFrom _ -> []



(** Sentinel path used when a computed node has not been built yet. *)
let unbuilt_path = "<unbuilt>"

(** Located constructors and accessors *)
let mk_expr ?loc node = { node; loc }
let mk_stmt ?loc node = { node; loc }
let expr_node (e : expr) = e.node
let expr_loc (e : expr) = e.loc
let stmt_node (s : stmt) = s.node
let stmt_loc (s : stmt) = s.loc

(** Global hook for resolving node names to values (e.g. from build logs) *)
let node_resolver : (string -> value option) ref = ref (fun _ -> None)

(** Global hook for resolving computed node metadata from build logs *)
let computed_node_resolver : (computed_node -> computed_node) ref = ref (fun cn -> cn)

(** Global hook for automatically flattening meta-pipelines in built-in argument projections *)
let meta_pipeline_flatten_resolver : (value -> value) ref = ref (fun v -> v)

(** Pipeline-scoped in-memory node value cache.
    Keyed by (pipeline_exprs, node_name) to avoid cross-pipeline contamination.

    NOTE: The key uses structural equality on (string * expr) list via the
    polymorphic `=` operator. This works reliably because p_exprs is always
    passed by reference (same physical list is used for both writes and lookups).
    If the list is ever reconstructed from deserialized data or copied, key
    equality will break, since `expr` records may contain mutable location
    fields. If that becomes necessary, use a stable key (e.g. a hash or UUID)
    instead. *)
let in_memory_node_values : ((string * expr) list * string, value) Hashtbl.t = Hashtbl.create 50

(** Store an in-memory node value scoped to a specific pipeline *)
let set_in_memory_node_value ~(p_exprs : (string * expr) list) ~(node_name : string) (v : value) =
  Hashtbl.replace in_memory_node_values (p_exprs, node_name) v

(** Look up an in-memory node value for a specific pipeline *)
let get_in_memory_node_value ~(p_exprs : (string * expr) list) ~(node_name : string) =
  Hashtbl.find_opt in_memory_node_values (p_exprs, node_name)

(** Remove all in-memory node values for a specific pipeline *)
let clear_pipeline_in_memory ~(p_exprs : (string * expr) list) =
  let to_remove = Hashtbl.fold (fun (pe, n) _ acc ->
    if pe = p_exprs then n :: acc else acc
  ) in_memory_node_values [] in
  List.iter (fun n -> Hashtbl.remove in_memory_node_values (p_exprs, n)) to_remove

(** Find an in-memory value by node name across all pipelines (fallback).
    Should only be used when no pipeline identity is available.
    Returns the most recently stored value matching the node name,
    or None if no match is found. *)
let find_in_memory_node_value_by_name (node_name : string) : value option =
  let results = Hashtbl.fold (fun (_, n) v acc ->
    if n = node_name then v :: acc else acc
  ) in_memory_node_values [] in
  match results with [] -> None | v :: _ -> Some v

(** Look up an in-memory node value, preferring scoped lookup when a pipeline identity is available. *)
let get_in_memory_node_value_for_cn (cn : computed_node) : value option =
  match cn.cn_p_exprs with
  | Some p_exprs -> get_in_memory_node_value ~p_exprs ~node_name:cn.cn_name
  | None -> find_in_memory_node_value_by_name cn.cn_name

(** Global hook for storing mapping from pipeline expressions to build log paths *)
let pipeline_build_logs : ((string * expr) list, string) Hashtbl.t = Hashtbl.create 10

(** When true, build_pipeline/populate_pipeline skip Nix builds.
    Set by `t check` so structural validation runs without triggering builds. *)
let check_mode = ref false

(** When true, build_pipeline streams NDJSON events to stdout instead of
    human-readable output to stderr.  Set by `t run --json`. *)
let ndjson_mode = ref false

(** Convert a value (single path or list of paths) to a string list. *)
let rec options_value_to_strings = function
  | VString s -> [s]
  | VSymbol s -> [s]
  | VList items -> List.filter_map (fun (_, v) -> 
      match options_value_to_strings v with [s] -> Some s | _ -> None
    ) items
  | _ -> []

(** Convert a value (single path or list of paths) to an expr list,
    suitable for merging into un_functions / un_includes. *)
let options_value_to_expr_list v =
  List.map (fun s -> mk_expr (Value (VString s))) (options_value_to_strings v)

(** Extract identifier-like tokens from a raw code string.
    Used by RawCode blocks for automatic pipeline dependency detection.
    Scans for [a-zA-Z_][a-zA-Z0-9_]* patterns and returns unique results.

    Comment- and string-aware: a cross-node reference only resolves when it
    appears as a bare executable identifier (it binds to the generated
    `dep_<name>` variable), so identifiers inside `'...'`/`"..."` string
    literals (backslash escapes honoured) and `#` comments can never be
    working dependencies and are excluded — with one deliberate exception:
    `read_node("name")` / `read_node('name')` literals ARE working references
    (the Quarto emitter rewrites them to store paths via sed), so the names
    they mention are always included. Whole-line `--` comments are also
    dropped for compatibility; trailing `--` is kept because R uses `--x`
    as double negation. `#!` shebang lines are kept as code. *)
type raw_lang = RLang | PythonLang | JuliaLang | ShLang | OtherLang

let lang_of_runtime = function
  | "R" -> RLang
  | "Python" -> PythonLang
  | "Julia" -> JuliaLang
  | "sh" -> ShLang
  | _ -> OtherLang

(* Reserved words that never end an expression: a quote directly after
   one opens a literal (return 'x'), never a transpose. Value-capable
   words (end, true, false) and contextual ones (outer, type) are
   deliberately absent: they can end an expression. If Julia gains
   reserved words, add them here; the Julia manual keeps the full
   reserved-words list. *)
let julia_hard_keywords =
  [ "baremodule"; "begin"; "break"; "catch"; "const"; "continue"; "do";
    "else"; "elseif"; "export"; "for"; "function"; "global"; "if";
    "import"; "in"; "isa"; "let"; "local"; "macro"; "module"; "mutable";
    "new"; "primitive"; "quote"; "return"; "struct"; "using"; "while";
    "try"; "finally" ]

let strip_noncode_spans ?(lang : raw_lang option = None) text =
  let n = String.length text in
  let buf = Buffer.create n in
  let line_start i =
    (* True when position [i] begins a line (modulo leading whitespace,
       which the whole-line `--` check below handles on the raw line). *)
    let rec back j =
      if j < 0 then true
      else match text.[j] with
        | '\n' -> true
        | ' ' | '\t' | '\r' -> back (j - 1)
        | _ -> false
    in
    back (i - 1)
  in
  let interp = match lang with Some ShLang | Some JuliaLang -> true | _ -> false in
  let pyf = lang = Some PythonLang in
  let julia = lang = Some JuliaLang in
  let is_name_start c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
  in
  let is_name_char c = is_name_start c || (c >= '0' && c <= '9') in
  (* Julia single-quote end: transpose after an expression-ending
     character, as in `A'`, `A''`, `f(x)'` or `(A')'`; otherwise a char
     literal opens, including after hard keywords that never end an
     expression (`return 'x'`). Non-ASCII bytes transpose (Unicode
     identifiers). Only clear literal shapes blank; ambiguity stays
     visible. Julia has no triple-single-quoted strings. Known gap:
     byte ranges cannot separate Unicode letters from Unicode operators,
     so a literal right after a Unicode operator reads as transpose;
     that spot needs a quote or hash literal to matter, which is rare.
     Fixing it means decoding the previous UTF-8 character and checking
     a small operator set. *)
  let julia_squote_end i =
    let is_word_byte c =
      match c with
      | 'a'..'z' | 'A'..'Z' | '_' | '0'..'9' | '\x80'..'\xFF' -> true
      | _ -> false
    in
    let rec prev_pos j =
      if j < 0 then None
      else match text.[j] with
      | ' ' | '\t' | '\r' -> prev_pos (j - 1)
      | '\n' -> None
      | _ -> Some j
    in
    let transpose_prev =
      match prev_pos (i - 1) with
      | None -> false
      | Some j ->
          (match text.[j] with
           | ']' | ')' | '"' | '\'' | '.' -> true
           | c when is_word_byte c ->
               let rec start k =
                 if k < 0 then 0
                 else if is_word_byte text.[k] then start (k - 1)
                 else k + 1
               in
               let w = String.sub text (start j) (j - start j + 1) in
               not (List.mem w julia_hard_keywords)
           | _ -> false)
    in
    if transpose_prev then `Transpose
    else if i + 2 < n && text.[i + 1] <> '\\' && text.[i + 1] <> '\n' && text.[i + 2] = '\'' then
      `String (i + 3)
    else if i + 1 < n && text.[i + 1] = '\\' then
      let j = i + 2 in
      if j < n && text.[j] <> '\n' then
        let k =
          if text.[j] = 'u' || text.[j] = 'U' then
            let digits = if text.[j] = 'u' then 4 else 8 in
            let t = ref (j + 1) in
            while !t < n && !t < j + 1 + digits
                  && (match text.[!t] with '0'..'9' | 'a'..'f' | 'A'..'F' -> true | _ -> false) do
              incr t
            done;
            (* Short escapes are invalid Julia: stay visible (fail loud). *)
            if !t = j + 1 + digits then !t else -1
          else j + 1
        in
        if k >= 0 && k < n && text.[k] = '\'' then `String (k + 1) else `Transpose
      else `Transpose
    else
      (* Malformed open: legacy fallback, blank to the next quote. Only
         reachable on invalid Julia. *)
      let rec loop k =
        if k >= n then n
        else if text.[k] = '\\' then loop (k + 2)
        else if text.[k] = '\'' then k + 1
        else loop (k + 1)
      in
      `String (loop (i + 1))
  in
  (* End index (exclusive) past a balanced opener at [j], honouring
     nested quotes, backticks and backslash escapes. Returns [n] when
     unbalanced. *)
  let balanced_end ?(julia=false) open_c close_c j =
    let rec skip_quoted q k =
      if k >= n then n
      else if text.[k] = '\\' then skip_quoted q (k + 2)
      else if text.[k] = q then k + 1
      else skip_quoted q (k + 1)
    in
    let rec loop k d =
      if k >= n then n
      else if text.[k] = '\\' then loop (k + 2) d
      else if julia && text.[k] = '\'' then
        (match julia_squote_end k with
         | `String e -> loop e d
         | `Transpose -> loop (k + 1) d)
      else if text.[k] = '\'' || text.[k] = '"' || text.[k] = '`' then
        loop (skip_quoted text.[k] (k + 1)) d
      else if text.[k] = open_c then loop (k + 1) (d + 1)
      else if text.[k] = close_c then
        if d = 0 then k + 1 else loop (k + 1) (d - 1)
      else loop (k + 1) d
    in
    loop j 0
  in
  (* End index (exclusive) past the closing unescaped backtick from [j]. *)
  let backtick_end j =
    let rec loop k =
      if k >= n then n
      else if text.[k] = '\\' then loop (k + 2)
      else if text.[k] = '`' then k + 1
      else loop (k + 1)
    in
    loop j
  in
  (* Python f-string prefix: identifier chars from [rRbBuUfF] immediately
     before the quote, containing f/F, and not part of a longer name.
     Any identifier abutting a string literal is a prefix in valid
     Python, so this is exact, not heuristic. *)
  let is_fstring_prefix i =
    let rec back k acc =
      if k < 0 then (acc, k)
      else match text.[k] with
        | 'r' | 'R' | 'b' | 'B' | 'u' | 'U' | 'f' | 'F' -> back (k - 1) (text.[k] :: acc)
        | _ -> (acc, k)
    in
    let (run, k) = back (i - 1) [] in
    run <> [] && List.exists (fun c -> c = 'f' || c = 'F') run
    && (k < 0 || (let c = text.[k] in not (is_name_char c || c = '.' || c = '\'' || c = '"')))
  in
  let is_triple i q = i + 2 < n && text.[i + 1] = q && text.[i + 2] = q in
  let rec scan i in_str =
    if i >= n then ()
    else match in_str with
    | Some q ->
        (match text.[i] with
         | '\\' ->
             (* Escape: blank out backslash and escaped char, stay in string. *)
             Buffer.add_string buf "  ";
             scan (i + 2) in_str
         | c when c = q ->
             Buffer.add_char buf ' ';
             scan (i + 1) None
         | _ ->
             Buffer.add_char buf ' ';
             scan (i + 1) in_str)
    | None ->
        (match text.[i] with
         | '"' when interp ->
             (* Double quotes interpolate `$name`, `${...}`, `$(...)`
                and backticks (shell) / `$name`, `$(...)` (Julia): keep
                those spans readable, blank the rest. Single quotes never
                interpolate. Triple-quoted Julia strings take the same
                rule with a triple closer. *)
             if i + 2 < n && text.[i + 1] = '"' && text.[i + 2] = '"' then begin
               Buffer.add_string buf "   ";
               scan_interp (i + 3) true
             end else begin
               Buffer.add_char buf ' ';
               scan_interp (i + 1) false
             end
         | ('\'' | '"' as q) when pyf && is_fstring_prefix i ->
             (* Python f-string: `{...}` interpolates (balanced, with
                `{{`/`}}` as literal braces); everything else blanks. *)
             if is_triple i q then begin
               Buffer.add_string buf "   ";
               scan_fstring (i + 3) true q
             end else begin
               Buffer.add_char buf ' ';
               scan_fstring (i + 1) false q
             end
         | '\'' when julia ->
             (* Julia `'` is the transpose operator unless it opens a char
                literal here: a bare transpose must not blank the rest of
                the block and drop dependency reads. *)
             (match julia_squote_end i with
              | `String e ->
                  Buffer.add_string buf (String.make (e - i) ' ');
                  scan e None
              | `Transpose ->
                  Buffer.add_char buf '\'';
                  scan (i + 1) None)
         | '\'' | '"' as q ->
             Buffer.add_char buf ' ';
             scan (i + 1) (Some q)
         | '#' ->
             if i + 1 < n && text.[i + 1] = '!' && line_start i then begin
               (* Shebang line: keep the rest of the line as code. *)
               Buffer.add_char buf '#';
               scan (i + 1) None
             end else begin
               (* Comment: blank to end of line. *)
               let j = ref i in
               while !j < n && text.[!j] <> '\n' do
                 Buffer.add_char buf ' ';
                 incr j
               done;
               scan !j None
             end
         | c ->
             Buffer.add_char buf c;
             scan (i + 1) None)
  and scan_interp i triple =
    if i >= n then ()
    else match text.[i] with
    | '\\' ->
        Buffer.add_string buf "  ";
        scan_interp (i + 2) triple
    | '"' ->
        if triple && i + 2 < n && text.[i + 1] = '"' && text.[i + 2] = '"' then begin
          Buffer.add_string buf "   ";
          scan (i + 3) None
        end else if not triple then begin
          Buffer.add_char buf ' ';
          scan (i + 1) None
        end else begin
          Buffer.add_char buf ' ';
          scan_interp (i + 1) triple
        end
    | '$' ->
        let j = i + 1 in
        if j < n && text.[j] = '(' then
          let e = balanced_end ~julia '(' ')' (j + 1) in
          Buffer.add_substring buf text i (e - i);
          scan_interp e triple
        else if j < n && text.[j] = '{' && not julia then begin
          Buffer.add_char buf '$';
          let k = ref (j + 1) in
          if !k < n && is_name_start text.[!k] then begin
            while !k < n && is_name_char text.[!k] do
              Buffer.add_char buf text.[!k]; incr k
            done
          end;
          scan_interp !k triple
        end else if j < n && is_name_start text.[j] then begin
          Buffer.add_char buf '$';
          let k = ref j in
          while !k < n && is_name_char text.[!k] do
            Buffer.add_char buf text.[!k]; incr k
          done;
          scan_interp !k triple
        end else begin
          Buffer.add_char buf ' ';
          scan_interp (i + 1) triple
        end
    | '`' ->
        let e = backtick_end (i + 1) in
        Buffer.add_substring buf text i (e - i);
        scan_interp e triple
    | _ ->
        Buffer.add_char buf ' ';
        scan_interp (i + 1) triple
  and scan_fstring i triple q =
    (* Inside a Python f-string: `{...}` interpolates (balanced spans stay
       readable, with `{{`/`}}` as literal braces); everything else blanks,
       including the closing quote, which returns to code scanning. *)
    if i >= n then ()
    else if triple && i + 2 < n && text.[i] = q && text.[i + 1] = q && text.[i + 2] = q then begin
      Buffer.add_string buf "   ";
      scan (i + 3) None
    end else match text.[i] with
    | '\\' ->
        Buffer.add_string buf "  ";
        scan_fstring (i + 2) triple q
    | c when c = q ->
        Buffer.add_char buf ' ';
        scan (i + 1) None
    | '{' ->
        if i + 1 < n && text.[i + 1] = '{' then begin
          Buffer.add_string buf "  ";
          scan_fstring (i + 2) triple q
        end else begin
          let e = balanced_end '{' '}' i in
          Buffer.add_substring buf text i (e - i);
          scan_fstring e triple q
        end
    | _ ->
        Buffer.add_char buf ' ';
        scan_fstring (i + 1) triple q
  in
  scan 0 None;
  Buffer.contents buf

(* Split of extract_identifiers for dependency scoping (see below). *)
let extract_identifiers_parts ?(lang : raw_lang option = None) text =
  (* Whole-line `--` comments are dropped before scanning (as before), so a
     stray quote inside them cannot open a phantom string span. Trailing `--`
     is intentionally kept: R uses `--x` as double negation. *)
  let code_lines =
    String.split_on_char '\n' text
    |> List.filter_map (fun line ->
        if String.starts_with ~prefix:"--" (String.trim line) then None
        else Some line)
    |> String.concat "\n"
  in
  let filtered_text = strip_noncode_spans ~lang code_lines in
  let re = Str.regexp {|[a-zA-Z_][a-zA-Z0-9_]*|} in
  let rec find acc pos =
    match (try Some (Str.search_forward re filtered_text pos) with Not_found -> None) with
    | None -> List.rev acc
    | Some _ ->
        let word = Str.matched_string filtered_text in
        let next_pos = Str.match_end () in
        find (word :: acc) next_pos
  in
  let inferred = find [] 0 in
  (* `read_node("name")` literals are rewritten to store paths by the Quarto
     emitter, so they are genuine references even though they sit inside
     strings (which are otherwise skipped above). Mirror the emitter's two
     spellings, tolerating surrounding whitespace. Whitespace classes use
     plain double-quoted strings so \t stays a genuine tab. *)
  let read_node_names =
    let re_rn = Str.regexp "read_node[ \t]*([ \t]*\"\\([a-zA-Z_][a-zA-Z0-9_]*\\)\"[ \t]*)" in
    let re_rn_sq = Str.regexp "read_node[ \t]*([ \t]*'\\([a-zA-Z_][a-zA-Z0-9_]*\\)'[ \t]*)" in
    let collect re =
      let rec loop acc pos =
        match (try Some (Str.search_forward re text pos) with Not_found -> None) with
        | None -> acc
        | Some _ ->
            let name =
              try Str.matched_group 1 text with Not_found | Invalid_argument _ -> ""
            in
            loop (name :: acc) (Str.match_end ())
      in
      loop [] 0
    in
    List.filter (fun s -> s <> "") (collect re_rn @ collect re_rn_sq)
  in
  (inferred, read_node_names)

(** Identifiers from executable code only (strings, comments and read_node
    literals excluded). Local bindings (below) are subtracted from exactly
    this set. *)
let extract_code_identifiers ?(lang : raw_lang option = None) text =
  fst (extract_identifiers_parts ~lang text)

(** Names mentioned inside read_node("name") literals. These are genuine
    references even though they sit inside strings. *)
let extract_read_node_names text =
  snd (extract_identifiers_parts text)

let extract_identifiers ?(lang : raw_lang option = None) text =
  let (inferred, read_node_names) = extract_identifiers_parts ~lang text in
  let all_set = List.fold_left (fun acc d -> String_set.add d acc) String_set.empty (inferred @ read_node_names) in
  String_set.elements all_set

(** A binding spotted by the raw-block scan: name, position of the name,
    and span of its right-hand side (for `->` the span precedes the name).
    The filter in [extract_shadowed_locals] uses these to keep the edge
    whenever the name is read before it is bound or inside its own
    right-hand side (e.g. `x <- x + 1`). *)
type raw_binding = { b_name : string; b_pos : int; b_rhs_start : int; b_rhs_end : int }

(** Bindings spotted in a raw block, for dependency scoping.
    Dependency inference subtracts only *pure shadows* (see
    [extract_shadowed_locals]): a foreign local that merely shares a
    sibling name cannot wire a phantom edge (which could surface as a
    false dependency cycle), while a name read before its binding or
    inside its own right-hand side (`x <- x + 1`, `df = df.dropna()`)
    keeps a real edge (dropping it would silently under-build).

    Certain-only: a name counts as bound only for unambiguous statement
    forms at paren depth 0 (call keyword arguments live deeper), outside
    conditional regions. Anything doubtful keeps its dependency.

    Per runtime (all on text with strings/comments blanked, so positions
    below refer to real code):
    - R: `<-`, `<<-`, rightward `->`, and `=` (never `==`, `!=`, `<=`,
      `>=`; single `=` inside calls is a keyword argument and sits
      deeper). `->>` superassignment is out of scope.
      `for (i in ...)` binds `i`. Function bodies
      (`function(...) {...}`, `\(...) {...}`) are skipped: their locals
      are invisible outside, while their uses still count via
      extract_code_identifiers. `if`/`for`/`while`/`else`/`repeat` branch
      bodies are conditional regions.
    - Python: `=` and `:=` (same guards), `for i in`, `def`/`class` names.
      `def`/`class` suites are tracked by indent and skipped;
      `if`/`elif`/`else`/`for`/`while`/`except` suites are conditional
      regions. `try`/`finally`/`with` bodies count.
    - Julia: `=` (same guards) and `function`/`macro`/`struct`/`module`
      names, with an end-matched scope stack (`if`/`for`/`while`/`catch`
      nest as conditional frames; `begin`/`try`/`finally` nest without
      scoping). Loop variables are never bound: Julia `for` scopes them.
    - sh: statement-start `name=` with an adjacent `=` (so `echo x=1` does
      not count) and `for` names. `local`/`export`/`readonly`/`declare`
      targets never match (the name is not statement-first). `if`/`for`/
      `while`/`until`/`case` bodies and function bodies are conditional
      regions. `read`, `select`, and one-liner `if x=1` conditions are
      not tracked.

    Documented limitations (all fail safe toward keeping the edge):
    tuple unpacking, `import`/`from` bindings, shell `read`/`select`,
    multi-line `$(...)` self-reads in sh, one-line `def f(): x = 1`
    suites, R single-expression function bodies containing assignment,
    backquote command substitutions in sh, and mixed tabs/spaces
    confusing Python suite tracking (CPython rejects such files
    outright). *)

let scan_raw_bindings ~runtime text =
  (match lang_of_runtime runtime with
   | OtherLang -> (strip_noncode_spans text, [], [])
   | lang ->
       let stripped = strip_noncode_spans ~lang:(Some lang) text in
       let n = String.length stripped in
       let is_id_char c =
         (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
         || (c >= '0' && c <= '9') || c = '_'
       in
       let is_space c = c = ' ' || c = '\t' || c = '\r' in
       let skip_spaces i =
         let rec loop j = if j < n && is_space stripped.[j] then loop (j + 1) else j in
         loop i
       in
       let skip_spaces_back i =
         let rec loop j = if j >= 0 && is_space stripped.[j] then loop (j - 1) else j in
         loop i
       in
       let read_ident i =
         let rec loop j = if j < n && is_id_char stripped.[j] then loop (j + 1) else j in
         let e = loop i in
         (String.sub stripped i (e - i), e)
       in
       let is_word_at w i =
         let m = String.length w in
         i + m <= n && String.sub stripped i m = w
         && (i = 0 || not (is_id_char stripped.[i - 1]))
         && (i + m >= n || not (is_id_char stripped.[i + m]))
       in
       (* Paren depth before each position. R counts parens only (braces do
          not scope, except function bodies which are skipped explicitly);
          Python/Julia count all three pairs; sh counts parens (subshells
          hide bindings). Unbalanced fragments go negative and match
          nothing, which keeps dependencies (safe). *)
       let depth = Array.make (n + 1) 0 in
       let () =
         for i = 0 to n - 1 do
           let d = match stripped.[i], lang with
             | '(', (RLang | PythonLang | JuliaLang | ShLang) -> 1
             | '[', (PythonLang | JuliaLang) -> 1
             | '{', (PythonLang | JuliaLang) -> 1
             | ')', (RLang | PythonLang | JuliaLang | ShLang) -> -1
             | ']', (PythonLang | JuliaLang) -> -1
             | '}', (PythonLang | JuliaLang) -> -1
             | _ -> 0
           in
           depth.(i + 1) <- depth.(i) + d
         done
       in
       (* End of the statement starting at [k]: first `;` or newline at
          relative bracket depth 0, extended across lines while brackets
          are unbalanced or the line ends with a continuation operator
          (`x <-` + newline is one statement). Overlong spans fail safe
          (extra self-reads keep the edge); truncated ones would wrongly
          subtract, hence the continuation handling. *)
       let cont_op c = match c with
         | '+' | '-' | '*' | '/' | '^' | ':' | ',' | '<' | '>' | '='
         | '!' | '&' | '|' | '?' | '~' | '$' | '@' | '%' | '.' -> true
         | _ -> false
       in
       let stmt_end_from k =
         let rec loop j d seg =
           if j >= n then n
           else match stripped.[j] with
           | '(' | '[' | '{' -> loop (j + 1) (d + 1) seg
           | ')' | ']' | '}' -> loop (j + 1) (d - 1) seg
           | '\\' when j + 1 < n && stripped.[j + 1] = '\n' -> loop (j + 2) d seg
           | ';' when d = 0 -> j
           | '&' | '|' as c when d = 0 ->
               if j + 1 < n && stripped.[j + 1] = c then loop (j + 1) d seg
               else j
           | '\n' when d = 0 ->
               let rec last p =
                 if p < seg then None
                 else if is_space stripped.[p] || stripped.[p] = '\r' then last (p - 1)
                 else Some stripped.[p]
               in
               (match last (j - 1) with
                | None -> loop (j + 1) d (j + 1)
                | Some c when cont_op c -> loop (j + 1) d (j + 1)
                | _ -> j)
           | _ -> loop (j + 1) d seg
         in
         loop k 0 k
       in
       (* Start of the statement containing [pos]: scan back past the
          current line/chunk to the previous terminator. Used for rightward
          (`->`) bindings whose right-hand side precedes the name. *)
       let stmt_start_back pos =
         let rec back j =
           if j < 0 then 0
           else match stripped.[j] with
           | '\n' | ';' | '{' | '}' -> j + 1
           | _ -> back (j - 1)
         in
         back (pos - 1)
       in
       (* A binding name is never a member access (`obj.x`, `df$col`) and
          never starts with a digit. Applies to every rule below. *)
       let member_guarded pos =
         pos <= 0
         || (let c = stripped.[pos - 1] in c <> '.' && c <> '$' && c <> '@')
       in
       let is_name_start pos =
         let c = stripped.[pos] in
         (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
       in
       (* R: skip `{...}` bodies of function definitions; their locals are
          invisible outside while their uses still count elsewhere. *)
       let skip_until = ref 0 in
       let skip_balanced open_c close_c i =
         (* [i] is just after an unmatched [open_c]; start one level deep
            so the first [close_c] at that level ends the span. *)
         let rec loop j level =
           if j >= n then n
           else if stripped.[j] = open_c then loop (j + 1) (level + 1)
           else if stripped.[j] = close_c then
             if level = 1 then j + 1 else loop (j + 1) (level - 1)
           else loop (j + 1) level
         in
         loop i 1
       in
       let skip_r_function_body i =
         (* i at `function` or `\(`: skip params, then a braced body if any. *)
         let j = skip_spaces (i + if stripped.[i] = '\\' then 2 else 8) in
         if j < n && stripped.[j] = '(' then begin
           let k = skip_balanced '(' ')' (j + 1) in
           let k = skip_spaces k in
           if k < n && stripped.[k] = '{' then skip_balanced '{' '}' (k + 1) else k
         end else j
       in
       let skip_spaces_nl i =
         let rec loop j =
           if j < n && (is_space stripped.[j] || stripped.[j] = '\n') then loop (j + 1) else j
         in
         loop i
       in
       (* Statement starts in shell: line starts and separators. Factored
          out for use by both the region precompute below and the main
          scan (`then x=1` is valid shell; backquotes are excluded since
          command substitutions do not leak bindings). *)
       let sh_stmt_start pos =
         let rec back j =
           if j < 0 then true
           else match stripped.[j] with
             | '\n' | ';' | '(' | '{' | '}' | '!' -> true
             (* Lone `|` pipes the element into a subshell, so an
                assignment there never persists (`||` still separates
                statements). `|&` (pipe stderr) likewise. A lone `&`
                backgrounds the previous job but the next statement runs
                in the current shell, so it still starts one. *)
             | '&' -> not (j > 0 && stripped.[j - 1] = '|')
             | '|' -> j > 0 && stripped.[j - 1] = '|'
             | ' ' | '\t' | '\r' -> back (j - 1)
             | _ ->
                 let rec wstart k =
                   if k >= 0 && is_id_char stripped.[k] then wstart (k - 1) else k + 1
                 in
                 let ws = wstart j in
                 let w = String.sub stripped ws (j - ws + 1) in
                 w = "then" || w = "do" || w = "else" || w = "elif"
         in
         back (pos - 1)
       in
       (* Bindings inside these spans are conditional (branch bodies,
          loop bodies, function bodies): they may never execute, so they
          cannot shadow a sibling. Recorded bindings exclude them, keeping
          the edge. Regions may overlap or nest; membership is what
          matters. *)
       let cond_regions =
         let regs = ref [] in
         let add_region s e = if e > s then regs := (s, e) :: !regs in
         let rec whole_words j =
           if j >= n then ()
           else if not (is_id_char stripped.[j]) then whole_words (j + 1)
           else if j > 0 && is_id_char stripped.[j - 1] then
             let rec skip k = if k < n && is_id_char stripped.[k] then skip (k + 1) else k in
             whole_words (skip j)
           else
             let (w, e) = read_ident j in
             (match lang with
              | RLang when w = "if" || w = "for" || w = "while" ->
                  let q = skip_spaces e in
                  if q < n && stripped.[q] = '(' then begin
                    let k = skip_balanced '(' ')' (q + 1) in
                    let k2 = skip_spaces_nl k in
                    if k2 < n && stripped.[k2] = '{' then
                      add_region k2 (skip_balanced '{' '}' (k2 + 1))
                    else
                      add_region k2 (stmt_end_from k2)
                  end else
                    add_region e (stmt_end_from e);
                  whole_words e
              | RLang when w = "else" || w = "repeat" ->
                  let q = skip_spaces_nl e in
                  if q < n && stripped.[q] = '{' then
                    add_region q (skip_balanced '{' '}' (q + 1))
                  else
                    add_region q (stmt_end_from q);
                  whole_words e
              | _ -> whole_words e)
         in
         (match lang with
          | RLang -> whole_words 0
          | ShLang ->
              (* Branch and function regions via a small stack machine over
                 statement-start keywords. Regions start *after* the header
                 (`do`/`then`), so loop variables in the header itself stay
                 visible. Mismatched closers pop with a region
                 (over-exclusion fails safe); unclosed openers run to end
                 of text. *)
              let stack = ref [] in
              let push closer o = stack := (closer, o, ref None) :: !stack in
              let set_start e =
                (match !stack with
                 | (_, _, r) :: _ when !r = None -> r := Some e
                 | _ -> ())
              in
              let pop_to e =
                (match !stack with
                 | (_, o, r) :: rest ->
                     (* Matched or not, the opener's span is conditional
                        territory; over-exclusion fails safe. *)
                     stack := rest;
                     add_region (match !r with Some s -> s | None -> o) e
                 | [] -> ())
              in
              let rec scan j =
                if j >= n then ()
                else if not (is_id_char stripped.[j]) then scan (j + 1)
                else if j > 0 && is_id_char stripped.[j - 1] then
                  let rec skip k = if k < n && is_id_char stripped.[k] then skip (k + 1) else k in
                  scan (skip j)
                else
                  let (w, e) = read_ident j in
                  let at_start = sh_stmt_start j in
                  (if at_start && depth.(j) = 0 then
                     match w with
                     | "if" -> push "fi" j
                     | "for" | "while" | "until" | "select" -> push "done" j
                     | "case" -> push "esac" j
                     | "fi" | "done" | "esac" -> pop_to e
                     | "do" | "then" -> set_start e
                     | "function" ->
                         let q = skip_spaces e in
                         let q = if q < n && is_name_start q then (snd (read_ident q)) else q in
                         let q = skip_spaces q in
                         let q = if q < n && stripped.[q] = '(' then skip_balanced '(' ')' (q + 1) else q in
                         let q = skip_spaces q in
                         if q < n && stripped.[q] = '{' then
                           add_region q (skip_balanced '{' '}' (q + 1))
                     | _ ->
                         (* name() { ... } function form *)
                         let q = skip_spaces e in
                         if q < n && stripped.[q] = '(' then begin
                           let qc = skip_balanced '(' ')' (q + 1) in
                           let q2 = skip_spaces qc in
                           if q2 < n && stripped.[q2] = '{' then
                             add_region q2 (skip_balanced '{' '}' (q2 + 1))
                         end
                   else if depth.(j) = 0 then
                     (* `do`/`then` off statement-start (e.g. after `;`). *)
                     (match w with "do" | "then" -> set_start e | _ -> ()));
                  scan e
              in
              scan 0;
              List.iter (fun (_, o, r) -> add_region (match !r with Some s -> s | None -> o) n) !stack
          | _ -> ());
         !regs
       in
       let in_cond_region p =
         List.exists (fun (s, e) -> s <= p && p < e) cond_regions
       in
       (* Same-line control-flow guard: a binding preceded on its statement
          by a complete branch header or a short-circuit operator is
          conditional (`if (flag) src <- 99`, `cond && x=1`). Headers must
          be *complete* before the binding (closed parens for R
          `if`/`for`/`while`, header colon for Python, `;` for Julia,
          `then`/`do`/`;`/`)` for shell): a keyword whose header cannot
          close yet (`if (y := ...)` — the walrus lives *inside* the
          condition and binds unconditionally) does not guard. Loop
          variables bypass the `for` member (the `for` introduces them).
          A `;`/newline at depth 0 resets the statement, so later
          statements on the line are unaffected. Multi-line branches are
          covered by regions/stacks instead; this guard is their same-line
          complement plus the operator cases regions cannot see. *)
       let line_guarded ~include_for bpos =
         (* A newline preceded (outside quotes, which are already blanked)
            by `&&`, `||`, `|` or `\` continues the statement (multiline
            lists and pipelines). A lone `&` still terminates, since
            background ends the statement. *)
         let nl_continues j =
           let rec back k =
             if k < 0 then None
             else match stripped.[k] with
               | ' ' | '\t' | '\r' -> back (k - 1)
               | '\\' | '|' -> Some true
               | '&' ->
                   let rec back2 k2 =
                     if k2 < 0 then false
                     else match stripped.[k2] with
                       | ' ' | '\t' | '\r' -> back2 (k2 - 1)
                       | '&' -> true
                       | _ -> false
                   in
                   Some (back2 (k - 1))
               | _ -> Some false
           in
           back (j - 1) = Some true
         in
         let rec line_start j =
           if j < 0 then 0
           else if stripped.[j] = '\n' && not (nl_continues j) then j + 1
           else line_start (j - 1)
         in
         let ls = line_start (bpos - 1) in
         (* Last statement terminator before [bpos]; only triggers after
            it count. `&&`/`||` guard but never reset. Continued newlines
            (see nl_continues) do not terminate either, so operators on
            the previous line still guard. *)
         let rec last_term j acc =
           if j >= bpos then acc
           else if stripped.[j] = ';' && depth.(j) = 0 then
             last_term (j + 1) (Some j)
           else if stripped.[j] = '\n' && depth.(j) = 0 && not (nl_continues j) then
             last_term (j + 1) (Some j)
           else last_term (j + 1) acc
         in
         let from = match last_term ls None with Some t -> t + 1 | None -> ls in
         let kws = ["if"; "elif"; "else"; "elseif"; "while"; "until"; "unless";
                    "then"; "do"; "case"; "and"; "or"]
                   @ (if include_for then ["for"] else []) in
         let header_complete w e =
           match lang with
           | RLang ->
               (match w with
                | "if" | "for" | "while" ->
                    let q = skip_spaces e in
                    q < bpos && stripped.[q] = '('
                    && skip_balanced '(' ')' (q + 1) <= bpos
                | _ -> true)
           | PythonLang ->
               (match w with
                | "if" | "elif" | "else" | "for" | "while" | "except" ->
                    let rec colon k =
                      if k >= bpos then false
                      else if stripped.[k] = ':' && depth.(k) = depth.(e) then true
                      else colon (k + 1)
                    in
                    colon e
                | _ -> true)
           | JuliaLang ->
               (match w with
                | "if" | "elseif" | "while" | "for" ->
                    let rec semi k =
                      if k >= bpos then false
                      else if stripped.[k] = ';' && depth.(k) = 0 then true
                      else semi (k + 1)
                    in
                    semi e
                | _ -> true)
           | ShLang ->
               (match w with
                | "if" | "while" | "until" | "for" | "case" | "select" ->
                    let rec closer k =
                      if k >= bpos then false
                      else if depth.(k) <> 0 then closer (k + 1)
                      else
                        let (ww, ee) =
                          if is_id_char stripped.[k]
                             && (k = 0 || not (is_id_char stripped.[k - 1])) then
                            read_ident k
                          else ("", k + 1)
                        in
                        if ww = "then" || ww = "do" then true
                        else if stripped.[k] = ';' || stripped.[k] = ')' then true
                        else closer ee
                    in
                    closer e
                | _ -> true)
           | OtherLang -> true
         in
         let rec scan j =
           if j >= bpos then false
           else if not (is_id_char stripped.[j]) then
             if ((stripped.[j] = '&' && j + 1 < bpos && stripped.[j + 1] = '&')
                 || (stripped.[j] = '|' && j + 1 < bpos && stripped.[j + 1] = '|'))
                && depth.(j) = 0 then true
             else scan (j + 1)
           else if j > from && is_id_char stripped.[j - 1] then
             let rec skip k = if k < bpos && is_id_char stripped.[k] then skip (k + 1) else k in
             scan (skip j)
           else
             let (w, e) = read_ident j in
             if List.mem w kws && depth.(j) = 0 && header_complete w e then true
             else scan e
         in
         scan from
       in
       let found = ref [] in
       (* Every syntactic binder spotted, including conditional ones that
          [record] below filters out: binder positions must never be
          substituted (see [dep_substitution_spans]), even when the
          binding itself is conditional. *)
       let all_binders = ref [] in
       let record ?(is_loopvar=false) name bpos rs re =
         if name = "" then ()
         else begin
           all_binders := (name, bpos) :: !all_binders;
           if in_cond_region bpos then ()
           else if line_guarded ~include_for:(not is_loopvar) bpos then ()
           else found := { b_name = name; b_pos = bpos; b_rhs_start = rs; b_rhs_end = re } :: !found
         end
       in
       (* Python suite tracking is line-oriented and lives inside scan_python
          below. *)
       (* Julia: end-matched scope stack of (scoping, conditional, depth).
          Only function/macro/struct/module/let/quote/do scope; if/for/
          while/try/catch/finally bodies are conditional (may never
          execute); only begin bodies count. *)
       let jl_stack = ref [] in
       let jl_in_scope () = List.exists (fun (_, s, _, _) -> s) !jl_stack in
       let jl_in_cond () = List.exists (fun (_, _, c, _) -> c) !jl_stack in
       (* Python suite maps: per-position flags for lines inside a def/class
          suite (function-locals, invisible outside) or a conditional suite
          (`if`/`elif`/`else`/`for`/`while`/`except`: may never execute).
          `try`/`finally`/`with` bodies count. Computed up front by walking
          line indents; blank lines never pop. Only meaningful when
          lang = PythonLang. *)
       let py_skip, py_cond =
         let skip = Array.make n false and cond = Array.make n false in
         let () =
           if lang = PythonLang then begin
             let lines = ref [] in
             let ls = ref 0 in
             for i = 0 to n do
               if i = n || stripped.[i] = '\n' then begin
                 lines := (!ls, i) :: !lines;
                 ls := i + 1
               end
             done;
             let suites = ref [] and csuites = ref [] in
             let defnames = ref [] in
             List.iter (fun (s, e) ->
               let ind = ref s in
               while !ind < e && (stripped.[!ind] = ' ' || stripped.[!ind] = '\t') do
                 incr ind
               done;
               if !ind < e then begin
                 while !suites <> [] && !ind <= List.hd !suites do
                   suites := List.tl !suites
                 done;
                 while !csuites <> [] && !ind <= List.hd !csuites do
                   csuites := List.tl !csuites
                 done;
                 let j0 = ref !ind in
                 if is_word_at "async" !j0 then
                   j0 := skip_spaces (!j0 + 5);
                 let word_at =
                   let (w, _) = read_ident !j0 in w
                 in
                 let is_def =
                   (word_at = "def" || word_at = "class")
                   && !j0 + 3 < n
                 in
                 let is_cond =
                   List.mem word_at ["if"; "elif"; "else"; "for"; "while"; "except"]
                 in
                 if is_def then begin
                   let kwlen = if word_at = "def" then 3 else 5 in
                   let j = skip_spaces (!j0 + kwlen) in
                   if j < e && is_name_start j then begin
                     let (nm, e2) = read_ident j in
                     if !suites = [] && !csuites = [] then
                       defnames := (nm, j, e2) :: !defnames;
                     suites := !ind :: !suites;
                     for k = e2 to e - 1 do skip.(k) <- true done
                   end else
                     suites := !ind :: !suites
                 end else if is_cond then begin
                   (* One-liner tail after the header colon is conditional
                      too (`if c: x = 1`); the colon is the first `:` at
                      the header's own depth. *)
                   let rec find_colon k =
                     if k >= e then e
                     else if stripped.[k] = ':' && depth.(k) = depth.(!ind) then k
                     else find_colon (k + 1)
                   in
                   let c = find_colon !ind in
                   for k = (if c < e then c else s) to e - 1 do cond.(k) <- true done;
                   csuites := !ind :: !csuites
                 end else begin
                   if !suites <> [] then
                     for k = s to e - 1 do skip.(k) <- true done;
                   if !csuites <> [] then
                     for k = s to e - 1 do cond.(k) <- true done
                 end
               end
             ) (List.rev !lines);
             List.iter (fun (nm, j, e2) -> record nm j e2 e2) !defnames
           end
         in
         (skip, cond)
       in
       let i = ref 0 in
       (* Shell assignment persistence, decided on the ORIGINAL text
          (quotes intact: stripping blanks them, so `"a b"` would look
          like several tokens there). From just after `=`:
          - quoted spans, `$(...)`, backticks, `${...}` and `\x` escapes
            belong to the current word; `(` at value start opens an
            array assignment (balanced);
          - a word boundary ends the value;
          - end of input, `;`, newline, `#`-comment, `&`, `|` end the
            statement: the chain persists;
          - a `NAME=` word at a boundary continues the chain (recorded);
          - any other word is a command: the chain is a prefix only.
          Unbalanced constructs fail safe to prefix (edge kept).
          Returns the chain (outer first) when it persists, else None:
          `FOO=1 cmd` binds nothing, `A=1 B=2` binds both, `x=$(date)`
          binds, `FOO="a b" cmd` binds nothing, `x="a b"` binds. *)
       let tx_skip_quoted q j =
         let rec loop k =
           if k >= n then None
           else if text.[k] = '\\' then
             if k + 1 >= n then None else loop (k + 2)
           else if text.[k] = q then Some (k + 1)
           else loop (k + 1)
         in
         loop j
       in
       let rec tx_skip_balanced open_c close_c depth j =
         if j >= n then None
         else if text.[j] = '\\' then
           if j + 1 >= n then None
           else tx_skip_balanced open_c close_c depth (j + 2)
         else if text.[j] = '\'' || text.[j] = '"' then
           (match tx_skip_quoted text.[j] (j + 1) with
            | None -> None
            | Some e -> tx_skip_balanced open_c close_c depth e)
         else if text.[j] = '`' then
           (match tx_skip_quoted '`' (j + 1) with
            | None -> None
            | Some e -> tx_skip_balanced open_c close_c depth e)
         else if text.[j] = open_c then
           tx_skip_balanced open_c close_c (depth + 1) (j + 1)
         else if text.[j] = close_c then
           if depth = 0 then Some (j + 1)
           else tx_skip_balanced open_c close_c (depth - 1) (j + 1)
         else tx_skip_balanced open_c close_c depth (j + 1)
       in
       let tx_is_name_start c =
         (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
       in
       let tx_is_name_char c =
         tx_is_name_start c || (c >= '0' && c <= '9')
       in
       let tx_read_name j =
         let rec loop k =
           if k < n && tx_is_name_char text.[k] then loop (k + 1) else k
         in
         (String.sub text j (loop j - j), loop j)
       in
       (* Skip one shell word from [j]; returns the index just past it,
          or None on unbalanced constructs. *)
       let rec tx_skip_word j =
         if j >= n then Some j
         else match text.[j] with
         | ' ' | '\t' | '\r' | '\n' | ';' | '&' | '|' -> Some j
         | '\'' | '"' as q ->
             (match tx_skip_quoted q (j + 1) with
              | None -> None
              | Some e -> tx_skip_word e)
         | '`' ->
             (match tx_skip_quoted '`' (j + 1) with
              | None -> None
              | Some e -> tx_skip_word e)
         | '$' ->
             if j + 1 < n && text.[j + 1] = '(' then
               (match tx_skip_balanced '(' ')' 0 (j + 2) with
                | None -> None
                | Some e -> tx_skip_word e)
             else if j + 1 < n && text.[j + 1] = '{' then
               (match tx_skip_balanced '{' '}' 0 (j + 2) with
                | None -> None
                | Some e -> tx_skip_word e)
             else if j + 1 < n && tx_is_name_start text.[j + 1] then
               let (_, e) = tx_read_name (j + 1) in tx_skip_word e
             else tx_skip_word (j + 1)
         | '\\' ->
             if j + 1 >= n then Some (j + 1) else tx_skip_word (j + 2)
         | _ -> tx_skip_word (j + 1)
       in
       (* Skip blanks and line continuations; classify what follows:
          [`End] (statement over, a completed `&&`/`||`, or a `#`
          comment: the assignment already ran), [`BgPipe] (lone `&`/`|`
          runs in a background job or pipeline subshell: no persist),
          [`Word] (a word follows, including the `&>` redirect). *)
       let rec tx_skip_blanks j =
         if j >= n then `End
         else match text.[j] with
         | ' ' | '\t' | '\r' -> tx_skip_blanks (j + 1)
         | '\\' when j + 1 < n && text.[j + 1] = '\n' -> tx_skip_blanks (j + 2)
         | '\n' | ';' | '#' -> `End
         | '&' ->
             if j + 1 < n && text.[j + 1] = '&' then `End
             else if j + 1 < n && text.[j + 1] = '>' then `Word j
             else `BgPipe
         | '|' -> if j + 1 < n && text.[j + 1] = '|' then `End else `BgPipe
         | _ -> `Word j
       in
       (* Skip blanks, reporting whether any were skipped. *)
       let skip_blanks_nb j =
         let rec loop k blank =
           if k >= n then (k, blank)
           else match text.[k] with
           | ' ' | '\t' | '\r' -> loop (k + 1) true
           | '\\' when k + 1 < n && text.[k + 1] = '\n' -> loop (k + 2) true
           | _ -> (k, blank)
         in
         loop j false
       in
       (* Skip one I/O redirect starting at word [w]: optional fd digits,
          `<`/`>`/`>>`, then a target word. `<<` heredocs bail (None):
          bodies are out of scope, so the edge stays. `<(` consumes the
          balanced substitution as its own target. A bare `&` never
          reaches here (background). Returns the index past the target,
          or None when malformed. *)
       let rec tx_redirect w =
         let k = ref w in
         while !k < n && text.[!k] >= '0' && text.[!k] <= '9' do incr k done;
         if !k >= n then None
         else match text.[!k] with
         | '>' ->
             incr k;
             if !k < n && text.[!k] = '>' then incr k;
             tx_redirect_target !k
         | '<' ->
             if !k + 1 < n && text.[!k + 1] = '<' then None
             else if !k + 1 < n && text.[!k + 1] = '(' then
               tx_skip_balanced '(' ')' 0 (!k + 2)
             else begin
               incr k;
               tx_redirect_target !k
             end
         | '&' ->
             (* `&>` / `&>>` redirect stdout and stderr together. *)
             if !k + 1 < n && text.[!k + 1] = '>' then begin
               k := !k + 2;
               if !k < n && text.[!k] = '>' then incr k;
               tx_redirect_target !k
             end else None
         | _ -> None
       (* After a redirect operator: blanks, then one target word. A
          leading `&` starts an fd target (`>&2`, `>&-`) or a combined
          file (`>&log`); consume past it so the redirect is skipped
          whole. Anything else malformed bails (None): the edge stays. *)
       and tx_redirect_target k =
         let rec blanks t =
           if t >= n then None
           else match text.[t] with
           | ' ' | '\t' | '\r' -> blanks (t + 1)
           | '\\' when t + 1 < n && text.[t + 1] = '\n' -> blanks (t + 2)
           | '#' -> None
           | _ -> Some t
         in
         match blanks k with
         | None -> None
         | Some t ->
             if text.[t] = '&' then
               if t + 1 >= n then None
               else (match tx_skip_word (t + 1) with
                | Some e when e > t + 1 -> Some e
                | _ -> None)
             else tx_skip_word t
       (* Persistence from just past `=` (chain [acc], outer first).
          `(` abutting `=` opens an array assignment (balanced, then
          re-evaluate). Otherwise blanks decide: end persists (possibly
          empty value); a redirect skips to after its target; a
          blank-separated `NAME=` extends the chain; an abutting word
          (even `foo=bar`) is the value; anything else after a blank is
          a command (prefix only). *)
       and tx_after_eq acc j =
         if j < n && text.[j] = '(' then
           (match tx_skip_balanced '(' ')' 0 (j + 1) with
            | None -> None
            | Some e -> tx_after_value acc e)
         else
           let (b, blank) = skip_blanks_nb j in
           (match tx_skip_blanks b with
            | `End -> Some acc
            | `BgPipe -> None
            | `Word w ->
                (match tx_redirect w with
                 | Some e -> tx_after_value acc e
                 | None ->
                     if tx_is_name_start text.[w] then
                       let (nm, e) = tx_read_name w in
                       (* A chain link needs a blank before it: an abutting
                          `foo=bar` is the value (`x=foo=bar` binds only
                          `x`), while `x= A=1` extends the chain. *)
                       if blank && e < n && text.[e] = '=' && (e + 1 >= n || text.[e + 1] <> '=') then
                         tx_after_eq ((nm, w, e) :: acc) (e + 1)
                       else if blank then None
                       else
                         (match tx_skip_word w with
                          | None -> None
                          | Some e2 -> tx_after_value acc e2)
                     else if blank then None
                     else
                       (match tx_skip_word w with
                        | None -> None
                        | Some e2 -> tx_after_value acc e2)))
       (* Just past a value/array/redirect: blanks, then end (persists),
          a redirect (skip, re-evaluate), another `NAME=` (chain), or a
          command/subshell (prefix). `(` opens a subshell: prefix. *)
       and tx_after_value acc j =
         match tx_skip_blanks j with
         | `End -> Some acc
         | `BgPipe -> None
         | `Word w ->
             (match tx_redirect w with
              | Some e -> tx_after_value acc e
              | None ->
                  if text.[w] = '(' then None
                  else if tx_is_name_start text.[w] then
                    let (nm, e) = tx_read_name w in
                    if e < n && text.[e] = '=' && (e + 1 >= n || text.[e + 1] <> '=') then
                      tx_after_eq ((nm, w, e) :: acc) (e + 1)
                    else None
                  else None)
       in
       let sh_persists nm pos veq =
         match tx_after_eq [(nm, pos, veq)] (veq + 1) with
         | Some chain -> Some (List.rev chain)
         | None -> None
       in
       (* Record a whole chain with per-name right-hand spans. *)
       let record_chain chain =
         List.iter (fun (cnm, cpos, ceq) ->
           record cnm cpos (ceq + 1) (stmt_end_from (ceq + 1))) chain
       in
       (* A `{`/`(` granting statement start that is itself `$`-prefixed
          runs in a subshell (`$(...)`) or expands a parameter (`${...}`):
          assignments inside never persist in the current shell. *)
       let dollar_opener pos =
         let rec back j =
           if j < 0 then None
           else match stripped.[j] with
             | ' ' | '\t' | '\r' -> back (j - 1)
             | '{' | '(' as c ->
                 if j > 0 && stripped.[j - 1] = '$' then Some c else None
             | _ -> None
         in
         back (pos - 1)
       in
       while !i < n do
         let pos = !i in
         if pos < !skip_until then i := !skip_until
         else if lang = RLang && stripped.[pos] = '\\' && pos + 1 < n && stripped.[pos + 1] = '(' then
           (* R \(...) lambda: skip params and a braced body, like function. *)
           i := skip_r_function_body pos
         else if not (is_id_char stripped.[pos])
                 || (pos > 0 && is_id_char stripped.[pos - 1]) then
           incr i
         else begin
           let (word, epos) = read_ident pos in
           let advanced_to = ref epos in
           (match lang with
            | RLang ->
                if word = "function" then begin
                  skip_until := skip_r_function_body pos;
                  advanced_to := max epos !skip_until
                end else if word = "for" && depth.(pos) = 0 then begin
                  let j = skip_spaces epos in
                  if j < n && stripped.[j] = '(' then begin
                    let k = skip_spaces (j + 1) in
                    if k < n && is_name_start k then begin
                      let (nm, e2) = read_ident k in
                      let e3 = skip_spaces e2 in
                      if is_word_at "in" e3 then
                        record ~is_loopvar:true nm k j (skip_balanced '(' ')' (j + 1))
                    end
                  end
                end else if depth.(pos) = 0 && member_guarded pos && is_name_start pos then begin
                  let j = skip_spaces epos in
                  if j + 1 < n && stripped.[j] = '<' && stripped.[j + 1] = '-' then
                    record word pos (j + 2) (stmt_end_from (j + 2))
                  else if j < n && stripped.[j] = '=' then begin
                    (* `:` before the name means annotation (`x: int`) or
                       namespace (`pkg::fun`): never a binding target. The
                       `==`/`!=` cases are ruled out by [next_ok] below. *)
                    let prev_ok = pos = 0 || stripped.[pos - 1] <> ':' in
                    let next_ok = j + 1 >= n || (stripped.[j + 1] <> '=' && stripped.[j + 1] <> '>') in
                    if prev_ok && next_ok then record word pos (j + 1) (stmt_end_from (j + 1))
                  end else begin
                    let k = skip_spaces_back (pos - 1) in
                    if k >= 1 && stripped.[k] = '>' && stripped.[k - 1] = '-'
                       && (k - 2 < 0 || stripped.[k - 2] <> '-') then
                      record word pos (stmt_start_back pos) pos
                  end
                end
            | PythonLang ->
                if py_skip.(pos) || py_cond.(pos) then
                  ()
                else if word = "def" || word = "class" || word = "async" then
                  (* Owned by the suite precompute above; never a binding. *)
                  ()
                else if word = "lambda" then begin
                  (* Skip a lambda header up to its own colon; parameters
                     never bind outward. Depth-aware so nested brackets with
                     colons do not end the search early. *)
                  let rec find_colon k d =
                    if k >= n then n
                    else if stripped.[k] = '(' || stripped.[k] = '[' || stripped.[k] = '{' then
                      find_colon (k + 1) (d + 1)
                    else if stripped.[k] = ')' || stripped.[k] = ']' || stripped.[k] = '}' then
                      find_colon (k + 1) (d - 1)
                    else if d = depth.(pos) && stripped.[k] = ':' then k
                    else find_colon (k + 1) d
                  in
                  skip_until := max !skip_until (find_colon epos depth.(pos));
                  advanced_to := max epos !skip_until
                end else if word = "for" && depth.(pos) = 0 then begin
                  let j = skip_spaces epos in
                  if j < n && is_name_start j then begin
                    let (nm, e2) = read_ident j in
                    let e3 = skip_spaces e2 in
                    if is_word_at "in" e3 then begin
                      let rec find_colon k =
                        if k >= n then n
                        else if stripped.[k] = ':' && depth.(k) = depth.(pos) then k
                        else find_colon (k + 1)
                      in
                      record ~is_loopvar:true nm j pos (find_colon epos)
                    end
                  end
                end else if member_guarded pos && is_name_start pos then begin
                  let j = skip_spaces epos in
                  if j + 1 < n && stripped.[j] = ':' && stripped.[j + 1] = '=' then
                    (* Walrus binds the enclosing scope at any depth
                       (`f(x := 1)` included), so no depth check here. *)
                    record word pos (j + 2) (stmt_end_from (j + 2))
                  else if depth.(pos) = 0 then begin
                    (if j < n && stripped.[j] = '=' then begin
                      (* Annotation type names (`y: int = 1`) are never
                         binding targets: skip a word whose non-space
                         predecessor is `:`. `==`/`!=` are ruled out by
                         [next_ok] below. *)
                      let prev_ok =
                        let pb = skip_spaces_back (pos - 1) in
                        pb < 0 || stripped.[pb] <> ':'
                      in
                      let next_ok = j + 1 >= n || (stripped.[j + 1] <> '=' && stripped.[j + 1] <> '>') in
                      if prev_ok && next_ok then record word pos (j + 1) (stmt_end_from (j + 1))
                    end else if j < n && stripped.[j] = ':' && (j + 1 >= n || stripped.[j + 1] <> ':') then begin
                      (* Annotated assignment `x: int = ...`: bind x only if an
                         `=` follows at the same depth first. *)
                      let rec find_eq k d =
                        if k >= n || stripped.[k] = '\n' || stripped.[k] = ';' then None
                        else if stripped.[k] = '(' || stripped.[k] = '[' || stripped.[k] = '{' then find_eq (k + 1) (d + 1)
                        else if stripped.[k] = ')' || stripped.[k] = ']' || stripped.[k] = '}' then find_eq (k + 1) (d - 1)
                        else if d = 0 && stripped.[k] = '=' && (k + 1 >= n || (stripped.[k + 1] <> '=' && stripped.[k + 1] <> '>')) then Some k
                        else find_eq (k + 1) d
                      in
                      (match find_eq (j + 1) depth.(pos) with
                       | Some eq -> record word pos (eq + 1) (stmt_end_from (eq + 1))
                       | None -> ())
                    end)
                  end
                end
            | JuliaLang ->
                (* Frames carry their keyword so `end` handling stays
                   balanced: `catch`/`finally` pop a pending `try`/`catch`
                   frame first (one `end` closes the whole chain), and
                   branch keywords only push at depth 0 — `for`/`if` inside
                   comprehensions or generators (`[x for x in xs]`) have no
                   `end` and must not leak a frame that disables later
                   subtraction. `do` and named definitions always push:
                   they live inside call parens by nature yet always pair
                   with `end`. *)
                if word = "function" || word = "macro" || word = "struct"
                   || word = "module" || word = "abstract" || word = "primitive" then begin
                  (* Named scope definitions bind in the enclosing scope;
                     check scope before pushing. `abstract` and `primitive`
                     are followed by the `type` keyword, which is skipped so
                     the type name itself records; their `end` then balances
                     instead of popping the enclosing frame early. *)
                  if not (jl_in_scope ()) then begin
                    let j = skip_spaces epos in
                    let j =
                      if (word = "abstract" || word = "primitive")
                         && j < n && is_name_start j then
                        let (w2, e2) = read_ident j in
                        if w2 = "type" then skip_spaces e2 else j
                      else j
                    in
                    if j < n && is_name_start j then begin
                      let (nm, e2) = read_ident j in
                      if member_guarded j then record nm j e2 e2
                    end
                  end;
                  jl_stack := (word, true, false, depth.(pos)) :: !jl_stack
                end else if word = "let" || word = "quote" || word = "do" then
                  jl_stack := (word, true, false, depth.(pos)) :: !jl_stack
                else if (word = "if" || word = "for" || word = "while"
                         || word = "catch" || word = "finally"
                         || word = "begin" || word = "try")
                        && depth.(pos) = 0 then begin
                  (match word with
                   | "catch" | "finally" ->
                       (match !jl_stack with
                        | (k, _, _, d) :: rest
                          when (k = "try" || k = "catch") && d = depth.(pos) ->
                            jl_stack := rest
                        | _ -> ())
                   | _ -> ());
                  let cond = word = "if" || word = "for" || word = "while"
                             || word = "catch" || word = "try" || word = "finally" in
                  jl_stack := (word, false, cond, depth.(pos)) :: !jl_stack
                end else if word = "end" then begin
                  (match !jl_stack with
                   | (_, _, _, d) :: rest when d = depth.(pos) -> jl_stack := rest
                   | _ -> ())
                end else if not (jl_in_scope ()) && not (jl_in_cond ())
                            && depth.(pos) = 0
                            && member_guarded pos && is_name_start pos then begin
                  let j = skip_spaces epos in
                  if j < n && stripped.[j] = '=' then begin
                    (* Only the `:` quote guard survives here: `.` is covered
                       by member_guarded and `next_ok` rules out `==`. *)
                    let prev_ok = pos = 0 || stripped.[pos - 1] <> ':' in
                    let next_ok = j + 1 >= n || (stripped.[j + 1] <> '=' && stripped.[j + 1] <> '>') in
                    if prev_ok && next_ok then record word pos (j + 1) (stmt_end_from (j + 1))
                  end
                end
            | ShLang ->
                if word = "for" && depth.(pos) = 0 && sh_stmt_start pos then begin
                  let j = skip_spaces epos in
                  if j < n && is_name_start j then begin
                    let (nm, e2) = read_ident j in
                    let e3 = skip_spaces e2 in
                    if e3 >= n || stripped.[e3] = ';' || stripped.[e3] = '\n'
                       || is_word_at "in" e3 || is_word_at "do" e3 then
                      record ~is_loopvar:true nm j pos (stmt_end_from pos)
                  end
                end else if (word = "export" || word = "declare" || word = "readonly" || word = "local")
                          && depth.(pos) = 0 && sh_stmt_start pos then begin
                  (* `export NAME=...` (and declare/readonly/local) persist
                     like plain assignments; with a following command they
                     are prefixes (see `sh_persists` above). Bare `export
                     NAME` assigns nothing. Regions still apply through
                     `record`, so function bodies stay conditional. *)
                  let j = skip_spaces epos in
                  if j < n && is_name_start j && member_guarded j then begin
                    let (nm, e2) = read_ident j in
                    let e3 = skip_spaces e2 in
                    if e3 < n && stripped.[e3] = '='
                       && (e3 + 1 >= n || stripped.[e3 + 1] <> '=') then
                      (match sh_persists nm j e3 with
                       | Some chain -> record_chain chain
                       | None -> ())
                  end
                end else if depth.(pos) = 0 && member_guarded pos && is_name_start pos
                          && sh_stmt_start pos
                          && epos < n && stripped.[epos] = '='
                          && (epos + 1 >= n || stripped.[epos + 1] <> '=') then
                  (match dollar_opener pos with
                   | Some _ ->
                       (* `$`-prefixed opener: subshell `$(...)` assignments
                          never persist, and parameter expansion (`${X=...}`)
                          assigns only when unset (all other `${...}`
                          operators are pure reads and never reach here).
                          Record as conditional-only so the edge stays and
                          later reads stay bare. *)
                       all_binders := (word, pos) :: !all_binders
                   | None ->
                       (match sh_persists word pos epos with
                        | Some chain -> record_chain chain
                        | None -> ()))
            | OtherLang -> ());
           i := max !advanced_to epos
         end
       done;
       (stripped, !found, !all_binders))

(** All recorded bindings (names only), preserving the historical
    behavior of [extract_local_bindings]: every unconditional binding
    the scan spots, including ones later filtered from dependency
    subtraction (read-before, right-hand-side self-reads). *)
let extract_local_bindings ~runtime text =
  let _, bs, _ = scan_raw_bindings ~runtime text in
  List.sort_uniq String.compare (List.map (fun b -> b.b_name) bs)

(** Names purely shadowed by the block: no whole-word read before the
    earliest binding and none inside its right-hand side. Only these are
    safe to subtract before sibling matching; anything else keeps the
    edge (a spurious edge fails loudly at cycle check, a dropped real
    edge would silently under-build). *)
let extract_shadowed_locals ~runtime text =
  let stripped, bs, _ = scan_raw_bindings ~runtime text in
  let n = String.length stripped in
  let is_id c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '_'
  in
  let occs name lo hi =
    let m = String.length name in
    if m = 0 then [] else
    let rec loop i acc =
      if i + m > hi then List.rev acc
      else if i >= lo && String.sub stripped i m = name
              && (i = 0 || not (is_id stripped.[i - 1]))
              && (i + m >= n || not (is_id stripped.[i + m])) then
        loop (i + m) (i :: acc)
      else loop (i + 1) acc
    in
    loop (max lo 0) []
  in
  let table = Hashtbl.create 16 in
  List.iter (fun b ->
    match Hashtbl.find_opt table b.b_name with
    | Some (prev : raw_binding) when prev.b_pos <= b.b_pos -> ()
    | _ -> Hashtbl.replace table b.b_name b
  ) bs;
  Hashtbl.fold (fun _ b acc ->
    let pre = occs b.b_name 0 b.b_pos in
    let in_rhs =
      List.filter ((<>) b.b_pos) (occs b.b_name b.b_rhs_start b.b_rhs_end)
    in
    if pre = [] && in_rhs = [] then b.b_name :: acc else acc
  ) table [] |> List.sort_uniq String.compare

(** Occurrence spans of [dep_name] that resolve to the dependency and may
    be textually replaced with its expanded value — or [None] when the
    name is never bound in the block (the caller keeps its legacy
    whole-text replacement, so behavior outside shadowing is unchanged).

    A bound name splits the block: occurrences strictly before the
    earliest binding (of any kind, conditional included) still read the
    dependency, as do occurrences inside the earliest *unconditional*
    binding's right-hand side (e.g. the RHS `x` in `x <- x + 1`).
    Binder occurrences themselves are never substituted, nor are later
    reads, which may resolve to the local. With only conditional
    bindings, just the pre-binding prefix substitutes; ambiguous later
    reads stay bare and resolve through the branch's dependency edge.

    Matching runs on the original text with whole-word,
    identifier-character boundaries — the same rule the legacy path used
    — including inside strings. Positions align because stripping is
    length-preserving. *)
let dep_substitution_spans ~runtime text dep_name =
  if dep_name = "" then None
  else
    let m = String.length dep_name in
    let n = String.length text in
    let is_id c =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      || (c >= '0' && c <= '9') || c = '_'
    in
    let rec occs i acc =
      if i + m > n then List.rev acc
      else if String.sub text i m = dep_name
              && (i = 0 || not (is_id text.[i - 1]))
              && (i + m >= n || not (is_id text.[i + m])) then
        occs (i + m) ((i, m) :: acc)
      else occs (i + 1) acc
    in
    let _, detailed, binders = scan_raw_bindings ~runtime text in
    let mine = List.filter (fun (nm, _) -> nm = dep_name) binders in
    match mine with
    | [] -> None
    | _ ->
        let first_all = List.fold_left (fun a (_, p) -> min a p) max_int mine in
        let binder_pos = List.map snd mine in
        let uncond_rhs =
          let rec earliest acc = function
            | [] -> acc
            | b :: rest when b.b_name = dep_name ->
                (match acc with
                 | None -> earliest (Some b) rest
                 | Some prev ->
                     earliest (Some (if b.b_pos < prev.b_pos then b else prev)) rest)
            | _ :: rest -> earliest acc rest
          in
          match earliest None detailed with
          | Some r -> Some (r.b_rhs_start, r.b_rhs_end)
          | None -> None
        in
        let in_rhs (s, _) =
          match uncond_rhs with
          | Some (rs, re) -> rs <= s && s + m <= re
          | None -> false
        in
        Some (List.filter (fun (s, _) ->
          (s < first_all || in_rhs (s, m)) && not (List.mem s binder_pos)
        ) (occs 0 []))

(** True when [dep_name] is bound only conditionally in [text] and read
    after the first binder. Those late reads stay bare during pattern
    expansion (see [dep_substitution_spans]) and would resolve to the
    whole artifact instead of the per-branch slice, so expansion must
    fail loudly and ask for a rename. `read_node("dep")` literals are
    deliberate whole-artifact reads and do not count. *)
let has_conditional_shadow_read ~runtime text dep_name =
  if dep_name = "" then false
  else
    let _, bs, all = scan_raw_bindings ~runtime text in
    let mine = List.filter (fun (nm, _) -> nm = dep_name) all in
    if mine = [] then false
    else if List.exists (fun b -> b.b_name = dep_name) bs then false
    else
      let first_all = List.fold_left (fun a (_, p) -> min a p) max_int mine in
      (* Occurrences come from the stripped text (same length, so positions
         transfer): mentions inside comments and strings are not reads and
         must not trigger the rename error. The `read_node` exemption
         below still reads the original text, where quotes are intact. *)
      let stripped = strip_noncode_spans ~lang:(Some (lang_of_runtime runtime)) text in
      let m = String.length dep_name and n = String.length stripped in
      let is_id c =
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9') || c = '_'
      in
      (* A whole-word occurrence is a deliberate whole-artifact read when
         it sits inside read_node("dep") / read_node('dep'). Only the
         immediate `read_node` + quote shape counts. *)
      let in_read_node_literal i =
        let j = ref (i - 1) in
        while !j >= 0 && (text.[!j] = ' ' || text.[!j] = '\t') do decr j done;
        if !j < 1 then false
        else
          let q = text.[!j] in
          if q <> '"' && q <> '\'' then false
          else
            let k = !j - 1 in
            let w = "read_node" in
            let m = String.length w in
            k + 1 >= m && String.sub text (k + 1 - m) m = w
            && (k + 1 - m = 0 || not (is_id text.[k - m]))
      in
      let rec loop i =
        if i + m > n then false
        else if String.sub stripped i m = dep_name
                && (i = 0 || not (is_id stripped.[i - 1]))
                && (i + m >= n || not (is_id stripped.[i + m]))
                && i > first_all
                && not (in_read_node_literal i) then true
        else loop (i + 1)
      in
      loop 0

(** Convenience type alias *)
type environment = value Env.t

module Utils = struct
  let rec arrow_table_equal ta tb =
    let nrows = Arrow_table.num_rows ta in
    nrows = Arrow_table.num_rows tb &&
    let cols_a = Arrow_table.column_names ta in
    let cols_b = Arrow_table.column_names tb in
    cols_a = cols_b &&
    let col_equal ca cb =
      match ca, cb with
      | Arrow_table.IntColumn arr_a, Arrow_table.IntColumn arr_b -> arr_a = arr_b
      | Arrow_table.FloatColumn arr_a, Arrow_table.FloatColumn arr_b ->
          Array.length arr_a = Array.length arr_b &&
          (try
             Array.iteri (fun i va ->
               let vb = arr_b.(i) in
               match va, vb with
               | None, None -> ()
               | Some fa, Some fb ->
                   if Float.is_nan fa && Float.is_nan fb then ()
                   else if Float.equal fa fb then ()
                   else raise Exit
               | _ -> raise Exit
             ) arr_a;
             true
           with Exit -> false)
      | Arrow_table.BoolColumn arr_a, Arrow_table.BoolColumn arr_b -> arr_a = arr_b
      | Arrow_table.StringColumn arr_a, Arrow_table.StringColumn arr_b -> arr_a = arr_b
      | Arrow_table.DateColumn arr_a, Arrow_table.DateColumn arr_b -> arr_a = arr_b
      | Arrow_table.DatetimeColumn (arr_a, tz_a), Arrow_table.DatetimeColumn (arr_b, tz_b) ->
          tz_a = tz_b && arr_a = arr_b
      | Arrow_table.DictionaryColumn (idx_a, lvl_a, ord_a), Arrow_table.DictionaryColumn (idx_b, lvl_b, ord_b) ->
          idx_a = idx_b && lvl_a = lvl_b && ord_a = ord_b
      | Arrow_table.NAColumn n_a, Arrow_table.NAColumn n_b -> n_a = n_b
      | Arrow_table.ListColumn arr_a, Arrow_table.ListColumn arr_b ->
          Array.length arr_a = Array.length arr_b &&
          (try
             Array.iteri (fun i va ->
               let vb = arr_b.(i) in
               match va, vb with
               | None, None -> ()
               | Some ta', Some tb' -> if not (arrow_table_equal ta' tb') then raise Exit
               | _ -> raise Exit
             ) arr_a;
             true
           with Exit -> false)
      | _ -> false
    in
    List.for_all (fun col ->
      match Arrow_table.get_column ta col, Arrow_table.get_column tb col with
      | Some ca, Some cb -> col_equal ca cb
      | _ -> false
    ) cols_a

  let dataframe_equal dfa dfb =
    dfa.group_keys = dfb.group_keys &&
    arrow_table_equal dfa.arrow_table dfb.arrow_table

  let empty_node_diagnostics = {
    nd_warnings = [];
    nd_error = None;
    nd_warnings_suppressed = false;
    nd_recovered = false;
    nd_upstream_errors = [];
  }

  let format_single_warning_message (w : node_warning) =
    match w.nw_source with
    | WarningOwn -> w.nw_message
    | WarningUpstream name ->
        Printf.sprintf "Ancestor node '%s' reported following warning: %s" name w.nw_message

  let format_warning_messages (warnings : node_warning list) =
    match warnings with
    | [] -> ""
    | _ -> String.concat ". Furthermore, " (List.map format_single_warning_message warnings)

  (** Canonical list of field names exposed on read-pipeline node records
      (as constructed by [which_nodes] and [errored_nodes]). The evaluator
      uses this list to decide when a bare-word expression should be
      auto-wrapped into a scoped lambda ([\\(node) node.<field> ...]).

      Keep this in sync with the [node_record] constructor in
      [src/packages/pipeline/which_nodes.ml]. *)
  let node_record_scope_fields = ["name"; "value"; "diagnostics"]

  let rec unwrap_value = function
    | VNodeResult { v; _ } -> unwrap_value v
    | v -> v

  let display_params params autoquote_params =
    let rec go acc ps aqs =
      match ps, aqs with
      | [], _ -> List.rev acc
      | p :: ps_rest, true :: aqs_rest -> go (("$" ^ p) :: acc) ps_rest aqs_rest
      | p :: ps_rest, false :: aqs_rest -> go (p :: acc) ps_rest aqs_rest
      | p :: ps_rest, [] -> go (p :: acc) ps_rest []
    in
    go [] params autoquote_params

  let rec is_truthy = function
    | VBool false | VInt 0 -> false
    | VError _ -> false
    | VNA _ -> false
    | VNullNode -> false
    | VNodeResult { v; _ } -> is_truthy v
    | VExpect Expect_pass -> true
    | VExpect (Expect_stop _ | Expect_hold _) -> false
    | _ -> true

  (** Check if an expression is a column reference and extract the column name.
      Intended for use in NSE-aware functions that need to inspect AST nodes
      before evaluation (e.g., future filter/mutate NSE support). *)
  let is_column_ref = function
    | { node = ColumnRef field; _ } -> Some field
    | _ -> None

  (** Extract column name from a runtime value, supporting NSE ($column) syntax.
      Used by data verbs (select, arrange, group_by, etc.) to accept
      $column_name NSE syntax.  String arguments are intentionally rejected;
      users should write $col, not "col". *)
  let is_string = function VString _ -> true | VRawCode _ -> true | _ -> false
  let is_symbol = function VSymbol _ -> true | _ -> false
  
  let extract_column_name = function
    | VSymbol s when String.length s > 0 && s.[0] = '$' ->
        Some (String.sub s 1 (String.length s - 1))
    | VSymbol s -> Some s
    | VString s -> Some s
    | _ -> None

  (** Strip a leading `$` prefix from a string, if present. Used to make
      `get(d, $col)` / `get(p, $node)` and `pipeline_node(p, $node)` accept
      bare-word NSE-style selectors. *)
  let strip_dollar s =
    if String.length s > 0 && s.[0] = '$' then String.sub s 1 (String.length s - 1)
    else s

  let rec list_take n = function
    | [] -> []
    | h :: t -> if n <= 0 then [] else h :: list_take (n - 1) t

  let node_warning_source_to_value = function
    | WarningOwn ->
        VDict [("kind", VString "Own")]
    | WarningUpstream node ->
        VDict [("kind", VString "Upstream"); ("node", VString node)]

  let node_warning_to_value warning =
    VDict [
      ("kind", VString warning.nw_kind);
      ("fn", VString warning.nw_fn);
      ("na_count", VInt warning.nw_na_count);
      ("na_indices", VList (List.map (fun idx -> (None, VInt idx)) warning.nw_na_indices));
      ("message", VString warning.nw_message);
      ("source", node_warning_source_to_value warning.nw_source);
    ]

  let node_error_to_value error =
    VDict [
      ("kind", VString error.ne_kind);
      ("fn", VString error.ne_fn);
      ("message", VString error.ne_message);
      ("na_count", VInt error.ne_na_count);
    ]

  let node_diagnostics_to_value diagnostics =
    VDict [
      ("warnings", VList (List.map (fun warning -> (None, node_warning_to_value warning)) diagnostics.nd_warnings));
      ("error",
       match diagnostics.nd_error with
       | Some error -> node_error_to_value error
       | None -> VNA NAGeneric);
      ("warnings_suppressed", VBool diagnostics.nd_warnings_suppressed);
      ("recovered", VBool diagnostics.nd_recovered);
      ("upstream_errors", VList (List.map (fun s -> (None, VString s)) diagnostics.nd_upstream_errors));
    ]

  let node_has_own_warnings diagnostics =
    List.exists (fun warning ->
      match warning.nw_source with
      | WarningOwn -> true
      | WarningUpstream _ -> false
    ) diagnostics.nd_warnings

  let pipeline_diagnostics_to_value node_diagnostics =
    let warning_nodes =
      node_diagnostics
      |> List.filter_map (fun (name, diagnostics) ->
           if node_has_own_warnings diagnostics then Some (None, VString name) else None)
    in
    let error_nodes =
      node_diagnostics
      |> List.filter_map (fun (name, diagnostics) ->
           match diagnostics.nd_error with
           | Some _ -> Some (None, VString name)
           | None -> None)
    in
    let suppressed_nodes =
      node_diagnostics
      |> List.filter_map (fun (name, diagnostics) ->
           if diagnostics.nd_warnings_suppressed && node_has_own_warnings diagnostics 
           then Some (None, VString name) else None)
    in
    let recovered_nodes =
      node_diagnostics
      |> List.filter_map (fun (name, diagnostics) ->
           if diagnostics.nd_recovered then Some (None, VString name) else None)
    in
    let warning_count = List.length warning_nodes in
    let error_count = List.length error_nodes in
    let suppressed_count = List.length suppressed_nodes in
    let recovered_count = List.length recovered_nodes in
    VDict [
      ("warning_nodes", VList warning_nodes);
      ("error_nodes", VList error_nodes);
      ("suppressed_nodes", VList suppressed_nodes);
      ("recovered_nodes", VList recovered_nodes);
      ("summary",
       VString (Printf.sprintf "%d node(s) with warnings, %d suppressed, %d error(s), %d recovered" 
                 warning_count suppressed_count error_count recovered_count));
    ]

  let error_code_to_string = function
    | TypeError -> "TypeError"
    | AggregationError -> "AggregationError"
    | ArityError -> "ArityError"
    | NameError -> "NameError"
    | DivisionByZero -> "DivisionByZero"
    | KeyError -> "KeyError"
    | IndexError -> "IndexError"
    | AssertionError -> "AssertionError"
    | FileError -> "FileError"
    | ValueError -> "ValueError"
    | MatchError -> "MatchError"
    | SyntaxError -> "SyntaxError"
    | ShellError -> "ShellError"
    | RuntimeError -> "RuntimeError"
    | GenericError -> "GenericError"
    | NAPredicateError -> "NAPredicateError"
    | MissingArtifactError -> "MissingArtifactError"
    | StructuralError -> "StructuralError"

  let error_code_of_string = function
    | "TypeError" -> TypeError
    | "AggregationError" -> AggregationError
    | "ArityError" -> ArityError
    | "NameError" -> NameError
    | "DivisionByZero" -> DivisionByZero
    | "KeyError" -> KeyError
    | "IndexError" -> IndexError
    | "AssertionError" -> AssertionError
    | "FileError" -> FileError
    | "ValueError" -> ValueError
    | "MatchError" -> MatchError
    | "SyntaxError" -> SyntaxError
    | "ShellError" -> ShellError
    | "RuntimeError" -> RuntimeError
    | "GenericError" -> GenericError
    | "NAPredicateError" -> NAPredicateError
    | "MissingArtifactError" -> MissingArtifactError
    | "StructuralError" -> StructuralError
    | _ -> RuntimeError

  let na_type_to_string = function
    | NABool -> "Bool"
    | NAInt -> "Int"
    | NAFloat -> "Float"
    | NAString -> "String"
    | NADate -> "Date"
    | NADatetime -> "Datetime"
    | NAGeneric -> ""

  let rec typ_to_string = function
    | TInt -> "Int"
    | TFloat -> "Float"
    | TBool -> "Bool"
    | TString -> "String"
    | TCustom "NA" -> "NA"
    | TList None -> "List"
    | TList (Some t) -> "List[" ^ typ_to_string t ^ "]"
    | TDict (None, None) -> "Dict"
    | TDict (Some k, Some v) -> "Dict[" ^ typ_to_string k ^ ", " ^ typ_to_string v ^ "]"
    | TDict (Some k, None) -> "Dict[" ^ typ_to_string k ^ ", _]"
    | TDict (None, Some v) -> "Dict[_, " ^ typ_to_string v ^ "]"
    | TTuple ts -> "Tuple[" ^ (String.concat ", " (List.map typ_to_string ts)) ^ "]"
    | TUnion ts -> String.concat " | " (List.map typ_to_string ts)
    | TDataFrame None -> "DataFrame"
    | TDataFrame (Some schema) -> "DataFrame[" ^ typ_to_string schema ^ "]"
    | TVar s -> s
    | TCustom s -> s
    | TComputedNode -> "ComputedNode"
    | TSerializer -> "Serializer"
    | TExpr -> "Expression"
    | TArrow (params, ret) ->
        let params_str = String.concat ", " (List.map typ_to_string params) in
        "(" ^ params_str ^ ") -> " ^ typ_to_string ret
  | TUnknown -> "Unknown"

  let rec type_name = function
    | VBuildLog _ -> "BuildLog"
    | VInt _ -> "Int" | VFloat _ -> "Float"
    | VBool _ -> "Bool" | VString _ -> "String" | VRawCode _ -> "Code"
    | VSymbol _ -> "Symbol" | VDate _ -> "Date" | VDatetime _ -> "Datetime"
    | VList _ -> "List" | VDict _ -> "Dict"
    | VUnion u -> u.un_type
    | VRecord r -> r.rec_type
    | VTypeDef _ -> "Type"
    | VVector _ -> "Vector" | VNDArray _ -> "NDArray" | VDataFrame _ -> "DataFrame"
    | VPipeline _ -> "Pipeline" | VMetaPipeline _ -> "MetaPipeline" | VLens _ -> "Lens"
    | VLambda _ -> "Function" | VBuiltin _ -> "BuiltinFunction"
    | VNA _ -> "NA" | VError _ -> "Error"
    | VFactor _ -> "Factor"
    | VPeriod _ -> "Period"
    | VDuration _ -> "Duration"
    | VInterval _ -> "Interval"
    | VIntent _ -> "Intent"
    | VFormula _ -> "Formula"
    | VSerializer _ -> "Serializer"
    | VComputedNode _ -> "ComputedNode"
    | VNode _ -> "Node"
    | VNullNode -> "NullNode"
    | VPattern _ -> "Pattern"
    | VExpr _ -> "Expression"
    | VQuo _ -> "Quosure"
    | VShellResult _ -> "ShellResult"
    | VUnquote _ -> "Unquote"
    | VUnquoteSplice _ -> "UnquoteSplice"
    | VDynamicArg _ -> "DynamicArg"
    | VEnv _ -> "Environment"
    | VNodeResult { v; _ } -> type_name v
    | VExpect _ -> "Expect"

  let escape_string_utf8 s =
    let buf = Buffer.create (String.length s * 2) in
    String.iter (fun c ->
      let code = Char.code c in
      if code >= 128 then
        Buffer.add_char buf c
      else
        match c with
        | '\n' -> Buffer.add_string buf "\\n"
        | '\r' -> Buffer.add_string buf "\\r"
        | '\t' -> Buffer.add_string buf "\\t"
        | '\\' -> Buffer.add_string buf "\\\\"
        | '"'  -> Buffer.add_string buf "\\\""
        | _ when code < 32 || code = 127 ->
            Buffer.add_string buf (Printf.sprintf "\\%03d" code)
        | _ -> Buffer.add_char buf c
    ) s;
    Buffer.contents buf

  let rec binop_to_string = function
    | Plus -> "+" | Minus -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%"
    | Eq -> "==" | NEq -> "!=" | Gt -> ">" | Lt -> "<" | GtEq -> ">=" | LtEq -> "<="
    | And -> "&&" | Or -> "||" | BitAnd -> "&" | BitOr -> "|"
    | In -> "in" | Pipe -> "|>" | MaybePipe -> "?|>" | Formula -> "~" | FatArrow -> "=>"

  and unparse_match_pattern = function
    | PWildcard -> "_"
    | PVar s -> s
    | PNA -> "NA"
    | PList (patterns, rest) ->
        let items =
          List.map unparse_match_pattern patterns
          @
          match rest with
          | Some name -> [".." ^ name]
          | None -> []
        in
        "[" ^ String.concat ", " items ^ "]"
    | PError None -> "Error"
    | PError (Some field) -> "Error { " ^ field ^ " }"
    | PUnion { pu_case; pu_args } ->
        pu_case ^ "(" ^ String.concat ", " (List.map unparse_match_pattern pu_args) ^ ")"

  and unparse_expr expr =
    match expr.node with
    | Value v -> value_to_string v
    | Var s -> s
    | ColumnRef s -> "$" ^ s
    | Call { fn; args } ->
        let args_s = List.map (fun (name, e) ->
          match name with
          | Some n -> n ^ " = " ^ unparse_expr e
          | None -> unparse_expr e
        ) args in
        unparse_expr fn ^ "(" ^ String.concat ", " args_s ^ ")"
    | Lambda { params; autoquote_params; body; _ } ->
        "\\(" ^ String.concat ", " (display_params params autoquote_params) ^ ") " ^ unparse_expr body
    | IfElse { cond; then_; else_ } ->
        "if (" ^ unparse_expr cond ^ ") " ^ unparse_expr then_ ^ " else " ^ unparse_expr else_
    | Match { scrutinee; cases } ->
        let cases_s =
          List.map (fun (pattern, body) ->
            unparse_match_pattern pattern ^ " => " ^ unparse_expr body
          ) cases
        in
        "match(" ^ unparse_expr scrutinee ^ ") { " ^ String.concat ", " cases_s ^ " }"
    | ListLit items ->
        let items_s = List.map (fun (name, e) ->
          match name with
          | Some n -> n ^ ": " ^ unparse_expr e
          | None -> unparse_expr e
        ) items in
        "[" ^ String.concat ", " items_s ^ "]"
    | DictLit pairs ->
        let pairs_s = List.map (fun (k, v) -> k ^ ": " ^ unparse_expr v) pairs in
        "{ " ^ (pairs_s |> String.concat ", ") ^ " }"
    | BinOp { op; left; right } ->
        unparse_expr left ^ " " ^ binop_to_string op ^ " " ^ unparse_expr right
    | UnOp { op; operand } ->
        let op_s = match op with Not -> "!" | Neg -> "-" in
        op_s ^ unparse_expr operand
    | DotAccess { target; field } ->
        unparse_expr target ^ "." ^ field
    | RawCode { raw_text; _ } -> "<{ " ^ raw_text ^ " }>"
    | PipelineDef nodes ->
        "pipeline { " ^ String.concat "; " (List.map (fun (n, e) -> n ^ " = " ^ unparse_expr e) nodes) ^ " }"
    | PipelineOfDef nodes ->
        "pipeline_of { " ^ String.concat "; " (List.map (fun (n, e) -> n ^ " = " ^ unparse_expr e) nodes) ^ " }"

    | BroadcastOp { op; left; right } ->
        unparse_expr left ^ " ." ^ binop_to_string op ^ " " ^ unparse_expr right
    | Unquote e -> "!!" ^ unparse_expr e
    | UnquoteSplice e -> "!!!" ^ unparse_expr e
    | Block stmts -> "{ " ^ (List.map unparse_stmt stmts |> String.concat "; ") ^ " }"
    | ShellExpr cmd -> "?<{ " ^ cmd ^ " }>"
    | IntentDef _ -> "intent { ... }"

  and unparse_stmt stmt =
    match stmt.node with
    | Expression e -> unparse_expr e
    | Assignment { name; expr; _ } -> name ^ " = " ^ unparse_expr expr
    | Reassignment { name; expr } -> name ^ " := " ^ unparse_expr expr
    | TypeDecl { tname; tdef = RecordDef { rd_fields } } ->
        "type " ^ tname ^ " = { "
        ^ String.concat ", " (List.map (fun (n, t) -> n ^ ": " ^ typ_to_string t) rd_fields)
        ^ " }"
    | TypeDecl { tname; tdef = UnionDef { ud_cases } } ->
        "type " ^ tname ^ " = "
        ^ String.concat " | " (List.map (fun (c, ts) ->
              c ^ "(" ^ String.concat ", " (List.map typ_to_string ts) ^ ")") ud_cases)
    | Import s -> "import \"" ^ s ^ "\""
    | ImportPackage s -> "import " ^ s
    | ImportFrom { package; names } -> 
        "import " ^ package ^ " [" ^ String.concat ", " (List.map (fun is -> is.import_name) names) ^ "]"
    | ImportFileFrom { filename; names } -> 
        "import \"" ^ filename ^ "\" [" ^ String.concat ", " (List.map (fun is -> is.import_name) names) ^ "]"

  and value_to_string = function
    | VBuildLog bl ->
        let total = List.length bl.bl_nodes in
        let count_status status_str =
          List.length (List.filter (function
            | VDict fields ->
                (match List.assoc_opt "status" fields with
                 | Some (VString s) -> String.lowercase_ascii s = String.lowercase_ascii status_str
                 | _ -> false)
            | _ -> false) bl.bl_nodes)
        in
        let succeeded_count = count_status "Completed" + count_status "Completed with warning" in
        let failed_count = count_status "Errored" + count_status "Completed with error" in
        let skipped_count = count_status "Skipped" in
        let building_count = count_status "Building" in
        let pending_count = count_status "Pending" in
        let warning_nodes =
          List.filter_map (function
            | VDict fields ->
                (match List.assoc_opt "status" fields, List.assoc_opt "name" fields with
                 | Some (VString "Completed with warning"), Some (VString name) -> Some name
                 | _ -> None)
            | _ -> None) bl.bl_nodes
        in
        let parts = [
          Printf.sprintf "%d succeeded" succeeded_count;
          Printf.sprintf "%d failed" failed_count;
        ] in
        let parts = if skipped_count > 0 then parts @ [Printf.sprintf "%d skipped" skipped_count] else parts in
        let parts = if building_count > 0 then parts @ [Printf.sprintf "%d building" building_count] else parts in
        let parts = if pending_count > 0 then parts @ [Printf.sprintf "%d pending" pending_count] else parts in
        let base =
          Printf.sprintf "Build Log: %d nodes [%s] (duration: %.2fs)"
            total (String.concat ", " parts) bl.bl_duration
        in
        if warning_nodes = [] then base
        else
          base ^ "\n  ⚠ Warnings in nodes: " ^ String.concat ", " warning_nodes
    | VInt n -> string_of_int n
    | VFloat f -> string_of_float f
    | VBool b -> string_of_bool b
    | VString s -> "\"" ^ escape_string_utf8 s ^ "\""
    | VRawCode s -> "<{ " ^ s ^ " }>"
    | VSymbol s -> s
    | VDate days ->
        let tm = Unix.gmtime (float_of_int days *. 86400.) in
        Printf.sprintf "Date(%04d-%02d-%02d)" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    | VDatetime (micros, tz) ->
        let seconds = Int64.to_float micros /. 1_000_000.0 in
        let tm = Unix.gmtime seconds in
        let micros_part =
          let raw = Int64.rem micros 1_000_000L |> Int64.to_int in
          if raw < 0 then raw + 1_000_000 else raw
        in
        let base =
          Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d"
            (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
            tm.tm_hour tm.tm_min tm.tm_sec
        in
        let frac =
          if micros_part = 0 then ""
          else Printf.sprintf ".%06d" micros_part
        in
        let tz_suffix =
          match tz with
          | Some name when name <> "" && name <> "UTC" -> "[" ^ name ^ "]"
          | _ -> "Z"
        in
        "Datetime(" ^ base ^ frac ^ tz_suffix ^ ")"
    | VList items ->
        let item_to_string = function
          | (Some name, v) -> name ^ ": " ^ value_to_string v
          | (None, v) -> value_to_string v
        in
        "[" ^ (items |> List.map item_to_string |> String.concat ", ") ^ "]"
    | VDict pairs ->
        let display_keys = List.fold_left (fun acc (k, v) ->
          match k, v with
          | "_display_keys", VList items ->
              Some (List.filter_map (fun (_, v) -> match v with VString s -> Some s | _ -> None) items)
          | _ -> acc
        ) None pairs in
        let visible_pairs = match display_keys with
          | None -> pairs
          | Some keys ->
              List.filter (fun (k, _) ->
                List.mem k keys
              ) pairs
        in
        let pair_to_string (k, v) = "`" ^ k ^ "`: " ^ value_to_string v in
        "{" ^ (visible_pairs |> List.map pair_to_string |> String.concat ", ") ^ "}"
    | VRecord r ->
        let field_to_string (k, v) = k ^ " = " ^ value_to_string v in
        r.rec_type ^ "(" ^ (r.rec_fields |> List.map field_to_string |> String.concat ", ") ^ ")"
    | VUnion u ->
        u.un_case ^ "(" ^ (u.un_payload |> List.map value_to_string |> String.concat ", ") ^ ")"
    | VTypeDef t ->
        "Type(" ^ t.td_name ^ ")"
    | VVector arr ->
        let items = Array.to_list arr |> List.map value_to_string in
        "Vector[" ^ String.concat ", " items ^ "]"
    | VNDArray { shape; data } ->
        let shape_s = shape |> Array.to_list |> List.map string_of_int |> String.concat ", " in
        let data_s = data |> Array.to_list |> List.map string_of_float |> String.concat ", " in
        Printf.sprintf "NDArray(shape=[%s], data=[%s])" shape_s data_s
    | VDataFrame { arrow_table; group_keys } ->
        let col_names = Arrow_table.column_names arrow_table in
        let base = Printf.sprintf "DataFrame(%d rows x %d cols: [%s])"
          (Arrow_table.num_rows arrow_table) (Arrow_table.num_columns arrow_table)
          (String.concat ", " col_names) in
        if group_keys = [] then base
        else Printf.sprintf "%s grouped by [%s]" base (String.concat ", " group_keys)
    | VPipeline { p_nodes; p_exprs; _ } ->
        let node_names = List.map fst p_nodes in
        let base = Printf.sprintf "Pipeline(%d nodes: [%s])"
          (List.length p_nodes) (String.concat ", " node_names) in
        let errors = List.filter_map (fun (name, v) ->
          match v with
          | VError err -> Some (Printf.sprintf "\n  - `%s` failed: %s" name err.message)
          | _ ->
            match get_in_memory_node_value ~p_exprs ~node_name:name with
            | Some (VNodeResult { v = VError err; _ }) ->
                Some (Printf.sprintf "\n  - `%s` failed: %s" name err.message)
            | _ -> None
        ) p_nodes in
        if errors = [] then base
        else base ^ "\nErrors:" ^ (String.concat "" errors)
    | VMetaPipeline { mp_pipelines; _ } ->
        let count = List.length mp_pipelines in
        Printf.sprintf "MetaPipeline(%d sub-pipeline(s))" count

    | VLambda { params; autoquote_params; variadic; _ } ->
        let dots = if variadic then ", ..." else "" in
        "\\(" ^ String.concat ", " (display_params params autoquote_params) ^ dots ^ ") -> <function>"
    | VBuiltin _ -> "<builtin_function>"
    | VNA na_t ->
        let tag = na_type_to_string na_t in
        if tag = "" then "NA" else "NA(" ^ tag ^ ")"
    | VError { code; message; location; _ } ->
        let rendered_message =
          match location with
          | Some { file; line; column } ->
              let prefix =
                match file with
                | Some filename -> Printf.sprintf "[%s:L%d:C%d]" filename line column
                | None -> Printf.sprintf "[L%d:C%d]" line column
              in
              prefix ^ " " ^ message
          | None -> message
        in
        "Error(" ^ error_code_to_string code ^ ": \"" ^ rendered_message ^ "\")"
    | VFactor (idx, levels, ordered) ->
        let level_str = match List.nth_opt levels idx with Some s -> "\"" ^ String.escaped s ^ "\"" | None -> "NA" in
        let ord_str = if ordered then ", ordered=true" else "" in
        Printf.sprintf "Factor(%s%s)" level_str ord_str
    | VPeriod p ->
        Printf.sprintf
          "Period(years=%d, months=%d, days=%d, hours=%d, minutes=%d, seconds=%d, micros=%d)"
          p.p_years p.p_months p.p_days p.p_hours p.p_minutes p.p_seconds p.p_micros
    | VDuration seconds ->
        Printf.sprintf "Duration(%g)" seconds
    | VInterval iv ->
        let start_s = value_to_string (VDatetime (iv.iv_start, iv.iv_tz)) in
        let end_s = value_to_string (VDatetime (iv.iv_end, iv.iv_tz)) in
        Printf.sprintf "Interval(start=%s, end=%s)" start_s end_s
    | VLens l ->
        let rec lens_to_string = function
          | ColLens s -> Printf.sprintf "col_lens(\"%s\")" s
          | IdxLens i -> Printf.sprintf "idx_lens(%d)" i
          | RowLens i -> Printf.sprintf "row_lens(%d)" i
          | NodeLens n -> Printf.sprintf "node_lens(\"%s\")" n
          | NodeMetaLens (n, f) -> Printf.sprintf "node_meta_lens(\"%s\", \"%s\")" n f
          | EnvVarLens (node, var) -> Printf.sprintf "env_var_lens(\"%s\", \"%s\")" node var
          | CompositeLens (l1, l2) -> Printf.sprintf "compose(%s, %s)" (lens_to_string l1) (lens_to_string l2)
          | FilterLens _ -> "filter_lens(...)"
        in
        lens_to_string l
    | VIntent { intent_fields } ->
        let field_to_string (k, v) = k ^ ": \"" ^ String.escaped v ^ "\"" in
        "Intent{" ^ (intent_fields |> List.map field_to_string |> String.concat ", ") ^ "}"
    | VFormula { response; predictors; _ } ->
        Printf.sprintf "%s ~ %s"
          (String.concat " + " response)
          (String.concat " + " predictors)
    | VExpr e ->
        Printf.sprintf "to_expr(%s)" (unparse_expr e)
    | VQuo { q_expr; _ } ->
        Printf.sprintf "quo(%s)" (unparse_expr q_expr)
    | VComputedNode cn ->
        Printf.sprintf "computed_node<%s>\nserializer: %s\nclass: %s"
          cn.cn_runtime cn.cn_serializer cn.cn_class
    | VSerializer s ->
        Printf.sprintf "serializer<^%s>" s.s_format
    | VNode un ->
        Printf.sprintf "node<%s>(...)" un.un_runtime
    | VNullNode -> "<null>"
    | VPattern pat ->
        let rec string_of_pattern = function
          | PatternMap deps -> "map_pattern(" ^ String.concat ", " deps ^ ")"
          | PatternCross sub -> "cross_pattern(" ^ String.concat ", " (List.map string_of_pattern sub) ^ ")"
          | PatternSlice (dep, idxs) -> "slice_pattern(" ^ dep ^ ", [" ^ String.concat ", " (List.map string_of_int idxs) ^ "])"
          | PatternHead (dep, n) -> "head_pattern(" ^ dep ^ ", " ^ string_of_int n ^ ")"
          | PatternTail (dep, n) -> "tail_pattern(" ^ dep ^ ", " ^ string_of_int n ^ ")"
          | PatternSample (dep, n) -> "sample_pattern(" ^ dep ^ ", " ^ string_of_int n ^ ")"
        in
        string_of_pattern pat
    | VShellResult { sr_stdout; _ } ->
        (* Display as the raw stdout string so ?<{cmd}> behaves like a string *)
        "\"" ^ String.escaped sr_stdout ^ "\""
    | VUnquote v -> "!!" ^ value_to_string v
    | VUnquoteSplice v -> "!!!" ^ value_to_string v
    | VDynamicArg (n, v) -> n ^ " := " ^ value_to_string v
    | VEnv _ -> "<environment>"
    | VNodeResult { v; _ } -> value_to_string v
    | VExpect Expect_pass -> "PASS"
    | VExpect (Expect_stop msg) -> Printf.sprintf "STOP(%s)" msg
    | VExpect (Expect_hold msg) -> Printf.sprintf "HOLD(%s)" msg

  let value_to_raw_string = function
    | VString s -> s
    | VRawCode s -> s
    | VShellResult { sr_stdout; _ } -> sr_stdout
    | VFloat f ->
        if Float.equal f (floor f) then
          let s = string_of_float f in
          if String.ends_with ~suffix:"." s then String.sub s 0 (String.length s - 1)
          else int_of_float f |> string_of_int
        else string_of_float f
    | VList items ->
        let item_to_string = function
          | (Some name, v) -> name ^ ": " ^ value_to_string v
          | (None, v) -> value_to_string v
        in
        "[" ^ (items |> List.map item_to_string |> String.concat ", ") ^ "]"
    | val_ -> value_to_string val_

  let option_source_to_string = function
    | Source_global -> "global"
    | Source_node -> "node"

  let empty_option_provenance = {
    prov_functions = []; prov_includes = []; prov_env_vars = []; prov_args = [];
    prov_shell_args = []; prov_explicit_deps = [];
    prov_serializer = None; prov_deserializer = None;
    prov_shell = None; prov_flake = None; prov_noop = None;
  }

  let option_provenance_of p name =
    match List.assoc_opt name p.p_provenance with
    | Some prov -> prov
    | None -> empty_option_provenance

  (** Render an option expr the same way pipeline_node_options does:
      concrete values pass through, bare variables are shown as their name. *)
  let expr_to_display_value e =
    match e.node with
    | Value v -> v
    | Var v -> VString v
    | _ -> VNA NAGeneric

  (** Pair values with their provenance sources, falling back to Source_node
      for values without a recorded source (defensive; provenance is recorded
      for every value at eval time). *)
  let rec zip_sources values prov =
    match values, prov with
    | [], _ -> []
    | v :: vs, (_, src) :: rest -> (v, src) :: zip_sources vs rest
    | v :: vs, [] -> (v, Source_node) :: zip_sources vs []

  (** Default serializer/deserializer expressions are bare vars "default" on
      any runtime, or "text" on sh/stdout-capture nodes.  Runtime-aware so
      that an explicit [^text] (which desugars to [Value (VSymbol "text")]) on
      a non-sh node is never conflated with an unset constructor default. *)
  let is_default_serializer_expr ~runtime e =
    match e.node with
    | Var "default" -> true
    | Var "text" -> runtime = "sh"
    | _ -> false

  (** Build the resolved per-node config snapshot for a pipeline node. *)
  let node_config_of_pipeline p name =
    let prov = option_provenance_of p name in
    let runtime =
      match List.assoc_opt name p.p_runtimes with
      | Some r -> r
      | None -> "T"
    in
    let functions =
      match List.assoc_opt name p.p_functions with
      | Some fs -> zip_sources fs prov.prov_functions
      | None -> []
    in
    let includes =
      match List.assoc_opt name p.p_includes with
      | Some fs -> zip_sources fs prov.prov_includes
      | None -> []
    in
    let env_vars =
      let env =
        match List.assoc_opt name p.p_env_vars with
        | Some e -> e
        | None -> []
      in
      List.map (fun (k, src) ->
        let v = match List.assoc_opt k env with Some v -> v | None -> VNA NAGeneric in
        (k, v, src)) prov.prov_env_vars
    in
    let args =
      let arg_list =
        match List.assoc_opt name p.p_args with
        | Some a -> a
        | None -> []
      in
      List.map (fun (k, src) ->
        let v = match List.assoc_opt k arg_list with Some v -> v | None -> VNA NAGeneric in
        (k, v, src)) prov.prov_args
    in
    let shell =
      match prov.prov_shell, List.assoc_opt name p.p_shells with
      | Some src, Some (Some s) -> Some (s, src)
      | Some _, _ -> invalid_arg "node_config_of_pipeline: shell provenance recorded without a shell value"
      | None, _ -> None
    in
    let shell_args =
      match List.assoc_opt name p.p_shell_args with
      | Some sa -> zip_sources sa prov.prov_shell_args
      | None -> []
    in
    let flake =
      match prov.prov_flake, List.assoc_opt name p.p_flakes with
      | Some src, Some (Some f) -> Some (f, src)
      | None, _ -> None
      | Some _, _ -> invalid_arg "node_config_of_pipeline: flake provenance recorded without a flake value"
    in
    let noop =
      match prov.prov_noop, List.assoc_opt name p.p_noops with
      | Some src, Some b -> Some (b, src)
      | None, _ -> None
      | Some src, _ -> Some (false, src)
    in
    let serializer =
      match prov.prov_serializer, List.assoc_opt name p.p_serializers with
      | Some src, Some e -> Some (e, src)
      | None, Some e when not (is_default_serializer_expr ~runtime e) -> Some (e, Source_node)
      | _ -> None
    in
    let deserializer =
      match prov.prov_deserializer, List.assoc_opt name p.p_deserializers with
      | Some src, Some e -> Some (e, src)
      | None, Some e when not (is_default_serializer_expr ~runtime e) -> Some (e, Source_node)
      | _ -> None
    in
    let deps =
      let dep_list = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
      let explicit = prov.prov_explicit_deps in
      let explicit_names = List.map fst explicit in
      let auto = List.filter (fun d -> not (List.mem d explicit_names)) dep_list in
      List.map (fun d -> (d, Source_node)) auto @ explicit
    in
    {
      nc_runtime = runtime;
      nc_functions = functions;
      nc_includes = includes;
      nc_env_vars = env_vars;
      nc_args = args;
      nc_shell = shell;
      nc_shell_args = shell_args;
      nc_flake = flake;
      nc_noop = noop;
      nc_serializer = serializer;
      nc_deserializer = deserializer;
      nc_deps = deps;
    }

  (** Re-attach fresh resolved-config snapshots onto every computed node of a
      pipeline. Used after any transform that changes resolved configuration
      (global options, merges, re-runs) so that nodes always reflect the
      current pipeline state. *)
  let attach_node_configs p =
    let update (name, v) =
      match v with
      | VComputedNode cn ->
          (name, VComputedNode { cn with cn_config = Some (node_config_of_pipeline p name) })
      | _ -> (name, v)
    in
    { p with p_nodes = List.map update p.p_nodes }

  let build_node_provenance un =
    {
      prov_functions = List.map (fun f -> (f, Source_node)) un.un_functions;
      prov_includes = List.map (fun i -> (i, Source_node)) un.un_includes;
      prov_env_vars = List.map (fun (k, _) -> (k, Source_node)) un.un_env_vars;
      prov_args = List.map (fun (k, _) -> (k, Source_node)) un.un_args;
      prov_shell_args = List.map (fun sa -> (sa, Source_node)) un.un_shell_args;
      prov_explicit_deps =
        (match un.un_dependencies with
         | Some d -> List.map (fun d -> (d, Source_node)) d
         | None -> []);
      prov_serializer =
        (if is_default_serializer_expr ~runtime:un.un_runtime un.un_serializer then None else Some Source_node);
      prov_deserializer =
        (if is_default_serializer_expr ~runtime:un.un_runtime un.un_deserializer then None else Some Source_node);
      prov_shell = (match un.un_shell with Some _ -> Some Source_node | None -> None);
      prov_flake = (match un.un_flake with Some _ -> Some Source_node | None -> None);
      prov_noop = (match un.un_noop with true -> Some Source_node | false -> None);
    }
end

(* --- Shared Helper Functions --- *)
(* These are used by eval.ml and all package modules. *)

(** Levenshtein edit distance between two strings *)
let levenshtein s t =
  let m = String.length s in
  let n = String.length t in
  if m = 0 then n
  else if n = 0 then m
  else
    let d = Array.make_matrix (m + 1) (n + 1) 0 in
    for i = 0 to m do d.(i).(0) <- i done;
    for j = 0 to n do d.(0).(j) <- j done;
    for i = 1 to m do
      for j = 1 to n do
        let cost = if s.[i - 1] = t.[j - 1] then 0 else 1 in
        d.(i).(j) <- min (min (d.(i - 1).(j) + 1) (d.(i).(j - 1) + 1))
                         (d.(i - 1).(j - 1) + cost)
      done
    done;
    d.(m).(n)

(** Find the closest matching name from a list of candidates.
    Returns Some name if there is a match within a reasonable edit distance.
    The threshold is max(2, len/3) — allowing up to ~33% character changes. *)
let suggest_names_with_scores name candidates =
  let max_dist = max 2 (String.length name / 3) in
  let scored = List.filter_map (fun c ->
    let d = levenshtein name c in
    if d > 0 && d <= max_dist then Some (c, d) else None
  ) candidates in
  List.sort (fun (_, d1) (_, d2) -> compare d1 d2) scored

let suggest_name name candidates =
  match suggest_names_with_scores name candidates with
  | (best, _) :: _ -> Some best
  | [] -> None

(** Hint for common type conversion between two types *)
let type_conversion_hint left_type right_type =
  match (left_type, right_type) with
  | ("String", "Int") | ("String", "Float") ->
    Some "Strings cannot be used in arithmetic. Convert with int() or float() if available, or check your data types."
  | ("Int", "String") | ("Float", "String") ->
    Some "Cannot combine numbers with strings. Use string concatenation (+) with two strings."
  | ("Bool", "Int") | ("Bool", "Float") | ("Int", "Bool") | ("Float", "Bool") ->
    Some "Booleans and numbers cannot be combined in arithmetic. Use if-else to branch on boolean values."
  | ("List", "Int") | ("List", "Float") | ("Int", "List") | ("Float", "List") ->
    Some "Use map() to apply arithmetic operations to each element of a list."
  | _ -> None

(** Create a structured error value *)
let make_error ?location ?(context=[]) ?(na_count=0) code message =
  VError { code; message; context; location; na_count }

(** Create a builtin function value (wraps func to strip arg names) *)
let make_builtin ?name ?(variadic=false) ?(unwrap=true) arity func =
  let arg_proj =
    if unwrap then (fun (_, v) -> !meta_pipeline_flatten_resolver (Utils.unwrap_value v))
    else (fun (_, v) -> !meta_pipeline_flatten_resolver v)
  in
  VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
             b_func = (fun named_args env_ref -> func (List.map arg_proj named_args) !env_ref) }

(** Create a builtin function value that receives named args *)
let make_builtin_named ?name ?(variadic=false) ?(unwrap=true) arity func =
  let arg_proj =
    if unwrap then (fun (n, v) -> (n, !meta_pipeline_flatten_resolver (Utils.unwrap_value v)))
    else (fun (n, v) -> (n, !meta_pipeline_flatten_resolver v))
  in
  VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
             b_func = (fun named_args env_ref -> func (List.map arg_proj named_args) !env_ref) }


(** Check if a value is an error *)
let is_error_value = function VError _ -> true | _ -> false

(** Check if a value is NA *)
let is_na_value = function VNA _ -> true | _ -> false

(** Runtime type compatibility check.
    Checks if a value matches a given type specification. *)
let rec is_compatible (v : value) (t : typ) : bool =
  match v, t with
  | _, TVar _ -> true (* Generics match anything at runtime for now *)
  | _, TCustom "Any" -> true
  | _, TUnknown -> true (* Unknown annotations cannot fail: nothing to check against *)
  | VInt _, TInt -> true
  | VFloat _, TFloat -> true
  | VBool _, TBool -> true
  | VString _, TString -> true
  | VRawCode _, TString -> true
  | VNA _, TCustom "NA" -> true
  | VNA _, _ -> true (* NA is compatible with any type (it's a special bottom/missing value) *)
  | VError _, _ -> true (* Errors flow through every type (bottom value), like NA: they propagate instead of raising spurious mismatches *)
  
  | VList _, TList None -> true
  | VList items, TList (Some et) ->
      List.for_all (fun (_, ev) -> is_compatible ev et) items
  
  | VDict _, TDict (None, None) -> true
  | VDict pairs, TDict (Some kt, Some vt) ->
      List.for_all (fun (k, v) -> 
        is_compatible (VString k) kt && is_compatible v vt
      ) pairs

  | VList items, TTuple ts ->
      List.length items = List.length ts &&
      List.for_all2 (fun (_, ev) et -> is_compatible ev et) items ts
  
  | VVector _, TList _ -> true (* Treat Vectors as compatible with List types for runtime checks *)
  | VNDArray _, TCustom "NDArray" -> true
  | VDataFrame _, TDataFrame _ -> true
  
  | VLambda _, TCustom "Function" -> true
  | VBuiltin _, TCustom "Function" -> true
  | VLambda _, TArrow _ -> true
  | VBuiltin _, TArrow _ -> true

  (* Nominal records: the type name is identity. A record is never a Dict
     and never another record type, even with an identical field shape. *)
  | VRecord r, TCustom name -> name = "Record" || r.rec_type = name
  (* Nominal unions: same rule by type name. Payload shapes never merge. *)
  | VUnion u, TCustom name -> u.un_type = name

  (* Relaxed numeric matching: Int can often be used where Float is expected in T *)
  | VInt _, TFloat -> true

  | VComputedNode _, TComputedNode -> true
  | VBuildLog _, TCustom "BuildLog" -> true
  | VExpr _, TExpr -> true
  | VQuo _, TExpr -> true
  | VExpr _, TCustom "Expr" | VQuo _, TCustom "Expr" -> true
  | VFactor _, TCustom "Factor" -> true
  | VNodeResult _, TCustom "NodeResult" -> true
  | VIntent _, TCustom "Intent" -> true
  | VQuo _, TCustom "Quosure" -> true
  | VShellResult _, TCustom "ShellResult" -> true

  (* Closed strategy type (permissive at value level): `Strategy` documents
     the closed set (`default`, `^csv`, `^json`, `^ipc`, `^parquet`, `^pmml`,
     `^onnx`, `^bin`, `^text`, `^tlang`, or a strategy dict with `format`
     plus inline snippets). Value-level checks stay permissive on purpose:
     custom formats are validated with pipeline context (runtime, role) in
     eval/validation, so rejecting shapes here would hide the precise
     diagnostic. The closed dict shape is enforced in
     pipeline_validation.check_known_formats. *)
  | VSymbol _, TCustom "Strategy" -> true
  | VSerializer _, TCustom "Strategy" -> true
  | VDict _, TCustom "Strategy" -> true
  | VPipeline _, TCustom "Pipeline" -> true
  | VMetaPipeline _, TCustom ("Pipeline" | "MetaPipeline") -> true

  | v, TUnion ts -> List.exists (fun t -> is_compatible v t) ts

  | _ -> false

(** Check if two AST types are compatible.

    Used to compare inferred types against user-provided annotations.
    Allows Int where Float is expected (T's relaxed numeric matching).
    [TCustom "Any"] matches anything.

    @param a The first type (typically inferred).
    @param b The second type (typically the annotation).
    @return [true] if the types are compatible. *)
let rec types_compatible a b =
  (* Element-wise compatibility where an unknown side (None) matches
     anything. Gives nested numeric widening (List[Int] fits List[Float])
     for free via the recursive call. *)
  let opt_compat x y = match x, y with
    | None, _ | _, None -> true
    | Some x, Some y -> types_compatible x y
  in
  match a, b with
  | _, TCustom "Any" -> true
  | TCustom "Any", _ -> true
  | _, TVar _ -> true
  | TVar _, _ -> true
  | _, TUnknown -> true
  | TUnknown, _ -> true
  | TInt, TFloat -> true
  | TFloat, TInt -> false
  | TArrow (p1, r1), TArrow (p2, r2) ->
      List.length p1 = List.length p2 &&
      List.for_all2 types_compatible p1 p2 &&
      types_compatible r1 r2
  | TList x, TList y -> opt_compat x y
  | TDict (a1, a2), TDict (b1, b2) -> opt_compat a1 b1 && opt_compat a2 b2
  | TUnion as_, TUnion bs ->
      List.for_all (fun a -> List.exists (fun b -> types_compatible a b) bs) as_
  | TUnion as_, b ->
      List.for_all (fun a -> types_compatible a b) as_
  | a, TUnion bs ->
      List.exists (fun b -> types_compatible a b) bs
  | _ -> a = b
