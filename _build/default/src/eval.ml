(* src/eval.ml *)
(* Tree-walking evaluator for the T language — Phase 0 Alpha *)

open Ast

(* Forward declarations for mutual recursion *)
let rec eval_expr (env : environment) (expr : Ast.expr) : value =
  match expr with
  | Value v -> v
  | Var s ->
      (match Env.find_opt s env with
      | Some v -> v
      | None -> VSymbol s) (* Return bare words as Symbols for future NSE *)

  | BinOp { op; left; right } -> eval_binop env op left right
  | UnOp { op; operand } -> eval_unop env op operand

  | IfElse { cond; then_; else_ } ->
      let cond_val = eval_expr env cond in
      (match cond_val with
       | VError _ as e -> e
       | _ -> if Utils.is_truthy cond_val then eval_expr env then_ else eval_expr env else_)

  | Call { fn; args } ->
      let fn_val = eval_expr env fn in
      eval_call env fn_val args

  | Lambda l -> VLambda { l with env = Some env } (* Capture the current environment *)

  (* Structural expressions *)
  | ListLit items -> eval_list_lit env items
  | DictLit pairs -> VDict (List.map (fun (k, e) -> (k, eval_expr env e)) pairs)
  | DotAccess { target; field } -> eval_dot_access env target field
  | ListComp _ -> VError "List comprehensions are not yet implemented"
  | Block exprs -> eval_block env exprs

and eval_block env = function
  | [] -> VNull
  | [e] -> eval_expr env e
  | e :: rest ->
      let _ = eval_expr env e in
      eval_block env rest

and eval_list_lit env items =
    let evaluated_items = List.map (fun (name, e) ->
        match eval_expr env e with
        | VError _ as err -> (name, err)
        | v -> (name, v)
    ) items in
    match List.find_opt (fun (_, v) -> match v with VError _ -> true | _ -> false) evaluated_items with
    | Some (_, err_val) -> err_val
    | None -> VList evaluated_items


and eval_dot_access env target_expr field =
  let target_val = eval_expr env target_expr in
  match target_val with
  | VDict pairs ->
      (match List.assoc_opt field pairs with
      | Some v -> v
      | None -> VError (Printf.sprintf "Key Error: key '%s' not found in dict" field))
  | VList named_items ->
      (match List.find_opt (fun (name, _) -> name = Some field) named_items with
      | Some (_, v) -> v
      | None -> VError (Printf.sprintf "Attribute Error: list has no named element '%s'" field))
  | VError _ as e -> e
  | other -> VError (Printf.sprintf "Type Error: Cannot access field '%s' on %s" field (Utils.type_name other))

and eval_call env fn_val raw_args =
  match fn_val with
  | VBuiltin { b_arity; b_variadic; b_func } ->
      let args = List.map (fun (_, e) -> eval_expr env e) raw_args in
      if not b_variadic && List.length args <> b_arity then
        VError (Printf.sprintf "Arity Error: Expected %d arguments but got %d" b_arity (List.length args))
      else
        b_func args env

  | VLambda { params; variadic = _; body; env = Some closure_env } ->
      let args = List.map (fun (_, e) -> eval_expr env e) raw_args in
      if List.length params <> List.length args then
        VError (Printf.sprintf "Arity Error: Expected %d arguments but got %d" (List.length params) (List.length args))
      else
        let call_env =
          List.fold_left2
            (fun current_env name value -> Env.add name value current_env)
            closure_env params args
        in
        eval_expr call_env body

  | VLambda { params; variadic = _; body; env = None } ->
      (* Lambda without closure — use current env *)
      let args = List.map (fun (_, e) -> eval_expr env e) raw_args in
      if List.length params <> List.length args then
        VError (Printf.sprintf "Arity Error: Expected %d arguments but got %d" (List.length params) (List.length args))
      else
        let call_env =
          List.fold_left2
            (fun current_env name value -> Env.add name value current_env)
            env params args
        in
        eval_expr call_env body

  | VSymbol s ->
      (* Try to look up the symbol in the env — might be a function name *)
      (match Env.find_opt s env with
       | Some fn -> eval_call env fn raw_args
       | None -> VError (Printf.sprintf "Name Error: '%s' is not defined" s))

  | VError _ as e -> e
  | _ -> VError (Printf.sprintf "Type Error: Cannot call %s as a function" (Utils.type_name fn_val))

