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

(* --- NSE (Non-Standard Evaluation) Helpers --- *)

(** Transform an NSE expression like ($age > 30) into (fun row -> row.age > 30).
    This recursively replaces ColumnRef nodes with DotAccess nodes. *)
let rec desugar_nse_expr (expr : Ast.expr) : Ast.expr =
  match expr with
  | ColumnRef field ->
      (* $field → row.field *)
      DotAccess { target = Var "row"; field }
  | BinOp { op; left; right } ->
      (* Recursively transform both sides *)
      BinOp { op; left = desugar_nse_expr left; right = desugar_nse_expr right }
  | UnOp { op; operand } ->
      UnOp { op; operand = desugar_nse_expr operand }
  | Call { fn; args } ->
      Call { fn = desugar_nse_expr fn; 
             args = List.map (fun (n, e) -> (n, desugar_nse_expr e)) args }
  | IfElse { cond; then_; else_ } ->
      IfElse { 
        cond = desugar_nse_expr cond;
        then_ = desugar_nse_expr then_;
        else_ = desugar_nse_expr else_ 
      }
  | ListLit items ->
      ListLit (List.map (fun (n, e) -> (n, desugar_nse_expr e)) items)
  | DictLit pairs ->
      DictLit (List.map (fun (k, e) -> (k, desugar_nse_expr e)) pairs)
  | DotAccess { target; field } ->
      DotAccess { target = desugar_nse_expr target; field }
  | Block exprs ->
      Block (List.map desugar_nse_expr exprs)
  (* Other expression types remain unchanged *)
  | Value _ | Var _ | Lambda _ | ListComp _ | PipelineDef _ | IntentDef _ as e -> e

(** Check if an expression uses NSE (contains $field references) *)
let rec uses_nse (expr : Ast.expr) : bool =
  match expr with
  | ColumnRef _ -> true
  | BinOp { left; right; _ } -> uses_nse left || uses_nse right
  | UnOp { operand; _ } -> uses_nse operand
  | Call { fn; args } -> uses_nse fn || List.exists (fun (_, e) -> uses_nse e) args
  | IfElse { cond; then_; else_ } ->
      uses_nse cond || uses_nse then_ || uses_nse else_
  | ListLit items -> List.exists (fun (_, e) -> uses_nse e) items
  | DictLit pairs -> List.exists (fun (_, e) -> uses_nse e) pairs
  | DotAccess { target; _ } -> uses_nse target
  | Block exprs -> List.exists uses_nse exprs
  | _ -> false

(* Forward declarations for mutual recursion *)

(** Extract variable names from a formula expression.
    Supports: x, x + y, x + y + z
    Returns list of variable names *)
let rec extract_formula_vars (expr : Ast.expr) : string list =
  match expr with
  | Var s -> [s]
  | BinOp { op = Plus; left; right } ->
      extract_formula_vars left @ extract_formula_vars right
  | Value (VInt 1) -> []  (* Intercept term: y ~ x + 1 *)
  | _ -> []  (* Unsupported formula syntax *)

let rec eval_expr (env : environment) (expr : Ast.expr) : value =
  match expr with
  | Value v -> v
  | Var s ->
      (match Env.find_opt s env with
      | Some v -> v
      | None -> VSymbol s) (* Return bare words as Symbols for future NSE *)
  
  | ColumnRef field ->
      (* Column references ($name) evaluate to a special symbol value
         that data verbs can recognize and process. The symbol is prefixed
         with "$" to distinguish it from regular symbols. *)
      VSymbol ("$" ^ field)

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
  | IntentDef pairs -> eval_intent env pairs

and eval_block env = function
  | [] -> VNull
  | [e] -> eval_expr env e
  | e :: rest ->
      let _ = eval_expr env e in
      eval_block env rest

(* --- Phase 6: Intent Block Evaluation --- *)

(** Evaluate an intent block definition *)
and eval_intent env pairs =
  let evaluated = List.map (fun (k, e) ->
    let v = eval_expr env e in
    match v with
    | VString s -> Ok (k, s)
    | VError _ -> Error v
    | _ -> Ok (k, Utils.value_to_string v)
  ) pairs in
  match List.find_opt (fun r -> match r with Error _ -> true | _ -> false) evaluated with
  | Some (Error e) -> e
  | _ ->
    let fields = List.map (fun r -> match r with Ok p -> p | _ -> ("", "")) evaluated in
    VIntent { intent_fields = fields }

