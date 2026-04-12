(* src/ast.ml *)
(* Phase 1: Values, Types, and Errors for the T language alpha. *)
(* Extends Phase 0 with explicit missingness, structured errors, *)
(* and placeholder types for vectors and DataFrames. *)

(** Environment module — immutable string map *)
module Env = Map.Make(String)
module String_set = Set.Make(String)

type symbol = string


(** NA type tags — missingness is explicit and typed *)
type na_type =
  | NABool
  | NAInt
  | NAFloat
  | NAString
  | NADate
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
}

(** Runtime values *)
and value =
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
  | VVector of value array
  | VNDArray of ndarray
  | VDataFrame of dataframe
  | VPipeline of pipeline_result
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



and builtin = {
  b_name: string option;
  b_arity: int;
  b_variadic: bool;
  b_func: ((string option * value) list -> value Env.t ref -> value);
}

and lambda = {
  params : symbol list;
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
  | ListComp of { expr : expr; clauses : comp_clause list }
  | DictLit of (string * expr) list
  | BinOp of { op : binop; left : expr; right : expr }
  | UnOp of { op : unop; operand : expr }
  | DotAccess of { target : expr; field : string }
  | RawCode of { raw_text : string; raw_identifiers : string list }  (* Foreign code block <{ ... }> *)
  | BroadcastOp of { op : binop; left : expr; right : expr }
  | PipelineDef of (string * expr) list
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
  | Import of string
  | ImportPackage of string
  | ImportFrom of { package: string; names: import_spec list }
  | ImportFileFrom of { filename: string; names: import_spec list }

and import_spec = {
  import_name: string;
  import_alias: string option;
}

and binop = Plus | Minus | Mul | Div | Mod | Eq | NEq | Gt | Lt | GtEq | LtEq | And | Or | BitAnd | BitOr
  | In (* New: membership check *) | Pipe | MaybePipe | Formula
and unop = Not | Neg
and comp_clause = CFor of { var : symbol; iter : expr } | CFilter of expr

and typ =
  | TInt
  | TFloat
  | TBool
  | TString
  | TList of typ option
  | TDict of typ option * typ option
  | TTuple of typ list
  | TDataFrame of typ option
  | TVar of string
  | TCustom of string
  | TComputedNode
  | TSerializer
  | TExpr

type program = stmt list

(** Located constructors and accessors *)
let mk_expr ?loc node = { node; loc }
let mk_stmt ?loc node = { node; loc }
let expr_node (e : expr) = e.node
let expr_loc (e : expr) = e.loc
let stmt_node (s : stmt) = s.node
let stmt_loc (s : stmt) = s.loc

(** Global hook for resolving node names to values (e.g. from build logs) *)
let node_resolver : (string -> value option) ref = ref (fun _ -> None)

(** Extract identifier-like tokens from a raw code string.
    Used by RawCode blocks for automatic pipeline dependency detection.
    Scans for [a-zA-Z_][a-zA-Z0-9_]* patterns and returns unique results.
    Strips lines starting with # or -- to avoid false positives from comments. *)
let extract_identifiers text =
  let lines = String.split_on_char '\n' text in
  let filtered_lines =
    lines
    |> List.filter_map (fun line ->
        let trimmed = String.trim line in
        if String.starts_with ~prefix:"--" trimmed then
          None
        else if String.starts_with ~prefix:"#" trimmed && not (String.starts_with ~prefix:"#!" trimmed) then
          None
        else
          Some line)
  in
  let filtered_text = String.concat "\n" filtered_lines in
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
  let all_set = List.fold_left (fun acc d -> String_set.add d acc) String_set.empty inferred in
  String_set.elements all_set

(** Convenience type alias *)
type environment = value Env.t

module Utils = struct
  let empty_node_diagnostics = {
    nd_warnings = [];
    nd_error = None;
  }

  let rec unwrap_value = function
    | VNodeResult { v; _ } -> unwrap_value v
    | v -> v

  let rec is_truthy = function
    | VBool false | VInt 0 -> false
    | VError _ -> false
    | VNA _ -> false
    | VNodeResult { v; _ } -> is_truthy v
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
    let warning_count = List.length warning_nodes in
    let error_count = List.length error_nodes in
    VDict [
      ("warning_nodes", VList warning_nodes);
      ("error_nodes", VList error_nodes);
      ("summary",
       VString
         (Printf.sprintf "%d nodes with warnings, %d errors" warning_count error_count));
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
    | _ -> RuntimeError

  let na_type_to_string = function
    | NABool -> "Bool"
    | NAInt -> "Int"
    | NAFloat -> "Float"
    | NAString -> "String"
    | NADate -> "Date"
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
    | TDataFrame None -> "DataFrame"
    | TDataFrame (Some schema) -> "DataFrame[" ^ typ_to_string schema ^ "]"
    | TVar s -> s
    | TCustom s -> s
    | TComputedNode -> "ComputedNode"
    | TSerializer -> "Serializer"
    | TExpr -> "Expression"

  let rec type_name = function
    | VInt _ -> "Int" | VFloat _ -> "Float"
    | VBool _ -> "Bool" | VString _ -> "String" | VRawCode _ -> "Code"
    | VSymbol _ -> "Symbol" | VDate _ -> "Date" | VDatetime _ -> "Datetime"
    | VList _ -> "List" | VDict _ -> "Dict"
    | VVector _ -> "Vector" | VNDArray _ -> "NDArray" | VDataFrame _ -> "DataFrame"
    | VPipeline _ -> "Pipeline"
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
    | VExpr _ -> "Expression"
    | VQuo _ -> "Quosure"
    | VShellResult _ -> "ShellResult"
    | VUnquote _ -> "Unquote"
    | VUnquoteSplice _ -> "UnquoteSplice"
    | VDynamicArg _ -> "DynamicArg"
    | VEnv _ -> "Environment"
    | VNodeResult { v; _ } -> type_name v

  let rec binop_to_string = function
    | Plus -> "+" | Minus -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%"
    | Eq -> "==" | NEq -> "!=" | Gt -> ">" | Lt -> "<" | GtEq -> ">=" | LtEq -> "<="
    | And -> "&&" | Or -> "||" | BitAnd -> "&" | BitOr -> "|"
    | In -> "in" | Pipe -> "|>" | MaybePipe -> "?|>" | Formula -> "~"

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
    | Lambda { params; body; _ } ->
        "\\(" ^ String.concat ", " params ^ ") " ^ unparse_expr body
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
    | BroadcastOp { op; left; right } ->
        unparse_expr left ^ " ." ^ binop_to_string op ^ " " ^ unparse_expr right
    | Unquote e -> "!!" ^ unparse_expr e
    | UnquoteSplice e -> "!!!" ^ unparse_expr e
    | Block stmts -> "{ " ^ (List.map unparse_stmt stmts |> String.concat "; ") ^ " }"
    | ListComp _ -> "[...]"
    | ShellExpr cmd -> "?<{ " ^ cmd ^ " }>"
    | IntentDef _ -> "intent { ... }"

  and unparse_stmt stmt =
    match stmt.node with
    | Expression e -> unparse_expr e
    | Assignment { name; expr; _ } -> name ^ " = " ^ unparse_expr expr
    | Reassignment { name; expr } -> name ^ " := " ^ unparse_expr expr
    | Import s -> "import \"" ^ s ^ "\""
    | ImportPackage s -> "import " ^ s
    | ImportFrom { package; names } -> 
        "import " ^ package ^ " [" ^ String.concat ", " (List.map (fun is -> is.import_name) names) ^ "]"
    | ImportFileFrom { filename; names } -> 
        "import \"" ^ filename ^ "\" [" ^ String.concat ", " (List.map (fun is -> is.import_name) names) ^ "]"

  and value_to_string = function
    | VInt n -> string_of_int n
    | VFloat f -> string_of_float f
    | VBool b -> string_of_bool b
    | VString s -> "\"" ^ String.escaped s ^ "\""
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
          | Some name when name <> "" -> "[" ^ name ^ "]"
          | _ -> "[UTC]"
        in
        "Datetime(" ^ base ^ frac ^ "Z" ^ tz_suffix ^ ")"
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
    | VPipeline { p_nodes; _ } ->
        let node_names = List.map fst p_nodes in
        let base = Printf.sprintf "Pipeline(%d nodes: [%s])"
          (List.length p_nodes) (String.concat ", " node_names) in
        let errors = List.filter_map (fun (name, v) ->
          match v with
          | VError err -> Some (Printf.sprintf "\n  - `%s` failed: %s" name err.message)
          | _ -> None
        ) p_nodes in
        if errors = [] then base
        else base ^ "\nErrors:" ^ (String.concat "" errors)
    | VLambda { params; variadic; _ } ->
        let dots = if variadic then ", ..." else "" in
        "\\(" ^ String.concat ", " params ^ dots ^ ") -> <function>"
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
    | VIntent { intent_fields } ->
        let field_to_string (k, v) = k ^ ": \"" ^ String.escaped v ^ "\"" in
        "Intent{" ^ (intent_fields |> List.map field_to_string |> String.concat ", ") ^ "}"
    | VFormula { response; predictors; _ } ->
        Printf.sprintf "%s ~ %s"
          (String.concat " + " response)
          (String.concat " + " predictors)
    | VExpr e ->
        Printf.sprintf "expr(%s)" (unparse_expr e)
    | VQuo { q_expr; _ } ->
        Printf.sprintf "quo(%s)" (unparse_expr q_expr)
    | VComputedNode cn ->
        Printf.sprintf "computed_node<%s>\nserializer: %s\nclass: %s\npath: %s"
          cn.cn_runtime cn.cn_serializer cn.cn_class cn.cn_path
    | VSerializer s ->
        Printf.sprintf "serializer<^%s>" s.s_format
    | VNode un ->
        Printf.sprintf "node<%s>(...)" un.un_runtime
    | VShellResult { sr_stdout; _ } ->
        (* Display as the raw stdout string so ?<{cmd}> behaves like a string *)
        "\"" ^ String.escaped sr_stdout ^ "\""
    | VUnquote v -> "!!" ^ value_to_string v
    | VUnquoteSplice v -> "!!!" ^ value_to_string v
    | VDynamicArg (n, v) -> n ^ " := " ^ value_to_string v
    | VEnv _ -> "<environment>"
    | VNodeResult { v; _ } -> value_to_string v

  let value_to_raw_string = function
    | VString s -> s
    | VRawCode s -> s
    | VShellResult { sr_stdout; _ } -> sr_stdout
    | VFloat f ->
        if f = floor f then
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
let suggest_name name candidates =
  let max_dist = max 2 (String.length name / 3) in
  let scored = List.filter_map (fun c ->
    let d = levenshtein name c in
    if d > 0 && d <= max_dist then Some (c, d) else None
  ) candidates in
  match List.sort (fun (_, d1) (_, d2) -> compare d1 d2) scored with
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
let make_builtin ?name ?(variadic=false) arity func =
  VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
             b_func = (fun named_args env_ref -> func (List.map (fun (_, v) -> Utils.unwrap_value v) named_args) !env_ref) }

(** Create a builtin function value that receives named args *)
let make_builtin_named ?name ?(variadic=false) arity func =
  VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
             b_func = (fun named_args env_ref -> func (List.map (fun (n, v) -> (n, Utils.unwrap_value v)) named_args) !env_ref) }


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
  | VInt _, TInt -> true
  | VFloat _, TFloat -> true
  | VBool _, TBool -> true
  | VString _, TString -> true
  | VRawCode _, TString -> true
  | VNA _, TCustom "NA" -> true
  | VNA _, _ -> true (* NA is compatible with any type (it's a special bottom/missing value) *)
  
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

  (* Relaxed numeric matching: Int can often be used where Float is expected in T *)
  | VInt _, TFloat -> true

  | VComputedNode _, TComputedNode -> true
  | VExpr _, TExpr -> true
  | VQuo _, TExpr -> true

  | _ -> false
