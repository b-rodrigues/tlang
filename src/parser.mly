%{
(* parser.mly *)
(* Menhir grammar for the T language *)
open Ast
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
%token EOF

/* PRECEDENCE AND ASSOCIATIVITY */
/* Lowest */
%left PIPE
%left OR
%left AND
%nonassoc EQ NEQ LT GT LTE GTE
%left PLUS MINUS
%left STAR SLASH
%right NOT NEG (* for unary minus *)
%precedence DOT_ACCESS (* Dot access, higher than most operators *)
%precedence UNARY
/* Highest */

/* ENTRY POINT */
%start <Ast.program> program
%%

/* GRAMMAR RULES */

/* A program is a list of statements separated by newlines or EOF */
program:
  | stmts = list(statement) EOF { stmts }
  ;

statement:
  | e = expr { Expression(e) }
  | a = assignment { a }
  ;

assignment:
  | name = any_ident; EQUALS; e = expr
    { Assignment { name; typ = None; expr = e } }
  | name = any_ident; COLON; t = typ; EQUALS; e = expr
    { Assignment { name; typ = Some t; expr = e } }
  ;

expr:
  | e = simple_expr { e }
  | f = call { f }
  | l = lambda { l }
  | i = if_expr { i }
  | left = expr; op = binop; right = expr
    { BinOp { op; left; right } }
  | op = unop; operand = expr %prec UNARY
    { UnOp { op; operand } }
  ;

simple_expr:
  | v = value_lit { Value v }
  | v = Var(any_ident) { v }
  | LPAREN; e = expr; RPAREN { e }
  | list_lit { list_lit }
  | list_comp { list_comp }
  | dict_lit { dict_lit }
  ;

/* Literal values that can be parsed directly */
value_lit:
  | INT i { Int i }
  | FLOAT f { Float f }
  | STRING s { String s }
  | TRUE { Bool true }
  | FALSE { Bool false }
  | NULL { Null }
  ;

/* Function calls and dot access have high precedence */
call:
  | fn = expr; LPAREN; args = separated_list(COMMA, expr); RPAREN %prec DOT_ACCESS
    { Call { fn; args } }
  | target = expr; DOT; field = any_ident %prec DOT_ACCESS
    { DotAccess { target; field } }
  ;

lambda:
  | LAMBDA; LPAREN; p = params; RPAREN; body = expr
    { Lambda { params = p.names; variadic = p.has_variadic; body; env = None } }
  | FUNCTION; LPAREN; p = params; RPAREN; body = expr
    { Lambda { params = p.names; variadic = p.has_variadic; body; env = None } }
  ;

/* Helper for parsing parameter lists with optional variadic `...` */
params:
  | (* empty *) { { names = []; has_variadic = false } }
  | ps = separated_list(COMMA, any_ident)
    { { names = ps; has_variadic = false } }
  | ps = separated_list(COMMA, any_ident); COMMA; DOTDOTDOT
    { { names = ps; has_variadic = true } }
  | DOTDOTDOT
    { { names = []; has_variadic = true } }
  ;

if_expr:
  | IF; cond = expr; then_ = expr; ELSE; else_ = expr
    { IfElse { cond; then_; else_ } }
  ;

list_lit:
  | LBRACK; items = separated_list(COMMA, named_expr); RBRACK
    { ListLit(items) }
  ;

named_expr:
  | e = expr { (None, e) }
  | name = any_ident; COLON; e = expr { (Some name, e) }
  ;

dict_lit:
  | LBRACE; pairs = separated_list(COMMA, dict_pair); RBRACE
    { DictLit(pairs) }
  ;

dict_pair:
  | key = any_ident; COLON; value = expr { (key, value) }
  ;

list_comp:
  | LBRACK; transform = expr; clauses = nonempty_list(comp_clause); RBRACK
    { ListComp { expr = transform; clauses } }
  ;

comp_clause:
  | FOR; var = any_ident; IN; iter = expr { For { var; iter } }
  | IF; cond = expr { Filter cond }
  ;

/* An identifier can be bare or backticked */
any_ident:
  | id = IDENT { id }
  | id = BACKTICK_IDENT { id }
  ;

/* Optional type annotations */
typ:
  | IDENT "Int" { TInt }
  | IDENT "Float" { TFloat }
  | IDENT "Bool" { TBool }
  | IDENT "String" { TString }
  | IDENT "List" { TList }
  | IDENT "Dict" { TDict }
  | IDENT "DataFrame" { TDataFrame }
  | id = IDENT { TCustom id }
  ;

binop:
  | PIPE { Pipe } | PLUS { Plus } | MINUS { Minus } | STAR { Mul } | SLASH { Div }
  | EQ { Eq } | NEQ { NEq } | LT { Lt } | GT { Gt } | LTE { Lte } | GTE { Gte }
  | AND { And } | OR { Or }
  ;

unop:
  | NOT { Not }
  | MINUS { Neg }
  ; 