(* --- Phase 3: Pipeline Evaluation --- *)

(** Extract free variable names from an expression *)
and free_vars (expr : Ast.expr) : string list =
  let rec collect = function
    | Value _ -> []
    | Var s -> [s]
    | ColumnRef _ -> []
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
    | IntentDef pairs -> List.concat_map (fun (_, e) -> collect e) pairs
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
  (* Helper: check if any column name in the table starts with the given prefix *)
  let has_column_prefix arrow_table prefix =
    let pfx = prefix ^ "." in
    let pfx_len = String.length pfx in
    List.exists (fun c -> String.length c > pfx_len &&
                          String.sub c 0 pfx_len = pfx)
      (Arrow_table.column_names arrow_table)
  in
  match target_val with
  | VDict pairs ->
      (match List.assoc_opt field pairs with
      | Some v -> v
      | None ->
        (* Check for partial dot-access on a DataFrame (e.g. df.Petal -> df."Petal.Length").
           Internal keys __partial_dot_df__ and __partial_dot_prefix__ carry the original
           DataFrame and accumulated prefix through chained dot accesses. *)
        (match List.assoc_opt "__partial_dot_df__" pairs with
         | Some (VDataFrame { arrow_table; _ } as df_val) ->
           let prefix = (match List.assoc_opt "__partial_dot_prefix__" pairs with
                         | Some (VString s) -> s | _ -> "") in
           let compound = prefix ^ "." ^ field in
           (match Arrow_column.get_column arrow_table compound with
            | Some col_view -> VVector (Array.of_list (Arrow_column.column_view_to_list col_view))
            | None ->
              if has_column_prefix arrow_table compound
              then VDict [("__partial_dot_df__", df_val);
                          ("__partial_dot_prefix__", VString compound)]
              else make_error KeyError (Printf.sprintf "column '%s' not found in DataFrame" compound))
         | _ ->
           (* Check for partial dot-access on a plain dict with compound keys
              (e.g. row.Petal.Length where dict has key "Petal.Length").
              Internal keys __partial_dot_dict__ and __partial_dot_prefix__ carry the
              original dict pairs and accumulated prefix through chained dot accesses. *)
           (match List.assoc_opt "__partial_dot_dict__" pairs with
            | Some (VDict orig_pairs) ->
              let prefix = (match List.assoc_opt "__partial_dot_prefix__" pairs with
                            | Some (VString s) -> s | _ -> "") in
              let compound = if prefix = "" then field else prefix ^ "." ^ field in
              (match List.assoc_opt compound orig_pairs with
               | Some v -> v
               | None ->
                 let cpfx = compound ^ "." in
                 let cpfx_len = String.length cpfx in
                 if List.exists (fun (k, _) ->
                   String.length k > cpfx_len && String.sub k 0 cpfx_len = cpfx) orig_pairs
                 then VDict [("__partial_dot_dict__", VDict orig_pairs);
                             ("__partial_dot_prefix__", VString compound)]
                 else make_error KeyError (Printf.sprintf "key '%s' not found in dict" compound))
            | _ ->
              (* Check if any keys have this field as a dotted prefix *)
              let pfx = field ^ "." in
              let pfx_len = String.length pfx in
              if List.exists (fun (k, _) ->
                String.length k > pfx_len && String.sub k 0 pfx_len = pfx) pairs
              then VDict [("__partial_dot_dict__", VDict pairs);
                          ("__partial_dot_prefix__", VString field)]
              else make_error KeyError (Printf.sprintf "key '%s' not found in dict" field))))
  | VList named_items ->
      (match List.find_opt (fun (name, _) -> name = Some field) named_items with
      | Some (_, v) -> v
      | None -> make_error KeyError (Printf.sprintf "list has no named element '%s'" field))
  | VDataFrame ({ arrow_table; _ } as df) ->
      (* Use column views for efficient access — avoids redundant copies
         when the column data is already available in the Arrow table. *)
      (match Arrow_column.get_column arrow_table field with
       | Some col_view -> VVector (Array.of_list (Arrow_column.column_view_to_list col_view))
       | None ->
         (* Column not found — check if there are columns with this prefix (e.g. "Petal.Length")
            to support R-style dotted column names via chained dot access (df.Petal.Length) *)
         if has_column_prefix arrow_table field
         then VDict [("__partial_dot_df__", VDataFrame df);
                     ("__partial_dot_prefix__", VString field)]
         else make_error KeyError (Printf.sprintf "column '%s' not found in DataFrame" field))
  | VPipeline { p_nodes; _ } ->
      (match List.assoc_opt field p_nodes with
       | Some v -> v
       | None -> make_error KeyError (Printf.sprintf "node '%s' not found in Pipeline" field))
  | VError _ as e -> e
  | VNA _ -> make_error TypeError "Cannot access field on NA"
  | other -> make_error TypeError (Printf.sprintf "Cannot access field '%s' on %s" field (Utils.type_name other))

