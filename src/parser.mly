%{
(* parser.mly *)
(* Menhir grammar for the T language — Phase 0 Alpha *)
open Ast

(* Custom exception for mixed bracket forms - avoids circular dependency with Parser.Error *)
exception Mixed_bracket_form

(* Helper to build a parameter record from parsing *)
type parsed_param = string * Ast.typ option
type param_info = { params: parsed_param list; has_variadic: bool; return_type: Ast.typ option }

type bracket_item =
  | BrExpr of Ast.expr
  | BrPair of string * Ast.expr
  | BrDynamic of Ast.expr

let build_bracket_literal (items : bracket_item list) : Ast.expr_node =
  let rec loop saw_expr saw_pair dict_rev list_rev = function
    | [] ->
      if saw_expr && saw_pair then raise Mixed_bracket_form
      else if saw_pair then DictLit (List.rev dict_rev)
      else ListLit (List.rev list_rev)
    | BrExpr e :: rest ->
      (match e.node with
       | UnquoteSplice _ -> 
           (* !!! can go anywhere, doesn't force list/dict *)
           loop saw_expr saw_pair dict_rev ((None, e) :: list_rev) rest
       | _ -> 
           loop true saw_pair dict_rev ((None, e) :: list_rev) rest)
    | BrPair (k, v) :: rest ->
      loop saw_expr true ((k, v) :: dict_rev) ((Some k, v) :: list_rev) rest
    | BrDynamic e :: rest ->
      (* Dynamic args can go in both List and Dict. They don't force one or the other. *)
      loop saw_expr saw_pair dict_rev ((None, e) :: list_rev) rest
  in
  loop false false [] [] items
;;

let loc_of_pos (pos : Lexing.position) : Ast.source_location =
  let file =
    if pos.Lexing.pos_fname = "" then None else Some pos.Lexing.pos_fname
  in
  {
    file;
    line = pos.Lexing.pos_lnum;
    column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1);
  }

let with_loc node pos =
  Ast.mk_expr ~loc:(loc_of_pos pos) node

let with_stmt_loc node pos =
  Ast.mk_stmt ~loc:(loc_of_pos pos) node
%}

/* TOKENS */
/* Keywords */
%token IF ELSE IMPORT FUNCTION PIPELINE INTENT TRUE FALSE NULL NA
/* Literals */
%token <int> INT
%token <float> FLOAT
%token <string> STRING
%token <string> RAW_CODE
%token <string> IDENT
%token <string> BACKTICK_IDENT
%token <string> COLUMN_REF
%token <string> SHELL_CMD
/* Symbols and Operators */
%token LPAREN RPAREN LBRACK RBRACK LBRACE RBRACE
%token COMMA COLON COLON_EQ DOT EQUALS ARROW DOTDOTDOT
%token PIPE
%token MAYBE_PIPE
%token PLUS MINUS STAR SLASH PERCENT

/* ... */



/* ... */


%token EQ NEQ LT GT LTE GTE
%token BITAND BITOR
%token AND OR BANG IN
%token DOT_PLUS DOT_MINUS DOT_MUL DOT_DIV
%token DOT_EQ DOT_NEQ DOT_LT DOT_GT DOT_LTE DOT_GTE
%token DOT_BITAND DOT_BITOR
%token DOT_PERCENT
%token TILDE
%token BANG_BANG BANG_BANG_BANG

/* ... PRECEDENCE ... */



%token LAMBDA (* \ character *)
%token NEWLINE SEMICOLON
%token EOF

/* PRECEDENCE AND ASSOCIATIVITY (lowest to highest) */
%nonassoc IF_WITHOUT_ELSE
%nonassoc ELSE
%left TILDE
%left PIPE MAYBE_PIPE
%left OR
%left AND
%left BITOR
%left BITAND
%nonassoc EQ NEQ LT GT LTE GTE IN
%nonassoc DOT_EQ DOT_NEQ DOT_LT DOT_GT DOT_LTE DOT_GTE
%left PLUS MINUS
%left DOT_PLUS DOT_MINUS
%left STAR SLASH PERCENT
%left DOT_MUL DOT_DIV DOT_PERCENT



/* ENTRY POINT */
%start <Ast.program> program
%%

/* GRAMMAR RULES */

/* A program is a list of statements, possibly separated by newlines/semicolons */
program:
  | skip_sep stmts = stmt_list EOF { stmts }
  ;

skip_sep:
  | { () }
  | skip_sep NEWLINE { () }
  | skip_sep SEMICOLON { () }
  ;

stmt_list:
  | { [] }
  | s = statement skip_sep { [s] }
  | s = statement sep skip_sep rest = stmt_list { s :: rest }
  ;

sep:
  | NEWLINE { () }
  | SEMICOLON { () }
  | sep NEWLINE { () }
  | sep SEMICOLON { () }
  ;

statement:
  | name = any_ident EQUALS e = expr
    { with_stmt_loc (Assignment { name; typ = None; expr = e }) $startpos }
  | name = any_ident COLON t = typ EQUALS e = expr
    { with_stmt_loc (Assignment { name; typ = Some t; expr = e }) $startpos }
  | name = any_ident COLON_EQ e = expr
    { with_stmt_loc (Reassignment { name; expr = e }) $startpos }
  | IMPORT s = STRING { with_stmt_loc (Import s) $startpos }
  | IMPORT s = STRING LBRACK skip_sep names = import_name_list RBRACK
    { with_stmt_loc (ImportFileFrom { filename = s; names }) $startpos }
  | IMPORT id = any_ident LBRACK skip_sep names = import_name_list RBRACK
    { with_stmt_loc (ImportFrom { package = id; names }) $startpos }
  | IMPORT id = any_ident { with_stmt_loc (ImportPackage id) $startpos }
  | e = expr { with_stmt_loc (Expression e) $startpos }
  ;

import_name_list:
  | n = import_name skip_sep { [n] }
  | n = import_name COMMA skip_sep rest = import_name_list { n :: rest }
  ;

import_name:
  | name = any_ident { { import_name = name; import_alias = None } }
  | alias = any_ident EQUALS name = any_ident
    { { import_name = name; import_alias = Some alias } }
  ;

expr:
  | e = pipe_expr { e }
  ;

pipe_expr:
  | e = formula_expr { e }
  | left = pipe_expr PIPE right = formula_expr
    { with_loc (BinOp { op = Pipe; left; right }) $startpos }
  | left = pipe_expr MAYBE_PIPE right = formula_expr
    { with_loc (BinOp { op = MaybePipe; left; right }) $startpos }
  ;

formula_expr:
  | e = or_expr { e }
  | left = or_expr TILDE right = or_expr
    { with_loc (BinOp { op = Formula; left; right }) $startpos }
  ;

or_expr:
  | e = and_expr { e }
  | left = or_expr OR right = and_expr
    { with_loc (BinOp { op = Or; left; right }) $startpos }
  ;

and_expr:
  | e = bit_or_expr { e }
  | left = and_expr AND right = bit_or_expr
    { with_loc (BinOp { op = And; left; right }) $startpos }
  ;

bit_or_expr:
  | e = bit_and_expr { e }
  | left = bit_or_expr BITOR right = bit_and_expr
    { with_loc (BinOp { op = BitOr; left; right }) $startpos }
  | left = bit_or_expr DOT_BITOR right = bit_and_expr
    { with_loc (BroadcastOp { op = BitOr; left; right }) $startpos }
  ;

bit_and_expr:
  | e = cmp_expr { e }
  | left = bit_and_expr BITAND right = cmp_expr
    { with_loc (BinOp { op = BitAnd; left; right }) $startpos }
  | left = bit_and_expr DOT_BITAND right = cmp_expr
    { with_loc (BroadcastOp { op = BitAnd; left; right }) $startpos }
  ;

cmp_expr:
  | e = add_expr { e }
  | left = add_expr EQ right = add_expr  { with_loc (BinOp { op = Eq; left; right }) $startpos }
  | left = add_expr NEQ right = add_expr { with_loc (BinOp { op = NEq; left; right }) $startpos }
  | left = add_expr LT right = add_expr  { with_loc (BinOp { op = Lt; left; right }) $startpos }
  | left = add_expr GT right = add_expr  { with_loc (BinOp { op = Gt; left; right }) $startpos }
  | left = add_expr LTE right = add_expr { with_loc (BinOp { op = LtEq; left; right }) $startpos }
  | left = add_expr GTE right = add_expr { with_loc (BinOp { op = GtEq; left; right }) $startpos }
  | left = add_expr DOT_EQ right = add_expr  { with_loc (BroadcastOp { op = Eq; left; right }) $startpos }
  | left = add_expr DOT_NEQ right = add_expr { with_loc (BroadcastOp { op = NEq; left; right }) $startpos }
  | left = add_expr DOT_LT right = add_expr  { with_loc (BroadcastOp { op = Lt; left; right }) $startpos }
  | left = add_expr DOT_GT right = add_expr  { with_loc (BroadcastOp { op = Gt; left; right }) $startpos }
  | left = add_expr DOT_LTE right = add_expr { with_loc (BroadcastOp { op = LtEq; left; right }) $startpos }
  | left = add_expr DOT_GTE right = add_expr { with_loc (BroadcastOp { op = GtEq; left; right }) $startpos }
  | left = add_expr IN right = add_expr { with_loc (BinOp { op = In; left; right }) $startpos }
  ;

add_expr:
  | e = mul_expr { e }
  | left = add_expr PLUS right = mul_expr  { with_loc (BinOp { op = Plus; left; right }) $startpos }
  | left = add_expr MINUS right = mul_expr { with_loc (BinOp { op = Minus; left; right }) $startpos }
  | left = add_expr DOT_PLUS right = mul_expr  { with_loc (BroadcastOp { op = Plus; left; right }) $startpos }
  | left = add_expr DOT_MINUS right = mul_expr { with_loc (BroadcastOp { op = Minus; left; right }) $startpos }
  ;

mul_expr:
  | e = unary_expr { e }
  | left = mul_expr STAR right = unary_expr  { with_loc (BinOp { op = Mul; left; right }) $startpos }
  | left = mul_expr SLASH right = unary_expr { with_loc (BinOp { op = Div; left; right }) $startpos }
  | left = mul_expr PERCENT right = unary_expr { with_loc (BinOp { op = Mod; left; right }) $startpos }
  | left = mul_expr DOT_MUL right = unary_expr  { with_loc (BroadcastOp { op = Mul; left; right }) $startpos }
  | left = mul_expr DOT_DIV right = unary_expr { with_loc (BroadcastOp { op = Div; left; right }) $startpos }
  | left = mul_expr DOT_PERCENT right = unary_expr { with_loc (BroadcastOp { op = Mod; left; right }) $startpos }
  ;

unary_expr:
  | e = postfix_expr { e }
  | MINUS e = unary_expr { with_loc (UnOp { op = Neg; operand = e }) $startpos }
  | BANG e = unary_expr { with_loc (UnOp { op = Not; operand = e }) $startpos }
  | BANG_BANG e = unary_expr { with_loc (Unquote e) $startpos }
  | BANG_BANG_BANG e = unary_expr { with_loc (UnquoteSplice e) $startpos }
  ;

/* Function calls and dot access are postfix operations */
postfix_expr:
  | e = primary_expr { e }
  | fn = postfix_expr LPAREN skip_sep args = call_args RPAREN
    { with_loc (Call { fn; args }) $startpos }
  | target = postfix_expr DOT field = any_ident
    { with_loc (DotAccess { target; field }) $startpos }
  ;

call_args:
  | { [] }
  | a = arg skip_sep { [a] }
  | a = arg COMMA skip_sep rest = call_args { a :: rest }
  ;

arg:
  | e = expr { (None, e) }
  | name = any_ident COLON e = expr { (Some name, e) }
  | name = any_ident EQUALS e = expr { (Some name, e) }
  | DOT name = IDENT EQUALS e = expr { (Some ("." ^ name), e) }
  | col = COLUMN_REF EQUALS e = expr { (Some col, e) }
  | BANG_BANG name_expr = unary_expr COLON_EQ e = expr
    { (None, with_loc (Call { fn = with_loc (Var "__dynamic_arg__") $startpos;
                            args = [(None, name_expr); (None, e)] }) $startpos) }
  ;

/* Primary (atomic) expressions */
primary_expr:
  | i = INT { with_loc (Value (VInt i)) $startpos }
  | f = FLOAT { with_loc (Value (VFloat f)) $startpos }
  | s = STRING { with_loc (Value (VString s)) $startpos }
  | TRUE { with_loc (Value (VBool true)) $startpos }
  | FALSE { with_loc (Value (VBool false)) $startpos }
  | NULL { with_loc (Value VNull) $startpos }
  | NA { with_loc (Value (VNA NAGeneric)) $startpos }
  | col = COLUMN_REF { with_loc (ColumnRef col) $startpos }
  | id = any_ident { with_loc (Var id) $startpos }
  | DOTDOTDOT { with_loc (Var "...") $startpos }
  | LPAREN skip_sep e = expr skip_sep RPAREN { e }
  | LPAREN skip_sep fn = expr COMMA skip_sep args = call_args RPAREN
    { with_loc (Call { fn; args }) $startpos }
  | b = bracket_lit { b }
  | l = lambda_expr { l }
  | i = if_expr { i }
  | p = pipeline_expr { p }
  | n = intent_expr { n }
  | b = block_expr { b }
  | raw = RAW_CODE
    { let text = String.trim raw in
      with_loc (RawCode { raw_text = text; raw_identifiers = Ast.extract_identifiers text }) $startpos }
  | cmd = SHELL_CMD { with_loc (ShellExpr cmd) $startpos }
  ;

block_expr:
  | LBRACE skip_sep stmts = stmt_list RBRACE { with_loc (Block stmts) $startpos }
  ;

lambda_expr:
  | LAMBDA g = generic_params_opt LPAREN p = params RPAREN body = expr
    {
      let names = List.map fst p.params in
      let param_types = List.map snd p.params in
      with_loc (Lambda {
        params = names;
        param_types;
        return_type = p.return_type;
        generic_params = g;
        variadic = p.has_variadic;
        body;
        env = None;
      }) $startpos
    }
  | FUNCTION g = generic_params_opt LPAREN p = params RPAREN body = expr
    {
      let names = List.map fst p.params in
      let param_types = List.map snd p.params in
      with_loc (Lambda {
        params = names;
        param_types;
        return_type = p.return_type;
        generic_params = g;
        variadic = p.has_variadic;
        body;
        env = None;
      }) $startpos
    }
  ;



/* Optional generic parameters like <T, U> */
generic_params_opt:
  | { [] }
  | LT gs = generic_param_list GT { gs }
  ;

generic_param_list:
  | g = IDENT skip_sep { [g] }
  | g = IDENT COMMA skip_sep rest = generic_param_list { g :: rest }
  ;

/* Helper for parsing parameter lists with optional variadic `...` and optional return type code `-> Type` */
params:
  | p = params_raw { { params = p.params; has_variadic = p.has_variadic; return_type = None } }
  | p = params_raw ARROW rt = typ { { params = p.params; has_variadic = p.has_variadic; return_type = Some rt } }
  ;

params_raw:
  | (* empty *) { { params = []; has_variadic = false; return_type = None } }
  | ps = param_list
    { { params = ps; has_variadic = false; return_type = None } }
  | ps = param_list COMMA skip_sep DOTDOTDOT
    { { params = ps; has_variadic = true; return_type = None } }
  | DOTDOTDOT
    { { params = []; has_variadic = true; return_type = None } }
  ;

param_list:
  | p = param skip_sep { [p] }
  | p = param COMMA skip_sep rest = param_list { p :: rest }
  ;

param:
  | id = any_ident { (id, None) }
  | id = any_ident COLON t = typ { (id, Some t) }
  ;

if_expr:
  | IF LPAREN cond = expr RPAREN then_ = primary_expr %prec IF_WITHOUT_ELSE
    { with_loc (IfElse { cond; then_; else_ = with_loc (Value VNull) $startpos }) $startpos }
  | IF LPAREN cond = expr RPAREN then_ = primary_expr ELSE else_ = primary_expr
    { with_loc (IfElse { cond; then_; else_ }) $startpos }
  ;

pipeline_expr:
  | PIPELINE LBRACE skip_sep nodes = pipeline_node_list RBRACE
    { with_loc (PipelineDef nodes) $startpos }
  ;

pipeline_node_list:
  | { [] }
  | n = pipeline_node skip_sep { [n] }
  | n = pipeline_node sep skip_sep rest = pipeline_node_list { n :: rest }
  ;

pipeline_node:
  | name = any_ident EQUALS e = expr { (name, e) }
  ;

intent_expr:
  | INTENT LBRACE skip_sep pairs = intent_field_list RBRACE
    { with_loc (IntentDef pairs) $startpos }
  ;

intent_field_list:
  | { [] }
  | p = intent_field skip_sep { [p] }
  | p = intent_field COMMA skip_sep rest = intent_field_list { p :: rest }
  | p = intent_field sep skip_sep rest = intent_field_list { p :: rest }
  ;

intent_field:
  | key = any_ident COLON value = expr { (key, value) }
  ;

bracket_lit:
  | LBRACK skip_sep items = bracket_items RBRACK
    { with_loc (build_bracket_literal items) $startpos }
  | LBRACK skip_sep COLON skip_sep RBRACK
    { with_loc (DictLit []) $startpos }
  ;

bracket_items:
  | { [] }
  | i = bracket_item skip_sep { [i] }
  | i = bracket_item COMMA skip_sep rest = bracket_items { i :: rest }
  ;

bracket_item:
  | key = any_ident COLON value = expr { BrPair (key, value) }
  | BANG_BANG name_expr = unary_expr COLON_EQ value = expr
    { BrDynamic (with_loc (Call { fn = with_loc (Var "__dynamic_arg__") $startpos;
                                              args = [(None, name_expr); (None, value)] }) $startpos) }
  | e = expr { BrExpr e }
  ;

/* An identifier can be bare or backticked */
any_ident:
  | id = IDENT { id }
  | id = BACKTICK_IDENT { id }
  ;

/* Optional type annotations */
typ:
  | id = IDENT {
    match id with
    | "Int" -> TInt
    | "Float" -> TFloat
    | "Bool" -> TBool
    | "String" -> TString
    | "Null" -> TNull
    | "List" -> TList None
    | "Dict" -> TDict (None, None)
    | "Tuple" -> TTuple []
    | "DataFrame" -> TDataFrame None
    | "Expr" -> TExpr
    | other when String.length other = 1 && Char.uppercase_ascii other.[0] = other.[0] -> TVar other
    | other -> TCustom other
  }
  | id = IDENT LBRACK ts = type_args RBRACK {
    match id, ts with
    | "List", [t] -> TList (Some t)
    | "Dict", [k; v] -> TDict (Some k, Some v)
    | "Tuple", _ -> TTuple ts
    | "DataFrame", [schema] -> TDataFrame (Some schema)
    | other, _ -> TCustom other
  }
  ;

type_args:
  | t = typ skip_sep { [t] }
  | t = typ COMMA skip_sep rest = type_args { t :: rest }
  ;
