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
  | [] -> VDataFrame { columns = []; nrows = 0; group_keys = [] }
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
        VDataFrame { columns; nrows; group_keys = [] }

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

  (* --- Phase 4: Core Data Verbs (colcraft) --- *)

  (* select(df, "col1", "col2", ...) — column selection by name *)
  ("select", make_builtin ~variadic:true 1 (fun args _env ->
    match args with
    | VDataFrame df :: col_args ->
        let col_names = List.map (fun v ->
          match v with
          | VString s -> Ok s
          | _ -> Error (make_error TypeError "select() expects string column names")
        ) col_args in
        (match List.find_opt Result.is_error col_names with
         | Some (Error e) -> e
         | _ ->
           let names = List.map (fun r -> match r with Ok s -> s | _ -> "") col_names in
           let missing = List.filter (fun n -> not (List.mem_assoc n df.columns)) names in
           if missing <> [] then
             make_error KeyError (Printf.sprintf "Column(s) not found: %s" (String.concat ", " missing))
           else
             let selected = List.map (fun n -> (n, List.assoc n df.columns)) names in
             let remaining_keys = List.filter (fun k -> List.mem k names) df.group_keys in
             VDataFrame { columns = selected; nrows = df.nrows; group_keys = remaining_keys })
    | _ :: _ -> make_error TypeError "select() expects a DataFrame as first argument"
    | _ -> make_error ArityError "select() requires a DataFrame and at least one column name"
  ));

  (* filter(df, pred_fn) — row filtering with a predicate function *)
  ("filter", make_builtin 2 (fun args env ->
    match args with
    | [VDataFrame df; fn] ->
        let keep = Array.make df.nrows false in
        let had_error = ref None in
        for i = 0 to df.nrows - 1 do
          if !had_error = None then begin
            let row_dict = VDict (List.map (fun (name, col) -> (name, col.(i))) df.columns) in
            let result = eval_call env fn [(None, Value row_dict)] in
            match result with
            | VBool true -> keep.(i) <- true
            | VBool false -> ()
            | VError _ as e -> had_error := Some e
            | _ -> had_error := Some (make_error TypeError "filter() predicate must return a Bool")
          end
        done;
        (match !had_error with
         | Some e -> e
         | None ->
           let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 keep in
           let new_columns = List.map (fun (name, col) ->
             let new_col = Array.init new_nrows (fun j ->
               let rec find_nth src_idx count =
                 if keep.(src_idx) then
                   (if count = j then col.(src_idx)
                    else find_nth (src_idx + 1) (count + 1))
                 else find_nth (src_idx + 1) count
               in
               find_nth 0 0
             ) in
             (name, new_col)
           ) df.columns in
           VDataFrame { columns = new_columns; nrows = new_nrows; group_keys = df.group_keys })
    | [VDataFrame _] -> make_error ArityError "filter() requires a DataFrame and a predicate function"
    | [_; _] -> make_error TypeError "filter() expects a DataFrame as first argument"
    | _ -> make_error ArityError "filter() takes exactly 2 arguments"
  ));

  (* mutate(df, "new_col", fn) — create or transform a column *)
  ("mutate", make_builtin 3 (fun args env ->
    match args with
    | [VDataFrame df; VString col_name; fn] ->
        let new_col = Array.init df.nrows (fun i ->
          let row_dict = VDict (List.map (fun (name, col) -> (name, col.(i))) df.columns) in
          eval_call env fn [(None, Value row_dict)]
        ) in
        (* Check for errors in computed column *)
        let first_error = ref None in
        Array.iter (fun v ->
          if !first_error = None then
            match v with VError _ -> first_error := Some v | _ -> ()
        ) new_col;
        (match !first_error with
         | Some e -> e
         | None ->
           (* Replace existing column or append new one *)
           let existing = List.mem_assoc col_name df.columns in
           let new_columns =
             if existing then
               List.map (fun (n, c) -> if n = col_name then (n, new_col) else (n, c)) df.columns
             else
               df.columns @ [(col_name, new_col)]
           in
           VDataFrame { columns = new_columns; nrows = df.nrows; group_keys = df.group_keys })
    | [VDataFrame _; VString _] -> make_error ArityError "mutate() requires a DataFrame, column name, and a function"
    | [VDataFrame _; _; _] -> make_error TypeError "mutate() expects a string column name as second argument"
    | [_; _; _] -> make_error TypeError "mutate() expects a DataFrame as first argument"
    | _ -> make_error ArityError "mutate() takes exactly 3 arguments"
  ));

  (* arrange(df, "col") or arrange(df, "col", "desc") — sort rows by column *)
  ("arrange", make_builtin ~variadic:true 2 (fun args _env ->
    match args with
    | [VDataFrame df; VString col_name] | [VDataFrame df; VString col_name; VString "asc"] ->
        (match List.assoc_opt col_name df.columns with
         | None -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" col_name)
         | Some col ->
           let indices = Array.init df.nrows (fun i -> i) in
           let compare_values a b =
             match (a, b) with
             | (VInt x, VInt y) -> compare x y
             | (VFloat x, VFloat y) -> compare x y
             | (VString x, VString y) -> String.compare x y
             | (VBool x, VBool y) -> compare x y
             | (VNA _, _) -> 1  (* NAs sort last *)
             | (_, VNA _) -> -1
             | _ -> 0
           in
           Array.sort (fun i j -> compare_values col.(i) col.(j)) indices;
           let new_columns = List.map (fun (name, c) ->
             (name, Array.init df.nrows (fun k -> c.(indices.(k))))
           ) df.columns in
           VDataFrame { columns = new_columns; nrows = df.nrows; group_keys = df.group_keys })
    | [VDataFrame df; VString col_name; VString "desc"] ->
        (match List.assoc_opt col_name df.columns with
         | None -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" col_name)
         | Some col ->
           let indices = Array.init df.nrows (fun i -> i) in
           let compare_values a b =
             match (a, b) with
             | (VInt x, VInt y) -> compare y x  (* reversed *)
             | (VFloat x, VFloat y) -> compare y x
             | (VString x, VString y) -> String.compare y x
             | (VBool x, VBool y) -> compare y x
             | (VNA _, _) -> 1
             | (_, VNA _) -> -1
             | _ -> 0
           in
           Array.sort (fun i j -> compare_values col.(i) col.(j)) indices;
           let new_columns = List.map (fun (name, c) ->
             (name, Array.init df.nrows (fun k -> c.(indices.(k))))
           ) df.columns in
           VDataFrame { columns = new_columns; nrows = df.nrows; group_keys = df.group_keys })
    | [VDataFrame _; VString _; VString dir] ->
        make_error ValueError (Printf.sprintf "arrange() direction must be \"asc\" or \"desc\", got \"%s\"" dir)
    | [VDataFrame _; _] | [VDataFrame _; _; _] ->
        make_error TypeError "arrange() expects a string column name"
    | [_; _] | [_; _; _] -> make_error TypeError "arrange() expects a DataFrame as first argument"
    | _ -> make_error ArityError "arrange() takes 2 or 3 arguments"
  ));

  (* group_by(df, "col1", "col2", ...) — mark grouping columns *)
  ("group_by", make_builtin ~variadic:true 1 (fun args _env ->
    match args with
    | VDataFrame df :: key_args ->
        let key_names = List.map (fun v ->
          match v with
          | VString s -> Ok s
          | _ -> Error (make_error TypeError "group_by() expects string column names")
        ) key_args in
        (match List.find_opt Result.is_error key_names with
         | Some (Error e) -> e
         | _ ->
           let names = List.map (fun r -> match r with Ok s -> s | _ -> "") key_names in
           let missing = List.filter (fun n -> not (List.mem_assoc n df.columns)) names in
           if missing <> [] then
             make_error KeyError (Printf.sprintf "Column(s) not found: %s" (String.concat ", " missing))
           else if names = [] then
             make_error ArityError "group_by() requires at least one column name"
           else
             VDataFrame { df with group_keys = names })
    | [_] -> make_error TypeError "group_by() expects a DataFrame as first argument"
    | _ -> make_error ArityError "group_by() requires a DataFrame and at least one column name"
  ));

  (* --- Phase 5: Math Package — pure numerical primitives --- *)

  (* sqrt(x) — square root, scalar or vector *)
  ("sqrt", make_builtin 1 (fun args _env ->
    match args with
    | [VInt n] ->
        if n < 0 then make_error ValueError "sqrt() is undefined for negative numbers"
        else VFloat (Float.sqrt (float_of_int n))
    | [VFloat f] ->
        if f < 0.0 then make_error ValueError "sqrt() is undefined for negative numbers"
        else VFloat (Float.sqrt f)
    | [VVector arr] ->
        let result = Array.make (Array.length arr) VNull in
        let had_error = ref None in
        Array.iteri (fun i v ->
          if !had_error = None then
            match v with
            | VInt n ->
                if n < 0 then had_error := Some (make_error ValueError "sqrt() is undefined for negative numbers")
                else result.(i) <- VFloat (Float.sqrt (float_of_int n))
            | VFloat f ->
                if f < 0.0 then had_error := Some (make_error ValueError "sqrt() is undefined for negative numbers")
                else result.(i) <- VFloat (Float.sqrt f)
            | VNA _ -> had_error := Some (make_error TypeError "sqrt() encountered NA value. Handle missingness explicitly.")
            | _ -> had_error := Some (make_error TypeError "sqrt() requires numeric values")
        ) arr;
        (match !had_error with Some e -> e | None -> VVector result)
    | [VNA _] -> make_error TypeError "sqrt() encountered NA value. Handle missingness explicitly."
    | [_] -> make_error TypeError "sqrt() expects a number or numeric Vector"
    | _ -> make_error ArityError "sqrt() takes exactly 1 argument"
  ));

  (* abs(x) — absolute value, scalar or vector *)
  ("abs", make_builtin 1 (fun args _env ->
    match args with
    | [VInt n] -> VInt (Int.abs n)
    | [VFloat f] -> VFloat (Float.abs f)
    | [VVector arr] ->
        let result = Array.make (Array.length arr) VNull in
        let had_error = ref None in
        Array.iteri (fun i v ->
          if !had_error = None then
            match v with
            | VInt n -> result.(i) <- VInt (Int.abs n)
            | VFloat f -> result.(i) <- VFloat (Float.abs f)
            | VNA _ -> had_error := Some (make_error TypeError "abs() encountered NA value. Handle missingness explicitly.")
            | _ -> had_error := Some (make_error TypeError "abs() requires numeric values")
        ) arr;
        (match !had_error with Some e -> e | None -> VVector result)
    | [VNA _] -> make_error TypeError "abs() encountered NA value. Handle missingness explicitly."
    | [_] -> make_error TypeError "abs() expects a number or numeric Vector"
    | _ -> make_error ArityError "abs() takes exactly 1 argument"
  ));

  (* log(x) — natural logarithm, scalar or vector *)
  ("log", make_builtin 1 (fun args _env ->
    match args with
    | [VInt n] ->
        if n <= 0 then make_error ValueError "log() is undefined for non-positive numbers"
        else VFloat (Float.log (float_of_int n))
    | [VFloat f] ->
        if f <= 0.0 then make_error ValueError "log() is undefined for non-positive numbers"
        else VFloat (Float.log f)
    | [VVector arr] ->
        let result = Array.make (Array.length arr) VNull in
        let had_error = ref None in
        Array.iteri (fun i v ->
          if !had_error = None then
            match v with
            | VInt n ->
                if n <= 0 then had_error := Some (make_error ValueError "log() is undefined for non-positive numbers")
                else result.(i) <- VFloat (Float.log (float_of_int n))
            | VFloat f ->
                if f <= 0.0 then had_error := Some (make_error ValueError "log() is undefined for non-positive numbers")
                else result.(i) <- VFloat (Float.log f)
            | VNA _ -> had_error := Some (make_error TypeError "log() encountered NA value. Handle missingness explicitly.")
            | _ -> had_error := Some (make_error TypeError "log() requires numeric values")
        ) arr;
        (match !had_error with Some e -> e | None -> VVector result)
    | [VNA _] -> make_error TypeError "log() encountered NA value. Handle missingness explicitly."
    | [_] -> make_error TypeError "log() expects a number or numeric Vector"
    | _ -> make_error ArityError "log() takes exactly 1 argument"
  ));

  (* exp(x) — exponential, scalar or vector *)
  ("exp", make_builtin 1 (fun args _env ->
    match args with
    | [VInt n] -> VFloat (Float.exp (float_of_int n))
    | [VFloat f] -> VFloat (Float.exp f)
    | [VVector arr] ->
        let result = Array.make (Array.length arr) VNull in
        let had_error = ref None in
        Array.iteri (fun i v ->
          if !had_error = None then
            match v with
            | VInt n -> result.(i) <- VFloat (Float.exp (float_of_int n))
            | VFloat f -> result.(i) <- VFloat (Float.exp f)
            | VNA _ -> had_error := Some (make_error TypeError "exp() encountered NA value. Handle missingness explicitly.")
            | _ -> had_error := Some (make_error TypeError "exp() requires numeric values")
        ) arr;
        (match !had_error with Some e -> e | None -> VVector result)
    | [VNA _] -> make_error TypeError "exp() encountered NA value. Handle missingness explicitly."
    | [_] -> make_error TypeError "exp() expects a number or numeric Vector"
    | _ -> make_error ArityError "exp() takes exactly 1 argument"
  ));

  (* pow(base, exponent) — power function, scalar or vector *)
  ("pow", make_builtin 2 (fun args _env ->
    match args with
    | [VInt b; VInt e] -> VFloat (Float.pow (float_of_int b) (float_of_int e))
    | [VFloat b; VInt e] -> VFloat (Float.pow b (float_of_int e))
    | [VInt b; VFloat e] -> VFloat (Float.pow (float_of_int b) e)
    | [VFloat b; VFloat e] -> VFloat (Float.pow b e)
    | [VVector arr; exp_val] ->
        let exp_f = match exp_val with
          | VInt n -> Some (float_of_int n)
          | VFloat f -> Some f
          | _ -> None
        in
        (match exp_f with
         | None -> make_error TypeError "pow() expects a numeric exponent"
         | Some e ->
           let result = Array.make (Array.length arr) VNull in
           let had_error = ref None in
           Array.iteri (fun i v ->
             if !had_error = None then
               match v with
               | VInt n -> result.(i) <- VFloat (Float.pow (float_of_int n) e)
               | VFloat f -> result.(i) <- VFloat (Float.pow f e)
               | VNA _ -> had_error := Some (make_error TypeError "pow() encountered NA value. Handle missingness explicitly.")
               | _ -> had_error := Some (make_error TypeError "pow() requires numeric values")
           ) arr;
           (match !had_error with Some e -> e | None -> VVector result))
    | [VNA _; _] | [_; VNA _] -> make_error TypeError "pow() encountered NA value. Handle missingness explicitly."
    | [_; _] -> make_error TypeError "pow() expects numeric arguments"
    | _ -> make_error ArityError "pow() takes exactly 2 arguments"
  ));

  (* --- Phase 5: Stats Package — statistical summaries and models --- *)

  (* mean(v) — arithmetic mean of a numeric vector or list *)
  ("mean", make_builtin 1 (fun args _env ->
    let extract_nums label vals =
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | (_, VInt n) :: rest -> go (float_of_int n :: acc) rest
        | (_, VFloat f) :: rest -> go (f :: acc) rest
        | (_, VNA _) :: _ -> Error (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
        | _ -> Error (make_error TypeError (label ^ "() requires numeric values"))
      in go [] vals
    in
    let extract_nums_arr label arr =
      let len = Array.length arr in
      let had_error = ref None in
      let result = Array.make len 0.0 in
      for i = 0 to len - 1 do
        if !had_error = None then
          match arr.(i) with
          | VInt n -> result.(i) <- float_of_int n
          | VFloat f -> result.(i) <- f
          | VNA _ -> had_error := Some (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
          | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values"))
      done;
      match !had_error with Some e -> Error e | None -> Ok result
    in
    match args with
    | [VList []] -> make_error ValueError "mean() called on empty list"
    | [VList items] ->
        (match extract_nums "mean" items with
         | Error e -> e
         | Ok nums ->
           let sum = List.fold_left ( +. ) 0.0 nums in
           VFloat (sum /. float_of_int (List.length nums)))
    | [VVector arr] when Array.length arr = 0 -> make_error ValueError "mean() called on empty vector"
    | [VVector arr] ->
        (match extract_nums_arr "mean" arr with
         | Error e -> e
         | Ok nums ->
           let sum = Array.fold_left ( +. ) 0.0 nums in
           VFloat (sum /. float_of_int (Array.length nums)))
    | [VNA _] -> make_error TypeError "mean() encountered NA value. Handle missingness explicitly."
    | [_] -> make_error TypeError "mean() expects a numeric List or Vector"
    | _ -> make_error ArityError "mean() takes exactly 1 argument"
  ));

  (* sd(v) — standard deviation of a numeric vector or list (sample sd, n-1) *)
  ("sd", make_builtin 1 (fun args _env ->
    let extract_nums_arr label arr =
      let len = Array.length arr in
      let had_error = ref None in
      let result = Array.make len 0.0 in
      for i = 0 to len - 1 do
        if !had_error = None then
          match arr.(i) with
          | VInt n -> result.(i) <- float_of_int n
          | VFloat f -> result.(i) <- f
          | VNA _ -> had_error := Some (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
          | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values"))
      done;
      match !had_error with Some e -> Error e | None -> Ok result
    in
    let compute_sd nums n =
      if n < 2 then make_error ValueError "sd() requires at least 2 values"
      else
        let mean = Array.fold_left ( +. ) 0.0 nums /. float_of_int n in
        let sum_sq = Array.fold_left (fun acc x -> acc +. (x -. mean) *. (x -. mean)) 0.0 nums in
        VFloat (Float.sqrt (sum_sq /. float_of_int (n - 1)))
    in
    match args with
    | [VList items] ->
        let arr = Array.of_list (List.map snd items) in
        (match extract_nums_arr "sd" arr with
         | Error e -> e
         | Ok nums -> compute_sd nums (Array.length nums))
    | [VVector arr] ->
        (match extract_nums_arr "sd" arr with
         | Error e -> e
         | Ok nums -> compute_sd nums (Array.length nums))
    | [VNA _] -> make_error TypeError "sd() encountered NA value. Handle missingness explicitly."
    | [_] -> make_error TypeError "sd() expects a numeric List or Vector"
    | _ -> make_error ArityError "sd() takes exactly 1 argument"
  ));

  (* quantile(v, p) — quantile at probability p (0 to 1) using linear interpolation *)
  ("quantile", make_builtin 2 (fun args _env ->
    let extract_nums_arr label arr =
      let len = Array.length arr in
      let had_error = ref None in
      let result = Array.make len 0.0 in
      for i = 0 to len - 1 do
        if !had_error = None then
          match arr.(i) with
          | VInt n -> result.(i) <- float_of_int n
          | VFloat f -> result.(i) <- f
          | VNA _ -> had_error := Some (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
          | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values"))
      done;
      match !had_error with Some e -> Error e | None -> Ok result
    in
    let get_p = function
      | VFloat f -> if f < 0.0 || f > 1.0 then None else Some f
      | VInt 0 -> Some 0.0
      | VInt 1 -> Some 1.0
      | _ -> None
    in
    let compute_quantile nums p =
      let n = Array.length nums in
      if n = 0 then make_error ValueError "quantile() called on empty data"
      else begin
        let sorted = Array.copy nums in
        Array.sort compare sorted;
        let h = p *. float_of_int (n - 1) in
        let lo = int_of_float (Float.floor h) in
        let hi = min (lo + 1) (n - 1) in
        let frac = h -. float_of_int lo in
        VFloat (sorted.(lo) +. frac *. (sorted.(hi) -. sorted.(lo)))
      end
    in
    match args with
    | [VVector arr; p_val] ->
        (match get_p p_val with
         | None -> make_error ValueError "quantile() expects a probability between 0 and 1"
         | Some p ->
           (match extract_nums_arr "quantile" arr with
            | Error e -> e
            | Ok nums -> compute_quantile nums p))
    | [VList items; p_val] ->
        (match get_p p_val with
         | None -> make_error ValueError "quantile() expects a probability between 0 and 1"
         | Some p ->
           let arr = Array.of_list (List.map snd items) in
           (match extract_nums_arr "quantile" arr with
            | Error e -> e
            | Ok nums -> compute_quantile nums p))
    | [VNA _; _] | [_; VNA _] -> make_error TypeError "quantile() encountered NA value. Handle missingness explicitly."
    | [_; _] -> make_error TypeError "quantile() expects a numeric List or Vector as first argument"
    | _ -> make_error ArityError "quantile() takes exactly 2 arguments"
  ));

  (* cor(v1, v2) — Pearson correlation coefficient between two numeric vectors *)
  ("cor", make_builtin 2 (fun args _env ->
    let extract_nums_arr label arr =
      let len = Array.length arr in
      let had_error = ref None in
      let result = Array.make len 0.0 in
      for i = 0 to len - 1 do
        if !had_error = None then
          match arr.(i) with
          | VInt n -> result.(i) <- float_of_int n
          | VFloat f -> result.(i) <- f
          | VNA _ -> had_error := Some (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
          | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values"))
      done;
      match !had_error with Some e -> Error e | None -> Ok result
    in
    let to_arr = function
      | VVector arr -> Some arr
      | VList items -> Some (Array.of_list (List.map snd items))
      | _ -> None
    in
    match args with
    | [v1; v2] ->
        (match (to_arr v1, to_arr v2) with
         | (None, _) | (_, None) ->
             (match (v1, v2) with
              | (VNA _, _) | (_, VNA _) -> make_error TypeError "cor() encountered NA value. Handle missingness explicitly."
              | _ -> make_error TypeError "cor() expects two numeric Vectors or Lists")
         | (Some arr1, Some arr2) ->
           if Array.length arr1 <> Array.length arr2 then
             make_error ValueError "cor() requires vectors of equal length"
           else if Array.length arr1 < 2 then
             make_error ValueError "cor() requires at least 2 values"
           else
             (match (extract_nums_arr "cor" arr1, extract_nums_arr "cor" arr2) with
              | (Error e, _) | (_, Error e) -> e
              | (Ok xs, Ok ys) ->
                let n = Array.length xs in
                let mean_x = Array.fold_left ( +. ) 0.0 xs /. float_of_int n in
                let mean_y = Array.fold_left ( +. ) 0.0 ys /. float_of_int n in
                let sum_xy = ref 0.0 in
                let sum_xx = ref 0.0 in
                let sum_yy = ref 0.0 in
                for i = 0 to n - 1 do
                  let dx = xs.(i) -. mean_x in
                  let dy = ys.(i) -. mean_y in
                  sum_xy := !sum_xy +. dx *. dy;
                  sum_xx := !sum_xx +. dx *. dx;
                  sum_yy := !sum_yy +. dy *. dy
                done;
                if !sum_xx = 0.0 || !sum_yy = 0.0 then
                  make_error ValueError "cor() undefined: one or both vectors have zero variance"
                else
                  VFloat (!sum_xy /. Float.sqrt (!sum_xx *. !sum_yy))))
    | _ -> make_error ArityError "cor() takes exactly 2 arguments"
  ));

  (* lm(df, "y_col", "x_col") — simple linear regression, returns a model dict *)
  ("lm", make_builtin 3 (fun args _env ->
    let extract_nums_arr label arr =
      let len = Array.length arr in
      let had_error = ref None in
      let result = Array.make len 0.0 in
      for i = 0 to len - 1 do
        if !had_error = None then
          match arr.(i) with
          | VInt n -> result.(i) <- float_of_int n
          | VFloat f -> result.(i) <- f
          | VNA _ -> had_error := Some (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
          | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values in column"))
      done;
      match !had_error with Some e -> Error e | None -> Ok result
    in
    match args with
    | [VDataFrame df; VString y_col; VString x_col] ->
        (match (List.assoc_opt y_col df.columns, List.assoc_opt x_col df.columns) with
         | (None, _) -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" y_col)
         | (_, None) -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" x_col)
         | (Some y_arr, Some x_arr) ->
           if df.nrows < 2 then
             make_error ValueError "lm() requires at least 2 observations"
           else
             (match (extract_nums_arr "lm" y_arr, extract_nums_arr "lm" x_arr) with
              | (Error e, _) | (_, Error e) -> e
              | (Ok ys, Ok xs) ->
                let n = Array.length xs in
                let nf = float_of_int n in
                let mean_x = Array.fold_left ( +. ) 0.0 xs /. nf in
                let mean_y = Array.fold_left ( +. ) 0.0 ys /. nf in
                let sum_xy = ref 0.0 in
                let sum_xx = ref 0.0 in
                for i = 0 to n - 1 do
                  let dx = xs.(i) -. mean_x in
                  sum_xy := !sum_xy +. dx *. (ys.(i) -. mean_y);
                  sum_xx := !sum_xx +. dx *. dx
                done;
                if !sum_xx = 0.0 then
                  make_error ValueError "lm() cannot fit model: predictor has zero variance"
                else begin
                  let slope = !sum_xy /. !sum_xx in
                  let intercept = mean_y -. slope *. mean_x in
                  (* Compute residuals and R-squared *)
                  let ss_res = ref 0.0 in
                  let ss_tot = ref 0.0 in
                  let residuals = Array.init n (fun i ->
                    let fitted = intercept +. slope *. xs.(i) in
                    let r = ys.(i) -. fitted in
                    ss_res := !ss_res +. r *. r;
                    ss_tot := !ss_tot +. (ys.(i) -. mean_y) *. (ys.(i) -. mean_y);
                    VFloat r
                  ) in
                  let r_squared = if !ss_tot = 0.0 then 1.0 else 1.0 -. !ss_res /. !ss_tot in
                  VDict [
                    ("intercept", VFloat intercept);
                    ("slope", VFloat slope);
                    ("r_squared", VFloat r_squared);
                    ("residuals", VVector residuals);
                    ("n", VInt n);
                    ("response", VString y_col);
                    ("predictor", VString x_col);
                  ]
                end))
    | [VDataFrame _; VString _; VNA _] | [VDataFrame _; VNA _; _] | [VNA _; _; _] ->
        make_error TypeError "lm() encountered NA value. Handle missingness explicitly."
    | [VDataFrame _; _; _] -> make_error TypeError "lm() expects string column names"
    | [_; _; _] -> make_error TypeError "lm() expects a DataFrame as first argument"
    | _ -> make_error ArityError "lm() takes exactly 3 arguments (DataFrame, y_column, x_column)"
  ));

  (* summarize(df, "result_col", agg_fn, ...) — aggregation, pairs of name+fn *)
  ("summarize", make_builtin ~variadic:true 1 (fun args env ->
    match args with
    | VDataFrame df :: summary_args ->
        (* Parse pairs of (col_name_string, agg_function) *)
        let rec parse_pairs acc = function
          | VString name :: fn :: rest -> parse_pairs ((name, fn) :: acc) rest
          | [] -> Ok (List.rev acc)
          | _ -> Error (make_error TypeError "summarize() expects pairs of (string_name, function)")
        in
        (match parse_pairs [] summary_args with
         | Error e -> e
         | Ok pairs ->
           if pairs = [] then
             make_error ArityError "summarize() requires at least one (name, function) pair"
           else if df.group_keys = [] then
             (* Ungrouped: apply each agg_fn to the whole DataFrame *)
             let result_cols = List.map (fun (name, fn) ->
               let result = eval_call env fn [(None, Value (VDataFrame df))] in
               (name, result)
             ) pairs in
             (match List.find_opt (fun (_, v) -> is_error_value v) result_cols with
              | Some (_, e) -> e
              | None ->
                let columns = List.map (fun (name, v) -> (name, Array.make 1 v)) result_cols in
                VDataFrame { columns; nrows = 1; group_keys = [] })
           else
             (* Grouped: split into groups, apply agg to each, combine *)
             let key_cols = List.map (fun k -> (k, List.assoc k df.columns)) df.group_keys in
             (* Build group index: group_key_values -> list of row indices *)
             let group_map = Hashtbl.create 16 in
             for i = 0 to df.nrows - 1 do
               let key_vals = List.map (fun (_, col) -> col.(i)) key_cols in
               let key_str = String.concat "|" (List.map Utils.value_to_string key_vals) in
               let existing = try Hashtbl.find group_map key_str with Not_found -> (key_vals, []) in
               Hashtbl.replace group_map key_str (fst existing, i :: snd existing)
             done;
             (* Collect groups in order of first appearance *)
             let seen = Hashtbl.create 16 in
             let group_order = ref [] in
             for i = 0 to df.nrows - 1 do
               let key_vals = List.map (fun (_, col) -> col.(i)) key_cols in
               let key_str = String.concat "|" (List.map Utils.value_to_string key_vals) in
               if not (Hashtbl.mem seen key_str) then begin
                 Hashtbl.add seen key_str true;
                 group_order := key_str :: !group_order
               end
             done;
             let group_keys_ordered = List.rev !group_order in
             let n_groups = List.length group_keys_ordered in
             (* Build result: key columns + summary columns *)
             let key_result_cols = List.map (fun k ->
               let col = Array.init n_groups (fun g_idx ->
                 let key_str = List.nth group_keys_ordered g_idx in
                 let (key_vals, _) = Hashtbl.find group_map key_str in
                 let key_idx = let rec find_idx i = function
                   | [] -> 0 | (kn, _) :: _ when kn = k -> i | _ :: rest -> find_idx (i+1) rest
                 in find_idx 0 key_cols in
                 List.nth key_vals key_idx
               ) in
               (k, col)
             ) df.group_keys in
             let had_error = ref None in
             let summary_result_cols = List.map (fun (name, fn) ->
               let col = Array.init n_groups (fun g_idx ->
                 if !had_error <> None then VNull
                 else begin
                   let key_str = List.nth group_keys_ordered g_idx in
                   let (_, row_indices) = Hashtbl.find group_map key_str in
                   let row_indices = List.rev row_indices in
                   let sub_nrows = List.length row_indices in
                   let sub_columns = List.map (fun (cname, col) ->
                     let sub_col = Array.init sub_nrows (fun j ->
                       col.(List.nth row_indices j)
                     ) in
                     (cname, sub_col)
                   ) df.columns in
                   let sub_df = VDataFrame { columns = sub_columns; nrows = sub_nrows; group_keys = [] } in
                   let result = eval_call env fn [(None, Value sub_df)] in
                   (match result with
                    | VError _ -> had_error := Some result; result
                    | v -> v)
                 end
               ) in
               (name, col)
             ) pairs in
             (match !had_error with
              | Some e -> e
              | None ->
                let all_columns = key_result_cols @ summary_result_cols in
                VDataFrame { columns = all_columns; nrows = n_groups; group_keys = [] }))
    | _ -> make_error TypeError "summarize() expects a DataFrame as first argument"
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
