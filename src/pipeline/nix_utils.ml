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
  | FatArrow -> "=>"

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

(** Escape user code for safe embedding inside Nix ''...'' strings.
    ${ is replaced by ${"$"}, and every ' is replaced by ${"'"},
    which Nix interpolates back to their literal values.
    Bare $ (not followed by {) is safe in Nix indented strings and is
    left unchanged so shell references like $1, $out, $PATH work. *)
let nix_escape_indented_code s =
  let len = String.length s in
  let buf = Buffer.create (len * 7) in
  let i = ref 0 in
  while !i < len do
    let c = s.[!i] in
    if c = '$' && !i + 1 < len && s.[!i + 1] = '{' then
      Buffer.add_string buf "${\"$\"}"
    else if c = '\'' then
      Buffer.add_string buf "${\"'\"}"
    else
      Buffer.add_char buf c;
    i := !i + 1
  done;
  Buffer.contents buf
