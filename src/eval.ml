(* src/eval.ml *)
(* Tree-walking evaluator for the T language — Phase 1 Alpha *)

open Ast

(* --- Error Construction Helpers --- *)

(** Create a structured error value *)
let make_error ?(context=[]) code message =
  VError { code; message; context }

(** Check if a value is an error *)
let is_error_value = function VError _ -> true | _ -> false

(** Check if a value is NA *)
let is_na_value = function VNA _ -> true | _ -> false

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
       | VNA _ -> make_error TypeError "Cannot use NA as a condition"
       | _ -> if Utils.is_truthy cond_val then eval_expr env then_ else eval_expr env else_)

  | Call { fn; args } ->
      let fn_val = eval_expr env fn in
      eval_call env fn_val args

  | Lambda l -> VLambda { l with env = Some env } (* Capture the current environment *)

  (* Structural expressions *)
  | ListLit items -> eval_list_lit env items
  | DictLit pairs -> VDict (List.map (fun (k, e) -> (k, eval_expr env e)) pairs)
  | DotAccess { target; field } -> eval_dot_access env target field
  | ListComp _ -> make_error GenericError "List comprehensions are not yet implemented"
  | Block exprs -> eval_block env exprs
  | PipelineDef nodes -> eval_pipeline env nodes

and eval_block env = function
  | [] -> VNull
  | [e] -> eval_expr env e
  | e :: rest ->
      let _ = eval_expr env e in
      eval_block env rest

(* --- Phase 3: Pipeline Evaluation --- *)

(** Extract free variable names from an expression *)
and free_vars (expr : Ast.expr) : string list =
  let rec collect = function
    | Value _ -> []
    | Var s -> [s]
    | Call { fn; args } ->
        collect fn @ List.concat_map (fun (_, e) -> collect e) args
    | Lambda { body; params; _ } ->
        let bound = params in
        List.filter (fun v -> not (List.mem v bound)) (collect body)
    | IfElse { cond; then_; else_ } ->
        collect cond @ collect then_ @ collect else_
    | ListLit items -> List.concat_map (fun (_, e) -> collect e) items
    | ListComp _ -> []
    | DictLit pairs -> List.concat_map (fun (_, e) -> collect e) pairs
    | BinOp { left; right; _ } -> collect left @ collect right
    | UnOp { operand; _ } -> collect operand
    | DotAccess { target; _ } -> collect target
    | Block exprs -> List.concat_map collect exprs
    | PipelineDef _ -> []
  in
  let vars = collect expr in
  List.sort_uniq String.compare vars

(** Topological sort of pipeline nodes based on dependencies *)
and topo_sort (nodes : Ast.pipeline_node list) (deps : (string * string list) list) : (string list, string) result =
  let node_names = List.map (fun n -> n.Ast.node_name) nodes in
  let visited = Hashtbl.create (List.length nodes) in
  let in_progress = Hashtbl.create (List.length nodes) in
  let order = ref [] in
  let rec visit name =
    if Hashtbl.mem visited name then Ok ()
    else if Hashtbl.mem in_progress name then Error name
    else begin
      Hashtbl.add in_progress name true;
      let node_deps = match List.assoc_opt name deps with Some d -> d | None -> [] in
      let result = List.fold_left (fun acc dep ->
        match acc with
        | Error _ as e -> e
        | Ok () ->
          if List.mem dep node_names then visit dep
          else Ok ()
      ) (Ok ()) node_deps in
      match result with
      | Error _ as e -> e
      | Ok () ->
        Hashtbl.remove in_progress name;
        Hashtbl.add visited name true;
        order := name :: !order;
        Ok ()
    end
  in
  let result = List.fold_left (fun acc name ->
    match acc with
    | Error _ as e -> e
    | Ok () -> visit name
  ) (Ok ()) node_names in
  match result with
  | Error name -> Error name
  | Ok () -> Ok (List.rev !order)

