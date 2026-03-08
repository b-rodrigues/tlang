open Ast

let op_to_string = function
  | Plus -> "+"
  | Minus -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Mod -> "%"
  | Eq -> "=="
  | NEq -> "!="
  | Gt -> ">"
  | Lt -> "<"
  | GtEq -> ">="
  | LtEq -> "<="
  | And -> "&&"
  | Or -> "||"
  | BitAnd -> "&"
  | BitOr -> "|"
  | In -> "in"
  | Pipe -> "|>"
  | MaybePipe -> "?|>"
  | Formula -> "~"

let shell_single_quote s =
  "'" ^ String.concat "'\"\\'\"'" (String.split_on_char '\'' s) ^ "'"

let nix_double_quote s =
  let buffer = Buffer.create (String.length s + 8) in
  String.iter (function
    | '\\' -> Buffer.add_string buffer "\\\\"
    | '"' -> Buffer.add_string buffer "\\\""
    | '$' -> Buffer.add_string buffer "\\$"
    | '\n' -> Buffer.add_string buffer "\\n"
    | '\r' -> Buffer.add_string buffer "\\r"
    | '\t' -> Buffer.add_string buffer "\\t"
    | c -> Buffer.add_char buffer c
  ) s;
  "\"" ^ Buffer.contents buffer ^ "\""
