(** Abstract Syntax Tree for the T programming language *)

(** Symbols represent identifiers in T *)
type symbol = string [@@deriving show, eq]

(** Runtime values in T *)
type value =
  | Int of int
  | Float of float  
  | Bool of bool
  | String of string
  | Symbol of symbol          (** Bare names for NSE, e.g., column names *)
  | List of value list
  | StartsWith of string
  | Dict of (string * value) list
  | Lambda of lambda
  | Table of table           (** Tabular data for data science *)
  | Error of string          (** Error values instead of exceptions *)
  | Null                     (** Missing/null values *)
[@@deriving show, eq]

(** Function values with lexical scoping *)
and lambda = {
  params : symbol list;
  body : expr;
  env : (symbol * value) list option; (** Captured environment for closures *)
} [@@deriving show, eq]

(** Expressions in T (before evaluation) *)
and expr =
  | Value of value
  | Var of symbol
  | Call of { fn : expr; args : expr list }
  | Lambda of lambda
  | If of { cond : expr; then_ : expr; else_ : expr option }
  | ListComp of { 
      expr : expr; 
      clauses : comp_clause list 
    }
  | DictLit of (string * expr) list
  | BinOp of { 
      op : string; 
      left : expr; 
      right : expr 
    }
  | UnOp of { 
      op : string; 
      operand : expr 
    }
  | Let of {
      bindings : (symbol * expr) list;
      body : expr
    }
[@@deriving show, eq]

(** Comprehension clauses for list/dict comprehensions *)
and comp_clause =
  | For of { var : symbol; iter : expr }
  | Filter of expr
[@@deriving show, eq]

(** Table structure optimized for columnar data operations *)
and table = {
  columns : (string * value array) list;  (** Named columns with array storage *)
  nrows : int;
  metadata : (string * value) list;       (** Attributes, types, etc. *)
} [@@deriving show, eq]

(** Location information for better error reporting *)
type location = {
  line : int;
  column : int;
  filename : string;
} [@@deriving show, eq]

(** Expression with location information *)
type located_expr = {
  expr : expr;
  loc : location option;
} [@@deriving show, eq]

(** Smart constructors for common patterns *)
module Constructors = struct
  let int n = Value (Int n)
  let float f = Value (Float f)
  let bool b = Value (Bool b)
  let string s = Value (String s)
  let symbol s = Value (Symbol s)
  let var s = Var s
  let null = Value Null
  let error msg = Value (Error msg)
  
  let call fn args = Call { fn; args }
  let binop op left right = BinOp { op; left; right }
  let unop op operand = UnOp { op; operand }
  let if_ cond then_ else_ = If { cond; then_; else_ }
  let lambda params body = Lambda { params; body; env = None }
  
  let list_comp expr clauses = ListComp { expr; clauses }
  let for_clause var iter = For { var; iter }
  let filter_clause expr = Filter expr
  
  let let_binding bindings body = Let { bindings; body }
  let dict pairs = DictLit pairs
  
  (** Create a table from column data *)
  let table columns =
    let nrows = 
      match columns with
      | [] -> 0
      | (_, col) :: _ -> Array.length col
    in
    { columns; nrows; metadata = [] }
end

(** Utility functions *)
module Utils = struct
  (** Check if a value is truthy (for conditionals) *)
  let is_truthy = function
    | Bool false | Null -> false
    | Error _ -> false
    | _ -> true
    
  (** Get the type name of a value (useful for error messages) *)
  let type_name = function
    | Int _ -> "int"
    | Float _ -> "float"
    | Bool _ -> "bool"
    | String _ -> "string"
    | Symbol _ -> "symbol"
    | List _ -> "list"
    | Dict _ -> "dict"
    | Lambda _ -> "function"
    | Table _ -> "table"
    | Error _ -> "error"
    | Null -> "null"
    
  (** Convert value to string representation *)
  let rec value_to_string = function
    | Int n -> string_of_int n
    | Float f -> string_of_float f
    | Bool true -> "true"
    | Bool false -> "false" 
    | String s -> "\"" ^ String.escaped s ^ "\""
    | Symbol s -> s
    | List vs -> 
        "[" ^ (vs |> List.map value_to_string |> String.concat ", ") ^ "]"
    | Dict pairs ->
        let pair_to_string (k, v) = k ^ ": " ^ value_to_string v in
        "{" ^ (pairs |> List.map pair_to_string |> String.concat ", ") ^ "}"
    | Lambda { params; _ } -> 
        "\\(" ^ String.concat ", " params ^ ") -> <function>"
    | Table { columns; nrows; _ } ->
        Printf.sprintf "<table %dx%d>" (List.length columns) nrows
    | Error msg -> "Error: " ^ msg
    | Null -> "null"
end

(** Exception types for the T language *)
exception Runtime_error of string * location option
exception Type_error of string * value * location option
exception Name_error of string * location option

(** Result type for operations that can fail *)
type 'a result = ('a, string) Result.t 
