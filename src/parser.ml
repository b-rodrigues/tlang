(* parser.ml *)

open Ast

(* A basic recursive descent parser outline *)

type token =
  | INT of int
  | FLOAT of float
  | BOOL of bool
  | STRING of string
  | SYMBOL of string           (* bare names *)
  | BACKTICK_SYMBOL of string (* backtick-quoted names *)
  | LET
  | FUNCTION
  | IF
  | ELSE
  | FOR
  | IN
  | DOT
  | COMMA
  | LPAREN
  | RPAREN
  | LBRACKET
  | RBRACKET
  | LBRACE
  | RBRACE
  | EQUALS
  | DOTDOTDOT                (* ... *)
  | PIPE                    (* |> *)
  | OP of string            (* +, -, *, /, ==, !=, etc. *)
  | EOF

(* Lexer is separate; assume tokens are provided *)

(* Parsing context *)

type parser_state = {
  tokens: token list;
  mutable current: token list;
}

exception Parse_error of string

let next_token state =
  match state.current with
  | [] -> EOF
  | hd :: tl ->
      state.current <- tl;
      hd

let peek_token state =
  match state.current with
  | [] -> EOF
  | hd :: _ -> hd

(* Helpers *)

let expect_token state expected =
  let tok = next_token state in
  if tok = expected then ()
  else raise (Parse_error ("Expected token " ^ (match expected with
    | LET -> "let"
    | FUNCTION -> "function"
    | IF -> "if"
    | ELSE -> "else"
    | FOR -> "for"
    | IN -> "in"
    | DOT -> "."
    | COMMA -> ","
    | LPAREN -> "("
    | RPAREN -> ")"
    | LBRACKET -> "["
    | RBRACKET -> "]"
    | LBRACE -> "{"
    | RBRACE -> "}"
    | EQUALS -> "="
    | DOTDOTDOT -> "..."
    | PIPE -> "|>"
    | EOF -> "EOF"
    | OP s -> "operator " ^ s
    | INT i -> string_of_int i
    | FLOAT f -> string_of_float f
    | BOOL b -> string_of_bool b
    | STRING s -> "\"" ^ s ^ "\""
    | SYMBOL s -> s
    | BACKTICK_SYMBOL s -> "`" ^ s ^ "`"
  )))

(* Parsing symbols: bare names or backtick symbols *)

let parse_symbol = function
  | SYMBOL s -> s
  | BACKTICK_SYMBOL s -> s
  | _ -> raise (Parse_error "Expected symbol")

(* Forward declarations *)

let rec parse_expr state : expr =
  parse_if state

and parse_if state =
  match peek_token state with
  | IF ->
      let _ = next_token state in
      expect_token state LPAREN;
      let cond = parse_expr state in
      expect_token state RPAREN;
      let then_ = parse_expr state in
      let else_ =
        match peek_token state with
        | ELSE ->
            let _ = next_token state in
            Some (parse_expr state)
        | _ -> None
      in
      If { cond; then_; else_ }
  | _ -> parse_pipe state

and parse_pipe state =
  let left = parse_lambda_or_assign state in
  match peek_token state with
  | PIPE ->
      let _ = next_token state in
      let right = parse_expr state in
      (* pipe: left |> right -> call right(left) *)
      let call_expr = Call { fn = right; args = [left] } in
      call_expr
  | _ -> left

and parse_lambda_or_assign state =
  (* parse function assignment or lambda or other expr *)
  match peek_token state with
  | SYMBOL s ->
      (* lookahead to see if next token is '=' *)
      (match state.current with
      | SYMBOL _ :: EQUALS :: FUNCTION :: _ -> parse_function_assign state
      | SYMBOL _ :: EQUALS :: BACKTICK_SYMBOL _ :: _ -> parse_assign state
      | SYMBOL _ :: EQUALS :: LPAREN :: _ -> parse_assign state
      | SYMBOL _ :: EQUALS :: _ -> parse_assign state
      | _ -> parse_simple_expr state)
  | _ -> parse_simple_expr state

and parse_function_assign state =
  (* parse f = function(x, y, ...) expr *)
  let name_token = next_token state in
  let name = parse_symbol name_token in
  expect_token state EQUALS;
  expect_token state FUNCTION;
  let (params, dots) = parse_params state in
  let body = parse_expr state in
  (* TODO: store dots (variadic) somehow? For now, add dots as param symbol "..." if present *)
  let params = if dots then params @ ["..."] else params in
  let lambda_val = Lambda { params; body; env = None } in
  (* represent assignment as Let binding with one binding *)
  Let { bindings = [(name, Value lambda_val)]; body = Value lambda_val }

and parse_assign state =
  (* parse x = expr *)
  let name_token = next_token state in
  let name = parse_symbol name_token in
  expect_token state EQUALS;
  let value = parse_expr state in
  Let { bindings = [(name, value)]; body = value }

