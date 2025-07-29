(* src/ast.ml *)
(*
  Major Revision:
  - Introduced VTensor, a true N-dimensional array backed by Bigarray for numerical computing.
  - Redefined VDataFrame to be a collection of named 1D vectors, not a 2D array.
  - Added a `vector` helper type to represent a single DataFrame column.
*)

open Bigarray

(* OCaml's Bigarray requires this kind of boilerplate to define a polymorphic variant over numeric types *)
type ('a, 'b) numeric_kind = ('a, 'b) Bigarray.kind
let float32 = Bigarray.float32
let float64 = Bigarray.float64
let int32 = Bigarray.int32
let int64 = Bigarray.int64

type symbol = string [@@deriving show, eq]

(** The location of a token or expression in the source code. *)
type location = {
  line: int;
  col_start: int;
  col_end: int;
} [@@deriving show, eq]


(** A 1D Vector, the building block of a DataFrame column. It is type-homogeneous. *)
type vector =
  | VFloat32_vec of (float, float32_elt, c_layout) Array1.t
  | VFloat64_vec of (float, float64_elt, c_layout) Array1.t
  | VInt32_vec of (int32, int32_elt, c_layout) Array1.t
  | VInt64_vec of (int64, int64_elt, c_layout) Array1.t
  | VBool_vec of bool array
  | VString_vec of string array
[@@deriving show] (* eq cannot be derived for Bigarrays *)

(** An N-dimensional Tensor for numerical computing. It is type-homogeneous. *)
type tensor =
  | VFloat32_tensor of (float, float32_elt, c_layout) Genarray.t
  | VFloat64_tensor of (float, float64_elt, c_layout) Genarray.t
  | VInt32_tensor of (int32, int32_elt, c_layout) Genarray.t
  | VInt64_tensor of (int64, int64_elt, c_layout) Genarray.t
[@@deriving show] (* eq cannot be derived for Bigarrays *)

and dataframe = {
  columns : (string * vector) list;
  nrows : int;
} [@@deriving show] (* eq cannot be derived *)

and value =
  (* Scalar Types *)
  | VInt64 of int64
  | VFloat64 of float
  | VBool of bool
  | VString of string
  | VSymbol of symbol            (** For Non-Standard Evaluation *)
  (* General-Purpose Containers *)
  | VList of (string option * value) list (** Ordered, heterogeneous, named/unnamed *)
  | VDict of (string * value) list      (** Unordered, string keys, heterogeneous *)
  (* High-Performance Containers *)
  | VDataFrame of dataframe             (** A collection of named, 1D vectors *)
  | VTensor of tensor                   (** A homogeneous N-dimensional numerical array *)
  (* Functional Types *)
  | VLambda of lambda
  | VBuiltin of builtin
  (* Special Values *)
  | VError of string
  | VNull
[@@deriving show] (* eq cannot be derived *)

and environment = value Map.Make(String).t

and builtin = { arity: int; variadic: bool; func: ((string option * value) list -> environment -> value); }
[@@deriving show] (* eq cannot be derived for functions *)

and lambda = {
  params : symbol list;
  variadic : bool;
  body : expr;
  env : environment option;
} [@@deriving show, eq]

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

and expr = { enode: expr_node; eloc: location option; } [@@deriving show, eq]
and binop = Plus | Minus | Mul | Div | Eq | NEq | Gt | Lt | GtEq | LtEq | And | Or | Pipe [@@deriving show, eq]
and unop = Not | Neg [@@deriving show, eq]
and comp_clause = | CFor of { var : symbol; iter : expr } | CFilter of expr [@@deriving show, eq]
and typ = TInt64 | TFloat64 | TBool | TString | TList | TDict | TDataFrame | TCustom of string [@@deriving show, eq]

and stmt_node =
  | SAssignment of { name: symbol; typ: typ option; expr: expr }
  | SExpression of expr
[@@deriving show, eq]

and statement = { snode: stmt_node; sloc: location option; } [@@deriving show, eq]
type program = statement list [@@deriving show, eq]


module Utils = struct
  let is_truthy = function
    | VBool false | VNull | VInt64 0L -> false
    | VError _ -> false
    | _ -> true

  let type_name = function
    | VInt64 _ -> "Int64" | VFloat64 _ -> "Float64"
    | VBool _ -> "Bool" | VString _ -> "String"
    | VSymbol _ -> "Symbol" | VList _ -> "List" | VDict _ -> "Dict"
    | VDataFrame _ -> "DataFrame" | VTensor _ -> "Tensor"
    | VLambda _ -> "Function" | VBuiltin _ -> "BuiltinFunction"
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
    | VDataFrame { columns; nrows; } ->
        Printf.sprintf "<DataFrame %dx%d>" nrows (List.length columns)
    | VTensor tensor ->
        let dims = match tensor with
          | VFloat32_tensor t -> Genarray.dims t
          | VFloat64_tensor t -> Genarray.dims t
          | VInt32_tensor t -> Genarray.dims t
          | VInt64_tensor t -> Genarray.dims t
        in
        let dims_str = dims |> Array.to_list |> List.map string_of_int |> String.concat "x" in
        Printf.sprintf "<Tensor %s>" dims_str
    | VBuiltin _ -> "<builtin_function>"
    | VError msg -> "Error(\"" ^ msg ^ "\")"
    | VNull -> "null"
end

(** Custom exceptions for different failure modes in the interpreter. *)
exception Name_error of string * location option
exception Type_error of string * location option
exception Arity_error of string * location option```