and eval_binop env op left right =
  (* Pipe is special: x |> f(y) becomes f(x, y), x |> f becomes f(x) *)
  match op with
  | Pipe ->
      let lval = eval_expr env left in
      (match lval with
       | VError _ as e -> e
       | _ ->
         match right with
         | Call { fn; args } ->
             (* Insert pipe value as first argument *)
             let fn_val = eval_expr env fn in
             eval_call env fn_val ((None, Value lval) :: args)
         | _ ->
             (* RHS is a bare function name or expression *)
             let fn_val = eval_expr env right in
             eval_call env fn_val [(None, Value lval)]
      )
  | _ ->
  let lval = eval_expr env left in
  (match lval with VError _ as e -> e | _ ->
  let rval = eval_expr env right in
  (match rval with VError _ as e -> e | _ ->
  match (op, lval, rval) with
  (* Arithmetic *)
  | (Plus, VInt a, VInt b) -> VInt (a + b)
  | (Plus, VFloat a, VFloat b) -> VFloat (a +. b)
  | (Plus, VInt a, VFloat b) -> VFloat (float_of_int a +. b)
  | (Plus, VFloat a, VInt b) -> VFloat (a +. float_of_int b)
  | (Plus, VString a, VString b) -> VString (a ^ b)
  | (Minus, VInt a, VInt b) -> VInt (a - b)
  | (Minus, VFloat a, VFloat b) -> VFloat (a -. b)
  | (Minus, VInt a, VFloat b) -> VFloat (float_of_int a -. b)
  | (Minus, VFloat a, VInt b) -> VFloat (a -. float_of_int b)
  | (Mul, VInt a, VInt b) -> VInt (a * b)
  | (Mul, VFloat a, VFloat b) -> VFloat (a *. b)
  | (Mul, VInt a, VFloat b) -> VFloat (float_of_int a *. b)
  | (Mul, VFloat a, VInt b) -> VFloat (a *. float_of_int b)
  | (Div, VInt _, VInt 0) -> VError "Division by zero"
  | (Div, VInt a, VInt b) -> VInt (a / b)
  | (Div, VFloat _, VFloat b) when b = 0.0 -> VError "Division by zero"
  | (Div, VFloat a, VFloat b) -> VFloat (a /. b)
  | (Div, VInt a, VFloat b) -> if b = 0.0 then VError "Division by zero" else VFloat (float_of_int a /. b)
  | (Div, VFloat a, VInt b) -> if b = 0 then VError "Division by zero" else VFloat (a /. float_of_int b)
  (* Comparison *)
  | (Eq, a, b) -> VBool (a = b)
  | (NEq, a, b) -> VBool (a <> b)
  | (Lt, VInt a, VInt b) -> VBool (a < b)
  | (Lt, VFloat a, VFloat b) -> VBool (a < b)
  | (Gt, VInt a, VInt b) -> VBool (a > b)
  | (Gt, VFloat a, VFloat b) -> VBool (a > b)
  | (LtEq, VInt a, VInt b) -> VBool (a <= b)
  | (LtEq, VFloat a, VFloat b) -> VBool (a <= b)
  | (GtEq, VInt a, VInt b) -> VBool (a >= b)
  | (GtEq, VFloat a, VFloat b) -> VBool (a >= b)
  (* Logical *)
  | (And, a, b) -> VBool (Utils.is_truthy a && Utils.is_truthy b)
  | (Or, a, b) -> VBool (Utils.is_truthy a || Utils.is_truthy b)
  | (_, l, r) -> VError (Printf.sprintf "Type Error: Cannot apply operator to %s and %s" (Utils.type_name l) (Utils.type_name r))))

and eval_unop env op operand =
  let v = eval_expr env operand in
  match v with VError _ as e -> e | _ ->
  match (op, v) with
  | (Not, v) -> VBool (not (Utils.is_truthy v))
  | (Neg, VInt i) -> VInt (-i)
  | (Neg, VFloat f) -> VFloat (-.f)
  | (Neg, other) -> VError (Printf.sprintf "Type Error: Cannot negate %s" (Utils.type_name other))

