%{
(* parser.mly *)
(* Menhir grammar for the T language — Phase 0 Alpha *)
open Ast

(* Helper to build a parameter record from parsing *)
type param_info = { names: string list; has_variadic: bool }
%}

/* TOKENS */
/* Keywords */
%token IF ELSE FUNCTION PIPELINE INTENT TRUE FALSE NULL NA
/* Literals */
%token <int> INT
%token <float> FLOAT
%token <string> STRING
%token <string> IDENT
%token <string> BACKTICK_IDENT
%token <string> COLUMN_REF
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

/* ... PRECEDENCE ... */



%token LAMBDA (* \ character *)
%token NEWLINE SEMICOLON
%token EOF

/* PRECEDENCE AND ASSOCIATIVITY (lowest to highest) */
%left TILDE

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
    { Assignment { name; typ = None; expr = e } }
  | name = any_ident COLON t = typ EQUALS e = expr
    { Assignment { name; typ = Some t; expr = e } }
  | name = any_ident COLON_EQ e = expr
    { Reassignment { name; expr = e } }
  | e = expr { Expression e }
  ;

expr:
  | e = pipe_expr { e }
  ;

pipe_expr:
  | e = formula_expr { e }
  | left = pipe_expr PIPE right = formula_expr
    { BinOp { op = Pipe; left; right } }
  | left = pipe_expr MAYBE_PIPE right = formula_expr
    { BinOp { op = MaybePipe; left; right } }
  ;

formula_expr:
  | e = or_expr { e }
  | left = or_expr TILDE right = or_expr
    { BinOp { op = Formula; left; right } }
  ;

or_expr:
  | e = and_expr { e }
  | left = or_expr OR right = and_expr
    { BinOp { op = Or; left; right } }
  ;

and_expr:
  | e = bit_or_expr { e }
  | left = and_expr AND right = bit_or_expr
    { BinOp { op = And; left; right } }
  ;

bit_or_expr:
  | e = bit_and_expr { e }
  | left = bit_or_expr BITOR right = bit_and_expr
    { BinOp { op = BitOr; left; right } }
  | left = bit_or_expr DOT_BITOR right = bit_and_expr
    { BroadcastOp { op = BitOr; left; right } }
  ;

bit_and_expr:
  | e = cmp_expr { e }
  | left = bit_and_expr BITAND right = cmp_expr
    { BinOp { op = BitAnd; left; right } }
  | left = bit_and_expr DOT_BITAND right = cmp_expr
    { BroadcastOp { op = BitAnd; left; right } }
  ;

cmp_expr:
  | e = add_expr { e }
  | left = add_expr EQ right = add_expr  { BinOp { op = Eq; left; right } }
  | left = add_expr NEQ right = add_expr { BinOp { op = NEq; left; right } }
  | left = add_expr LT right = add_expr  { BinOp { op = Lt; left; right } }
  | left = add_expr GT right = add_expr  { BinOp { op = Gt; left; right } }
  | left = add_expr LTE right = add_expr { BinOp { op = LtEq; left; right } }
  | left = add_expr GTE right = add_expr { BinOp { op = GtEq; left; right } }
  | left = add_expr DOT_EQ right = add_expr  { BroadcastOp { op = Eq; left; right } }
  | left = add_expr DOT_NEQ right = add_expr { BroadcastOp { op = NEq; left; right } }
  | left = add_expr DOT_LT right = add_expr  { BroadcastOp { op = Lt; left; right } }
  | left = add_expr DOT_GT right = add_expr  { BroadcastOp { op = Gt; left; right } }
  | left = add_expr DOT_LTE right = add_expr { BroadcastOp { op = LtEq; left; right } }
  | left = add_expr DOT_GTE right = add_expr { BroadcastOp { op = GtEq; left; right } }
  | left = add_expr IN right = add_expr { BinOp { op = In; left; right } }
  ;

add_expr:
  | e = mul_expr { e }
  | left = add_expr PLUS right = mul_expr  { BinOp { op = Plus; left; right } }
  | left = add_expr MINUS right = mul_expr { BinOp { op = Minus; left; right } }
  | left = add_expr DOT_PLUS right = mul_expr  { BroadcastOp { op = Plus; left; right } }
  | left = add_expr DOT_MINUS right = mul_expr { BroadcastOp { op = Minus; left; right } }
  ;

mul_expr:
  | e = unary_expr { e }
  | left = mul_expr STAR right = unary_expr  { BinOp { op = Mul; left; right } }
  | left = mul_expr SLASH right = unary_expr { BinOp { op = Div; left; right } }
  | left = mul_expr PERCENT right = unary_expr { BinOp { op = Mod; left; right } }
  | left = mul_expr DOT_MUL right = unary_expr  { BroadcastOp { op = Mul; left; right } }
  | left = mul_expr DOT_DIV right = unary_expr { BroadcastOp { op = Div; left; right } }
  | left = mul_expr DOT_PERCENT right = unary_expr { BroadcastOp { op = Mod; left; right } }
  ;

