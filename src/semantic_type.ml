(* src/semantic_type.ml *)

type column = {
  name : string;
  col_typ : t;
}

and t =
  | TInt
  | TString
  | TBool
  | TFloat
  | TDataFrame of column list
  | TGroupedDataFrame of column list * string list
  | TFunction of (string * t) list * t
  | TAny
  | TUnknown

(** Convert a semantic type to its string representation.

    @param t The semantic type to convert.
    @return A string representation of the semantic type (e.g. "int", "grouped_dataframe[...]"). *)
let rec to_string = function
  | TInt -> "int"
  | TString -> "string"
  | TBool -> "bool"
  | TFloat -> "float"
  | TDataFrame cols ->
      let col_names = List.map (fun c -> c.name) cols in
      "to_dataframe[" ^ String.concat ", " col_names ^ "]"
  | TGroupedDataFrame (cols, groups) ->
      let col_names = List.map (fun c -> c.name) cols in
      "grouped_dataframe[" ^ String.concat ", " col_names ^ " | groups: " ^ String.concat ", " groups ^ "]"
  | TFunction (args, ret) ->
      let arg_strs = List.map (fun (name, typ) -> name ^ ": " ^ to_string typ) args in
      "Function(" ^ String.concat ", " arg_strs ^ " -> " ^ to_string ret ^ ")"
  | TAny -> "any"
  | TUnknown -> "unknown"
 
(** Parse a semantic type from its string representation.

    @param str The string representation of the type to parse.
    @return The corresponding semantic type [t], defaulting to [TAny] or [TUnknown] on mismatch. *)
let from_string str =
  let str = String.lowercase_ascii (String.trim str) in
  match str with
  | "int" | "integer" -> TInt
  | "string" | "text" -> TString
  | "bool" | "boolean" | "logical" -> TBool
  | "float" | "double" | "number" | "numeric" -> TFloat
  | "to_dataframe" | "table" -> TDataFrame []
  | "any" | "value" | "all" | "mixed" | "..." -> TAny
  | _ ->
      if String.starts_with ~prefix:"vector" str then TAny
      else if String.starts_with ~prefix:"list" str then TAny
      else TUnknown

(** Convert a semantic type to an AST type for comparison with annotations.

    @param t The semantic type to convert.
    @return The corresponding AST type [Ast.typ]. *)
let rec to_ast_typ (t : t) : Ast.typ =
  match t with
  | TInt -> Ast.TInt
  | TString -> Ast.TString
  | TBool -> Ast.TBool
  | TFloat -> Ast.TFloat
  | TDataFrame _ -> Ast.TDataFrame None
  | TGroupedDataFrame _ -> Ast.TDataFrame None
  | TFunction (args, ret) ->
      let param_types = List.map (fun (_, t) -> to_ast_typ t) args in
      Ast.TArrow (param_types, to_ast_typ ret)
  | TAny -> Ast.TCustom "Any"
  | TUnknown -> Ast.TCustom "Any"