(* --- Statement & Program Evaluation --- *)

let eval_statement (env : environment) (stmt : stmt) : value * environment =
  match stmt with
  | Expression e ->
      let v = eval_expr env e in
      (v, env)
  | Assignment { name; expr; _ } ->
      let v = eval_expr env expr in
      let new_env = Env.add name v env in
      (v, new_env)

(* --- Built-in Functions --- *)

let make_builtin ?(variadic=false) arity func =
  VBuiltin { b_arity = arity; b_variadic = variadic; b_func = func }

let builtins : (string * value) list = [
  ("print", make_builtin ~variadic:true 1 (fun args _env ->
    List.iter (fun v -> print_string (Utils.value_to_string v); print_char ' ') args;
    print_newline ();
    VNull
  ));
  ("type", make_builtin 1 (fun args _env ->
    match args with
    | [v] -> VString (Utils.type_name v)
    | _ -> VError "type() takes exactly 1 argument"
  ));
  ("length", make_builtin 1 (fun args _env ->
    match args with
    | [VList items] -> VInt (List.length items)
    | [VString s] -> VInt (String.length s)
    | [VDict pairs] -> VInt (List.length pairs)
    | [_] -> VError "Type Error: length() expects a List, String, or Dict"
    | _ -> VError "length() takes exactly 1 argument"
  ));
  ("assert", make_builtin 1 (fun args _env ->
    match args with
    | [v] ->
        if Utils.is_truthy v then VBool true
        else VError "Assertion failed"
    | _ -> VError "assert() takes exactly 1 argument"
  ));
  ("head", make_builtin 1 (fun args _env ->
    match args with
    | [VList []] -> VError "head() called on empty list"
    | [VList ((_, v) :: _)] -> v
    | [_] -> VError "Type Error: head() expects a List"
    | _ -> VError "head() takes exactly 1 argument"
  ));
  ("tail", make_builtin 1 (fun args _env ->
    match args with
    | [VList []] -> VError "tail() called on empty list"
    | [VList (_ :: rest)] -> VList rest
    | [_] -> VError "Type Error: tail() expects a List"
    | _ -> VError "tail() takes exactly 1 argument"
  ));
  ("is_error", make_builtin 1 (fun args _env ->
    match args with
    | [VError _] -> VBool true
    | [_] -> VBool false
    | _ -> VError "is_error() takes exactly 1 argument"
  ));
  ("seq", make_builtin 2 (fun args _env ->
    match args with
    | [VInt a; VInt b] ->
        let items = List.init (b - a + 1) (fun i -> (None, VInt (a + i))) in
        VList items
    | _ -> VError "seq() takes exactly 2 Int arguments"
  ));
  ("map", make_builtin 2 (fun args env ->
    match args with
    | [VList items; fn] ->
        let mapped = List.map (fun (name, v) ->
          let result = eval_call env fn [(None, Value v)] in
          (name, result)
        ) items in
        VList mapped
    | _ -> VError "map() takes a List and a Function"
  ));
  ("sum", make_builtin 1 (fun args _env ->
    match args with
    | [VList items] ->
        let rec add_all = function
          | [] -> VInt 0
          | (_, VInt n) :: rest ->
              (match add_all rest with
               | VInt acc -> VInt (acc + n)
               | VFloat acc -> VFloat (acc +. float_of_int n)
               | e -> e)
          | (_, VFloat f) :: rest ->
              (match add_all rest with
               | VInt acc -> VFloat (float_of_int acc +. f)
               | VFloat acc -> VFloat (acc +. f)
               | e -> e)
          | _ -> VError "sum() requires a list of numbers"
        in
        add_all items
    | _ -> VError "sum() takes exactly 1 List argument"
  ));
]

let initial_env () : environment =
  List.fold_left
    (fun env (name, v) -> Env.add name v env)
    Env.empty
    builtins

let eval_program (program : program) (env : environment) : value * environment =
  List.fold_left
    (fun (_v, current_env) stmt -> eval_statement current_env stmt)
    (VNull, env)
    program
