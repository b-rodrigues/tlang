(** ast.ml *)
(** Abstract Syntax Tree for the T programming language *)
(** Revised to incorporate list literals, dot access, and a statement/expression distinction. *)

type symbol = string [@@deriving show, eq]

(** Operators - using variants for type safety *)
type binop =
  | Plus | Minus | Mul | Div  (** Arithmetic *)
  | Eq | NEq | Gt | Lt | GtEq | LtEq (** Comparison *)
  | And | Or                  (** Logical *)
  | Pipe                      (** Pipe operator *)
[@@deriving show, eq]

type unop = Not | Neg
[@@deriving show, eq]

(** Runtime values that expressions evaluate to *)
type value =
  | Int of int
  | Float of float
  | Bool of bool
  | String of string
  | Symbol of symbol            (** Bare names for NSE, e.g., `select(df, name)`) *)
  | List of (string option * value) list  (** Named (`[a:1]`) or unnamed (`[1]`) *)
  | Dict of (string * value) list
  | Lambda of lambda
  | DataFrame of dataframe
  | Error of string
  | Null
[@@deriving show, eq]

and lambda = {
  params : symbol list;
  variadic : bool;              (** True if `...` is present *)
  body : expr;
  env : (symbol * value) list option; (** For closures *)
} [@@deriving show, eq]

(** Expressions - structures that evaluate to a value *)
and expr =
  | Value of value
  | Var of symbol
  | Call of { fn : expr; args : expr list }
  | Lambda of lambda
  | IfElse of { cond : expr; then_ : expr; else_ : expr }
  | ListLit of (string option * expr) list (** [1, 2] or [a: 1, b: 2] *)
  | ListComp of { expr : expr; clauses : comp_clause list }
  | DictLit of (string * expr) list
  | BinOp of { op : binop; left : expr; right : expr }
  | UnOp of { op : unop; operand : expr }
  | DotAccess of { target: expr; field: string }
[@@deriving show, eq]

(** A clause in a list comprehension, e.g., `for x in list` or `if x > 2` *)
and comp_clause =
  | For of { var : symbol; iter : expr }
  | Filter of expr
[@@deriving show, eq]

(** Types for optional annotations, parsed but not yet enforced *)
and typ =
  | TInt | TFloat | TBool | TString | TSymbol | TList | TDict | TFunction | TDataFrame
  | TCustom of string
[@@deriving show, eq]

(** Statements - top-level constructs. A program is a list of statements. *)
and statement =
  | Assignment of { name: symbol; typ: typ option; expr: expr } (** e.g., x = 3 or x: Int = 3 *)
  | Expression of expr                                        (** e.g., a function call like print(x) *)
[@@deriving show, eq]

and dataframe = {
  columns : (string * value array) list;
  nrows : int;
  metadata : (string * value) list;
} [@@deriving show, eq]

(** A program is a list of statements *)
type program = statement list [@@deriving show, eq]

type location = {
  line : int;
  column : int;
  filename : string;
} [@@deriving show, eq]

type located_expr = {
  expr : expr;
  loc : location option;
} [@@deriving show, eq]

(** Helper modules for constructing and inspecting AST nodes *)
module Constructors = struct
  let int n = Value (Int n)
  let float f = Value (Float f)
  let bool b = Value (Bool b)
  let string s = Value (String s)
  let symbol s = Value (Symbol s)
  let null = Value Null
  let error msg = Value (Error msg)

  let assign name ?typ expr = Assignment { name; typ; expr }
  let expr_stmt e = Expression e
  let var s = Var s
  let call fn args = Call { fn; args }
  let binop op left right = BinOp { op; left; right }
  let unop op operand = UnOp { op; operand }
  let dot target field = DotAccess { target; field }
  let if_ cond then_ else_ = IfElse { cond; then_; else_ }
  let lambda params variadic body = Lambda { params; variadic; body; env = None }
  let list_lit items = ListLit items
  let list_comp expr clauses = ListComp { expr; clauses }
  let for_clause var iter = For { var; iter }
  let filter_clause expr = Filter expr
  let dict pairs = DictLit pairs
end

module Utils = struct
  let is_truthy = function
    | Bool false | Null | Int 0 -> false
    | Error _ -> false
    | _ -> true

  let type_name = function
    | Int _ -> "int"
    | Float _ -> "float"
    | Bool _ -> "bool"
    | String _ -> "string"
    | Symbol _ -> "symbol"
    | List _ -> "list"
    | Dict _ -> "dict"
    | Lambda _ -> "function"
    | DataFrame _ -> "dataframe"
    | Error _ -> "error"
    | Null -> "null"

  let rec value_to_string = function
    | Int n -> string_of_int n
    | Float f -> string_of_float f
    | Bool true -> "true"
    | Bool false -> "false"
    | String s -> "\"" ^ String.escaped s ^ "\""
    | Symbol s -> s
    | List vs ->
        let items =
          vs |> List.map (function
            | (Some name, v) -> name ^ ": " ^ value_to_string v
            | (None, v) -> value_to_string v)
        in
        "[" ^ String.concat ", " items ^ "]"
    | Dict pairs ->
        let pair_to_string (k, v) = "`" ^ k ^ "`: " ^ value_to_string v in
        "{" ^ (pairs |> List.map pair_to_string |> String.concat ", ") ^ "}"
    | Lambda { params; variadic; _ } ->
        let dots = if variadic then ", ..." else "" in
        "\\(" ^ String.concat ", " params ^ dots ^ ") -> <function>"
    | DataFrame { columns; nrows; _ } ->
        Printf.sprintf "<DataFrame %dx%d>" (List.length columns) nrows
    | Error msg -> "Error(\"" ^ msg ^ "\")"
    | Null -> "null"
end

exception Runtime_error of string * location option
exception Type_error of string * value * location option
exception Name_error of string * location option

type 'a result = ('a, string) Result.t
