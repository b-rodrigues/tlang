(* src/eval.ml *)
(* Revised evaluator with a functional, immutable environment and a modular, extensible design. *)

open Ast
open Eval_helpers (* Uses helpers for type errors, etc. *)

(* The environment is an immutable map from symbols to values. *)
module Env = Map.Make(String)
type environment = value Env.t

(* Forward declarations for mutual recursion *)
let rec eval_expr env expr =
  match expr with
  | Value v -> v
  | Var s ->
      (match Env.find_opt s env with
      | Some v -> v
      | None -> Symbol s) (* Return bare words as Symbols for Non-Standard Evaluation (NSE) *)

  | BinOp { op; left; right } -> eval_binop env op left right
  | UnOp { op; operand } -> eval_unop env op operand

  | IfElse { cond; then_; else_ } ->
      let cond_val = eval_expr env cond in
      (match cond_val with
       | Error _ as e -> e
       | _ -> if Utils.is_truthy cond_val then eval_expr env then_ else eval_expr env else_)

  | Call { fn; args } ->
      let fn_val = eval_expr env fn in
      eval_call env fn_val args

  | Lambda l -> VLambda { l with env = Some env } (* Capture the current environment *)

  (* Structural expressions *)
  | ListLit items -> eval_list_lit env items
  | DictLit pairs -> VDict (List.map (fun (k, e) -> (k, eval_expr env e)) pairs)
  | DotAccess { target; field } -> eval_dot_access env target field
  | ListComp _ -> Error "List comprehensions are not yet implemented"

and eval_list_lit env items =
    let evaluated_items = List.map (fun (name, e) ->
        match eval_expr env e with
        | Error _ as err -> (name, err) (* Propagate errors *)
        | v -> (name, v)
    ) items in
    (* Check if any item failed to evaluate *)
    match List.find_opt (fun (_, v) -> match v with Error _ -> true | _ -> false) evaluated_items with
    | Some (_, err_val) -> err_val
    | None -> VList evaluated_items


and eval_dot_access env target_expr field =
  let target_val = eval_expr env target_expr in
  match target_val with
  | VDict pairs ->
      (match List.assoc_opt field pairs with
      | Some v -> v
      | None -> Error (Printf.sprintf "Key Error: key '%s' not found in dict" field))
  | VList named_items ->
      (match List.find_opt (fun (name, _) -> name = Some field) named_items with
      | Some (_, v) -> v
      | None -> Error (Printf.sprintf "Attribute Error: list has no named element '%s'" field))
  | VDataFrame { columns; _ } ->
      (match List.assoc_opt field columns with
       | Some col_data -> VList (List.map (fun v -> (None, v)) (Array.to_list col_data))
       | None -> Error (Printf.sprintf "Column Error: column '%s' not found in DataFrame" field))
  | Error _ as e -> e
  | other -> type_error "Dict, named List, or DataFrame" other

and eval_call env fn_val raw_args =
  match fn_val with
  | VBuiltin { arity; variadic; func } ->
      (* For NSE, we pass some arguments as raw expressions *)
      let args = List.map (eval_expr env) raw_args in
      if not variadic && List.length args <> arity then
        Error (Printf.sprintf "Arity Error: Expected %d arguments but got %d" arity (List.length args))
      else
        func args env (* Pass current env for complex functions like 'filter' *)

  | VLambda { params; variadic; body; env = Some closure_env } ->
      let args = List.map (eval_expr env) raw_args in
      (* TODO: Check for arity errors *)
      let call_env =
        List.fold_left2
          (fun current_env name value -> Env.add name value current_env)
          closure_env params args
      in
      eval_expr call_env body

  | Error _ as e -> e
  | _ -> type_error "function" fn_val

and eval_binop env op left right =
  let lval = eval_expr env left in
  match lval with Error _ as e -> e | _ ->
  let rval = eval_expr env right in
  match rval with Error _ as e -> e | _ ->
  match (op, lval, rval) with
  (* Arithmetic *)
  | (Plus, VInt a, VInt b) -> VInt (a + b)
  | (Plus, VFloat a, VFloat b) -> VFloat (a +. b)
  | (Minus, VInt a, VInt b) -> VInt (a - b)
  | (Minus, VFloat a, VFloat b) -> VFloat (a -. b)
  | (Mul, VInt a, VInt b) -> VInt (a * b)
  | (Mul, VFloat a, VFloat b) -> VFloat (a *. b)
  | (Div, VInt a, VInt b) -> if b = 0 then Error "Division by zero" else VInt (a / b)
  | (Div, VFloat a, VFloat b) -> if b = 0.0 then Error "Division by zero" else VFloat (a /. b)
  (* Comparison *)
  | (Eq, a, b) -> VBool (a = b)
  | (NEq, a, b) -> VBool (a <> b)
  | (Lt, VInt a, VInt b) -> VBool (a < b)
  | (Gt, VInt a, VInt b) -> VBool (a > b)
  (* TODO: Add more type combinations for comparisons *)
  | (_, l, r) -> Error (Printf.sprintf "Cannot apply operator to types %s and %s" (Utils.type_name l) (Utils.type_name r))

and eval_unop env op operand =
  let v = eval_expr env operand in
  match v with Error _ as e -> e | _ ->
  match (op, v) with
  | (Not, v) -> VBool (not (Utils.is_truthy v))
  | (Neg, VInt i) -> VInt (-i)
  | (Neg, VFloat f) -> VFloat (-.f)
  | (Neg, other) -> type_error "Int or Float" other

(* --- Statement & Program Evaluation --- *)

let eval_statement env stmt =
  match stmt with
  | Expression e ->
      let v = eval_expr env e in
      (v, env) (* Return value, environment is unchanged *)
  | Assignment { name; expr; _ } ->
      let v = eval_expr env expr in
      let new_env = Env.add name v env in
      (v, new_env) (* Return value, and the new environment with the binding *)

let initial_env () =
  let env = Env.empty in
  let env = Builtins.load env in
  let env = Colcraft.load env in
  env

let eval_program program env =
  let last_val, _final_env =
    List.fold_left
      (fun (_v, current_env) stmt -> eval_statement current_env stmt)
      (VNull, env)
      program
  in
  last_val
