(* src/eval.ml *)
(* Tree-walking evaluator for the T language — Phase 1 Alpha *)

open Ast

(* --- Error Construction Helpers --- *)

(** Create a structured error value *)
let rec desugar_nse_expr (expr : Ast.expr) : Ast.expr =
  match expr with
  | ColumnRef field ->
      (* $field → row.field *)
      DotAccess { target = Var "row"; field }
  | BinOp { op; left; right } ->
      (* Recursively transform both sides *)
      BinOp { op; left = desugar_nse_expr left; right = desugar_nse_expr right }
  | BroadcastOp { op; left; right } ->
      BroadcastOp { op; left = desugar_nse_expr left; right = desugar_nse_expr right }
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
  | DictLit entries ->
      DictLit (List.map (fun (k, v) -> (k, desugar_nse_expr v)) entries)
  | DotAccess { target; field } ->
      DotAccess { target = desugar_nse_expr target; field }
  | Block stmts ->
      (* We need to desugar inside statements too *)
      Block (List.map desugar_nse_stmt stmts)
  | _ -> expr

and desugar_nse_stmt stmt =
  match stmt with
  | Expression e -> Expression (desugar_nse_expr e)
  | Assignment { name; typ; expr } -> Assignment { name; typ; expr = desugar_nse_expr expr }
  | Reassignment { name; expr } -> Reassignment { name; expr = desugar_nse_expr expr }
  | Import _ | ImportPackage _ | ImportFrom _ -> stmt

(** Global flag to control warning output (e.g., for tests) *)
let show_warnings = ref true

(** Check if an expression uses NSE (contains $field references) *)
let rec uses_nse (expr : Ast.expr) : bool =
  match expr with
  | ColumnRef _ -> true
  | BinOp { left; right; _ } -> uses_nse left || uses_nse right
  | BroadcastOp { left; right; _ } -> uses_nse left || uses_nse right
  | UnOp { operand; _ } -> uses_nse operand
  | Call { fn; args } -> uses_nse fn || List.exists (fun (_, e) -> uses_nse e) args
  | IfElse { cond; then_; else_ } ->
      uses_nse cond || uses_nse then_ || uses_nse else_
  | ListLit items -> List.exists (fun (_, e) -> uses_nse e) items
  | DictLit pairs -> List.exists (fun (_, e) -> uses_nse e) pairs
  | DotAccess { target; _ } -> uses_nse target
  | Block stmts -> List.exists uses_nse_stmt stmts
  | _ -> false

and uses_nse_stmt stmt =
  match stmt with
  | Expression e -> uses_nse e
  | Assignment { expr; _ } -> uses_nse expr
  | Reassignment { expr; _ } -> uses_nse expr
  | Import _ | ImportPackage _ | ImportFrom _ -> false

(* --- Scalar and Broadcasting Logic --- *)

(** Evaluate scalar binary operations.
    Strictly handles scalar values (Int, Float, Bool, String).
    Does NOT handle lists, vectors, or broadcasting. *)