and parse_params state : (symbol list * bool) =
  (* parse function parameters, returning (params, has_dots) *)
  expect_token state LPAREN;
  let rec loop acc =
    match peek_token state with
    | RPAREN ->
        let _ = next_token state in
        (List.rev acc, false)
    | DOTDOTDOT ->
        let _ = next_token state in
        expect_token state RPAREN;
        (List.rev acc, true)
    | SYMBOL s ->
        let _ = next_token state in
        (match peek_token state with
        | COMMA ->
            let _ = next_token state in
            loop (s :: acc)
        | RPAREN ->
            let _ = next_token state in
            (List.rev (s :: acc), false)
        | _ -> raise (Parse_error "Expected , or ) after param"))
    | BACKTICK_SYMBOL s ->
        let _ = next_token state in
        (match peek_token state with
        | COMMA ->
            let _ = next_token state in
            loop (s :: acc)
        | RPAREN ->
            let _ = next_token state in
            (List.rev (s :: acc), false)
        | _ -> raise (Parse_error "Expected , or ) after param"))
    | _ -> raise (Parse_error "Unexpected token in parameter list")
  in
  loop []

and parse_simple_expr state =
  (* parse simple expressions: values, variables, calls, parentheses, list comprehensions, etc. *)
  match peek_token state with
  | INT n -> let _ = next_token state in Value (Int n)
  | FLOAT f -> let _ = next_token state in Value (Float f)
  | BOOL b -> let _ = next_token state in Value (Bool b)
  | STRING s -> let _ = next_token state in Value (String s)
  | SYMBOL s -> 
      let _ = next_token state in
      parse_postfix (Var s) state
  | BACKTICK_SYMBOL s ->
      let _ = next_token state in
      parse_postfix (Var s) state
  | LPAREN ->
      let _ = next_token state in
      let e = parse_expr state in
      expect_token state RPAREN;
      parse_postfix e state
  | LBRACKET ->
      (* List or comprehension *)
      parse_list_or_comp state
  | LBRACE ->
      (* Dict literal *)
      parse_dict state
  | _ -> raise (Parse_error "Unexpected token in expression")

and parse_postfix expr state =
  (* parse postfix constructs like function call, dot access *)
  match peek_token state with
  | LPAREN ->
      (* function call *)
      let _ = next_token state in
      let rec args acc =
        match peek_token state with
        | RPAREN -> let _ = next_token state in List.rev acc
        | _ -> 
            let arg = parse_expr state in
            (match peek_token state with
            | COMMA -> let _ = next_token state in args (arg :: acc)
            | RPAREN -> let _ = next_token state in List.rev (arg :: acc)
            | _ -> raise (Parse_error "Expected ',' or ')' in function call arguments"))
      in
      let arguments = args [] in
      parse_postfix (Call { fn = expr; args = arguments }) state
  | DOT ->
      let _ = next_token state in
      (match peek_token state with
      | SYMBOL s -> 
          let _ = next_token state in
          parse_postfix (Call { fn = Var "."; args = [expr; Var s] }) state
      | BACKTICK_SYMBOL s ->
          let _ = next_token state in
          parse_postfix (Call { fn = Var "."; args = [expr; Var s] }) state
      | _ -> raise (Parse_error "Expected symbol after dot"))
  | _ -> expr

and parse_list_or_comp state =
  (* parse list literal or list comprehension *)
  let _ = expect_token state LBRACKET in
  match peek_token state with
  | _ ->
      let expr = parse_expr state in
      (match peek_token state with
      | FOR ->
          (* list comprehension *)
          let _ = next_token state in
          let var_token = next_token state in
          let var = parse_symbol var_token in
          expect_token state IN;
          let iterable = parse_expr state in
          expect_token state RBRACKET;
          ListComp { expr; var; iterable }
      | RBRACKET ->
          let _ = next_token state in
          ListLit [expr]
      | COMMA ->
          (* multiple elements *)
          let rec collect acc =
            match peek_token state with
            | RBRACKET -> let _ = next_token state in ListLit (List.rev acc)
            | _ ->
                let e = parse_expr state in
                (match peek_token state with
                | COMMA -> let _ = next_token state in collect (e :: acc)
                | RBRACKET -> let _ = next_token state in ListLit (List.rev (e :: acc))
                | _ -> raise (Parse_error "Expected ',' or ']' in list literal"))
          in
          collect [expr]
      | _ -> raise (Parse_error "Unexpected token after list element"))
  | _ -> raise (Parse_error "Unexpected token in list or comprehension")

and parse_dict state =
  (* parse dict literal: { key: value, ... } *)
  let _ = expect_token state LBRACE in
  let rec parse_pairs acc =
    match peek_token state with
    | RBRACE -> let _ = next_token state in DictLit (List.rev acc)
    | SYMBOL key ->
        let _ = next_token state in
        expect_token state COLON;
        let value = parse_expr state in
        (match peek_token state with
        | COMMA -> let _ = next_token state in parse_pairs ((key, value) :: acc)
        | RBRACE -> let _ = next_token state in DictLit (List.rev ((key, value) :: acc))
        | _ -> raise (Parse_error "Expected ',' or '}' in dict literal"))
    | BACKTICK_SYMBOL key ->
        let _ = next_token state in
        expect_token state COLON;
        let value = parse_expr state in
        (match peek_token state with
        | COMMA -> let _ = next_token state in parse_pairs ((key, value) :: acc)
        | RBRACE -> let _ = next_token state in DictLit (List.rev ((key, value) :: acc))
        | _ -> raise (Parse_error "Expected ',' or '}' in dict literal"))
    | _ -> raise (Parse_error "Expected symbol key in dict literal")
  in
  parse_pairs []

(* Entry point *)

let parse tokens =
  let state = { tokens; current = tokens } in
  let expr = parse_expr state in
  match peek_token state with
  | EOF -> expr
  | _ -> raise (Parse_error "Unexpected tokens after expression")