and lambda_arity_error params args =
  let sig_str = String.concat ", " params in
  make_error ArityError (Printf.sprintf "Expected %d arguments (%s) but got %d" (List.length params) sig_str (List.length args))

and eval_call env fn_val raw_args =
  (* NSE auto-transformation: if an argument is a complex expression containing
     ColumnRef nodes (not a bare ColumnRef), wrap it in a lambda \(row) <desugared>
     before evaluation. Bare ColumnRef stays as-is (evaluates to VSymbol). *)
  let transform_nse_args args =
    List.map (fun (name, expr) ->
      match expr with
      | ColumnRef _ -> (name, expr)  (* bare $col → keep, evaluates to VSymbol *)
      | _ when uses_nse expr ->
          (* Complex expression with NSE → wrap in lambda *)
          let desugared = desugar_nse_expr expr in
          (name, Lambda { params = ["row"]; variadic = false;
                          body = desugared; env = None })
      | _ -> (name, expr)
    ) args
  in
  let raw_args = transform_nse_args raw_args in
  match fn_val with
  | VBuiltin { b_arity; b_variadic; b_func } ->
      let named_args = List.map (fun (name, e) -> (name, eval_expr env e)) raw_args in
      let arg_count = List.length named_args in
      if not b_variadic && arg_count <> b_arity then
        make_error ArityError (Printf.sprintf "Expected %d arguments but got %d" b_arity arg_count)
      else
        b_func named_args env

  | VLambda { params; variadic = _; body; env = Some closure_env } ->
      let args = List.map (fun (_, e) -> eval_expr env e) raw_args in
      if List.length params <> List.length args then
        lambda_arity_error params args
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
        lambda_arity_error params args
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
       | None ->
         let names = List.map fst (Env.bindings env) in
         let msg = match Ast.suggest_name s names with
           | Some suggestion -> Printf.sprintf "'%s' is not defined. Did you mean '%s'?" s suggestion
           | None -> Printf.sprintf "'%s' is not defined" s
         in
         make_error NameError msg)

  | VError _ -> make_error TypeError "Cannot call Error as a function"
  | VNA _ -> make_error TypeError "Cannot call NA as a function"
  | _ -> make_error TypeError (Printf.sprintf "Cannot call %s as a function" (Utils.type_name fn_val))