let eval_scalar_binop op v1 v2 =
  match (op, v1, v2) with
  (* Propagate errors first *)
  | (_, VError _, _) -> v1
  | (_, _, VError _) -> v2
  (* Then handle NA *)
  | (_, VNA _, _) | (_, _, VNA _) ->
      Error.type_error "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly."
  (* Arithmetic *)
  | (Plus, VInt a, VInt b) -> VInt (a + b)
  | (Plus, VFloat a, VFloat b) -> VFloat (a +. b)
  | (Plus, VInt a, VFloat b) -> VFloat (float_of_int a +. b)
  | (Plus, VFloat a, VInt b) -> VFloat (a +. float_of_int b)
  | (Plus, VString _, VString _) ->
      Error.type_error "String concatenation with '+' is not supported. Use 'join([a, b], sep)' or 'paste(a, b, sep)' instead."

  | (Minus, VInt a, VInt b) -> VInt (a - b)
  | (Minus, VFloat a, VFloat b) -> VFloat (a -. b)
  | (Minus, VInt a, VFloat b) -> VFloat (float_of_int a -. b)
  | (Minus, VFloat a, VInt b) -> VFloat (a -. float_of_int b)

  | (Mul, VInt a, VInt b) -> VInt (a * b)
  | (Mul, VFloat a, VFloat b) -> VFloat (a *. b)
  | (Mul, VInt a, VFloat b) -> VFloat (float_of_int a *. b)
  | (Mul, VFloat a, VInt b) -> VFloat (a *. float_of_int b)

  | (Div, VInt _, VInt 0) -> Error.division_by_zero ()
  | (Div, VInt a, VInt b) -> VFloat (float_of_int a /. float_of_int b)
  | (Div, VFloat _, VFloat b) when b = 0.0 -> Error.division_by_zero ()
  | (Div, VFloat a, VFloat b) -> VFloat (a /. b)
  | (Div, VInt a, VFloat b) -> if b = 0.0 then Error.division_by_zero () else VFloat (float_of_int a /. b)
  | (Div, VFloat a, VInt b) -> if b = 0 then Error.division_by_zero () else VFloat (a /. float_of_int b)

  | (Mod, VInt a, VInt b) -> if b = 0 then Error.division_by_zero () else VInt (a mod b)
  | (Mod, VFloat a, VFloat b) -> if b = 0.0 then Error.division_by_zero () else VFloat (mod_float a b)
  | (Mod, VInt a, VFloat b) -> if b = 0.0 then Error.division_by_zero () else VFloat (mod_float (float_of_int a) b)
  | (Mod, VFloat a, VInt b) -> if b = 0 then Error.division_by_zero () else VFloat (mod_float a (float_of_int b))

  (* Comparison *)
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

  (* Boolean / Bitwise *)
  | (BitAnd, VInt a, VInt b) -> VInt (a land b)
  | (BitOr, VInt a, VInt b) -> VInt (a lor b)
  | (BitAnd, VBool a, VBool b) -> VBool (a && b)
  | (BitOr, VBool a, VBool b) -> VBool (a || b)

  (* Error handling *)
  | (And, _, _) | (Or, _, _) ->
      Error.internal_error "Short-circuit operators should not reach eval_scalar_binop"




  (* Improved Error Messages for Bitwise Ops *)
  | (BitOr, _, _) | (BitAnd, _, _) as op_tuple ->
      let (op, l, r) = op_tuple in
      (* Check if we have a vector/list involved to give a helpful hint *)
      let is_sequence v = match v with VList _ | VVector _ -> true | _ -> false in
      
      if is_sequence l || is_sequence r then
        let op_str = if op = BitOr then "|" else "&" in
        let elem_op_str = if op = BitOr then ".|" else ".&" in
        let hint = Printf.sprintf "Use `%s` for element-wise boolean operations." elem_op_str in
        Error.op_type_error_with_hint op_str "Bool" "Bool" hint
      else
        (* Fallback for other invalid types (e.g. 1 | "a") *)
        let op_name = if op = BitOr then "|" else "&" in
        Error.op_type_error op_name (Utils.type_name l) (Utils.type_name r)

  | (op, l, r) ->
      let op_name = match op with
        | Plus -> "+" | Minus -> "-" | Mul -> "*" | Div -> "/"
        | Lt -> "<" | Gt -> ">" | LtEq -> "<=" | GtEq -> ">=" | Eq -> "==" | NEq -> "!="
        | BitAnd -> "&" | BitOr -> "|"
        | _ -> "operator"
      in
      match Ast.type_conversion_hint (Utils.type_name l) (Utils.type_name r) with
      | Some hint -> Error.op_type_error_with_hint op_name (Utils.type_name l) (Utils.type_name r) hint
      | None -> Error.op_type_error op_name (Utils.type_name l) (Utils.type_name r)

(** Broadcasting engine.
    Applies eval_scalar_binop across lists/vectors. *)
