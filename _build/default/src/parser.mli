
(* The type of tokens. *)

type token = 
  | TRUE
  | STRING of (string)
  | STAR
  | SLASH
  | SEMICOLON
  | RPAREN
  | RBRACK
  | RBRACE
  | PLUS
  | PIPE
  | OR
  | NULL
  | NOT
  | NEWLINE
  | NEQ
  | MINUS
  | LTE
  | LT
  | LPAREN
  | LBRACK
  | LBRACE
  | LAMBDA
  | INT of (int)
  | IN
  | IF
  | IDENT of (string)
  | GTE
  | GT
  | FUNCTION
  | FOR
  | FLOAT of (float)
  | FALSE
  | EQUALS
  | EQ
  | EOF
  | ELSE
  | DOTDOTDOT
  | DOT
  | COMMA
  | COLON
  | BACKTICK_IDENT of (string)
  | ARROW
  | AND

(* This exception is raised by the monolithic API functions. *)

exception Error

(* The monolithic API. *)

val program: (Lexing.lexbuf -> token) -> Lexing.lexbuf -> (Ast.program)