and eval_binop env op left right =
  (* Pipe is special: x |> f(y) becomes f(x, y), x |> f becomes f(x) *)
  match op with
  | Formula ->
      (* Formulas are not evaluated - they're data structures *)
      let lhs_vars = extract_formula_vars left in
      let rhs_vars = extract_formula_vars right in
      VFormula {
        response = lhs_vars;
        predictors = rhs_vars;
        raw_lhs = left;
        raw_rhs = right;
      }
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
  | MaybePipe ->
      let lval = eval_expr env left in
      (* Unconditional pipe — always forward, even errors *)
      (match right with
       | Call { fn; args } ->
           let fn_val = eval_expr env fn in
           eval_call env fn_val ((None, Value lval) :: args)
       | _ ->
           let fn_val = eval_expr env right in
           eval_call env fn_val [(None, Value lval)]
      )
  | _ ->
  let lval = eval_expr env left in
  let rval = eval_expr env right in
  (* Error values in arithmetic produce TypeError instead of propagating *)
  (match (lval, rval) with
  | (VError _, _) | (_, VError _) ->
    let op_name = match op with
      | Plus -> "add" | Minus -> "subtract" | Mul -> "multiply" | Div -> "divide"
      | Lt | Gt | LtEq | GtEq -> "compare" | Eq | NEq -> "compare" | _ -> "apply operator to"
    in
    make_error TypeError (Printf.sprintf "Cannot %s %s and %s" op_name (Utils.type_name lval) (Utils.type_name rval))
  (* NA does not propagate implicitly — operations with NA produce explicit errors *)
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
  | (Div, VInt a, VInt b) -> VFloat (float_of_int a /. float_of_int b)
  | (Div, VFloat _, VFloat b) when b = 0.0 -> make_error DivisionByZero "Division by zero"
  | (Div, VFloat a, VFloat b) -> VFloat (a /. b)
  | (Div, VInt a, VFloat b) -> if b = 0.0 then make_error DivisionByZero "Division by zero" else VFloat (float_of_int a /. b)
  | (Div, VFloat a, VInt b) -> if b = 0 then make_error DivisionByZero "Division by zero" else VFloat (a /. float_of_int b)
  (* Comparison - with cross-type int/float promotion *)
  | (Eq, VInt a, VFloat b) -> VBool (float_of_int a = b)
  | (Eq, VFloat a, VInt b) -> VBool (a = float_of_int b)
  | (Eq, a, b) -> VBool (a = b)
  | (NEq, VInt a, VFloat b) -> VBool (float_of_int a <> b)
  | (NEq, VFloat a, VInt b) -> VBool (a <> float_of_int b)
  | (NEq, a, b) -> VBool (a <> b)
  | (Lt, VInt a, VInt b) -> VBool (a < b)
  | (Lt, VFloat a, VFloat b) -> VBool (a < b)
  | (Lt, VInt a, VFloat b) -> VBool (float_of_int a < b)
  | (Lt, VFloat a, VInt b) -> VBool (a < float_of_int b)
  | (Gt, VInt a, VInt b) -> VBool (a > b)
  | (Gt, VFloat a, VFloat b) -> VBool (a > b)
  | (Gt, VInt a, VFloat b) -> VBool (float_of_int a > b)
  | (Gt, VFloat a, VInt b) -> VBool (a > float_of_int b)
  | (LtEq, VInt a, VInt b) -> VBool (a <= b)
  | (LtEq, VFloat a, VFloat b) -> VBool (a <= b)
  | (LtEq, VInt a, VFloat b) -> VBool (float_of_int a <= b)
  | (LtEq, VFloat a, VInt b) -> VBool (a <= float_of_int b)
  | (GtEq, VInt a, VInt b) -> VBool (a >= b)
  | (GtEq, VFloat a, VFloat b) -> VBool (a >= b)
  | (GtEq, VInt a, VFloat b) -> VBool (float_of_int a >= b)
  | (GtEq, VFloat a, VInt b) -> VBool (a >= float_of_int b)
  (* Logical *)
  | (And, a, b) -> VBool (Utils.is_truthy a && Utils.is_truthy b)
  | (Or, a, b) -> VBool (Utils.is_truthy a || Utils.is_truthy b)
  | (op, l, r) ->
    let op_name = match op with
      | Plus -> "add" | Minus -> "subtract" | Mul -> "multiply" | Div -> "divide"
      | Lt | Gt | LtEq | GtEq -> "compare" | _ -> "apply operator to"
    in
    let base_msg = Printf.sprintf "Cannot %s %s and %s" op_name (Utils.type_name l) (Utils.type_name r) in
    let msg = match Ast.type_conversion_hint (Utils.type_name l) (Utils.type_name r) with
      | Some hint -> base_msg ^ ". " ^ hint
      | None -> base_msg
    in
    make_error TypeError msg)

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
      if Env.mem name env then
        let msg = Printf.sprintf "Cannot reassign immutable variable '%s'. Use ':=' to overwrite." name in
        (make_error NameError msg, env)
      else
        let v = eval_expr env expr in
        let new_env = Env.add name v env in
        (match v with
         | VError _ -> (v, new_env)
         | _ -> (VNull, new_env))
  | Reassignment { name; expr } ->
      if not (Env.mem name env) then
        let msg = Printf.sprintf "Cannot overwrite '%s': variable not defined. Use '=' for first assignment." name in
        (make_error NameError msg, env)
      else
        let v = eval_expr env expr in
        Printf.eprintf "Warning: overwriting variable '%s'\n" name;
        let new_env = Env.add name v env in
        (match v with
         | VError _ -> (v, new_env)
         | _ -> (VNull, new_env))

(* --- Built-in Functions --- *)

let make_builtin ?(variadic=false) arity func =
  VBuiltin { b_arity = arity; b_variadic = variadic;
             b_func = (fun named_args env -> func (List.map snd named_args) env) }

let make_builtin_named ?(variadic=false) arity func =
  VBuiltin { b_arity = arity; b_variadic = variadic; b_func = func }

(* --- Phase 2: Arrow-Backed CSV Parser --- *)

(** Split a CSV line into fields, handling quoted fields *)
let parse_csv_line ?(sep=',') (line : string) : string list =
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
      end else if c = sep then begin
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

(** Parse a CSV string into an Arrow-backed DataFrame *)
let parse_csv_string ?(sep=',') ?(skip_header=false) ?(skip_lines=0) ?(clean_colnames=false) (content : string) : value =
  let lines = split_lines content in
  (* Remove trailing empty lines *)
  let lines = List.filter (fun l -> String.trim l <> "") lines in
  (* Skip the first N lines *)
  let rec drop n lst = if n <= 0 then lst else match lst with [] -> [] | _ :: rest -> drop (n - 1) rest in
  let lines = drop skip_lines lines in
  match lines with
  | [] -> VDataFrame { arrow_table = Arrow_table.empty; group_keys = [] }
  | first_line :: rest_lines ->
      let headers, data_lines =
        if skip_header then
          (* No header row: generate column names V1, V2, ... *)
          let ncols = List.length (parse_csv_line ~sep first_line) in
          let headers = List.init ncols (fun i -> Printf.sprintf "V%d" (i + 1)) in
          (headers, lines)
        else
          (parse_csv_line ~sep first_line, rest_lines)
      in
      (* Apply column name cleaning if requested *)
      let headers =
        if clean_colnames then Clean_colnames.clean_names headers
        else headers
      in
      let ncols = List.length headers in
      let data_rows = List.map (parse_csv_line ~sep) data_lines in
      (* Validate column count consistency *)
      let valid_rows = List.filter (fun row -> List.length row = ncols) data_rows in
      let nrows = List.length valid_rows in
      if nrows = 0 && List.length data_rows > 0 then
        make_error ValueError
          (Printf.sprintf "CSV Error: Row column counts do not match header (expected %d columns)" ncols)
      else
        (* Convert rows to array for O(1) access *)
        let rows_arr = Array.of_list valid_rows in
        (* Build column arrays using per-cell type inference for backward compatibility *)
        let value_columns = List.mapi (fun col_idx name ->
          let col_data = Array.init nrows (fun row_idx ->
            let row = rows_arr.(row_idx) in
            parse_csv_value (List.nth row col_idx)
          ) in
          (name, col_data)
        ) headers in
        (* Convert to Arrow table via bridge *)
        let arrow_table = Arrow_bridge.table_from_value_columns value_columns nrows in
        VDataFrame { arrow_table; group_keys = [] }


(* --- Load All Packages --- *)
(* Each package module provides a `register` function that adds its builtins to the environment. *)
(* Modules that need eval_call or rerun_pipeline receive them as labeled parameters. *)

let initial_env () : environment =
  let env = Env.empty in
  (* Core package *)
  let env = T_print.register env in
  let env = T_type.register env in
  let env = Length.register env in
  let env = Head.register env in
  let env = Tail.register env in
  let env = Is_error.register env in
  let env = T_seq.register env in
  let env = T_map.register ~eval_call env in
  let env = Sum.register env in
  (* Base package *)
  let env = T_assert.register env in
  let env = Is_na.register env in
  let env = Na.register env in
  let env = Error_mod.register env in
  let env = Error_utils.register env in
  (* Dataframe package *)
  let env = T_read_csv.register ~parse_csv_string:(fun ~sep ~skip_header ~skip_lines ~clean_colnames content -> parse_csv_string ~sep ~skip_header ~skip_lines ~clean_colnames content) env in
  let env = T_write_csv.register ~write_csv_fn:(fun ~sep table path -> Arrow_io.write_csv ~sep table path) env in
  let env = Colnames.register env in
  let env = Nrow.register env in
  let env = Ncol.register env in
  let env = Glimpse.register env in
  (* clean_colnames as a standalone function on DataFrames *)
  let env = Env.add "clean_colnames"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; group_keys }] ->
          let old_names = Arrow_table.column_names arrow_table in
          let new_names = Clean_colnames.clean_names old_names in
          let columns = List.map2 (fun old_name new_name ->
            match Arrow_table.get_column arrow_table old_name with
            | Some col -> (new_name, col)
            | None -> (new_name, Arrow_table.NullColumn (Arrow_table.num_rows arrow_table))
          ) old_names new_names in
          let nrows = Arrow_table.num_rows arrow_table in
          let new_table = Arrow_table.create columns nrows in
          VDataFrame { arrow_table = new_table; group_keys }
      | [VList items] ->
          let strs = List.map (fun (_, v) ->
            match v with VString s -> s | _ -> Ast.Utils.value_to_string v
          ) items in
          let cleaned = Clean_colnames.clean_names strs in
          VList (List.map (fun s -> (None, VString s)) cleaned)
      | [VNA _] -> make_error TypeError "clean_colnames() expects a DataFrame or List, got NA"
      | [_] -> make_error TypeError "clean_colnames() expects a DataFrame or List of strings"
      | _ -> make_error ArityError "clean_colnames() takes exactly 1 argument"
    ))
    env
  in
  (* Pipeline package *)
  let env = Pipeline_nodes.register env in
  let env = Pipeline_deps.register env in
  let env = Pipeline_node.register env in
  let env = Pipeline_run.register ~rerun_pipeline env in
  (* Colcraft package *)
  let env = T_select.register env in
  let env = T_filter.register ~eval_call ~eval_expr ~uses_nse ~desugar_nse_expr env in
  let env = Mutate.register ~eval_call ~eval_expr ~uses_nse ~desugar_nse_expr env in
  let env = Arrange.register env in
  let env = Group_by.register env in
  let env = Ungroup.register env in
  let env = Summarize.register ~eval_call ~eval_expr ~uses_nse ~desugar_nse_expr env in
  let env = Window_rank.register env in
  let env = Window_offset.register env in
  let env = Window_cumulative.register env in
  (* Math package *)
  let env = T_sqrt.register env in
  let env = T_abs.register env in
  let env = T_log.register env in
  let env = T_exp.register env in
  let env = Pow.register env in
  (* Stats package *)
  let env = Mean.register env in
  let env = Sd.register env in
  let env = Quantile.register env in
  let env = Cor.register env in
  let env = Lm.register env in
  let env = Fit_stats.register env in
  let env = Add_diagnostics.register env in
  let env = Min.register env in
  let env = Max.register env in
  (* Explain package *)
  let env = Intent_fields.register env in
  let env = Intent_get.register env in
  let env = T_explain.register env in
  let env = Explain_json.register ~eval_call env in
  (* Phase 7: Pretty-print and packages *)
  let env = Pretty_print.register env in
  let env = Packages.register env in
  env

let eval_program (program : program) (env : environment) : value * environment =
  let rec go env = function
    | [] -> (VNull, env)
    | [stmt] -> eval_statement env stmt
    | stmt :: rest ->
        let (v, new_env) = eval_statement env stmt in
        (match stmt, v with
         | (Assignment _ | Reassignment _), VError _ when new_env == env -> (v, env)
         | _ -> go new_env rest)
  in
  go env program
