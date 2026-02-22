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
