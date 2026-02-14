{
(* lexer.mll *)
(* OCamllex lexer for the T language — Phase 0 Alpha *)
open Parser (* The tokens are defined in parser.mly *)
exception SyntaxError of string
}

let digit = ['0'-'9']
let int = digit+
let float = digit+ '.' digit*

(* Identifiers can't start with a digit *)
let ident_start = ['a'-'z' 'A'-'Z' '_']
let ident_char = ident_start | digit
let identifier = ident_start ident_char*

rule token = parse
  | [' ' '\t' '\r'] { token lexbuf } (* Whitespace — skip *)
  (* Allow pipelines to continue on the next indented line.
     This rule must come before the general newline rule so the newline
     doesn't terminate the expression when immediately followed by |> . *)
  | '\n' [' ' '\t']* "?|>" { Lexing.new_line lexbuf; MAYBE_PIPE }
  | '\n' [' ' '\t']* "|>" { Lexing.new_line lexbuf; PIPE }
  | '\n'            { Lexing.new_line lexbuf; NEWLINE }
  | ';'             { SEMICOLON }
  | "--" [^ '\n']*  { token lexbuf } (* Line comments *)

  (* Keywords *)
  | "if"        { IF }
  | "else"      { ELSE }

  | "function"  { FUNCTION }
  | "pipeline"  { PIPELINE }
  | "intent"    { INTENT }
  | "true"      { TRUE }
  | "false"     { FALSE }
  | "null"      { NULL }
  | "NA"        { NA }
  | "in"        { IN }

  | "&&"        { AND }
  | "||"        { OR }
  | "&"         { BITAND }
  | "|"         { BITOR } (* Note: PIPE is |> which is longer, so it should be fine *)
  | "!"         { BANG }

  (* Literals — float must be tried before int *)
  | float as lxm { FLOAT (float_of_string lxm) }
  | int as lxm   { INT (int_of_string lxm) }
  | '"' ([^'"']* as s) '"' { STRING s }
  | '\'' ([^'\'']* as s) '\'' { STRING s }
  | "`" ([^'`']* as s) "`" { BACKTICK_IDENT s }

  (* Symbols and Operators *)
  | '(' { LPAREN }   | ')' { RPAREN }
  | '[' { LBRACK }   | ']' { RBRACK }
  | '{' { LBRACE }   | '}' { RBRACE }
  | '\\' { LAMBDA }  | ',' { COMMA }
  | ":=" { COLON_EQ }
  | ':' { COLON }    | '.' { DOT }
  | '=' { EQUALS }   | "->" { ARROW }
  | "..." { DOTDOTDOT }
  | "?|>" { MAYBE_PIPE }
  | "|>" { PIPE }
  (* Dotted operators *)
  | ".+"  { DOT_PLUS }
  | ".-"  { DOT_MINUS }
  | ".*"  { DOT_MUL }
  | "./"  { DOT_DIV }
  | ".==" { DOT_EQ }
  | ".!=" { DOT_NEQ }
  | ".<"  { DOT_LT }
  | ".>"  { DOT_GT }
  | ".<=" { DOT_LTE }
  | ".>=" { DOT_GTE }
  | ".&"  { DOT_BITAND }
  | ".|"  { DOT_BITOR }
  | '+' { PLUS }     | '-' { MINUS }
  | '*' { STAR }     | '/' { SLASH }
  | "==" { EQ }      | "!=" { NEQ }
  | '<' { LT }       | '>' { GT }
  | "<=" { LTE }     | ">=" { GTE }
  | '~' { TILDE }

  (* Column references with $ prefix — must come before identifiers *)
  | '$' (identifier as col) { COLUMN_REF col }

  (* Identifiers must be matched after keywords *)
  | identifier as lxm { IDENT lxm }

  (* End of file *)
  | eof { EOF }
  | _ as char { raise (SyntaxError ("Unexpected character: " ^ Char.escaped char)) }
