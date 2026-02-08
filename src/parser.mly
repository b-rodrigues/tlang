%{
(* parser.mly *)
(* Menhir grammar for the T language — Phase 0 Alpha *)
open Ast

(* Helper to build a parameter record from parsing *)
type param_info = { names: string list; has_variadic: bool }
%}

/* TOKENS */
/* Keywords */
%token IF ELSE FOR IN FUNCTION TRUE FALSE NULL
/* Literals */
%token <int> INT
%token <float> FLOAT
%token <string> STRING
%token <string> IDENT
%token <string> BACKTICK_IDENT
/* Symbols and Operators */
%token LPAREN RPAREN LBRACK RBRACK LBRACE RBRACE
%token COMMA COLON DOT EQUALS ARROW DOTDOTDOT
%token PIPE
%token PLUS MINUS STAR SLASH
%token EQ NEQ LT GT LTE GTE
%token AND OR NOT
%token LAMBDA (* \ character *)
%token NEWLINE SEMICOLON
%token EOF

/* PRECEDENCE AND ASSOCIATIVITY (lowest to highest) */
%left PIPE
%left OR
%left AND
%nonassoc EQ NEQ LT GT LTE GTE
%left PLUS MINUS
%left STAR SLASH
%nonassoc UMINUS UNOT

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
  | e = expr { Expression e }
  ;

expr:
  | e = pipe_expr { e }
  ;

pipe_expr:
  | e = or_expr { e }
  | left = pipe_expr PIPE right = or_expr
    { BinOp { op = Pipe; left; right } }
  ;

or_expr:
  | e = and_expr { e }
  | left = or_expr OR right = and_expr
    { BinOp { op = Or; left; right } }
  ;

and_expr:
  | e = cmp_expr { e }
  | left = and_expr AND right = cmp_expr
    { BinOp { op = And; left; right } }
  ;

cmp_expr:
  | e = add_expr { e }
  | left = add_expr EQ right = add_expr  { BinOp { op = Eq; left; right } }
  | left = add_expr NEQ right = add_expr { BinOp { op = NEq; left; right } }
  | left = add_expr LT right = add_expr  { BinOp { op = Lt; left; right } }
  | left = add_expr GT right = add_expr  { BinOp { op = Gt; left; right } }
  | left = add_expr LTE right = add_expr { BinOp { op = LtEq; left; right } }
  | left = add_expr GTE right = add_expr { BinOp { op = GtEq; left; right } }
  ;

add_expr:
  | e = mul_expr { e }
  | left = add_expr PLUS right = mul_expr  { BinOp { op = Plus; left; right } }
  | left = add_expr MINUS right = mul_expr { BinOp { op = Minus; left; right } }
  ;

mul_expr:
  | e = unary_expr { e }
  | left = mul_expr STAR right = unary_expr  { BinOp { op = Mul; left; right } }
  | left = mul_expr SLASH right = unary_expr { BinOp { op = Div; left; right } }
  ;

unary_expr:
  | e = postfix_expr { e }
  | MINUS e = unary_expr %prec UMINUS { UnOp { op = Neg; operand = e } }
  | NOT e = unary_expr %prec UNOT    { UnOp { op = Not; operand = e } }
  ;

/* Function calls and dot access are postfix operations */
postfix_expr:
  | e = primary_expr { e }
  | fn = postfix_expr LPAREN args = separated_list(COMMA, arg) RPAREN
    { Call { fn; args } }
  | target = postfix_expr DOT field = any_ident
    { DotAccess { target; field } }
  ;

arg:
  | e = expr { (None, e) }
  | name = IDENT COLON e = expr { (Some name, e) }
  ;

/* Primary (atomic) expressions */
primary_expr:
  | i = INT { Value (VInt i) }
  | f = FLOAT { Value (VFloat f) }
  | s = STRING { Value (VString s) }
  | TRUE { Value (VBool true) }
  | FALSE { Value (VBool false) }
  | NULL { Value VNull }
  | id = any_ident { Var id }
  | LPAREN e = expr RPAREN { e }
  | l = list_lit { l }
  | d = dict_lit { d }
  | l = lambda_expr { l }
  | i = if_expr { i }
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
  | ps = separated_nonempty_list(COMMA, any_ident)
    { { names = ps; has_variadic = false } }
  | ps = separated_nonempty_list(COMMA, any_ident) COMMA DOTDOTDOT
    { { names = ps; has_variadic = true } }
  | DOTDOTDOT
    { { names = []; has_variadic = true } }
  ;

if_expr:
  | IF LPAREN cond = expr RPAREN then_ = primary_expr ELSE else_ = primary_expr
    { IfElse { cond; then_; else_ } }
  ;

list_lit:
  | LBRACK items = separated_list(COMMA, named_item) RBRACK
    { ListLit items }
  ;

named_item:
  | e = expr { (None, e) }
  | name = IDENT COLON e = expr { (Some name, e) }
  ;

dict_lit:
  | LBRACE pairs = separated_list(COMMA, dict_pair) RBRACE
    { DictLit pairs }
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