(** Evaluate a pipeline definition *)
and eval_pipeline env (nodes : Ast.pipeline_node list) : value =
  let node_names = List.map (fun n -> n.Ast.node_name) nodes in
  (* Compute dependencies: only consider references to other node names *)
  let deps = List.map (fun (n : Ast.pipeline_node) ->
    let fv = free_vars n.node_expr in
    let node_deps = List.filter (fun v -> List.mem v node_names) fv in
    (n.node_name, node_deps)
  ) nodes in
  (* Topological sort *)
  match topo_sort nodes deps with
  | Error cycle_node ->
    make_error ValueError (Printf.sprintf "Pipeline has a dependency cycle involving node '%s'" cycle_node)
  | Ok exec_order ->
    (* Execute nodes in topological order *)
    let node_expr_map = List.map (fun (n : Ast.pipeline_node) -> (n.node_name, n.node_expr)) nodes in
    let (results, _) = List.fold_left (fun (results, pipe_env) name ->
      let expr = List.assoc name node_expr_map in
      let v = eval_expr pipe_env expr in
      let new_env = Env.add name v pipe_env in
      ((name, v) :: results, new_env)
    ) ([], env) exec_order in
    let p_nodes = List.rev results in
    (* Check for errors in any node *)
    match List.find_opt (fun (_, v) -> is_error_value v) p_nodes with
    | Some (name, err) ->
      make_error ValueError (Printf.sprintf "Pipeline node '%s' failed: %s" name (Ast.Utils.value_to_string err))
    | None ->
      VPipeline {
        p_nodes;
        p_exprs = node_expr_map;
        p_deps = deps;
      }

(** Re-run a pipeline, skipping nodes whose dependencies haven't changed *)
and rerun_pipeline env (prev : Ast.pipeline_result) : value =
  let node_names = List.map fst prev.p_exprs in
  match topo_sort
    (List.map (fun (name, expr) -> { Ast.node_name = name; node_expr = expr }) prev.p_exprs)
    prev.p_deps with
  | Error cycle_node ->
    make_error ValueError (Printf.sprintf "Pipeline has a dependency cycle involving node '%s'" cycle_node)
  | Ok exec_order ->
    let (results, _, _changed_set) = List.fold_left (fun (results, pipe_env, changed) name ->
      let expr = List.assoc name prev.p_exprs in
      let node_deps = match List.assoc_opt name prev.p_deps with Some d -> d | None -> [] in
      (* A node needs re-evaluation if any of its dependencies changed *)
      let deps_changed = List.exists (fun d -> List.mem d changed) node_deps in
      (* Also check if any dep refers to something outside the pipeline that may have changed *)
      let fv = free_vars expr in
      let external_deps = List.filter (fun v -> not (List.mem v node_names)) fv in
      let external_changed = List.exists (fun v ->
        let old_val = Env.find_opt v env in
        let prev_val = match List.assoc_opt v prev.p_nodes with Some x -> Some x | None -> None in
        old_val <> prev_val
      ) external_deps in
      if deps_changed || external_changed then begin
        let v = eval_expr pipe_env expr in
        let new_env = Env.add name v pipe_env in
        ((name, v) :: results, new_env, name :: changed)
      end else begin
        (* Reuse cached value *)
        let cached = List.assoc name prev.p_nodes in
        let new_env = Env.add name cached pipe_env in
        ((name, cached) :: results, new_env, changed)
      end
    ) ([], env, []) exec_order in
    let p_nodes = List.rev results in
    match List.find_opt (fun (_, v) -> is_error_value v) p_nodes with
    | Some (name, err) ->
      make_error ValueError (Printf.sprintf "Pipeline node '%s' failed: %s" name (Ast.Utils.value_to_string err))
    | None ->
      VPipeline {
        p_nodes;
        p_exprs = prev.p_exprs;
        p_deps = prev.p_deps;
      }

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
      | None -> make_error KeyError (Printf.sprintf "key '%s' not found in dict" field))
  | VList named_items ->
      (match List.find_opt (fun (name, _) -> name = Some field) named_items with
      | Some (_, v) -> v
      | None -> make_error KeyError (Printf.sprintf "list has no named element '%s'" field))
  | VDataFrame { columns; _ } ->
      (match List.assoc_opt field columns with
       | Some col -> VVector col
       | None -> make_error KeyError (Printf.sprintf "column '%s' not found in DataFrame" field))
  | VPipeline { p_nodes; _ } ->
      (match List.assoc_opt field p_nodes with
       | Some v -> v
       | None -> make_error KeyError (Printf.sprintf "node '%s' not found in Pipeline" field))
  | VError _ as e -> e
  | VNA _ -> make_error TypeError "Cannot access field on NA"
  | other -> make_error TypeError (Printf.sprintf "Cannot access field '%s' on %s" field (Utils.type_name other))

