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
  | GenericError

(** Structured error information *)
type error_info = {
  code : error_code;
  message : string;
  context : (string * value) list;
}

(** DataFrame type — Phase 2 base, Phase 4 adds group_keys *)
and dataframe = {
  columns : (string * value array) list;
  nrows : int;
  group_keys : string list;
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
  | VDataFrame of dataframe
  | VPipeline of pipeline_result
  (* Functional Types *)
  | VLambda of lambda
  | VBuiltin of builtin
  (* Special Values *)
  | VNA of na_type
  | VError of error_info
  | VNull

and builtin = {
  b_arity: int;
  b_variadic: bool;
  b_func: (value list -> value Env.t -> value);
}

and lambda = {
  params : symbol list;
  variadic : bool;
  body : expr;
  env : value Env.t option;
}

and expr =
  | Value of value
  | Var of symbol
  | Call of { fn : expr; args : (string option * expr) list }
  | Lambda of lambda
  | IfElse of { cond : expr; then_ : expr; else_ : expr }
  | ListLit of (string option * expr) list
  | ListComp of { expr : expr; clauses : comp_clause list }
  | DictLit of (string * expr) list
  | BinOp of { op : binop; left : expr; right : expr }
  | UnOp of { op : unop; operand : expr }
  | DotAccess of { target : expr; field : string }
  | Block of expr list
  | PipelineDef of pipeline_node list

and binop = Plus | Minus | Mul | Div | Eq | NEq | Gt | Lt | GtEq | LtEq | And | Or | Pipe
and unop = Not | Neg
and comp_clause = CFor of { var : symbol; iter : expr } | CFilter of expr

type typ = TInt | TFloat | TBool | TString | TList | TDict | TDataFrame | TCustom of string

type stmt =
  | Expression of expr
  | Assignment of { name : symbol; typ : typ option; expr : expr }

type program = stmt list

(** Convenience type alias *)
type environment = value Env.t

module Utils = struct
  let is_truthy = function
    | VBool false | VNull | VInt 0 -> false
    | VError _ -> false
    | VNA _ -> false
    | _ -> true

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
    | GenericError -> "GenericError"

  let na_type_to_string = function
    | NABool -> "Bool"
    | NAInt -> "Int"
    | NAFloat -> "Float"
    | NAString -> "String"
    | NAGeneric -> ""

  let type_name = function
    | VInt _ -> "Int" | VFloat _ -> "Float"
    | VBool _ -> "Bool" | VString _ -> "String"
    | VSymbol _ -> "Symbol" | VList _ -> "List" | VDict _ -> "Dict"
    | VVector _ -> "Vector" | VDataFrame _ -> "DataFrame"
    | VPipeline _ -> "Pipeline"
    | VLambda _ -> "Function" | VBuiltin _ -> "BuiltinFunction"
    | VNA _ -> "NA" | VError _ -> "Error" | VNull -> "Null"

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
        let pair_to_string (k, v) = "`" ^ k ^ "`: " ^ value_to_string v in
        "{" ^ (pairs |> List.map pair_to_string |> String.concat ", ") ^ "}"
    | VVector arr ->
        let items = Array.to_list arr |> List.map value_to_string in
        "Vector[" ^ String.concat ", " items ^ "]"
    | VDataFrame { columns; nrows; group_keys } ->
        let col_names = List.map fst columns in
        let base = Printf.sprintf "DataFrame(%d rows x %d cols: [%s])"
          nrows (List.length columns) (String.concat ", " col_names) in
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
end
