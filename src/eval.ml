(* src/eval.ml *)

open Ast

exception RuntimeError of string

(* Environment: maps symbols to values *)
module Env = struct
  type t = (symbol, value) Hashtbl.t

  let empty () = Hashtbl.create 32
  let copy env = Hashtbl.copy env

  let get env key =
    try Hashtbl.find env key
    with Not_found -> VError ("Unbound variable: " ^ key)

  let set env key value =
    Hashtbl.replace env key value

  let of_bindings bindings =
    let env = empty () in
    List.iter (fun (k, v) -> set env k v) bindings;
    env
end

let global_env : Env.t = Env.empty ()

(* Unwrap errors, propagating exceptions *)
let unwrap = function
  | VError msg -> raise (RuntimeError msg)
  | v -> v

(* Built-in printers registry *)
module Print_builtin = struct
  let printers : (string * (value -> bool)) list ref = ref []

  let register ~tag f =
    printers := (tag, f) :: !printers

  let dispatch v =
    let handled =
      List.exists (fun (_, f) -> f v) !printers
    in
    if not handled then Printf.printf "<unhandled value>\n"
end

(* Pretty-printing for tables *)
let () =
  Print_builtin.register ~tag:"table" (function
    | VTable columns ->
        let col_names = List.map fst columns in
        let rows =
          let col_lists = List.map snd columns in
          let row_count =
            match col_lists with
            | [] -> 0
            | vs :: _ -> List.length (match vs with VList xs -> xs | _ -> [])
          in
          let get_col_row cidx ridx =
            match List.nth col_lists cidx with
            | VList xs -> (try List.nth xs ridx with _ -> VNull)
            | _ -> VNull
          in
          let rec build_rows r =
            if r >= row_count then []
            else
              (List.init (List.length col_lists) (fun c -> get_col_row c r))
              :: build_rows (r + 1)
          in
          build_rows 0
        in
        (* Print header *)
        Printf.printf "| %s |\n" (String.concat " | " col_names);
        Printf.printf "|%s|\n"
          (String.concat "" (List.map (fun _ -> "------|") col_names));
        (* Print rows *)
        List.iter (fun row ->
          Printf.printf "| %s |\n"
            (String.concat " | " (List.map
              (function
                | VString s -> s
                | VInt i -> string_of_int i
                | VFloat f -> string_of_float f
                | VNull -> ""
                | VBool b -> string_of_bool b
                | _ -> "<complex>"
              ) row))
        ) rows;
        true
    | _ -> false
  )

(* Apply a function value to arguments *)
let rec apply fn_val args env =
  match fn_val with
  | VLambda { params; body } ->
      if List.length params <> List.length args then
        VError "Incorrect number of arguments"
      else
        let local_env = Env.copy env in
        List.iter2 (Env.set local_env) params args;
        eval local_env body
  | VBuiltin f -> f args
  | _ -> VError "Not a function"

(* Evaluate binary operators *)
and eval_binop op a b =
  match op, a, b with
  | "+", VInt x, VInt y -> VInt (x + y)
  | "+", VFloat x, VFloat y -> VFloat (x +. y)
  | "-", VInt x, VInt y -> VInt (x - y)
  | "-", VFloat x, VFloat y -> VFloat (x -. y)
  | "*", VInt x, VInt y -> VInt (x * y)
  | "*", VFloat x, VFloat y -> VFloat (x *. y)
  | "/", VInt x, VInt y -> VFloat (float x /. float y)
  | "/", VFloat x, VFloat y -> VFloat (x /. y)
  | "==", a, b -> VBool (a = b)
  | "!=", a, b -> VBool (a <> b)
  | "<", VInt x, VInt y -> VBool (x < y)
  | "<", VFloat x, VFloat y -> VBool (x < y)
  | "<=", VInt x, VInt y -> VBool (x <= y)
  | "<=", VFloat x, VFloat y -> VBool (x <= y)
  | ">", VInt x, VInt y -> VBool (x > y)
  | ">", VFloat x, VFloat y -> VBool (x > y)
  | ">=", VInt x, VInt y -> VBool (x >= y)
  | ">=", VFloat x, VFloat y -> VBool (x >= y)
  | "and", VBool x, VBool y -> VBool (x && y)
  | "or", VBool x, VBool y -> VBool (x || y)
  | _ -> VError ("Unsupported binary operation: " ^ op)

(* Evaluate unary operators *)
and eval_unop op v =
  match op, v with
  | "-", VInt x -> VInt (-x)
  | "-", VFloat x -> VFloat (-.x)
  | "!", VBool b -> VBool (not b)
  | _ -> VError ("Unsupported unary operation: " ^ op)

(* Evaluate list comprehensions *)
and eval_list_comp env expr clauses =
  let rec loop env clauses =
    match clauses with
    | [] -> [eval env expr |> unwrap]
    | For (var, src_expr) :: rest ->
        (match eval env src_expr |> unwrap with
         | VList items ->
             List.flatten (List.map (fun v ->
               let local_env = Env.copy env in
               Env.set local_env var v;
               loop local_env rest
             ) items)
         | _ -> raise (RuntimeError "for in comprehension expects a list"))
    | If cond :: rest ->
        (match eval env cond |> unwrap with
         | VBool true -> loop env rest
         | VBool false -> []
         | _ -> raise (RuntimeError "if in list comprehension expects a boolean"))
  in
  VList (loop env clauses)

(* Main eval function *)
and eval env (e : expr) : value =
  match e with
  | EValue v -> v
  | EVar name -> Env.get env name
  | ECall (fn_expr, arg_exprs) ->
      let fn_val = eval env fn_expr |> unwrap in
      let args = List.map (fun e -> eval env e |> unwrap) arg_exprs in
      apply fn_val args env
  | ELambda lam -> VLambda lam
  | EIf (cond, thn, els) ->
      (match eval env cond |> unwrap with
       | VBool true -> eval env thn
       | VBool false -> (match els with Some e -> eval env e | None -> VNull)
       | _ -> VError "Condition must be boolean")
  | EBinOp (op, lhs, rhs) ->
      eval_binop op (eval env lhs |> unwrap) (eval env rhs |> unwrap)
  | EUnOp (op, e1) ->
      eval_unop op (eval env e1 |> unwrap)
  | EListComp (body, clauses) ->
      eval_list_comp env body clauses
  | EDictLit entries ->
      let pairs = List.map (fun (k, v_expr) -> (k, eval env v_expr |> unwrap)) entries in
      VDict pairs

let print_value v = Print_builtin.dispatch v

(* Register CSV builtins *)
let register_csv_builtins () =
  Hashtbl.replace global_env "Csv.read"
    (VBuiltin (function
      | [VString filename] -> Builtins_csv_reader.read_csv filename
      | _ -> VError "Csv.read expects a single filename string"
    ))