and eval_call env fn_val raw_args =
  match fn_val with
  | VBuiltin { b_arity; b_variadic; b_func } ->
      let args = List.map (fun (_, e) -> eval_expr env e) raw_args in
      if not b_variadic && List.length args <> b_arity then
        make_error ArityError (Printf.sprintf "Expected %d arguments but got %d" b_arity (List.length args))
      else
        b_func args env

  | VLambda { params; variadic = _; body; env = Some closure_env } ->
      let args = List.map (fun (_, e) -> eval_expr env e) raw_args in
      if List.length params <> List.length args then
        make_error ArityError (Printf.sprintf "Expected %d arguments but got %d" (List.length params) (List.length args))
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
        make_error ArityError (Printf.sprintf "Expected %d arguments but got %d" (List.length params) (List.length args))
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
       | None -> make_error NameError (Printf.sprintf "'%s' is not defined" s))

  | VError _ as e -> e
  | VNA _ -> make_error TypeError "Cannot call NA as a function"
  | _ -> make_error TypeError (Printf.sprintf "Cannot call %s as a function" (Utils.type_name fn_val))

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
  (* NA does not propagate implicitly — operations with NA produce explicit errors *)
  match (lval, rval) with
  | (VNA _, _) | (_, VNA _) ->
      make_error TypeError "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly."
  | _ ->
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
  | (Div, VInt _, VInt 0) -> make_error DivisionByZero "Division by zero"
  | (Div, VInt a, VInt b) -> VInt (a / b)
  | (Div, VFloat _, VFloat b) when b = 0.0 -> make_error DivisionByZero "Division by zero"
  | (Div, VFloat a, VFloat b) -> VFloat (a /. b)
  | (Div, VInt a, VFloat b) -> if b = 0.0 then make_error DivisionByZero "Division by zero" else VFloat (float_of_int a /. b)
  | (Div, VFloat a, VInt b) -> if b = 0 then make_error DivisionByZero "Division by zero" else VFloat (a /. float_of_int b)
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
  | (_, l, r) -> make_error TypeError (Printf.sprintf "Cannot apply operator to %s and %s" (Utils.type_name l) (Utils.type_name r))))

and eval_unop env op operand =
  let v = eval_expr env operand in
  match v with VError _ as e -> e | _ ->
  match v with
  | VNA _ -> make_error TypeError "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly."
  | _ ->
  match (op, v) with
  | (Not, v) -> VBool (not (Utils.is_truthy v))
  | (Neg, VInt i) -> VInt (-i)
  | (Neg, VFloat f) -> VFloat (-.f)
  | (Neg, other) -> make_error TypeError (Printf.sprintf "Cannot negate %s" (Utils.type_name other))

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

(* --- Phase 2: Simple CSV Parser --- *)

(** Split a CSV line into fields, handling quoted fields *)
let parse_csv_line (line : string) : string list =
  let len = String.length line in
  let buf = Buffer.create 64 in
  let fields = ref [] in
  let i = ref 0 in
  let in_quotes = ref false in
  while !i < len do
    let c = line.[!i] in
    if !in_quotes then begin
      if c = '"' then begin
        if !i + 1 < len && line.[!i + 1] = '"' then begin
          Buffer.add_char buf '"';
          i := !i + 2
        end else begin
          in_quotes := false;
          i := !i + 1
        end
      end else begin
        Buffer.add_char buf c;
        i := !i + 1
      end
    end else begin
      if c = '"' then begin
        in_quotes := true;
        i := !i + 1
      end else if c = ',' then begin
        fields := Buffer.contents buf :: !fields;
        Buffer.clear buf;
        i := !i + 1
      end else begin
        Buffer.add_char buf c;
        i := !i + 1
      end
    end
  done;
  fields := Buffer.contents buf :: !fields;
  List.rev !fields

