(* src/ast.ml *)
(* Phase 1: Values, Types, and Errors for the T language alpha. *)
(* Extends Phase 0 with explicit missingness, structured errors, *)
(* and placeholder types for vectors and DataFrames. *)

(** Environment module — immutable string map *)
module Env = Map.Make(String)

type symbol = string

(** NA type tags — missingness is explicit and typed *)
type na_type =
  | NABool
  | NAInt
  | NAFloat
  | NAString
  | NAGeneric

(** Symbolic error codes *)
type error_code =
  | TypeError
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
  | GenericError

(** Structured error information *)
type error_info = {
  code : error_code;
  message : string;
  context : (string * value) list;
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

(** Phase 3: Pipeline node definition *)
and pipeline_node = {
  node_name : string;
  node_expr : expr;
}

(** Phase 3: Pipeline result with cached values and dependency info *)
and pipeline_result = {
  p_nodes : (string * value) list;           (* Cached node results *)
  p_exprs : (string * expr) list;            (* Original expressions *)
  p_deps  : (string * string list) list;     (* Dependency graph *)
  p_imports : stmt list;                     (* Import statements to propagate into Nix sandboxes *)
}

(** Formula specification — captures LHS/RHS of ~ expressions *)
and formula_spec = {
  response: string list;
  predictors: string list;
  raw_lhs: expr;
  raw_rhs: expr;
}

(** Runtime values *)
and value =
  (* Scalar Types *)
  | VInt of int
  | VFloat of float
  | VBool of bool
  | VString of string
  | VSymbol of symbol
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
  | VNull
  (* Phase 6: Intent block value *)
  | VIntent of intent_block
  (* Formula value *)
  | VFormula of formula_spec

and builtin = {
  b_name: string option;
  b_arity: int;
  b_variadic: bool;
  b_func: ((string option * value) list -> value Env.t -> value);
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

and expr =
  | Value of value
  | Var of symbol
  | ColumnRef of string  (* NSE: $column_name references *)
  | Call of { fn : expr; args : (string option * expr) list }
  | Lambda of lambda
  | IfElse of { cond : expr; then_ : expr; else_ : expr }
  | ListLit of (string option * expr) list
  | ListComp of { expr : expr; clauses : comp_clause list }
  | DictLit of (string * expr) list
  | BinOp of { op : binop; left : expr; right : expr }
  | UnOp of { op : unop; operand : expr }
  | DotAccess of { target : expr; field : string }
  | BroadcastOp of { op : binop; left : expr; right : expr }
  | PipelineDef of pipeline_node list
  | IntentDef of (string * expr) list

  | Block of stmt list

and stmt =
  | Expression of expr
  | Assignment of { name : symbol; typ : typ option; expr : expr }
  | Reassignment of { name : symbol; expr : expr }
  | Import of string
  | ImportPackage of string
  | ImportFrom of { package: string; names: import_spec list }

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
  | TNull
  | TList of typ option
  | TDict of typ option * typ option
  | TTuple of typ list
  | TDataFrame of typ option
  | TVar of string
  | TCustom of string

type program = stmt list

(** Convenience type alias *)
type environment = value Env.t

module Utils = struct
  let is_truthy = function
    | VBool false | VNull | VInt 0 -> false
    | VError _ -> false
    | VNA _ -> false
    | _ -> true

  (** Check if an expression is a column reference and extract the column name.
      Intended for use in NSE-aware functions that need to inspect AST nodes
      before evaluation (e.g., future filter/mutate NSE support). *)
  let is_column_ref = function
    | ColumnRef field -> Some field
    | _ -> None

  (** Extract column name from a runtime value, supporting NSE ($column) syntax.
      Used by data verbs (select, arrange, group_by, etc.) to accept
      $column_name NSE syntax. *)
  let extract_column_name = function
    | VSymbol s when String.length s > 0 && s.[0] = '$' ->
        Some (String.sub s 1 (String.length s - 1))
    | VSymbol s -> Some s
    | VString s -> Some s
    | _ -> None

  let error_code_to_string = function
    | TypeError -> "TypeError"
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
    | GenericError -> "GenericError"

  let na_type_to_string = function
    | NABool -> "Bool"
    | NAInt -> "Int"
    | NAFloat -> "Float"
    | NAString -> "String"
    | NAGeneric -> ""

  let rec typ_to_string = function
    | TInt -> "Int"
    | TFloat -> "Float"
    | TBool -> "Bool"
    | TString -> "String"
    | TNull -> "Null"
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

  let type_name = function
    | VInt _ -> "Int" | VFloat _ -> "Float"
    | VBool _ -> "Bool" | VString _ -> "String"
    | VSymbol _ -> "Symbol" | VList _ -> "List" | VDict _ -> "Dict"
    | VVector _ -> "Vector" | VNDArray _ -> "NDArray" | VDataFrame _ -> "DataFrame"
    | VPipeline _ -> "Pipeline"
    | VLambda _ -> "Function" | VBuiltin _ -> "BuiltinFunction"
    | VNA _ -> "NA" | VError _ -> "Error" | VNull -> "Null"
    | VIntent _ -> "Intent"
    | VFormula _ -> "Formula"

  let rec value_to_string = function
    | VInt n -> string_of_int n
    | VFloat f -> string_of_float f
    | VBool b -> string_of_bool b
    | VString s -> "\"" ^ String.escaped s ^ "\""
    | VSymbol s -> s
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
        Printf.sprintf "Pipeline(%d nodes: [%s])"
          (List.length p_nodes) (String.concat ", " node_names)
    | VLambda { params; variadic; _ } ->
        let dots = if variadic then ", ..." else "" in
        "\\(" ^ String.concat ", " params ^ dots ^ ") -> <function>"
    | VBuiltin _ -> "<builtin_function>"
    | VNA na_t ->
        let tag = na_type_to_string na_t in
        if tag = "" then "NA" else "NA(" ^ tag ^ ")"
    | VError { code; message; _ } ->
        "Error(" ^ error_code_to_string code ^ ": \"" ^ message ^ "\")"
    | VNull -> "null"
    | VIntent { intent_fields } ->
        let field_to_string (k, v) = k ^ ": \"" ^ String.escaped v ^ "\"" in
        "Intent{" ^ (intent_fields |> List.map field_to_string |> String.concat ", ") ^ "}"
    | VFormula { response; predictors; _ } ->
        Printf.sprintf "%s ~ %s"
          (String.concat " + " response)
          (String.concat " + " predictors)

  let value_to_raw_string = function
    | VString s -> s
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
let make_error ?(context=[]) code message =
  VError { code; message; context }

(** Create a builtin function value (wraps func to strip arg names) *)
let make_builtin ?name ?(variadic=false) arity func =
  VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
             b_func = (fun named_args env -> func (List.map snd named_args) env) }

(** Create a builtin function value that receives named args *)
let make_builtin_named ?name ?(variadic=false) arity func =
  VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic; b_func = func }

(** Check if a value is an error *)
let is_error_value = function VError _ -> true | _ -> false

(** Check if a value is NA *)
let is_na_value = function VNA _ -> true | _ -> false

(** Runtime type compatibility check.
    Checks if a value matches a given type specification. *)
let rec is_compatible (v : value) (t : typ) : bool =
  match v, t with
  | _, TVar _ -> true (* Generics match anything at runtime for now *)
  | VInt _, TInt -> true
  | VFloat _, TFloat -> true
  | VBool _, TBool -> true
  | VString _, TString -> true
  | VNull, TNull -> true
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

  | _ -> false