let rec broadcast2 op v1 v2 =
  match v1, v2 with
  (* Propagate errors *)
  | VError _, _ -> v1
  | _, VError _ -> v2

  (* List-List *)
  | VList l1, VList l2 ->
      let len1 = List.length l1 in
      let len2 = List.length l2 in
      if len1 <> len2 then
        Error.broadcast_length_error len1 len2
      else
        let res = List.map2 (fun (n1, x) (n2, y) ->
          let name = match n1, n2 with Some s, _ -> Some s | _, Some s -> Some s | _ -> None in
          (name, broadcast2 op x y)
        ) l1 l2 in
        VList res

  (* Vector-Vector *)
  | VVector arr1, VVector arr2 ->
      let len1 = Array.length arr1 in
      let len2 = Array.length arr2 in
      if len1 <> len2 then
        Error.broadcast_length_error len1 len2
      else
        VVector (Array.map2 (fun x y -> broadcast2 op x y) arr1 arr2)

  (* Vector-Scalar *)
  | VVector arr, scalar ->
      VVector (Array.map (fun x -> broadcast2 op x scalar) arr)

  (* Scalar-Vector *)
  | scalar, VVector arr ->
      VVector (Array.map (fun x -> broadcast2 op scalar x) arr)

  (* List-Scalar *)
  | VList l, scalar ->
      VList (List.map (fun (n, x) -> (n, broadcast2 op x scalar)) l)

  (* Scalar-List *)
  | scalar, VList l ->
      VList (List.map (fun (n, x) -> (n, broadcast2 op scalar x)) l)

  (* NDArray-NDArray elementwise *)
  | VNDArray a1, VNDArray a2 ->
      if a1.shape <> a2.shape then
        Error.make_error ValueError "NDArray shapes must match for element-wise operations."
      else
        let first_error = ref None in
        let out = Array.init (Array.length a1.data) (fun i ->
          match eval_scalar_binop op (VFloat a1.data.(i)) (VFloat a2.data.(i)) with
          | VInt n -> float_of_int n
          | VFloat f -> f
          | VBool b -> if b then 1.0 else 0.0
          | VError _ as err ->
              first_error := Some err;
              nan
          | _ -> nan
        ) in
        begin match !first_error with
        | Some err -> err
        | None ->
            if Array.exists Float.is_nan out then
              Error.type_error "NDArray element-wise operation produced non-numeric results."
            else VNDArray { shape = Array.copy a1.shape; data = out }
        end

  (* NDArray-Scalar *)
  | VNDArray arr, scalar ->
      (match scalar with
       | VError _ -> scalar
       | _ ->
           let first_error = ref None in
           let out = Array.init (Array.length arr.data) (fun i ->
             match eval_scalar_binop op (VFloat arr.data.(i)) scalar with
             | VInt n -> float_of_int n
             | VFloat f -> f
             | VBool b -> if b then 1.0 else 0.0
             | VError _ as err ->
                 first_error := Some err;
                 nan
             | _ -> nan
           ) in
           match !first_error with
           | Some err -> err
           | None ->
               if Array.exists Float.is_nan out then
                 Error.type_error "NDArray operation requires numeric scalar values."
               else VNDArray { shape = Array.copy arr.shape; data = out })

  (* Scalar-NDArray *)
  | scalar, VNDArray arr ->
      (match scalar with
       | VError _ -> scalar
       | _ ->
           let first_error = ref None in
           let out = Array.init (Array.length arr.data) (fun i ->
             match eval_scalar_binop op scalar (VFloat arr.data.(i)) with
             | VInt n -> float_of_int n
             | VFloat f -> f
             | VBool b -> if b then 1.0 else 0.0
             | VError _ as err ->
                 first_error := Some err;
                 nan
             | _ -> nan
           ) in
           match !first_error with
           | Some err -> err
           | None ->
               if Array.exists Float.is_nan out then
                 Error.type_error "NDArray operation requires numeric scalar values."
               else VNDArray { shape = Array.copy arr.shape; data = out })

  (* Scalar-Scalar *)
  | s1, s2 ->
      eval_scalar_binop op s1 s2

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

(* Module-level mutable ref to track accumulated imports for pipeline propagation *)
let current_imports : Ast.stmt list ref = ref []

