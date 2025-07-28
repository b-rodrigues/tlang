{
(* lexer.mll *)
(* OCamllex lexer for the T language *)
open Parser (* The tokens are defined in parser.mly *)
exception SyntaxError of string
}

let digit = ['0'-'9']
let int = '-'? digit+
let float = '-'? digit+ '.' digit*

(* Identifiers can't start with a digit *)
let ident_start = ['a'-'z' 'A'-'Z' '_']
let ident_char = ident_start | digit
let identifier = ident_start ident_char*

rule token = parse
  | [' ' '\t' '\r'] { token lexbuf } (* Whitespace *)
  | '\n'            { Lexing.new_line lexbuf; token lexbuf } (* Newlines *)
  | "--" [^ '\n']*  { token lexbuf } (* Comments *)

  (* Keywords *)
  | "if"        { IF }
  | "else"      { ELSE }
  | "for"       { FOR }
  | "in"        { IN }
  | "function"  { FUNCTION }
  | "true"      { TRUE }
  | "false"     { FALSE }
  | "null"      { NULL }
  | "and"       { AND }
  | "or"        { OR }
  | "not"       { NOT }

  (* Literals *)
  | float as lxm { FLOAT (float_of_string lxm) }
  | int as lxm   { INT (int_of_string lxm) }
  | '"' ([^'"']*) '"' as s { STRING (String.sub s 1 (String.length s - 2)) }
  | '\'' ([^'\'']*) '\'' as s { STRING (String.sub s 1 (String.length s - 2)) }
  | "`" ([^'`']*) "`" as s { BACKTICK_IDENT (String.sub s 1 (String.length s - 2)) }

  (* Symbols and Operators *)
  | '(' { LPAREN }   | ')' { RPAREN }
  | '[' { LBRACK }   | ']' { RBRACK }
  | '{' { LBRACE }   | '}' { RBRACE }
  | '\\' { LAMBDA }  | ',' { COMMA }
  | ':' { COLON }    | '.' { DOT }
  | '=' { EQUALS }   | "->" { ARROW }
  | "..." { DOTDOTDOT }
  | "|>" { PIPE }
  | '+' { PLUS }     | '-' { MINUS }
  | '*' { STAR }     | '/' { SLASH }
  | "==" { EQ }      | "!=" { NEQ }
  | '<' { LT }       | '>' { GT }
  | "<=" { LTE }     | ">=" { GTE }

  (* Identifiers must be matched after keywords *)
  | identifier as lxm { IDENT lxm }

  (* End of file *)
  | eof { EOF }
  | _ as char { raise (SyntaxError ("Unexpected character: " ^ Char.escaped char)) } 