(** Try to parse a string as a typed value (Int, Float, Bool, NA, or String) *)
let parse_csv_value (s : string) : value =
  let trimmed = String.trim s in
  if trimmed = "" || trimmed = "NA" || trimmed = "na" || trimmed = "N/A" then
    VNA NAGeneric
  else
    match int_of_string_opt trimmed with
    | Some n -> VInt n
    | None ->
      match float_of_string_opt trimmed with
      | Some f -> VFloat f
      | None ->
        match String.lowercase_ascii trimmed with
        | "true" -> VBool true
        | "false" -> VBool false
        | _ -> VString trimmed

(** Split a string into lines, handling \r\n and \n *)
let split_lines (s : string) : string list =
  let lines = String.split_on_char '\n' s in
  List.map (fun line ->
    if String.length line > 0 && line.[String.length line - 1] = '\r' then
      String.sub line 0 (String.length line - 1)
    else
      line
  ) lines

(** Parse a CSV string into a DataFrame *)
let parse_csv_string (content : string) : value =
  let lines = split_lines content in
  (* Remove trailing empty lines *)
  let lines = List.filter (fun l -> String.trim l <> "") lines in
  match lines with
  | [] -> VDataFrame { columns = []; nrows = 0 }
  | header_line :: data_lines ->
      let headers = parse_csv_line header_line in
      let ncols = List.length headers in
      let data_rows = List.map parse_csv_line data_lines in
      (* Validate column count consistency *)
      let valid_rows = List.filter (fun row -> List.length row = ncols) data_rows in
      let nrows = List.length valid_rows in
      if nrows = 0 && List.length data_rows > 0 then
        make_error ValueError
          (Printf.sprintf "CSV Error: Row column counts do not match header (expected %d columns)" ncols)
      else
        (* Convert rows to array for O(1) access *)
        let rows_arr = Array.of_list valid_rows in
        (* Build column arrays *)
        let columns = List.mapi (fun col_idx name ->
          let col_data = Array.init nrows (fun row_idx ->
            let row = rows_arr.(row_idx) in
            parse_csv_value (List.nth row col_idx)
          ) in
          (name, col_data)
        ) headers in
        VDataFrame { columns; nrows }