let rec eval_expr (env_ref : environment ref) (expr : Ast.expr) : value =
  match expr with
  | Value v -> v
  | Var s ->
      (match Env.find_opt s !env_ref with
      | Some v -> v
      | None -> VSymbol s) (* Return bare words as Symbols for future NSE *)
  
  | ColumnRef field ->
      (* Column references ($name) evaluate to a special symbol value
         that data verbs can recognize and process. The symbol is prefixed
         with "$" to distinguish it from regular symbols. *)
      VSymbol ("$" ^ field)

  | BinOp { op; left; right } -> eval_binop env_ref op left right
  | BroadcastOp { op; left; right } ->
      let v1 = eval_expr env_ref left in
      let v2 = eval_expr env_ref right in
      broadcast2 op v1 v2
  | UnOp { op; operand } -> eval_unop env_ref op operand

  | IfElse { cond; then_; else_ } ->
      let cond_val = eval_expr env_ref cond in
      (match cond_val with
       | VError _ as e -> e
       | VNA _ -> make_error TypeError "Cannot use NA as a condition"
       | VBool true -> eval_expr env_ref then_
       | VBool false -> eval_expr env_ref else_
       | _ -> make_error TypeError ("If condition must be Bool, got " ^ Utils.type_name cond_val))

  | Call { fn; args } ->
      let fn_val = eval_expr env_ref fn in
      eval_call env_ref fn_val args

  | Lambda l -> VLambda { l with env = Some !env_ref } (* Capture the current environment *)

  (* Structural expressions *)
  | ListLit items -> eval_list_lit env_ref items
  | DictLit pairs -> VDict (List.map (fun (k, e) -> (k, eval_expr env_ref e)) pairs)
  | DotAccess { target; field } -> eval_dot_access env_ref target field
  | ListComp _ -> Error.internal_error "List comprehensions are not yet implemented"
  | Block stmts -> eval_block env_ref stmts
  | PipelineDef nodes -> eval_pipeline env_ref nodes
  | IntentDef pairs -> eval_intent env_ref pairs

and eval_block env_ref stmts =
  let rec loop () = function
    | [] -> VNull
    | [stmt] -> 
        let (v, new_env) = eval_statement !env_ref stmt in
        env_ref := new_env;
        v
    | stmt :: rest ->
        let (_, new_env) = eval_statement !env_ref stmt in
        env_ref := new_env;
        loop () rest
  in
  loop () stmts

(* --- Phase 6: Intent Block Evaluation --- *)

