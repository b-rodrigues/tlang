(* src/ast.ml *)
(* Phase 0: Core AST for the T language alpha. *)
(* Kept simple — no Bigarray/Tensor/DataFrame until Phase 2. *)

(** Environment module — immutable string map *)
module Env = Map.Make(String)

type symbol = string

(** Runtime values *)
type value =
  (* Scalar Types *)
  | VInt of int
  | VFloat of float
  | VBool of bool
  | VString of string
  | VSymbol of symbol
  (* General-Purpose Containers *)
  | VList of (string option * value) list
  | VDict of (string * value) list
  (* Functional Types *)
  | VLambda of lambda
  | VBuiltin of builtin
  (* Special Values *)
  | VError of string
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
    | _ -> true

  let type_name = function
    | VInt _ -> "Int" | VFloat _ -> "Float"
    | VBool _ -> "Bool" | VString _ -> "String"
    | VSymbol _ -> "Symbol" | VList _ -> "List" | VDict _ -> "Dict"
    | VLambda _ -> "Function" | VBuiltin _ -> "BuiltinFunction"
    | VError _ -> "Error" | VNull -> "Null"

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
    | VLambda { params; variadic; _ } ->
        let dots = if variadic then ", ..." else "" in
        "\\(" ^ String.concat ", " params ^ dots ^ ") -> <function>"
    | VBuiltin _ -> "<builtin_function>"
    | VError msg -> "Error(\"" ^ msg ^ "\")"
    | VNull -> "null"
end