let builtins : (string * value) list = [
  ("print", make_builtin ~variadic:true 1 (fun args _env ->
    List.iter (fun v -> print_string (Utils.value_to_string v); print_char ' ') args;
    print_newline ();
    VNull
  ));
  ("type", make_builtin 1 (fun args _env ->
    match args with
    | [v] -> VString (Utils.type_name v)
    | _ -> make_error ArityError "type() takes exactly 1 argument"
  ));
  ("length", make_builtin 1 (fun args _env ->
    match args with
    | [VList items] -> VInt (List.length items)
    | [VString s] -> VInt (String.length s)
    | [VDict pairs] -> VInt (List.length pairs)
    | [VVector arr] -> VInt (Array.length arr)
    | [VNA _] -> make_error TypeError "Cannot get length of NA"
    | [_] -> make_error TypeError "length() expects a List, String, Dict, or Vector"
    | _ -> make_error ArityError "length() takes exactly 1 argument"
  ));

  (* --- Phase 1: Enhanced assert --- *)
  ("assert", make_builtin ~variadic:true 1 (fun args _env ->
    match args with
    | [v] ->
        if is_na_value v then
          make_error AssertionError "Assertion received NA"
        else if Utils.is_truthy v then VBool true
        else make_error AssertionError "Assertion failed"
    | [v; VString msg] ->
        if is_na_value v then
          make_error AssertionError ("Assertion received NA: " ^ msg)
        else if Utils.is_truthy v then VBool true
        else make_error AssertionError ("Assertion failed: " ^ msg)
    | _ -> make_error ArityError "assert() takes 1 or 2 arguments"
  ));

  ("head", make_builtin 1 (fun args _env ->
    match args with
    | [VList []] -> make_error ValueError "head() called on empty list"
    | [VList ((_, v) :: _)] -> v
    | [VNA _] -> make_error TypeError "Cannot call head() on NA"
    | [_] -> make_error TypeError "head() expects a List"
    | _ -> make_error ArityError "head() takes exactly 1 argument"
  ));
  ("tail", make_builtin 1 (fun args _env ->
    match args with
    | [VList []] -> make_error ValueError "tail() called on empty list"
    | [VList (_ :: rest)] -> VList rest
    | [VNA _] -> make_error TypeError "Cannot call tail() on NA"
    | [_] -> make_error TypeError "tail() expects a List"
    | _ -> make_error ArityError "tail() takes exactly 1 argument"
  ));
  ("is_error", make_builtin 1 (fun args _env ->
    match args with
    | [VError _] -> VBool true
    | [_] -> VBool false
    | _ -> make_error ArityError "is_error() takes exactly 1 argument"
  ));
  ("seq", make_builtin 2 (fun args _env ->
    match args with
    | [VInt a; VInt b] ->
        let items = List.init (b - a + 1) (fun i -> (None, VInt (a + i))) in
        VList items
    | _ -> make_error TypeError "seq() takes exactly 2 Int arguments"
  ));
  ("map", make_builtin 2 (fun args env ->
    match args with
    | [VList items; fn] ->
        let mapped = List.map (fun (name, v) ->
          let result = eval_call env fn [(None, Value v)] in
          (name, result)
        ) items in
        VList mapped
    | _ -> make_error TypeError "map() takes a List and a Function"
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
          | (_, VNA _) :: _ -> make_error TypeError "sum() encountered NA value. Handle missingness explicitly."
          | _ -> make_error TypeError "sum() requires a list of numbers"
        in
        add_all items
    | _ -> make_error ArityError "sum() takes exactly 1 List argument"
  ));

  (* --- Phase 1: NA builtins --- *)
  ("is_na", make_builtin 1 (fun args _env ->
    match args with
    | [VNA _] -> VBool true
    | [_] -> VBool false
    | _ -> make_error ArityError "is_na() takes exactly 1 argument"
  ));
  ("na", make_builtin 0 (fun _args _env -> VNA NAGeneric));
  ("na_bool", make_builtin 0 (fun _args _env -> VNA NABool));
  ("na_int", make_builtin 0 (fun _args _env -> VNA NAInt));
  ("na_float", make_builtin 0 (fun _args _env -> VNA NAFloat));
  ("na_string", make_builtin 0 (fun _args _env -> VNA NAString));

  (* --- Phase 1: Error construction and inspection builtins --- *)
  ("error", make_builtin ~variadic:true 1 (fun args _env ->
    match args with
    | [VString msg] -> make_error GenericError msg
    | [VString code_str; VString msg] ->
        let code = match code_str with
          | "TypeError" -> TypeError
          | "ArityError" -> ArityError
          | "NameError" -> NameError
          | "DivisionByZero" -> DivisionByZero
          | "KeyError" -> KeyError
          | "IndexError" -> IndexError
          | "AssertionError" -> AssertionError
          | "FileError" -> FileError
          | "ValueError" -> ValueError
          | _ -> GenericError
        in
        make_error code msg
    | _ -> make_error ArityError "error() takes 1 or 2 string arguments"
  ));
  ("error_code", make_builtin 1 (fun args _env ->
    match args with
    | [VError { code; _ }] -> VString (Utils.error_code_to_string code)
    | [_] -> make_error TypeError "error_code() expects an Error value"
    | _ -> make_error ArityError "error_code() takes exactly 1 argument"
  ));
  ("error_message", make_builtin 1 (fun args _env ->
    match args with
    | [VError { message; _ }] -> VString message
    | [_] -> make_error TypeError "error_message() expects an Error value"
    | _ -> make_error ArityError "error_message() takes exactly 1 argument"
  ));
  ("error_context", make_builtin 1 (fun args _env ->
    match args with
    | [VError { context; _ }] ->
        VDict context
    | [_] -> make_error TypeError "error_context() expects an Error value"
    | _ -> make_error ArityError "error_context() takes exactly 1 argument"
  ));

  (* --- Phase 2: Tabular Data and Arrow Integration --- *)

  ("read_csv", make_builtin 1 (fun args _env ->
    match args with
    | [VString path] ->
        (try
          let ch = open_in path in
          let content = really_input_string ch (in_channel_length ch) in
          close_in ch;
          parse_csv_string content
        with
        | Sys_error msg -> make_error FileError ("File Error: " ^ msg))
    | [VNA _] -> make_error TypeError "read_csv() expects a String path, got NA"
    | [_] -> make_error TypeError "read_csv() expects a String path"
    | _ -> make_error ArityError "read_csv() takes exactly 1 argument"
  ));

  ("colnames", make_builtin 1 (fun args _env ->
    match args with
    | [VDataFrame { columns; _ }] ->
        VList (List.map (fun (name, _) -> (None, VString name)) columns)
    | [VNA _] -> make_error TypeError "colnames() expects a DataFrame, got NA"
    | [_] -> make_error TypeError "colnames() expects a DataFrame"
    | _ -> make_error ArityError "colnames() takes exactly 1 argument"
  ));

  ("nrow", make_builtin 1 (fun args _env ->
    match args with
    | [VDataFrame { nrows; _ }] -> VInt nrows
    | [VNA _] -> make_error TypeError "nrow() expects a DataFrame, got NA"
    | [_] -> make_error TypeError "nrow() expects a DataFrame"
    | _ -> make_error ArityError "nrow() takes exactly 1 argument"
  ));

  ("ncol", make_builtin 1 (fun args _env ->
    match args with
    | [VDataFrame { columns; _ }] -> VInt (List.length columns)
    | [VNA _] -> make_error TypeError "ncol() expects a DataFrame, got NA"
    | [_] -> make_error TypeError "ncol() expects a DataFrame"
    | _ -> make_error ArityError "ncol() takes exactly 1 argument"
  ));

  (* --- Phase 3: Pipeline Introspection and Execution --- *)

  ("pipeline_nodes", make_builtin 1 (fun args _env ->
    match args with
    | [VPipeline { p_nodes; _ }] ->
        VList (List.map (fun (name, _) -> (None, VString name)) p_nodes)
    | [_] -> make_error TypeError "pipeline_nodes() expects a Pipeline"
    | _ -> make_error ArityError "pipeline_nodes() takes exactly 1 argument"
  ));

  ("pipeline_deps", make_builtin 1 (fun args _env ->
    match args with
    | [VPipeline { p_deps; _ }] ->
        VDict (List.map (fun (name, deps) ->
          (name, VList (List.map (fun d -> (None, VString d)) deps))
        ) p_deps)
    | [_] -> make_error TypeError "pipeline_deps() expects a Pipeline"
    | _ -> make_error ArityError "pipeline_deps() takes exactly 1 argument"
  ));

  ("pipeline_node", make_builtin 2 (fun args _env ->
    match args with
    | [VPipeline { p_nodes; _ }; VString name] ->
        (match List.assoc_opt name p_nodes with
         | Some v -> v
         | None -> make_error KeyError (Printf.sprintf "node '%s' not found in Pipeline" name))
    | [VPipeline _; _] -> make_error TypeError "pipeline_node() expects a String node name as second argument"
    | [_; _] -> make_error TypeError "pipeline_node() expects a Pipeline as first argument"
    | _ -> make_error ArityError "pipeline_node() takes exactly 2 arguments"
  ));

  ("pipeline_run", make_builtin 1 (fun args env ->
    match args with
    | [VPipeline prev] -> rerun_pipeline env prev
    | [_] -> make_error TypeError "pipeline_run() expects a Pipeline"
    | _ -> make_error ArityError "pipeline_run() takes exactly 1 argument"
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