(** Evaluate an intent block definition *)
and eval_intent env_ref pairs =
  let evaluated = List.map (fun (k, e) ->
    let v = eval_expr env_ref e in
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
    | BroadcastOp { left; right; _ } -> collect left @ collect right
    | DotAccess { target; _ } -> collect target
    | Block stmts -> List.concat_map collect_stmt stmts
    | PipelineDef _ -> []
    | IntentDef pairs -> List.concat_map (fun (_, e) -> collect e) pairs

  and collect_stmt = function
    | Expression e -> collect e
    | Assignment { expr; _ } -> collect expr
    | Reassignment { expr; _ } -> collect expr
    | Import _ | ImportPackage _ | ImportFrom _ -> []
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
and eval_pipeline env_ref (nodes : Ast.pipeline_node list) : value =
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
    Error.value_error (Printf.sprintf "Pipeline has a dependency cycle involving node `%s`." cycle_node)
  | Ok exec_order ->
    (* Execute nodes in topological order *)
    let node_expr_map = List.map (fun (n : Ast.pipeline_node) -> (n.node_name, n.node_expr)) nodes in
    let (results, _) = List.fold_left (fun (results, current_env_ref) name ->
      let expr = List.assoc name node_expr_map in
      let node_deps = match List.assoc_opt name deps with Some d -> d | None -> [] in
      let upstream_err_opt = List.find_opt (fun d -> 
         match Env.find_opt d !current_env_ref with
         | Some (VError _) -> true
         | _ -> false) node_deps in
      let v = match upstream_err_opt with
        | Some failed_dep -> 
            (match Env.find_opt failed_dep !current_env_ref with
             | Some (VError err) -> 
                 let msg = if String.starts_with ~prefix:"Upstream error: " err.message then
                     err.message
                 else
                     "Upstream error: " ^ err.message
                 in
                 Ast.VError { err with message = msg }
             | _ -> eval_expr current_env_ref expr)
        | None -> eval_expr current_env_ref expr
      in
      current_env_ref := Env.add name v !current_env_ref;
      ((name, v) :: results, current_env_ref)
    ) ([], ref !env_ref) exec_order in
    let p_nodes = List.rev results in
    VPipeline {
      p_nodes;
      p_exprs = node_expr_map;
      p_deps = deps;
      p_imports = !current_imports;
    }

(** Re-run a pipeline, skipping nodes whose dependencies haven't changed *)
and rerun_pipeline env_ref (prev : Ast.pipeline_result) : value =
  let node_names = List.map fst prev.p_exprs in
  match topo_sort
    (List.map (fun (name, expr) -> { Ast.node_name = name; node_expr = expr }) prev.p_exprs)
    prev.p_deps with
  | Error cycle_node ->
    Error.value_error (Printf.sprintf "Pipeline has a dependency cycle involving node `%s`." cycle_node)
  | Ok exec_order ->
    let (results, _, _changed_set) = List.fold_left (fun (results, current_env_ref, changed) name ->
      let expr = List.assoc name prev.p_exprs in
      let node_deps = match List.assoc_opt name prev.p_deps with Some d -> d | None -> [] in
      (* A node needs re-evaluation if any of its dependencies changed *)
      let deps_changed = List.exists (fun d -> List.mem d changed) node_deps in
      (* Also check if any dep refers to something outside the pipeline that may have changed *)
      let fv = free_vars expr in
      let external_deps = List.filter (fun v -> not (List.mem v node_names)) fv in
      let external_changed = List.exists (fun v ->
        let old_val = Env.find_opt v !env_ref in
        let prev_val = match List.assoc_opt v prev.p_nodes with Some x -> Some x | None -> None in
        old_val <> prev_val
      ) external_deps in
      if deps_changed || external_changed then begin
        let upstream_err_opt = List.find_opt (fun d -> 
           match Env.find_opt d !current_env_ref with
           | Some (VError _) -> true
           | _ -> false) node_deps in
        let v = match upstream_err_opt with
          | Some failed_dep -> 
              (match Env.find_opt failed_dep !current_env_ref with
               | Some (VError err) -> 
                   let msg = if String.starts_with ~prefix:"Upstream error: " err.message then
                       err.message
                   else
                       "Upstream error: " ^ err.message
                   in
                   Ast.VError { err with message = msg }
               | _ -> eval_expr current_env_ref expr)
          | None -> eval_expr current_env_ref expr
        in
        current_env_ref := Env.add name v !current_env_ref;
        ((name, v) :: results, current_env_ref, name :: changed)
      end else begin
        (* Reuse cached value *)
        let cached = List.assoc name prev.p_nodes in
        current_env_ref := Env.add name cached !current_env_ref;
        ((name, cached) :: results, current_env_ref, changed)
      end
    ) ([], ref !env_ref, []) exec_order in
    let p_nodes = List.rev results in
    VPipeline {
      p_nodes;
      p_exprs = prev.p_exprs;
      p_deps = prev.p_deps;
      p_imports = prev.p_imports;
    }

and eval_list_lit env_ref items =
    let evaluated_items = List.map (fun (name, e) ->
        match eval_expr env_ref e with
        | VError _ as err -> (name, err)
        | v -> (name, v)
    ) items in
    match List.find_opt (fun (_, v) -> match v with VError _ -> true | _ -> false) evaluated_items with
    | Some (_, err_val) -> err_val
    | None -> VList evaluated_items


and eval_dot_access env_ref target_expr field =
  let target_val = eval_expr env_ref target_expr in
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
              else Error.index_error (0) (0) (* Placeholder as original did not have index info, using KeyError context *)
                  |> fun _ -> Error.make_error KeyError (Printf.sprintf "Column `%s` not found in DataFrame." compound))
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
                 else Error.make_error KeyError (Printf.sprintf "Key `%s` not found in Dict." compound))
            | _ ->
              (* Check if any keys have this field as a dotted prefix *)
              let pfx = field ^ "." in
              let pfx_len = String.length pfx in
              if List.exists (fun (k, _) ->
                String.length k > pfx_len && String.sub k 0 pfx_len = pfx) pairs
              then VDict [("__partial_dot_dict__", VDict pairs);
                          ("__partial_dot_prefix__", VString field)]
              else Error.make_error KeyError (Printf.sprintf "Key `%s` not found in Dict." field))))
  | VList named_items ->
      (match List.find_opt (fun (name, _) -> name = Some field) named_items with
      | Some (_, v) -> v
      | None -> Error.make_error KeyError (Printf.sprintf "List has no named element `%s`." field))
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
         else Error.make_error KeyError (Printf.sprintf "Column `%s` not found in DataFrame." field))
  | VPipeline { p_nodes; _ } ->
      (match List.assoc_opt field p_nodes with
       | Some v -> v
       | None -> Error.make_error KeyError (Printf.sprintf "Node `%s` not found in Pipeline." field))
  | VError _ as e -> e
  | VNA _ -> Error.type_error "Cannot access field on NA."
  | other -> Error.type_error (Printf.sprintf "Cannot access field `%s` on %s." field (Utils.type_name other))

