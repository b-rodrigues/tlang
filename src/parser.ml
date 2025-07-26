(** Parser for the T programming language *)

open Ast

(** Token types for the T language *)
type token =
  | Int of int
  | Float of float
  | String of string
  | Ident of string
  | Symbol of string
  | LParen | RParen
  | LBracket | RBracket
  | LBrace | RBrace
  | Comma | Colon | Arrow | Lambda
  | Op of string
  | For | If | In
  | Equal | EOF
[@@deriving show, eq]

(** Parser state with position tracking *)
type parser_state = {
  tokens : token list;
  position : int;
  current : token option;
}

(** Parser result type *)
type 'a parse_result = ('a, string) result

(** Parser exceptions *)
exception Parse_error of string * int

(** Create initial parser state *)
let make_state tokens =
  { tokens; position = 0; current = List.hd_opt tokens }

(** Advance to next token *)
let advance state =
  match state.tokens with
  | [] -> { state with current = None }
  | [_] -> { state with current = Some EOF; position = state.position + 1 }
  | _ :: rest -> 
      { tokens = rest; 
        position = state.position + 1; 
        current = List.hd_opt rest }

(** Peek at current token *)
let current_token state = state.current

(** Check if current token matches expected *)
let matches state expected =
  match current_token state with
  | Some token -> token = expected
  | None -> false

(** Consume expected token or fail *)
let expect state expected =
  if matches state expected then
    Ok (advance state)
  else
    Error (Printf.sprintf "Expected %s at position %d" 
           (show_token expected) state.position)

(** Try to consume a token, return (matched, new_state) *)
let try_consume state expected =
  if matches state expected then
    (true, advance state)
  else
    (false, state)

(** Parse functions using monadic error handling *)
let (>>=) result f =
  match result with
  | Ok value -> f value
  | Error _ as err -> err

let (>>|) result f =
  match result with
  | Ok value -> Ok (f value)
  | Error _ as err -> err

let return x = Ok x

(** Main parsing functions *)
let rec parse_expr state =
  parse_lambda state

and parse_lambda state =
  match current_token state with
  | Some Lambda ->
      let state = advance state in
      parse_params [] state >>= fun (params, state) ->
      expect state Arrow >>= fun state ->
      parse_expr state >>= fun (body, state) ->
      return (Constructors.lambda params body, state)
  | _ -> parse_if state

and parse_params acc state =
  match current_token state with
  | Some (Ident param) ->
      let state = advance state in
      let (found_comma, state) = try_consume state Comma in
      if found_comma then
        parse_params (param :: acc) state
      else
        return (List.rev (param :: acc), state)
  | _ when acc = [] ->
      Error "Expected parameter list"
  | _ ->
      return (List.rev acc, state)

and parse_if state =
  match current_token state with
  | Some If ->
      let state = advance state in
      parse_logical_or state >>= fun (cond, state) ->
      parse_logical_or state >>= fun (then_, state) ->
      (match current_token state with
       | Some If -> (* else clause *)
           let state = advance state in
           parse_logical_or state >>= fun (else_, state) ->
           return (Constructors.if_ cond then_ (Some else_), state)
       | _ ->
           return (Constructors.if_ cond then_ None, state))
  | _ -> parse_logical_or state

and parse_logical_or state =
  parse_binary_left parse_logical_and ["||"] state

and parse_logical_and state =
  parse_binary_left parse_equality ["&&"] state

and parse_equality state =
  parse_binary_left parse_comparison ["=="; "!="] state

and parse_comparison state =
  parse_binary_left parse_addition ["<"; "<="; ">"; ">="] state

and parse_addition state =
  parse_binary_left parse_multiplication ["+"; "-"] state

and parse_multiplication state =
  parse_binary_left parse_unary ["*"; "/"; "%"] state

and parse_binary_left parse_next ops state =
  parse_next state >>= fun (left, state) ->
  let rec loop left state =
    match current_token state with
    | Some (Op op) when List.mem op ops ->
        let state = advance state in
        parse_next state >>= fun (right, state) ->
        loop (Constructors.binop op left right) state
    | _ ->
        return (left, state)
  in
  loop left state

and parse_unary state =
  match current_token state with
  | Some (Op op) when List.mem op ["!"; "-"; "+"] ->
      let state = advance state in
      parse_unary state >>= fun (operand, state) ->
      return (Constructors.unop op operand, state)
  | _ -> parse_call state

