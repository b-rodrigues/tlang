{
(* lexer.mll *)
(* OCamllex lexer for the T language — Phase 0 Alpha *)
open Parser (* The tokens are defined in parser.mly *)
exception SyntaxError of string

let is_ident_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '$' -> true
  | _ -> false

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
  | ('\n' [' ' '\t']*)+ '}' {
      let s = Lexing.lexeme lexbuf in
      String.iter (fun c -> if c = '\n' then Lexing.new_line lexbuf) s;
      RBRACE_TRAIL
    }
  | (';' [' ' '\t']*)+ '}' { RBRACE_TRAIL }
  | '\n'            { Lexing.new_line lexbuf; NEWLINE }
  | ',' [' ' '\t']* "..." { COMMA_DOTDOTDOT }
  | ';'             { SEMICOLON }
  | "--" [^ '\n']*  { token lexbuf } (* Line comments *)

  (* Keywords *)
  | "if"        { IF }
  | "else"      { ELSE }
  | "match"     { MATCH }
  | "import"    { IMPORT }

  | "function"  { FUNCTION }
  | "pipeline"  { PIPELINE }
  | "intent"    { INTENT }
  | "true"      { TRUE }
  | "false"     { FALSE }
  | "NA"        { NA }
  | "in"        { IN }

  | "&&"        { AND }
  | "||"        { OR }
  | "&"         { BITAND }
  | "|"         { BITOR } (* Note: PIPE is |> which is longer, so it should be fine *)
  | "!!!"       { BANG_BANG_BANG }
  | "!!"        { BANG_BANG }
  | "!"         { BANG }

  (* Literals — float must be tried before int *)
  | float as lxm { FLOAT (float_of_string lxm) }
  | int as lxm   { INT (int_of_string lxm) }
  | '"'          { read_string (Buffer.create 16) '"' lexbuf }
  | '\''         { read_string (Buffer.create 16) '\'' lexbuf }
  | "`" ([^'`']* as s) "`" { BACKTICK_IDENT s }

  (* Raw code block: <{ ... }> for embedding foreign language code verbatim *)
  | "<{" { raw_code (Buffer.create 256) lexbuf }
  | "?<{" { shell_cmd (Buffer.create 128) lexbuf }

  (* Symbols and Operators *)
  | '(' { LPAREN }   | ')' { RPAREN }
  | '[' { LBRACK }   | ']' { RBRACK }
  | '{' { LBRACE }   | '}' { RBRACE }
  | '\\' { LAMBDA }  | ',' { COMMA }
  | ":=" { COLON_EQ }
  | ':' { COLON }    | '.' { DOT }
  | "=>" { FAT_ARROW }
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
  | ".%"  { DOT_PERCENT }
  | '+' { PLUS }     | '-' { MINUS }
  | '*' { STAR }     | '/' { SLASH }
  | "==" { EQ }      | "!=" { NEQ }
  | '<' { LT }       | '>' { GT }
  | "<=" { LTE }     | ">=" { GTE }
  | '%' { PERCENT }
  | '~' { TILDE }

  (* Column references with $ prefix — must come before identifiers *)
  | '$' (identifier as col) { COLUMN_REF col }
  | '$' '`' ([^'`']* as col) '`' { COLUMN_REF col }

  (* Serializer identifiers with ^ prefix *)
  | '^' (identifier as s) { SERIALIZER_ID s }

  (* Identifiers must be matched after keywords *)
  | identifier as lxm { IDENT lxm }

  (* End of file *)
  | eof { EOF }
  | _ as char { raise (SyntaxError ("Unexpected character: " ^ Char.escaped char)) }

(* Secondary lexer rule: captures raw foreign code inside <{ ... }> *)
and raw_code buf = parse
  | "}>" { RAW_CODE (Buffer.contents buf) }
  | '\n' { Lexing.new_line lexbuf; Buffer.add_char buf '\n'; raw_code buf lexbuf }
  | _ as c { Buffer.add_char buf c; raw_code buf lexbuf }
  | eof { raise (SyntaxError "Unterminated raw code block (missing '}>'))") }

and shell_cmd buf = parse
  | "}>" { SHELL_CMD (Buffer.contents buf) }
  | '\n' { Lexing.new_line lexbuf; Buffer.add_char buf '\n'; shell_cmd buf lexbuf }
  | _ as c { Buffer.add_char buf c; shell_cmd buf lexbuf }
  | eof { raise (SyntaxError "Unterminated shell command (missing '}>'))") }

and read_string buf delim = parse
  | '"' | '\'' as c { if c = delim then STRING (Buffer.contents buf) else (Buffer.add_char buf c; read_string buf delim lexbuf) }
  | '\\' 'n'  { Buffer.add_char buf '\n'; read_string buf delim lexbuf }
  | '\\' 'r'  { Buffer.add_char buf '\r'; read_string buf delim lexbuf }
  | '\\' 't'  { Buffer.add_char buf '\t'; read_string buf delim lexbuf }
  | '\\' '"'  { Buffer.add_char buf '"'; read_string buf delim lexbuf }
  | '\\' '\'' { Buffer.add_char buf '\''; read_string buf delim lexbuf }
  | '\\' '\\' { Buffer.add_char buf '\\'; read_string buf delim lexbuf }
  | [^ '"' '\'' '\\']+ as s { Buffer.add_string buf s; read_string buf delim lexbuf }
  | eof { raise (SyntaxError "Unterminated string") }
  | _ as c { Buffer.add_char buf c; read_string buf delim lexbuf }