and lambda_arity_error params args =
  Error.arity_error ~expected:(List.length params) ~received:(List.length args)

and eval_call env_ref fn_val raw_args =
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
          (name, Lambda { params = ["row"]; param_types = [None]; return_type = None; generic_params = []; variadic = false;
                          body = desugared; env = None })
      | _ -> (name, expr)
    ) args
  in
  let raw_args = transform_nse_args raw_args in
  match fn_val with
  | VBuiltin { b_arity; b_variadic; b_func; _ } ->
      let named_args = List.map (fun (name, e) -> (name, eval_expr env_ref e)) raw_args in
      let arg_count = List.length named_args in
      if not b_variadic && arg_count <> b_arity then
        Error.arity_error ~expected:b_arity ~received:arg_count
      else
        b_func named_args env_ref

  | VLambda { params; param_types; return_type; variadic = _; body; env = Some closure_env; _ } ->
      let args = List.map (fun (_, e) -> eval_expr env_ref e) raw_args in
      if List.length params <> List.length args then
        lambda_arity_error params args
      else
        (* Runtime Type Check: Arguments *)
        let type_errors = List.filter_map (fun (v, t_opt) ->
          match t_opt with
          | Some t when not (Ast.is_compatible v t) ->
              let expected = Ast.Utils.typ_to_string t in
              let got = Ast.Utils.type_name v in
              Some (Printf.sprintf "Expected %s, got %s" expected got)
          | _ -> None
        ) (List.combine args param_types) in

        if type_errors <> [] then
          Error.type_error (String.concat "; " type_errors)
        else
          let call_env =
            List.fold_left2
              (fun current_env name value -> Env.add name value current_env)
              closure_env params args
          in
          let call_env_ref = ref call_env in
          let result = eval_expr call_env_ref body in
          (* Runtime Type Check: Return Value *)
          (match return_type with
           | Some t when not (Error.is_error_value result) && not (Ast.is_compatible result t) ->
               let expected = Ast.Utils.typ_to_string t in
               let got = Ast.Utils.type_name result in
               Error.type_error (Printf.sprintf "Function returned %s, but expected %s" got expected)
           | _ -> result)

  | VLambda { params; param_types; return_type; variadic = _; body; env = None; _ } ->
      (* Lambda without closure — use current env *)
      let args = List.map (fun (_, e) -> eval_expr env_ref e) raw_args in
      if List.length params <> List.length args then
        lambda_arity_error params args
      else
        (* Runtime Type Check: Arguments *)
        let type_errors = List.filter_map (fun (v, t_opt) ->
          match t_opt with
          | Some t when not (Ast.is_compatible v t) ->
              let expected = Ast.Utils.typ_to_string t in
              let got = Ast.Utils.type_name v in
              Some (Printf.sprintf "Expected %s, got %s" expected got)
          | _ -> None
        ) (List.combine args param_types) in

        if type_errors <> [] then
          Error.type_error (String.concat "; " type_errors)
        else
          let call_env =
            List.fold_left2
              (fun current_env name value -> Env.add name value current_env)
              !env_ref params args
          in
          let call_env_ref = ref call_env in
          let result = eval_expr call_env_ref body in
          (* Runtime Type Check: Return Value *)
          (match return_type with
           | Some t when not (Error.is_error_value result) && not (Ast.is_compatible result t) ->
               let expected = Ast.Utils.typ_to_string t in
               let got = Ast.Utils.type_name result in
               Error.type_error (Printf.sprintf "Function returned %s, but expected %s" got expected)
           | _ -> result)

  | VSymbol s ->
      (* Try to look up the symbol in the env — might be a function name *)
      (match Env.find_opt s !env_ref with
       | Some fn -> eval_call env_ref fn raw_args
       | None ->
         let names = List.map fst (Env.bindings !env_ref) in
         match Ast.suggest_name s names with
           | Some suggestion -> Error.name_error_with_suggestion s suggestion
           | None -> Error.name_error s)

  | VError _ -> Error.type_error "Cannot call Error as a function."
  | VNA _ -> Error.type_error "Cannot call NA as a function."
  | _ -> Error.not_callable_error (Utils.type_name fn_val)