and parse_call state =
  parse_primary state >>= fun (expr, state) ->
  let rec loop expr state =
    match current_token state with
    | Some LParen ->
        let state = advance state in
        parse_arg_list [] state >>= fun (args, state) ->
        expect state RParen >>= fun state ->
        loop (Constructors.call expr args) state
    | _ ->
        return (expr, state)
  in
  loop expr state

and parse_arg_list acc state =
  match current_token state with
  | Some RParen -> return (List.rev acc, state)
  | _ when acc = [] ->
      parse_expr state >>= fun (arg, state) ->
      parse_arg_list [arg] state
  | _ ->
      expect state Comma >>= fun state ->
      parse_expr state >>= fun (arg, state) ->
      parse_arg_list (arg :: acc) state

and parse_primary state =
  match current_token state with
  | Some (Int n) ->
      return (Constructors.int n, advance state)
  | Some (Float f) ->
      return (Constructors.float f, advance state)
  | Some (String s) ->
      return (Constructors.string s, advance state)
  | Some (Ident id) ->
      return (Constructors.var id, advance state)
  | Some (Symbol sym) ->
      return (Constructors.symbol sym, advance state)
  | Some LParen ->
      let state = advance state in
      parse_expr state >>= fun (expr, state) ->
      expect state RParen >>= fun state ->
      return (expr, state)
  | Some LBracket ->
      parse_list_or_comprehension state
  | Some LBrace ->
      parse_dict state
  | Some EOF ->
      Error "Unexpected end of input"
  | None ->
      Error "Unexpected end of input"
  | Some token ->
      Error (Printf.sprintf "Unexpected token: %s" (show_token token))

and parse_list_or_comprehension state =
  let state = advance state in (* consume [ *)
  
  (* Try to parse as comprehension first *)
  match try_parse_comprehension state with
  | Ok result -> Ok result
  | Error _ -> parse_list_literal state

and try_parse_comprehension state =
  parse_expr state >>= fun (expr, state) ->
  expect state For >>= fun state ->
  (match current_token state with
   | Some (Ident var) ->
       let state = advance state in
       expect state In >>= fun state ->
       parse_expr state >>= fun (iter, state) ->
       
       (* Optional filter clause *)
       let (has_if, state) = try_consume state If in
       (if has_if then
          parse_expr state >>= fun (filter, state) ->
          return ([Constructors.for_clause var iter; 
                   Constructors.filter_clause filter], state)
        else
          return ([Constructors.for_clause var iter], state)) >>= fun (clauses, state) ->
       
       expect state RBracket >>= fun state ->
       return (Constructors.list_comp expr clauses, state)
   | _ -> Error "Expected variable in comprehension")

and parse_list_literal state =
  let rec loop acc state =
    match current_token state with
    | Some RBracket ->
        return (Constructors.list (List.rev acc), advance state)
    | _ when acc = [] ->
        parse_expr state >>= fun (expr, state) ->
        loop [expr] state
    | _ ->
        expect state Comma >>= fun state ->
        parse_expr state >>= fun (expr, state) ->
        loop (expr :: acc) state
  in
  loop [] state

and parse_dict state =
  let state = advance state in (* consume { *)
  let rec loop acc state =
    match current_token state with
    | Some RBrace ->
        return (Constructors.dict (List.rev acc), advance state)
    | Some (Ident key) ->
        let state = advance state in
        expect state Colon >>= fun state ->
        parse_expr state >>= fun (value, state) ->
        let new_acc = (key, value) :: acc in
        (match current_token state with
         | Some Comma ->
             loop new_acc (advance state)
         | Some RBrace ->
             return (Constructors.dict (List.rev new_acc), advance state)
         | _ ->
             Error "Expected ',' or '}' in dictionary")
    | _ when acc = [] ->
        Error "Expected dictionary key or '}'"
    | _ ->
        Error "Expected dictionary key"
  in
  loop [] state

(** Main parse function *)
let parse tokens =
  let state = make_state tokens in
  match parse_expr state with
  | Ok (ast, final_state) ->
      (match current_token final_state with
       | Some EOF | None -> Ok ast
       | Some token -> 
           Error (Printf.sprintf "Unexpected token after expression: %s" 
                  (show_token token)))
  | Error msg -> Error msg

(** Placeholder tokenizer - to be implemented *)
let tokenize _source = 
  failwith "Tokenizer not yet implemented"

(** Parse from string *)
let parse_string source =
  try
    let tokens = tokenize source in
    parse tokens
  with
  | exn -> Error (Printexc.to_string exn) 
