(* src/t_type.ml *)

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
  | TUnknown

let rec to_string = function
  | TInt -> "Int"
  | TString -> "String"
  | TBool -> "Bool"
  | TFloat -> "Float"
  | TDataFrame cols ->
      let col_names = List.map (fun c -> c.name) cols in
      "DataFrame[" ^ String.concat ", " col_names ^ "]"
  | TGroupedDataFrame (cols, groups) ->
      let col_names = List.map (fun c -> c.name) cols in
      "GroupedDataFrame[" ^ String.concat ", " col_names ^ " | groups: " ^ String.concat ", " groups ^ "]"
  | TFunction (args, ret) ->
      let arg_strs = List.map (fun (name, typ) -> name ^ ": " ^ to_string typ) args in
      "Function([" ^ String.concat ", " arg_strs ^ "] -> " ^ to_string ret ^ ")"
  | TUnknown -> "Unknown"
