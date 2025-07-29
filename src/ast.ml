(* src/ast.ml *)
(* Revised AST incorporating feedback on location tracking and concrete types. *)

type symbol = string [@@deriving show, eq]

(** The location of a token or expression in the source code. *)
type location = {
  line: int;
  col_start: int;
  col_end: int;
} [@@deriving show, eq]


(** Runtime values that expressions can evaluate to. *)
type value =
  | VInt32 of int32
  | VInt64 of int64
  | VFloat32 of float
  | VFloat64 of float
  | VBool of bool
  | VString of string
  | VSymbol of symbol            (** Bare names for NSE, e.g., `select(df, name)`) *)
  | VList of (string option * value) list
  | VDict of (string * value) list
  | VLambda of lambda
  | VDataFrame of dataframe
  | VBuiltin of builtin         (** Wrapper for native OCaml functions *)
  | VError of string
  | VNull
[@@deriving show, eq]

(**
 * A native OCaml function exposed to the T language.
 * Arity checking is handled by the evaluator before calling `func`.
 *)
and builtin = {
  arity: int;
  variadic: bool;
  func: (value list -> environment -> value);
}
[@@deriving show] (* `eq` cannot be derived for functions *)

and environment = value Map.Make(String).t

and lambda = {
  params : symbol list;
  variadic : bool;
  body : expr;
  (**
   * The captured lexical environment.
   * This is `None` at parse time and becomes `Some(env)` at evaluation time,
   * turning a lambda definition into a runtime closure.
   *)
  env : environment option;
} [@@deriving show, eq]

(** The AST node for an expression, without location info. *)
and expr_node =
  | EValue of value
  | EVar of symbol
  | ECall of { fn : expr; args : (string option * expr) list }
  | ELambda of lambda
  | EIfElse of { cond : expr; then_ : expr; else_ : expr }
  | EListLit of (string option * expr) list
  | EListComp of { expr : expr; clauses : comp_clause list }
  | EDictLit of (string * expr) list
  | EBinOp of { op : binop; left : expr; right : expr }
  | EUnOp of { op : unop; operand : expr }
  | EDotAccess of { target: expr; field: string }
[@@deriving show, eq]

(** An expression is a node plus its location in the source code. *)
and expr = {
  enode: expr_node;
  eloc: location option;
}
[@@deriving show, eq]

and binop = Plus | Minus | Mul | Div | Eq | NEq | Gt | Lt | GtEq | LtEq | And | Or | Pipe
[@@deriving show, eq]

and unop = Not | Neg
[@@deriving show, eq]

and comp_clause =
  | CFor of { var : symbol; iter : expr }
  | CFilter of expr
[@@deriving show, eq]

and typ = TInt64 | TFloat64 | TBool | TString | TList | TDict | TDataFrame | TCustom of string
[@@deriving show, eq]

(** A top-level statement node, without location info. *)
and stmt_node =
  | SAssignment of { name: symbol; typ: typ option; expr: expr }
  | SExpression of expr
[@@deriving show, eq]

(** A statement is a node plus its location in the source code. *)
and statement = {
  snode: stmt_node;
  sloc: location option;
}
[@@deriving show, eq]

and dataframe = {
  columns : (string * value array) list;
  nrows : int;
  metadata : (string * value) list;
} [@@deriving show, eq]

type program = statement list [@@deriving show, eq]

(** Helper modules for constructing and inspecting AST nodes *)
module Constructors = struct
  let with_no_loc node = { node with loc = None }

  let expr enode = { enode; eloc = None }
  let stmt snode = { snode; sloc = None }

  let int64 i = expr (EValue (VInt64 i))
  let float64 f = expr (EValue (VFloat64 f))
  let bool b = expr (EValue (VBool b))
  let string s = expr (EValue (VString s))
  let symbol s = expr (EValue (VSymbol s))
  let null = expr (EValue VNull)

  let assign name ?typ e = stmt (SAssignment { name; typ; expr = e })
  let expr_stmt e = stmt (SExpression e)
  let var s = expr (EVar s)
  let call fn args = expr (ECall { fn; args })
  let binop op left right = expr (EBinOp { op; left; right })
  let unop op operand = expr (EUnOp { op; operand })
  let dot target field = expr (EDotAccess { target; field })
  let if_ cond then_ else_ = expr (EIfElse { cond; then_; else_ })
  let lambda params variadic body = expr (ELambda { params; variadic; body; env = None })
  let list_lit items = expr (EListLit items)
end

module Utils = struct
  let is_truthy = function
    | VBool false | VNull | VInt64 0L -> false
    | VError _ -> false
    | _ -> true

  let type_name = function
    | VInt32 _ -> "Int32" | VInt64 _ -> "Int64"
    | VFloat32 _ -> "Float32" | VFloat64 _ -> "Float64"
    | VBool _ -> "Bool" | VString _ -> "String"
    | VSymbol _ -> "Symbol" | VList _ -> "List"
    | VDict _ -> "Dict" | VLambda _ -> "Function"
    | VDataFrame _ -> "DataFrame" | VBuiltin _ -> "BuiltinFunction"
    | VError _ -> "Error" | VNull -> "Null"

  let rec value_to_string = function
    | VInt64 n -> Int64.to_string n
    | VFloat64 f -> string_of_float f
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
    | VLambda { params; variadic; _ } ->
        let dots = if variadic then ", ..." else "" in
        "\\(" ^ String.concat ", " params ^ dots ^ ") -> <function>"
    | VDataFrame { columns; nrows; _ } ->
        Printf.sprintf "<DataFrame %dx%d>" (List.length columns) nrows
    | VBuiltin _ -> "<builtin_function>"
    | VError msg -> "Error(\"" ^ msg ^ "\")"
    | VNull -> "null"
    | _ -> "<unhandled_value>" (* For other numeric types for now *)
end

(** Custom exceptions for different failure modes in the interpreter. *)
exception Name_error of string * location option
exception Type_error of string * location option
exception Arity_error of string * location option

(* Note: The custom 'a result type has been removed in favor of the standard library's Result.t *)
