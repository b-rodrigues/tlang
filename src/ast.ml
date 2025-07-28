(** Abstract Syntax Tree for the T programming language *)

type symbol = string [@@deriving show, eq]

(** Runtime values *)
type value =
  | Int of int
  | Float of float
  | Bool of bool
  | String of string
  | Symbol of symbol            (** Bare names for NSE, e.g., column names *)
  | List of (string option * value) list  (** Named or unnamed list elements *)
  | Dict of (string * value) list
  | Lambda of lambda
  | DataFrame of dataframe
  | Error of string
  | Null
[@@deriving show, eq]

and lambda = {
  params : symbol list;
  variadic : bool;                    (** True if ... is present *)
  body : expr;
  env : (symbol * value) list option;
} [@@deriving show, eq]

and expr =
  | Value of value
  | Var of symbol
  | Call of { fn : expr; args : expr list }
  | Lambda of lambda
  | IfElse of { cond : expr; then_ : expr; else_ : expr }
  | ListComp of { expr : expr; clauses : comp_clause list }
  | DictLit of (string * expr) list
  | BinOp of { op : string; left : expr; right : expr }
  | UnOp of { op : string; operand : expr }
  | Let of { bindings : (symbol * expr * typ option) list; body : expr }
  | Pipe of expr * expr         (** lhs |> rhs *)
[@@deriving show, eq]

(** Types for optional annotation *)
and typ =
  | TInt | TFloat | TBool | TString | TSymbol | TList | TDict | TFunction | TDataFrame
  | TCustom of string
[@@deriving show, eq]

and comp_clause =
  | For of { var : symbol; iter : expr }
  | Filter of expr
[@@deriving show, eq]

and dataframe = {
  columns : (string * value array) list;
  nrows : int;
  metadata : (string * value) list;
} [@@deriving show, eq]

type location = {
  line : int;
  column : int;
  filename : string;
} [@@deriving show, eq]

type located_expr = {
  expr : expr;
  loc : location option;
} [@@deriving show, eq]

module Constructors = struct
  let int n = Value (Int n)
  let float f = Value (Float f)
  let bool b = Value (Bool b)
  let string s = Value (String s)
  let symbol s = Value (Symbol s)
  let null = Value Null
  let error msg = Value (Error msg)

  let call fn args = Call { fn; args }
  let binop op left right = BinOp { op; left; right }
  let unop op operand = UnOp { op; operand }
  let if_ cond then_ else_ = IfElse { cond; then_; else_ }
  let lambda params variadic body = Lambda { params; variadic; body; env = None }
  let list_comp expr clauses = ListComp { expr; clauses }
  let for_clause var iter = For { var; iter }
  let filter_clause expr = Filter expr
  let let_binding bindings body = Let { bindings; body }
  let dict pairs = DictLit pairs
  let pipe lhs rhs = Pipe (lhs, rhs)

  let dataframe columns =
    let nrows =
      match columns with
      | [] -> 0
      | (_, col) :: _ -> Array.length col
    in
    { columns; nrows; metadata = [] }
end

module Utils = struct
  let is_truthy = function
    | Bool false | Null -> false
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
            | (Some name, v) -> name ^ "=" ^ value_to_string v
            | (None, v) -> value_to_string v)
        in
        "[" ^ String.concat ", " items ^ "]"
    | Dict pairs ->
        let pair_to_string (k, v) = k ^ ": " ^ value_to_string v in
        "{" ^ (pairs |> List.map pair_to_string |> String.concat ", ") ^ "}"
    | Lambda { params; variadic; _ } ->
        let dots = if variadic then ", ..." else "" in
        "\\(" ^ String.concat ", " params ^ dots ^ ") -> <function>"
    | DataFrame { columns; nrows; _ } ->
        Printf.sprintf "<DataFrame %dx%d>" (List.length columns) nrows
    | Error msg -> "Error: " ^ msg
    | Null -> "null"
end

exception Runtime_error of string * location option
exception Type_error of string * value * location option
exception Name_error of string * location option

type 'a result = ('a, string) Result.t