unary_expr:
  | e = postfix_expr { e }
  | MINUS e = unary_expr { UnOp { op = Neg; operand = e } }
  | BANG e = unary_expr { UnOp { op = Not; operand = e } }
  ;

/* Function calls and dot access are postfix operations */
postfix_expr:
  | e = primary_expr { e }
  | fn = postfix_expr LPAREN skip_sep args = call_args RPAREN
    { Call { fn; args } }
  | target = postfix_expr DOT field = any_ident
    { DotAccess { target; field } }
  ;

call_args:
  | { [] }
  | a = arg skip_sep { [a] }
  | a = arg COMMA skip_sep rest = call_args { a :: rest }
  ;

arg:
  | e = expr { (None, e) }
  | name = IDENT COLON e = expr { (Some name, e) }
  | name = IDENT EQUALS e = expr { (Some name, e) }
  | DOT name = IDENT EQUALS e = expr { (Some ("." ^ name), e) }
  | col = COLUMN_REF EQUALS e = expr { (Some col, e) }
  ;

/* Primary (atomic) expressions */
primary_expr:
  | i = INT { Value (VInt i) }
  | f = FLOAT { Value (VFloat f) }
  | s = STRING { Value (VString s) }
  | TRUE { Value (VBool true) }
  | FALSE { Value (VBool false) }
  | NULL { Value VNull }
  | NA { Value (VNA NAGeneric) }
  | col = COLUMN_REF { ColumnRef col }
  | id = any_ident { Var id }
  | LPAREN e = expr RPAREN { e }
  | l = list_lit { l }
  | d = dict_lit { d }
  | l = lambda_expr { l }
  | i = if_expr { i }
  | p = pipeline_expr { p }
  | n = intent_expr { n }
  | b = block_expr { b }
  ;

block_expr:
  | LBRACE skip_sep stmts = nonempty_stmt_list RBRACE { Block stmts } 
  ;

/* Helper to ensure blocks contain at least one statement.
   This avoids ambiguity with empty dict literals `{}`. */
nonempty_stmt_list:
  | s = statement skip_sep { [s] }
  | s = statement sep skip_sep rest = stmt_list { s :: rest }
  ;

lambda_expr:
  | LAMBDA LPAREN p = params RPAREN body = expr
    { Lambda { params = p.names; variadic = p.has_variadic; body; env = None } }
  | FUNCTION LPAREN p = params RPAREN body = expr
    { Lambda { params = p.names; variadic = p.has_variadic; body; env = None } }
  | LAMBDA LPAREN p = params RPAREN ARROW body = expr
    { Lambda { params = p.names; variadic = p.has_variadic; body; env = None } }
  ;

/* Helper for parsing parameter lists with optional variadic `...` */
params:
  | (* empty *) { { names = []; has_variadic = false } }
  | ps = param_list
    { { names = ps; has_variadic = false } }
  | ps = param_list COMMA skip_sep DOTDOTDOT
    { { names = ps; has_variadic = true } }
  | DOTDOTDOT
    { { names = []; has_variadic = true } }
  ;

param_list:
  | id = any_ident skip_sep { [id] }
  | id = any_ident COMMA skip_sep rest = param_list { id :: rest }
  ;

if_expr:
  | IF LPAREN cond = expr RPAREN then_ = primary_expr ELSE else_ = primary_expr
    { IfElse { cond; then_; else_ } }
  ;

pipeline_expr:
  | PIPELINE LBRACE skip_sep nodes = pipeline_node_list RBRACE
    { PipelineDef nodes }
  ;

pipeline_node_list:
  | { [] }
  | n = pipeline_node skip_sep { [n] }
  | n = pipeline_node sep skip_sep rest = pipeline_node_list { n :: rest }
  ;

pipeline_node:
  | name = any_ident EQUALS e = expr
    { { node_name = name; node_expr = e } }
  ;

intent_expr:
  | INTENT LBRACE skip_sep pairs = intent_field_list RBRACE
    { IntentDef pairs }
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

list_lit:
  | LBRACK skip_sep items = list_items RBRACK
    { ListLit items }
  ;

list_items:
  | { [] }
  | i = named_item skip_sep { [i] }
  | i = named_item COMMA skip_sep rest = list_items { i :: rest }
  ;

named_item:
  | e = expr { (None, e) }
  | name = IDENT COLON e = expr { (Some name, e) }
  ;

dict_lit:
  | LBRACE skip_sep pairs = dict_items RBRACE
    { DictLit pairs }
  ;

dict_items:
  | { [] }
  | p = dict_pair skip_sep { [p] }
  | p = dict_pair COMMA skip_sep rest = dict_items { p :: rest }
  ;

dict_pair:
  | key = any_ident COLON value = expr { (key, value) }
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
    | "List" -> TList
    | "Dict" -> TDict
    | "DataFrame" -> TDataFrame
    | other -> TCustom other
  }
  ;