and eval_binop env_ref op left right =
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
      let lval = eval_expr env_ref left in
      (match lval with
       | VError _ as e -> e
       | _ ->
         match right with
         | Call { fn; args } ->
             (* Insert pipe value as first argument *)
             let fn_val = eval_expr env_ref fn in
             eval_call env_ref fn_val ((None, Value lval) :: args)
         | _ ->
             (* RHS is a bare function name or expression *)
             let fn_val = eval_expr env_ref right in
             eval_call env_ref fn_val [(None, Value lval)]
      )
  | MaybePipe ->
      let lval = eval_expr env_ref left in
      (* Unconditional pipe — always forward, even errors *)
      (match right with
       | Call { fn; args } ->
           let fn_val = eval_expr env_ref fn in
           eval_call env_ref fn_val ((None, Value lval) :: args)
       | _ ->
           let fn_val = eval_expr env_ref right in
           eval_call env_ref fn_val [(None, Value lval)]
      )

  (* Logical (Short-circuiting) *)
  | And ->
      let lval = eval_expr env_ref left in
      (match lval with
       | VBool false -> VBool false
       | VBool true ->
           let rval = eval_expr env_ref right in
           (match rval with
            | VBool b -> VBool b
            | _ -> make_error TypeError ("Right operand of && must be Bool, got " ^ Utils.type_name rval))
       | _ -> make_error TypeError ("Left operand of && must be Bool, got " ^ Utils.type_name lval))
  | Or ->
      let lval = eval_expr env_ref left in
      (match lval with
       | VBool true -> VBool true
       | VBool false ->
           let rval = eval_expr env_ref right in
           (match rval with
            | VBool b -> VBool b
            | _ -> make_error TypeError ("Right operand of || must be Bool, got " ^ Utils.type_name rval))
       | _ -> make_error TypeError ("Left operand of || must be Bool, got " ^ Utils.type_name lval))
  (* Membership Operator *)
  | In ->
      let lval = eval_expr env_ref left in
      let rval = eval_expr env_ref right in
      (match (lval, rval) with
      | (VError _, _) -> lval
      | (_, VError _) -> rval
      | _ ->
      (* Helper: check if item is in haystack (handling errors/NA) *)
      let rec find_in item lst =
        match lst with
        | [] -> VBool false
        | h :: t ->
            let res = eval_scalar_binop Eq item h in
            match res with
            | VBool true -> VBool true
            | VBool false -> find_in item t
            | VError _ as err -> err
            | _ -> find_in item t
      in
      (match rval with
       | VList haystack ->
           let haystack_vals = List.map snd haystack in
           (match lval with
            | VList needles ->
                let res = List.map (fun (n, needle) ->
                  (n, find_in needle haystack_vals)
                ) needles in
                VList res
            | needle ->
                find_in needle haystack_vals)
       | _ -> make_error TypeError ("Right operand of 'in' must be a List, got " ^ Utils.type_name rval)))

  (* All other binary operators *)
  | _ ->
  let lval = eval_expr env_ref left in
  let rval = eval_expr env_ref right in
  match (op, lval, rval) with
  | (Plus | Minus | Mul | Div | Mod | Lt | Gt | LtEq | GtEq | Eq | NEq), _, _ ->
      (match lval, rval with
       | VNDArray _, _ | _, VNDArray _
       | Ast.VVector _, _ | _, Ast.VVector _
       | Ast.VList _, _ | _, Ast.VList _ -> 
          let op_str = match op with
            | Plus -> "+" | Minus -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%"
            | Lt -> "<" | Gt -> ">" | LtEq -> "<=" | GtEq -> ">=" | Eq -> "==" | NEq -> "!="
            | _ -> "??"
          in
          let dot_op = "." ^ op_str in
          let msg = Printf.sprintf "Operator '%s' is defined for scalars only.\nUse '%s' for element-wise (broadcast) operations." op_str dot_op in
          Error.type_error msg
       | _ -> eval_scalar_binop op lval rval)
  | _ -> eval_scalar_binop op lval rval

