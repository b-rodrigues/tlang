(* src/tdoc/simple_json.ml *)

type json =
  | JNull
  | JBool of bool
  | JInt of int
  | JFloat of float
  | JString of string
  | JArray of json list
  | JObject of (string * json) list

exception Json_error of string

let json_error msg = raise (Json_error msg)

(* Lexer *)
type token =
  | LBrace | RBrace | LBracket | RBracket | Colon | Comma
  | StringLit of string | IntLit of int | FloatLit of float
  | BoolLit of bool | NullLit | EOF

let rec lex str pos =
  let len = String.length str in
  if pos >= len then (EOF, pos)
  else
    match str.[pos] with
    | ' ' | '\t' | '\n' | '\r' -> lex str (pos + 1)
    | '{' -> (LBrace, pos + 1)
    | '}' -> (RBrace, pos + 1)
    | '[' -> (LBracket, pos + 1)
    | ']' -> (RBracket, pos + 1)
    | ':' -> (Colon, pos + 1)
    | ',' -> (Comma, pos + 1)
    | '"' -> lex_string str (pos + 1)
    | '-' | '0'..'9' -> lex_number str pos
    | 't' -> if String.sub str pos 4 = "true" then (BoolLit true, pos + 4) else json_error "Expected true"
    | 'f' -> if String.sub str pos 5 = "false" then (BoolLit false, pos + 5) else json_error "Expected false"
    | 'n' -> if String.sub str pos 4 = "null" then (NullLit, pos + 4) else json_error "Expected null"
    | _ -> json_error (Printf.sprintf "Unexpected char at %d" pos)

and lex_string str pos =
  let buf = Buffer.create 16 in
  let rec loop i =
    if i >= String.length str then json_error "Unterminated string";
    match str.[i] with
    | '"' -> (StringLit (Buffer.contents buf), i + 1)
    | '\\' ->
        if i + 1 >= String.length str then json_error "Unterminated escape";
        let c = match str.[i+1] with
          | '"' -> '"' | '\\' -> '\\' | '/' -> '/' | 'b' -> '\b'
          | 'f' -> '\012' | 'n' -> '\n' | 'r' -> '\r' | 't' -> '\t'
          | 'u' -> (* Simplified unicode handling: skip *) '?' 
          | _ -> str.[i+1]
        in
        Buffer.add_char buf c;
        loop (i + 2)
    | c -> Buffer.add_char buf c; loop (i + 1)
  in
  loop pos

and lex_number str pos =
  let len = String.length str in
  let start = pos in
  let rec loop i =
    if i >= len then i
    else match str.[i] with
    | '0'..'9' | '.' | 'e' | 'E' | '+' | '-' -> loop (i + 1)
    | _ -> i
  in
  let end_pos = loop (pos + 1) in
  let s = String.sub str start (end_pos - start) in
  try
    if String.contains s '.' || String.contains s 'e' || String.contains s 'E' then
      (FloatLit (float_of_string s), end_pos)
    else
      (IntLit (int_of_string s), end_pos)
  with _ -> json_error ("Invalid number: " ^ s)

(* Parser *)
let rec parse_json tokens =
  match tokens with
  | [] -> json_error "Unexpected EOF"
  | token :: rest ->
      match token with
      | LBrace -> parse_object rest
      | LBracket -> parse_array rest
      | StringLit s -> (JString s, rest)
      | IntLit i -> (JInt i, rest)
      | FloatLit f -> (JFloat f, rest)
      | BoolLit b -> (JBool b, rest)
      | NullLit -> (JNull, rest)
      | _ -> json_error "Unexpected token"

and parse_object tokens =
  let rec loop acc toks =
    match toks with
    | RBrace :: rest -> (JObject (List.rev acc), rest)
    | Comma :: rest -> 
       (match rest with
        | StringLit key :: Colon :: rest2 ->
            let (value, rest3) = parse_json rest2 in
            loop ((key, value) :: acc) rest3
        | _ -> json_error "Expected key-value pair after comma")
    | StringLit key :: Colon :: rest ->
        let (value, rest2) = parse_json rest in
        loop ((key, value) :: acc) rest2
    | _ -> json_error "Expected object key or }"
  in
  match tokens with
  | RBrace :: rest -> (JObject [], rest)
  | _ -> loop [] tokens

and parse_array tokens =
  let rec loop acc toks =
    match toks with
    | RBracket :: rest -> (JArray (List.rev acc), rest)
    | Comma :: rest ->
        let (value, rest2) = parse_json rest in
        loop (value :: acc) rest2
    | _ ->
        let (value, rest) = parse_json tokens in
        loop (value :: acc) rest
  in
  match tokens with
  | RBracket :: rest -> (JArray [], rest)
  | _ -> loop [] tokens

let from_string str =
  let rec tokenize pos acc =
    let (tok, next_pos) = lex str pos in
    match tok with
    | EOF -> List.rev acc
    | _ -> tokenize next_pos (tok :: acc)
  in
  let tokens = tokenize 0 [] in
  fst (parse_json tokens)

(* Accessors *)
let member key json =
  match json with
  | JObject pairs -> List.assoc_opt key pairs
  | _ -> None

let to_string json =
  match json with
  | JString s -> Some s
  | _ -> None

let to_int json =
  match json with
  | JInt i -> Some i
  | _ -> None

let to_bool json =
  match json with
  | JBool b -> Some b
  | _ -> None

let to_list json =
  match json with
  | JArray l -> Some l
  | _ -> None
