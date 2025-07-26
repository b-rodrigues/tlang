(** Lexer for the T programming language *)

type token =
  | TInt of int
  | TFloat of float
  | TString of string
  | TIdent of string
  | TSymbol of string
  | TLParen | TRParen
  | TLBracket | TRBracket
  | TLBrace | TRBrace
  | TComma
  | TColon
  | TArrow           (* -> *)
  | TLambda          (* \( *)
  | TOp of string    (* +, -, *, /, ==, <, etc. *)
  | TFor | TIf
  | TEqual
  | TEOF

exception LexError of string

let is_ident_start c =
  match c with 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false

let is_ident_char c =
  match c with 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true | _ -> false

let keywords = [
  "for", TFor;
  "if", TIf;
]

(* Helper: skip whitespace and comments (# ...) *)
let rec skip_ws input i =
  if i >= String.length input then i
  else match input.[i] with
    | ' ' | '\t' | '\r' | '\n' -> skip_ws input (i + 1)
    | '#' -> skip_comment input (i + 1)
    | _ -> i

and skip_comment input i =
  if i >= String.length input then i
  else if input.[i] = '\n' then skip_ws input (i + 1)
  else skip_comment input (i + 1)

(* Lex string literal with escapes *)
let lex_string input i =
  let buf = Buffer.create 16 in
  let rec loop j =
    if j >= String.length input then raise (LexError "unterminated string")
    else match input.[j] with
      | '"' -> (Buffer.contents buf, j + 1)
      | '\\' when j + 1 < String.length input ->
        (match input.[j + 1] with
         | '"' -> Buffer.add_char buf '"'; loop (j + 2)
         | '\\' -> Buffer.add_char buf '\\'; loop (j + 2)
         | 'n' -> Buffer.add_char buf '\n'; loop (j + 2)
         | 'r' -> Buffer.add_char buf '\r'; loop (j + 2)
         | 't' -> Buffer.add_char buf '\t'; loop (j + 2)
         | c   -> Buffer.add_char buf c; loop (j + 2))
      | c -> Buffer.add_char buf c; loop (j + 1)
  in
  loop (i + 1)

(* Lex symbol literal: backtick-delimited, e.g., `foo` *)
let lex_symbol input i =
  let buf = Buffer.create 8 in
  let rec loop j =
    if j >= String.length input then raise (LexError "unterminated symbol")
    else match input.[j] with
      | '`' -> (Buffer.contents buf, j + 1)
      | c -> Buffer.add_char buf c; loop (j + 1)
  in
  loop (i + 1)

(* Lex number (int or float) *)
let lex_number input i =
  let j = ref i in
  let has_dot = ref false in
  while !j < String.length input && (
    match input.[!j] with
      | '0' .. '9' -> true
      | '.' -> if !has_dot then false else (has_dot := true; true)
      | _ -> false
  ) do
    incr j
  done;
  let num_str = String.sub input i (!j - i) in
  if !has_dot then
    TFloat (float_of_string num_str), !j
  else
    TInt (int_of_string num_str), !j

(* Lex identifier or keyword *)
let lex_ident input i =
  let j = ref i in
  while !j < String.length input && is_ident_char input.[!j] do
    incr j
  done;
  let ident = String.sub input i (!j - i) in
  let token =
    match List.assoc_opt ident keywords with
    | Some kw -> kw
    | None -> TIdent ident
  in
  token, !j

(* Main recursive lexing function *)
let rec lex input =
  let len = String.length input in
  let rec next i =
    let i = skip_ws input i in
    if i >= len then [TEOF]
    else
      match input.[i] with
      (* Numbers *)
      | '0' .. '9' -> let tok, j = lex_number input i in tok :: next j

      (* Strings *)
      | '"' ->
        let str, j = lex_string input i in
        TString str :: next j

      (* Identifiers and Keywords *)
      | c when is_ident_start c ->
        let tok, j = lex_ident input i in
        tok :: next j

      (* Symbols: backtick-quoted names *)
      | '`' ->
        let sym, j = lex_symbol input i in
        TSymbol sym :: next j

      (* Punctuation *)
      | '(' -> TLParen   :: next (i + 1)
      | ')' -> TRParen   :: next (i + 1)
      | '[' -> TLBracket :: next (i + 1)
      | ']' -> TRBracket :: next (i + 1)
      | '{' -> TLBrace   :: next (i + 1)
      | '}' -> TRBrace   :: next (i + 1)
      | ',' -> TComma    :: next (i + 1)
      | ':' -> TColon    :: next (i + 1)

      (* Operators and composite tokens *)
      | '\\' ->
        if i + 1 < len && input.[i + 1] = '(' then TLambda :: next (i + 2)
        else TOp "\\" :: next (i + 1)

      | '-' ->
        if i + 1 < len && input.[i + 1] = '>' then TArrow :: next (i + 2)
        else TOp "-" :: next (i + 1)

      | '=' ->
        if i + 1 < len && input.[i + 1] = '=' then TOp "==" :: next (i + 2)
        else TEqual :: next (i + 1)

      | '<' ->
        if i + 1 < len && input.[i + 1] = '=' then TOp "<=" :: next (i + 2)
        else TOp "<" :: next (i + 1)

      | '>' ->
        if i + 1 < len && input.[i + 1] = '=' then TOp ">=" :: next (i + 2)
        else TOp ">" :: next (i + 1)

      | '+' -> TOp "+" :: next (i + 1)
      | '*' -> TOp "*" :: next (i + 1)
      | '/' -> TOp "/" :: next (i + 1)
      | '!' ->
        if i + 1 < len && input.[i + 1] = '=' then TOp "!=" :: next (i + 2)
        else TOp "!" :: next (i + 1)

      | c -> raise (LexError (Printf.sprintf "unexpected character: '%c' at %d" c i))
  in
  next 0 