and eval_unop env_ref op operand =
  let v = eval_expr env_ref operand in
  match v with VError _ as e -> e | _ ->
  match v with
  | VNA _ -> make_error TypeError "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly."
  | _ ->
  match (op, v) with
  | (Not, VBool b) -> VBool (not b)
  | (Not, other) -> make_error TypeError (Printf.sprintf "Operand of 'not' must be Bool, got %s" (Utils.type_name other))
  | (Neg, VInt i) -> VInt (-i)
  | (Neg, VFloat f) -> VFloat (-.f)
  | (Neg, other) -> make_error TypeError (Printf.sprintf "Cannot negate %s" (Utils.type_name other))

(* --- Statement & Program Evaluation --- *)

and eval_statement (env : environment) (stmt : stmt) : value * environment =
  match stmt with
  | Expression e ->
      let env_ref = ref env in
      let v = eval_expr env_ref e in
      (v, !env_ref)
  | Assignment { name; expr; _ } ->
      if Env.mem name env then
        let msg = Printf.sprintf "Cannot reassign immutable variable '%s'. Use ':=' to overwrite." name in
        (make_error NameError msg, env)
      else
        let env_ref = ref env in
        let v = eval_expr env_ref expr in
        let new_env = Env.add name v !env_ref in
        (match v with
         | VError _ -> (v, new_env)
         | _ -> (VNull, new_env))
  | Reassignment { name; expr } ->
      if not (Env.mem name env) then
        let msg = Printf.sprintf "Cannot overwrite '%s': variable not defined. Use '=' for first assignment." name in
        (make_error NameError msg, env)
      else
        let env_ref = ref env in
        let v = eval_expr env_ref expr in
        if !show_warnings then
          Printf.eprintf "Warning: overwriting variable '%s'\n" name;
        let new_env = Env.add name v !env_ref in
        (match v with
         | VError _ -> (v, new_env)
         | _ -> (VNull, new_env))
  | Import filename ->
      (try
        let ch = open_in filename in
        let content = really_input_string ch (in_channel_length ch) in
        close_in ch;
        let lexbuf = Lexing.from_string content in
        (try
          let program = Parser.program Lexer.token lexbuf in
          let (_v, new_env) = eval_program program env in
          current_imports := !current_imports @ [Import filename];
          (VNull, new_env)
        with
        | Lexer.SyntaxError msg ->
            (make_error GenericError (Printf.sprintf "Import syntax error in '%s': %s" filename msg), env)
        | Parser.Error ->
            let pos = Lexing.lexeme_start_p lexbuf in
            let msg = Printf.sprintf "Import parse error in '%s' at line %d, column %d"
              filename pos.Lexing.pos_lnum (pos.Lexing.pos_cnum - pos.Lexing.pos_bol) in
            (make_error GenericError msg, env))
      with
      | Sys_error msg ->
          (make_error FileError (Printf.sprintf "Import failed: %s" msg), env))
  | ImportPackage pkg_name ->
      (match Package_loader.load_package ~do_eval_program:eval_program pkg_name env with
       | Ok new_env ->
           current_imports := !current_imports @ [ImportPackage pkg_name];
           (VNull, new_env)
       | Error msg -> (make_error FileError msg, env))
  | ImportFrom { package; names } ->
      (match Package_loader.load_package_selective ~do_eval_program:eval_program package names env with
       | Ok new_env ->
           current_imports := !current_imports @ [ImportFrom { package; names }];
           (VNull, new_env)
       | Error msg -> (make_error FileError msg, env))

and eval_program (program : program) (env : environment) : value * environment =
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

(* --- Built-in Functions --- *)

let make_builtin ?name ?(variadic=false) arity func =
  VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
             b_func = (fun named_args env_ref -> func (List.map snd named_args) !env_ref) }

let make_builtin_named ?name ?(variadic=false) arity func =
  VBuiltin { b_name = name; b_arity = arity; b_variadic = variadic;
             b_func = (fun named_args env_ref -> func named_args !env_ref) }

let eval_call_immutable env fn_val raw_args =
  eval_call (ref env) fn_val raw_args

let eval_expr_immutable env expr =
  eval_expr (ref env) expr
