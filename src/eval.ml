(* src/eval.ml *)
(* Tree-walking evaluator for the T language — Phase 1 Alpha *)

open Ast

(* --- Error Construction Helpers --- *)

(** Create a structured error value *)
let rec desugar_nse_expr (expr : Ast.expr) : Ast.expr =
  let loc = expr.loc in
  match expr.node with
  | ColumnRef field ->
      (* $field → row.field *)
      Ast.mk_expr ?loc (DotAccess { target = Ast.mk_expr ?loc (Var "row"); field })
  | BinOp { op; left; right } ->
      (* Recursively transform both sides *)
      Ast.mk_expr ?loc (BinOp { op; left = desugar_nse_expr left; right = desugar_nse_expr right })
  | BroadcastOp { op; left; right } ->
      Ast.mk_expr ?loc (BroadcastOp { op; left = desugar_nse_expr left; right = desugar_nse_expr right })
  | UnOp { op; operand } ->
      Ast.mk_expr ?loc (UnOp { op; operand = desugar_nse_expr operand })
  | Call { fn; args } ->
      Ast.mk_expr ?loc (Call { fn = desugar_nse_expr fn; 
             args = List.map (fun (n, e) -> (n, desugar_nse_expr e)) args })
  | IfElse { cond; then_; else_ } ->
      Ast.mk_expr ?loc (IfElse { 
        cond = desugar_nse_expr cond;
        then_ = desugar_nse_expr then_;
        else_ = desugar_nse_expr else_ 
      })
  | Match { scrutinee; cases } ->
      Ast.mk_expr ?loc (Match {
        scrutinee = desugar_nse_expr scrutinee;
        cases = List.map (fun (pattern, body) -> (pattern, desugar_nse_expr body)) cases;
      })
  | ListLit items ->
      Ast.mk_expr ?loc (ListLit (List.map (fun (n, e) -> (n, desugar_nse_expr e)) items))
  | DictLit entries ->
      Ast.mk_expr ?loc (DictLit (List.map (fun (k, v) -> (k, desugar_nse_expr v)) entries))
  | DotAccess { target; field } ->
      Ast.mk_expr ?loc (DotAccess { target = desugar_nse_expr target; field })
  | Block stmts ->
      (* We need to desugar inside statements too *)
      Ast.mk_expr ?loc (Block (List.map desugar_nse_stmt stmts))
  | RawCode _ -> expr  (* Foreign code, opaque *)
  | Unquote e -> Ast.mk_expr ?loc (Unquote (desugar_nse_expr e))
  | UnquoteSplice e -> Ast.mk_expr ?loc (UnquoteSplice (desugar_nse_expr e))
  | _ -> expr

and desugar_nse_stmt stmt =
  let loc = stmt.loc in
  match stmt.node with
  | Expression e -> Ast.mk_stmt ?loc (Expression (desugar_nse_expr e))
  | Assignment { name; typ; expr } -> Ast.mk_stmt ?loc (Assignment { name; typ; expr = desugar_nse_expr expr })
  | Reassignment { name; expr } -> Ast.mk_stmt ?loc (Reassignment { name; expr = desugar_nse_expr expr })
  | Import _ | ImportPackage _ | ImportFrom _ | ImportFileFrom _ -> stmt

(** Global flag to control warning output (e.g., for tests) *)
let show_warnings = ref true

let source_location ?file pos : Ast.source_location =
  {
    file;
    line = pos.Lexing.pos_lnum;
    column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1);
  }

let attach_location location value =
  match value, location with
  | VError err, Some loc when err.location = None -> VError { err with location = Some loc }
  | _ -> value

let attach_expr_location (expr : Ast.expr) value =
  attach_location expr.loc value

let attach_stmt_location (stmt : Ast.stmt) value =
  attach_location stmt.loc value

let pipeline_error_message ~node_name ~detail =
  let prefix = Printf.sprintf "Pipeline node `%s` failed" node_name in
  if String.starts_with ~prefix detail then detail
  else prefix ^ ": " ^ detail

let annotate_pipeline_error ?runtime node_name = function
  | VError err ->
      let context = match runtime with
        | Some r -> if List.mem_assoc "runtime" err.context then err.context else ("runtime", VString r) :: err.context
        | None -> err.context
      in
      VError { err with message = pipeline_error_message ~node_name ~detail:err.message; context }
  | value -> value

(** Check if an expression uses NSE (contains $field references) *)
let rec uses_nse (expr : Ast.expr) : bool =
  match expr.node with
  | ColumnRef _ -> true
  | BinOp { left; right; _ } -> uses_nse left || uses_nse right
  | BroadcastOp { left; right; _ } -> uses_nse left || uses_nse right
  | UnOp { operand; _ } -> uses_nse operand
  | Call { fn; args } -> uses_nse fn || List.exists (fun (_, e) -> uses_nse e) args
  | IfElse { cond; then_; else_ } ->
      uses_nse cond || uses_nse then_ || uses_nse else_
  | Match { scrutinee; cases } ->
      uses_nse scrutinee || List.exists (fun (_, body) -> uses_nse body) cases
  | ListLit items -> List.exists (fun (_, e) -> uses_nse e) items
  | DictLit pairs -> List.exists (fun (_, e) -> uses_nse e) pairs
  | DotAccess { target; _ } -> uses_nse target
  | RawCode _ -> false
  | Block stmts -> List.exists uses_nse_stmt stmts
  | Unquote e -> uses_nse e
  | UnquoteSplice e -> uses_nse e
  | _ -> false

and uses_nse_stmt stmt =
  match stmt.node with
  | Expression e -> uses_nse e
  | Assignment { expr; _ } -> uses_nse expr
  | Reassignment { expr; _ } -> uses_nse expr
  | Import _ | ImportPackage _ | ImportFrom _ | ImportFileFrom _ -> false

let is_standard_package = function
  | "core"
  | "strcraft"
  | "base"
  | "chrono"
  | "math"
  | "stats"
  | "dataframe"
  | "colcraft"
  | "pipeline"
  | "explain" -> true
  | _ -> false

(* --- Scalar and Broadcasting Logic --- *)

(** Evaluate scalar binary operations.
    Strictly handles scalar values (Int, Float, Bool, String).
    Does NOT handle lists, vectors, or broadcasting. *)
let eval_scalar_binop op v1 v2 =
  match (op, v1, v2) with
  (* Propagate errors first *)
  | (_, VError _, _) -> v1
  | (_, _, VError _) -> v2
  | ((Plus | Minus), (VDate _ | VDatetime _), VNA _) -> (VNA NAGeneric)
  | ((Plus | Minus), VNA _, (VDate _ | VDatetime _ | VPeriod _)) -> (VNA NAGeneric)
  | ((Plus | Minus), (VDate _ | VDatetime _), VPeriod p) ->
      if op = Plus then Chrono.add_period_to_value v1 p
      else Chrono.add_period_to_value v1 (Chrono.negate_period p)
  | (Plus, VPeriod p1, VPeriod p2) ->
      VPeriod {
        p_years = p1.p_years + p2.p_years;
        p_months = p1.p_months + p2.p_months;
        p_days = p1.p_days + p2.p_days;
        p_hours = p1.p_hours + p2.p_hours;
        p_minutes = p1.p_minutes + p2.p_minutes;
        p_seconds = p1.p_seconds + p2.p_seconds;
        p_micros = p1.p_micros + p2.p_micros;
      }
  | (Minus, (VDate _ | VDatetime _), (VDate _ | VDatetime _)) ->
      Chrono.date_diff_period v1 v2
  (* Then handle NA *)
  | (_, VNA _, _) | (_, _, VNA _) ->
      Error.type_error "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly."
  (* Arithmetic *)
  | (Plus, VInt a, VInt b) -> VInt (a + b)
  | (Plus, VFloat a, VFloat b) -> VFloat (a +. b)
  | (Plus, VInt a, VFloat b) -> VFloat (float_of_int a +. b)
  | (Plus, VFloat a, VInt b) -> VFloat (a +. float_of_int b)
  | (Plus, VString _, VString _) ->
      Error.type_error "String concatenation with '+' is not supported. Use 'str_join([a, b], sep)' or 'paste(a, b, sep)' instead."

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
  | (Lt, VDate a, VDate b) -> VBool (a < b)
  | (Lt, VDatetime (a, _), VDatetime (b, _)) -> VBool (Int64.compare a b < 0)

  | (Gt, VInt a, VInt b) -> VBool (a > b)
  | (Gt, VFloat a, VFloat b) -> VBool (a > b)
  | (Gt, VInt a, VFloat b) -> VBool (float_of_int a > b)
  | (Gt, VFloat a, VInt b) -> VBool (a > float_of_int b)
  | (Gt, VDate a, VDate b) -> VBool (a > b)
  | (Gt, VDatetime (a, _), VDatetime (b, _)) -> VBool (Int64.compare a b > 0)

  | (LtEq, VInt a, VInt b) -> VBool (a <= b)
  | (LtEq, VFloat a, VFloat b) -> VBool (a <= b)
  | (LtEq, VInt a, VFloat b) -> VBool (float_of_int a <= b)
  | (LtEq, VFloat a, VInt b) -> VBool (a <= float_of_int b)
  | (LtEq, VDate a, VDate b) -> VBool (a <= b)
  | (LtEq, VDatetime (a, _), VDatetime (b, _)) -> VBool (Int64.compare a b <= 0)

  | (GtEq, VInt a, VInt b) -> VBool (a >= b)
  | (GtEq, VFloat a, VFloat b) -> VBool (a >= b)
  | (GtEq, VInt a, VFloat b) -> VBool (float_of_int a >= b)
  | (GtEq, VFloat a, VInt b) -> VBool (a >= float_of_int b)
  | (GtEq, VDate a, VDate b) -> VBool (a >= b)
  | (GtEq, VDatetime (a, _), VDatetime (b, _)) -> VBool (Int64.compare a b >= 0)

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

let uniq_preserve (items : string list) : string list =
  let seen = Hashtbl.create (List.length items) in
  List.filter
    (fun item ->
      if Hashtbl.mem seen item then false
      else begin
        Hashtbl.add seen item ();
        true
      end)
    items

let combinations_of_size size lst =
  let rec aux k prefix rest acc =
    match k, rest with
    | 0, _ ->
        let combo = List.rev prefix in
        combo :: acc
    | _, [] ->
        acc
    | k, x :: xs ->
        let acc = aux (k - 1) (x :: prefix) xs acc in
        aux k prefix xs acc
  in
  aux size [] lst [] |> List.rev

let expand_formula_interaction (factors : string list) : string list =
  let factors = uniq_preserve factors in
  let n = List.length factors in
  let rec loop size acc =
    if size > n then
      List.rev acc
    else
      let terms =
        combinations_of_size size factors
        |> List.map (String.concat ":")
      in
      loop (size + 1) (List.rev_append terms acc)
  in
  loop 1 []

let rec extract_formula_product_factors (expr : Ast.expr) : string list option =
  match expr.node with
  | Var s -> Some [ s ]
  | BinOp { op = Mul; left; right } ->
      (match extract_formula_product_factors left, extract_formula_product_factors right with
       | Some lhs, Some rhs -> Some (lhs @ rhs)
       | _ -> None)
  | _ -> None

(** Extract variable names from a formula expression.
    Supports additive terms and interaction expansion via `*`.
    Returns predictor/response names in model-matrix order. *)
let rec extract_formula_vars (expr : Ast.expr) : string list =
  match expr.node with
  | Var s -> [ s ]
  | BinOp { op = Plus; left; right } ->
      uniq_preserve (extract_formula_vars left @ extract_formula_vars right)
  | BinOp { op = Mul; _ } ->
      (match extract_formula_product_factors expr with
       | Some factors -> expand_formula_interaction factors
       | None -> [])
  | Value (VInt 1) -> []  (* Intercept term: y ~ x + 1 *)
  | _ -> []  (* Unsupported formula syntax *)

(* Module-level mutable ref to track accumulated imports for pipeline propagation *)
let current_imports : Ast.stmt list ref = ref []

let dedent = Nix_unparse.dedent

let eval_shell_expr _env_ref cmd =
  let cmd = dedent cmd in
  let stripped = String.trim cmd in
  if stripped = "cd" || String.starts_with ~prefix:"cd " stripped then
    let path = if stripped = "cd" then Sys.getenv_opt "HOME" |> Option.value ~default:"."
               else String.trim (String.sub stripped 3 (String.length stripped - 3)) in
    let path = if String.starts_with ~prefix:"~" path then
                 let home = Sys.getenv_opt "HOME" |> Option.value ~default:"." in
                 home ^ String.sub path 1 (String.length path - 1)
               else path in
    (try
      Sys.chdir path;
      VShellResult { sr_stdout = ""; sr_stderr = ""; sr_exit_code = 0 }
    with Sys_error msg ->
      VShellResult { sr_stdout = ""; sr_stderr = "No such directory: " ^ path ^ " (" ^ msg ^ ")"; sr_exit_code = 1 })
  else
    try
      let ic, oc, ec = Unix.open_process_full cmd (Unix.environment ()) in
      close_out_noerr oc;
      let stdout_buf = Buffer.create 128 in
      let stderr_buf = Buffer.create 128 in
      (try
        while true do Buffer.add_char stdout_buf (input_char ic) done
      with End_of_file -> ());
      (try
        while true do Buffer.add_char stderr_buf (input_char ec) done
      with End_of_file -> ());
      let status = Unix.close_process_full (ic, oc, ec) in
      let stdout = Buffer.contents stdout_buf in
      let stderr = Buffer.contents stderr_buf |> String.trim in
      let exit_code = match status with
        | Unix.WEXITED n  -> n
        | Unix.WSIGNALED n -> -(abs n)
        | Unix.WSTOPPED n  -> -(abs n)
      in
      VShellResult { sr_stdout = stdout; sr_stderr = stderr; sr_exit_code = exit_code }
    with
    | Unix.Unix_error (Unix.ENOENT, _, _) ->
        VShellResult { sr_stdout = ""; sr_stderr = "command not found"; sr_exit_code = 127 }
    | _ ->
        VShellResult { sr_stdout = ""; sr_stderr = "failed to execute shell command"; sr_exit_code = 1 }

(** Produce a NameError for `name`, lazily computing a "Did you mean …?"
    suggestion only when we need to build the error value.
    This avoids materializing Env.bindings on every unbound-variable access. *)
let name_error_with_lazy_suggestion name env_ref =
  let names = 
    Env.bindings !env_ref 
    |> List.filter (fun (name, v) -> 
        match v with 
        | VSymbol _ -> false 
        | _ -> not (String.starts_with ~prefix:"__" name)
    )
    |> List.map fst 
  in
  match Ast.suggest_name name names with
  | Some suggestion -> Error.name_error_with_suggestion name suggestion
  | None -> Error.name_error name

let vexpr v = match v with
  | VExpr e -> e
  | VQuo { q_expr; _ } -> q_expr   (* strip env; used only for splice/inject *)
  | _ -> Ast.mk_expr (Value v)
let varexpr name = Ast.mk_expr (Var name)

let add_fresh_match_binding bindings name value =
  match List.assoc_opt name bindings with
  | Some _ -> None
  | None -> Some ((name, value) :: bindings)

let merge_match_bindings bindings additions =
  List.fold_left
    (fun acc (name, value) ->
      match acc with
      | None -> None
      | Some current -> add_fresh_match_binding current name value)
    (Some bindings)
    additions

let rec match_pattern (pattern : Ast.match_pattern) (value : Ast.value)
  : (string * Ast.value) list option =
  match pattern, value with
  | PWildcard, _ -> Some []
  | PVar name, matched -> Some [ (name, matched) ]
  | PNA, VNA _ -> Some []
  | PError field, VError err ->
      begin
        match field with
        | Some name -> Some [ (name, VString err.message) ]
        | None -> Some []
      end
  | PList (patterns, rest_name), VList items ->
      let rec match_list remaining_patterns remaining_items bindings =
        match remaining_patterns, remaining_items with
        | [], rest_items ->
            begin
              match rest_name with
              | Some name -> add_fresh_match_binding bindings name (VList rest_items)
              | None -> if rest_items = [] then Some bindings else None
            end
        | _ :: _, [] -> None
        | pattern :: rest_patterns, (_, item_value) :: rest_items ->
            begin
              match match_pattern pattern item_value with
              | None -> None
              | Some matched_bindings ->
                  begin
                    match merge_match_bindings bindings matched_bindings with
                    | None -> None
                    | Some combined -> match_list rest_patterns rest_items combined
                  end
            end
      in
      match_list patterns items []
  | _ -> None

let rec eval_match (env_ref : environment ref) scrutinee cases =
  let scrutinee_value = eval_expr env_ref scrutinee in
  let rec eval_cases = function
    | [] ->
        begin
          match scrutinee_value with
          (* Preserve the original error when no arm handles it. *)
          | VError _ as err -> err
          | _ -> Error.match_error "Match expression did not match any pattern."
        end
    | (pattern, body) :: rest ->
        begin
          match match_pattern pattern scrutinee_value with
          | None -> eval_cases rest
          | Some bindings ->
              let scoped_env =
                List.fold_left
                  (fun env (name, value) -> Env.add name value env)
                  !env_ref
                  bindings
              in
              eval_expr (ref scoped_env) body
        end
  in
  eval_cases cases

and eval_expr (env_ref : environment ref) (expr : Ast.expr) : value =
  let result =
    match expr.node with
    | Unquote inner -> VUnquote (eval_expr env_ref inner)
    | UnquoteSplice inner -> VUnquoteSplice (eval_expr env_ref inner)
    | ShellExpr cmd -> eval_shell_expr env_ref cmd
    | Value (VSymbol s) when String.length s > 0 && s.[0] = '^' ->
        (match Serialization_registry.lookup (String.sub s 1 (String.length s - 1)) with
         | Some ser -> VSerializer ser
         | None -> VSymbol s)
    | Value v -> v
    | Var s ->
        (match Env.find_opt s !env_ref with
        | Some v -> v
        | None -> 
            (match !Ast.node_resolver s with
             | Some v -> v
             | None -> name_error_with_lazy_suggestion s env_ref))
    
    | ColumnRef field ->
        (match Env.find_opt ("$" ^ field) !env_ref with
         | Some v -> v
         | None -> VSymbol ("$" ^ field))

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
    | Match { scrutinee; cases } ->
        eval_match env_ref scrutinee cases

    | Call { fn = { node = Var "expr"; _ }; args } ->
        (match args with
         | [(_name, e)] -> VExpr (quote_expr env_ref e)
         | _ -> make_error ArityError "expr() expects exactly 1 argument")

    | Call { fn = { node = Var "exprs"; _ }; args } ->
        VList (List.map (fun (name, e) -> (name, VExpr (quote_expr env_ref e))) args)

    (* quo/quos capture the expression WITH the current lexical environment (quosure) *)
    | Call { fn = { node = Var "quo"; _ }; args } ->
        (match args with
         | [(_name, e)] -> VQuo { q_expr = quote_expr env_ref e; q_env = !env_ref }
         | _ -> make_error ArityError "quo() expects exactly 1 argument")

    | Call { fn = { node = Var "quos"; _ }; args } ->
        let current_env = !env_ref in
        VList (List.map (fun (name, e) ->
          (name, VQuo { q_expr = quote_expr env_ref e; q_env = current_env })
        ) args)

    | Call { fn = { node = Var "eval"; _ }; args } ->
        (match args with
         | [(_name, e)] ->
             (match eval_expr env_ref e with
              | VExpr quoted -> eval_expr env_ref quoted
              | VQuo { q_expr; q_env } -> eval_expr (ref q_env) q_expr
              | v -> v)
         | _ -> make_error ArityError "eval() expects exactly 1 argument")

    | Call { fn = { node = Var "enquo"; _ }; args } ->
        (match args with
         | [(_, { node = Var name; _ })] ->
             let q_env = match Env.find_opt "__q_caller_env__" !env_ref with
               | Some (VEnv e) -> e
               | _ -> !env_ref
             in
             (match Env.find_opt ("__q_" ^ name) !env_ref with
              | Some (VExpr q) -> VQuo { q_expr = q; q_env }
              | _ -> Error.make_error NameError (Printf.sprintf "enquo: argument `%s` not found in current call context." name))
         | _ -> Error.make_error ArityError "enquo() expects exactly 1 symbol argument")

    | Call { fn = { node = Var "enquos"; _ }; args } ->
        let q_env = match Env.find_opt "__q_caller_env__" !env_ref with
          | Some (VEnv e) -> e
          | _ -> !env_ref
        in
        let wrap_as_quo = fun (name, v) -> match v with
          | VExpr e -> (name, VQuo { q_expr = e; q_env })
          | other -> (name, other)
        in
        (match args with
         | [(_, { node = Var name; _ })] when name = "..." ->
             (match Env.find_opt "__q_dots" !env_ref with
              | Some (VList q_dots) -> VList (List.map wrap_as_quo q_dots)
              | _ -> VList [])
         | [] ->
             (match Env.find_opt "__q_dots" !env_ref with
              | Some (VList q_dots) -> VList (List.map wrap_as_quo q_dots)
              | _ -> VList [])
         | _ -> Error.make_error ArityError "enquos() expects no arguments or `...`")

    | Call { fn = { node = Var name; _ }; args }
      when List.mem name ["node"; "py"; "pyn"; "rn"; "shn"] ->
        let fn_name = name in
        let lookup_arg name default =
          match List.assoc_opt (Some name) args with
          | Some e -> e
          | None ->
              (match name with
               | "command" ->
                   (match List.filter (fun (k, _) -> k = None) args with
                    | [(_, c)] -> c | _ -> default)
               | _ -> default)
        in
        (* Eagerly evaluate serializer/deserializer args in the current env.
           This lets users define serializers as top-level variables or import
           them from .t files. The result is re-wrapped as Value(v) so the Nix
           emitter (which calls eval_expr_safe with empty env) can still
           resolve the value at code-generation time.
           IMPORTANT: only evaluate when the user actually supplied the arg —
           the default sentinels (varexpr "text", varexpr "default") are NOT
           string literals but variable-name look-ups that would fail in env. *)
        let lookup_serializer_arg name default =
          match List.assoc_opt (Some name) args with
          | Some e ->
            let v = eval_expr env_ref e in
            Ast.mk_expr (Ast.Value v)
          | None -> default
        in
        let lookup_env_vars () =
          let is_env_value = function
            | VString _ | VSymbol _ | VInt _ | VFloat _ | VBool _ | VNA _ -> true
            | _ -> false
          in
          let is_valid_env_var_name key =
            let is_initial = function
              | 'A' .. 'Z' | 'a' .. 'z' | '_' -> true
              | _ -> false
            in
            let is_continue = function
              | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true
              | _ -> false
            in
            String.length key > 0
            && is_initial key.[0]
            && let rec loop idx =
                 idx >= String.length key
                 || (is_continue key.[idx] && loop (idx + 1))
               in
               loop 1
          in
          match List.assoc_opt (Some "env_vars") args with
          | None -> Ok []
          | Some e ->
               (match eval_expr env_ref e with
                | VDict pairs ->
                     (match List.find_opt (fun (key, _) -> not (is_valid_env_var_name key)) pairs with
                      | Some (key, _) ->
                          Error (Error.type_error
                                   (Printf.sprintf
                                      "Function `%s` expects `env_vars` key `%s` to be a valid environment variable name ([A-Za-z_][A-Za-z0-9_]*)."
                                      fn_name key))
                      | None ->
                     (match List.find_opt (fun (_, v) -> not (is_env_value v)) pairs with
                      | None -> Ok pairs
                      | Some (key, _) ->
                          Error (Error.type_error
                                   (Printf.sprintf "Function `%s` expects environment variable `%s` to be a String, Symbol, Int, Float, Bool, or NA." fn_name key))))
                | VNA _ -> Ok []
                | _ ->
                    Error (Error.type_error (Printf.sprintf "Function `%s` expects `env_vars` to be a Dict." fn_name)))
        in
        let lookup_dependencies () =
          match List.assoc_opt (Some "deps") args with
          | None -> Ok None
          | Some e ->
              let extract_dep_name expr =
                match expr.node with
                | Var s -> Some s
                | Value (VString s) | Value (VSymbol s) ->
                    if String.starts_with ~prefix:"^" s then
                      Some (String.sub s 1 (String.length s - 1))
                    else Some s
                | _ -> None
              in
              let deps_type_error () =
                Error (Error.type_error (Printf.sprintf "Function `%s` expects `deps` to be a List of identifiers, Strings or Symbols." fn_name))
              in
              let rec extract_dep_names items =
                match items with
                | [] -> Ok []
                | (_, item_e) :: rest ->
                    (match extract_dep_name item_e with
                     | Some dep ->
                         (match extract_dep_names rest with
                          | Ok deps -> Ok (dep :: deps)
                          | Error _ as err -> err)
                     | None -> deps_type_error ())
              in
              (match e.node with
               | ListLit items ->
                   (match extract_dep_names items with
                    | Ok deps -> Ok (Some deps)
                    | Error _ as err -> err)
               | _ ->
                   (match extract_dep_name e with
                    | Some s -> Ok (Some [s])
                    | None -> deps_type_error ()))
        in
        let lookup_runtime_args () =
          let rec is_arg_value ~allow_list = function
            | VString _ | VSymbol _ | VInt _ | VFloat _ | VBool _ | VNA _ -> true
            | VList items when allow_list ->
                List.for_all (fun (_, v) -> is_arg_value ~allow_list:false v) items
            | _ -> false
          in
          match List.assoc_opt (Some "args") args with
          | None -> Ok []
          | Some e ->
              (match eval_expr env_ref e with
               | VDict pairs ->
                    (match List.find_opt (fun (_, v) -> not (is_arg_value ~allow_list:true v)) pairs with
                     | None -> Ok pairs
                     | Some (key, _) ->
                         Error (Error.type_error
                                  (Printf.sprintf "Function `%s` expects runtime arg `%s` to be a String, Symbol, Int, Float, Bool, NA, or List of those values." fn_name key)))
               | VList items ->
                    (match List.find_opt (fun (_, v) -> not (is_arg_value ~allow_list:false v)) items with
                     | None -> Ok (List.mapi (fun i (_, v) -> (string_of_int i, v)) items)
                     | Some _ ->
                         Error (Error.type_error
                                  (Printf.sprintf "Function `%s` expects `args` list items to be String, Symbol, Int, Float, Bool, or NA values." fn_name)))
               | VNA _ -> Ok []
               | _ ->
                   Error (Error.type_error (Printf.sprintf "Function `%s` expects `args` to be a Dict or List." fn_name)))
        in
        let lookup_list name =
          match List.assoc_opt (Some name) args with
          | Some { node = ListLit items; _ } -> List.map snd items
          | Some expr -> [expr]
          | None -> []
        in
      let eval_string name default =
        match eval_expr env_ref (lookup_arg name (vexpr (VString default))) with
        | VString s -> s | VSymbol s -> s | _ -> default
      in
      let eval_bool name default =
        match eval_expr env_ref (lookup_arg name (vexpr (VBool default))) with
        | VBool b -> b | _ -> default
      in
      (* Evaluate the optional script argument — must be a string path to a .R, .py, or .qmd file *)
      let explicit_script_path_opt =
        match List.assoc_opt (Some "script") args with
        | Some e ->
            (match eval_expr env_ref e with
             | VString s -> Some s
             | VSymbol s -> Some s
             | _ -> None)
        | None -> None
      in
      let shell_opt =
        match List.assoc_opt (Some "shell") args with
        | Some e -> (match eval_expr env_ref e with VString s -> Some s | VSymbol s -> Some s | _ -> None)
        | None -> None
      in
      let shell_args = lookup_list "shell_args" in
      let command = lookup_arg "command" (vexpr ((VNA NAGeneric))) in
      (match lookup_env_vars (), lookup_runtime_args (), lookup_dependencies () with
      | Error err, _, _ | _, Error err, _ | _, _, Error err -> err
      | Ok un_env_vars, Ok un_args, Ok un_dependencies ->
          let arg_path_opt =
            let find_path key =
              match List.assoc_opt key un_args with
              | Some (VString s) -> Some s
              | Some (VSymbol s) -> Some s
              | _ -> None
            in
            List.find_map find_path [ "path"; "file"; "qmd_file"; "input" ]
          in
          let has_command = match command.node with Value ((VNA NAGeneric)) -> false | _ -> true in
          let execution_path_opt =
            match explicit_script_path_opt with
            | Some _ as s -> s
            | None -> if has_command then None else arg_path_opt
          in
          if has_command && explicit_script_path_opt <> None then
            Error.make_error TypeError (Printf.sprintf "%s() cannot use both 'command' and 'script' arguments — choose one." fn_name)
          else
             let default_runtime = match name with
               | "py" | "pyn" -> "Python"
               | "rn" -> "R"
               | "shn" -> "sh"
               | _ -> "T"
             in
            (* Auto-detect runtime from script/arg extension only if not explicit *)
            let runtime =
              let explicit = eval_string "runtime" "" in
              if explicit <> "" then explicit
              else match explicit_script_path_opt with
                | Some path -> (match Filename.extension path with ".R" -> "R" | ".py" -> "Python" | ".qmd" -> "Quarto" | ".sh" -> "sh" | _ -> default_runtime)
                | None -> (match arg_path_opt with
                    | Some path when not has_command -> (match Filename.extension path with ".R" -> "R" | ".py" -> "Python" | ".qmd" -> "Quarto" | ".sh" -> "sh" | _ -> default_runtime)
                    | _ -> default_runtime)
            in
            if has_command && runtime = "Quarto" then
              Error.make_error TypeError "Quarto nodes require a script and do not support inlined `command` blocks."
            else
              let un_command, un_script =
                match execution_path_opt with
                | Some path ->
                    let ids = try
                      let ic = open_in path in
                      let content = Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
                        let n = in_channel_length ic in
                        let buf = Bytes.create n in
                        really_input ic buf 0 n;
                        Bytes.to_string buf)
                      in Ast.extract_identifiers content
                    with Sys_error _ | End_of_file -> []
                    in (Ast.mk_expr (RawCode { raw_text = ""; raw_identifiers = ids }), Some path)
                | None -> (command, None)
              in
              let base_includes = lookup_list "includes" in
              let un_includes =
                match arg_path_opt with
                | Some p when has_command ->
                    let already_included = List.exists (function { node = Value (VString s); _ } | { node = Value (VSymbol s); _ } -> s = p | _ -> false) base_includes in
                    if already_included then base_includes else base_includes @ [vexpr (VString p)]
                | _ -> base_includes
              in
              if runtime = "Quarto" && un_script = None then
                Error.make_error TypeError
                  "Node with runtime `Quarto` requires `script` or `args.path`/`args.file`/`args.qmd_file`/`args.input` to point to a `.qmd` file."
              else if runtime <> "T" && runtime <> "Quarto" then
                match un_command.node with
                | RawCode _ ->
                    VNode {
                      un_command; un_script; un_runtime = runtime;
                      un_serializer = lookup_serializer_arg "serializer" (match runtime with "sh" -> varexpr "text" | _ -> varexpr "default");
                      un_deserializer = lookup_serializer_arg "deserializer" (varexpr "default");
                      un_env_vars; un_args;
                      un_shell = shell_opt;
                      un_shell_args = shell_args;
                      un_functions = lookup_list "functions";
                      un_includes;
                      un_noop = eval_bool "noop" false;
                      un_dependencies;
                    }
                | Value (VString _) | Value (VSymbol _) | Value ((VNA NAGeneric)) when runtime = "sh" ->
                    VNode {
                      un_command; un_script; un_runtime = runtime;
                      un_serializer = lookup_serializer_arg "serializer" (varexpr "text");
                      un_deserializer = lookup_serializer_arg "deserializer" (varexpr "default");
                      un_env_vars; un_args;
                      un_shell = shell_opt;
                      un_shell_args = shell_args;
                      un_functions = lookup_list "functions";
                      un_includes;
                      un_noop = eval_bool "noop" false;
                      un_dependencies;
                    }
                | _ when Option.is_some un_script ->
                    VNode {
                      un_command; un_script; un_runtime = runtime;
                      un_serializer = lookup_serializer_arg "serializer" (match runtime with "sh" -> varexpr "text" | _ -> varexpr "default");
                      un_deserializer = lookup_serializer_arg "deserializer" (varexpr "default");
                      un_env_vars; un_args;
                      un_shell = shell_opt;
                      un_shell_args = shell_args;
                      un_functions = lookup_list "functions";
                      un_includes;
                      un_noop = eval_bool "noop" false;
                      un_dependencies;
                    }
                | _ ->
                    let msg = Printf.sprintf "Node with runtime `%s` requires command to be wrapped in <{ ... }> blocks (RawCode), or use the 'script' argument to point to a .R, .py, .sh, or .qmd file." runtime in
                    Error.make_error TypeError msg
              else
                VNode {
                  un_command; un_script; un_runtime = runtime;
                  un_serializer = lookup_serializer_arg "serializer" (varexpr "default");
                  un_deserializer = lookup_serializer_arg "deserializer" (varexpr "default");
                  un_env_vars; un_args;
                  un_shell = shell_opt;
                  un_shell_args = shell_args;
                  un_functions = lookup_list "functions";
                  un_includes;
                  un_noop = eval_bool "noop" false;
                  un_dependencies;
                }
)
    | Call { fn; args } ->
        let fn_val = eval_expr env_ref fn in
        eval_call env_ref fn_val args

    | Lambda l -> VLambda { l with env = Some !env_ref } (* Capture the current environment *)


    (* Structural expressions *)
    | ListLit items -> eval_list_lit env_ref items
    | DictLit pairs -> eval_dict_lit env_ref pairs
    | DotAccess { target; field } -> eval_dot_access env_ref target field
    | RawCode { raw_text; _ } -> VRawCode raw_text
    | ListComp _ -> Error.internal_error "List comprehensions are not yet implemented"
    | Block stmts -> eval_block env_ref stmts
    | PipelineDef nodes -> eval_pipeline env_ref nodes
    | IntentDef pairs -> eval_intent env_ref pairs
  in
  attach_expr_location expr result

and eval_block env_ref stmts =
  let rec loop () = function
    | [] -> (VNA NAGeneric)
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
  let rec collect is_call_target = function
    | { node = Value _; _ } -> []
    | { node = Var s; _ } -> if is_call_target then [] else [s]
    | { node = ColumnRef _; _ } -> []
    | { node = Call { fn; args }; _ } ->
        collect true fn @ List.concat_map (fun (_, e) -> collect false e) args
    | { node = Lambda { body; params; _ }; _ } ->
        let bound = params in
        List.filter (fun v -> not (List.mem v bound)) (collect false body)
    | { node = IfElse { cond; then_; else_ }; _ } ->
        collect false cond @ collect false then_ @ collect false else_
    | { node = Match { scrutinee; cases }; _ } ->
        let collect_case (pattern, body) =
          let rec bound_vars = function
            | PWildcard | PNA -> []
            | PVar name -> [name]
            | PError None -> []
            | PError (Some name) -> [name]
            | PList (patterns, rest) ->
                let names = List.concat_map bound_vars patterns in
                match rest with
                | Some name -> name :: names
                | None -> names
          in
          let bound = bound_vars pattern in
          List.filter (fun v -> not (List.mem v bound)) (collect false body)
        in
        collect false scrutinee @ List.concat_map collect_case cases
    | { node = ListLit items; _ } -> List.concat_map (fun (_, e) -> collect false e) items
    | { node = ListComp _; _ } -> []
    | { node = DictLit pairs; _ } -> List.concat_map (fun (_, e) -> collect false e) pairs
    | { node = BinOp { left; right; _ }; _ } -> collect false left @ collect false right
    | { node = UnOp { operand; _ }; _ } -> collect false operand
    | { node = BroadcastOp { left; right; _ }; _ } -> collect false left @ collect false right
    | { node = DotAccess { target; _ }; _ } -> collect false target
    | { node = RawCode { raw_identifiers; _ }; _ } -> raw_identifiers  (* Lexically extracted identifiers for dependency detection *)
    | { node = Block stmts; _ } -> List.concat_map (collect_stmt false) stmts
    | { node = PipelineDef _; _ } -> []
    | { node = IntentDef pairs; _ } -> List.concat_map (fun (_, e) -> collect false e) pairs
    | { node = Unquote e; _ } | { node = UnquoteSplice e; _ } -> collect false e
    | { node = ShellExpr _; _ } -> []

  and collect_stmt is_call_target = function
    | { node = Expression e; _ } -> collect is_call_target e
    | { node = Assignment { expr; _ }; _ } -> collect false expr
    | { node = Reassignment { expr; _ }; _ } -> collect false expr
    | { node = Import _ | ImportPackage _ | ImportFrom _ | ImportFileFrom _; _ } -> []
  in
  let vars = collect false expr in
  List.sort_uniq String.compare vars

(** Topological sort of pipeline nodes based on dependencies *)
and topo_sort (nodes : (string * 'a) list) (deps : (string * string list) list) : (string list, string) result =
  let node_names = List.map fst nodes in
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
and eval_pipeline env_ref (nodes : (string * Ast.expr) list) : value =
  let default_un expr = {
    un_command = expr;
    un_script = None;
    un_runtime = "T";
    un_serializer = varexpr "default";
    un_deserializer = varexpr "default";
    un_env_vars = [];
    un_args = [];
    un_shell = None;
    un_shell_args = [];
    un_functions = [];
    un_includes = [];
    un_noop = false;
    un_dependencies = None;
  } in

  (* Desugar nodes into enriched structures with defaults.
     We evaluate potential node expressions early so pre-defined nodes
     (e.g. `p = pipeline { data = data_node }`) are correctly imported.
     If a NameError occurs (e.g. `b = a` referencing an undefined sibling `a`), 
     we catch it and defer it as an unbuilt node so pipeline topological
     sorting can resolve it as an internal dependency. *)
  let desugar_node (name, node_expr) : (string * Ast.unbuilt_node, value) result =
    let is_node_call = match node_expr.node with
      | Call { fn = { node = Var ("node" | "py" | "pyn" | "rn" | "shn"); _ }; _ }
      | Var _ | ColumnRef _ | DotAccess _ | Value (VNode _) | Value (VComputedNode _) -> true
      | _ -> false
    in
    if is_node_call then
      match eval_expr env_ref node_expr with
      | VNode un -> Ok (name, un)
      | VComputedNode cn ->
          Ok (name, {
            un_command = vexpr (VComputedNode cn);
            un_script = None;
            un_runtime = cn.cn_runtime;
            un_serializer = vexpr (VString cn.cn_serializer);
            un_deserializer = varexpr "default";
            un_env_vars = [];
            un_args = [];
            un_shell = None;
            un_shell_args = [];
            un_functions = [];
            un_includes = [];
            un_noop = false;
            un_dependencies = None;
          })
      | VError { code = NameError; _ } -> Ok (name, default_un node_expr)
      | VError _ as e -> Error e
      | _ -> Ok (name, default_un node_expr)
    else
      Ok (name, default_un node_expr)
  in

  let rec desugar_all acc = function
    | [] -> Ok (List.rev acc)
    | node :: rest ->
        (match desugar_node node with
         | Error err -> Error err
         | Ok res -> desugar_all (res :: acc) rest)
  in

  match desugar_all [] nodes with
  | Error err -> err
  | Ok desugared_nodes ->
  
  (* Compute dependencies based on the 'command' part of the desugared node.
     A free variable counts as a pipeline dependency iff it is:
     (a) the name of another node defined in THIS pipeline block, or
     (b) NOT bound in the outer environment at all — meaning it is an unresolved
         reference intended to be satisfied by another pipeline via `chain`. *)
  let node_names = List.map fst desugared_nodes in
  let rec compute_deps acc = function
    | [] -> Ok (List.rev acc)
    | (name, un) :: rest ->
        (match un.un_dependencies with
         | Some explicit ->
             if List.mem name explicit then
               Error (Error.value_error (Printf.sprintf
                 "Self-referential node: `%s` lists itself in `deps`." name))
             else
               (* Validate that all explicit deps are known sibling nodes in this pipeline *)
               let unknown = List.filter (fun d -> not (List.mem d node_names)) explicit in
               if unknown <> [] then
                 Error (Error.value_error (Printf.sprintf
                   "Node `%s`: explicit `deps` contains unknown node(s): %s. All dependencies must be nodes declared in the same pipeline."
                   name (String.concat ", " (List.map (fun d -> "`" ^ d ^ "`") unknown))))
               else
                 compute_deps ((name, explicit) :: acc) rest
         | None ->
             let fv = free_vars un.un_command in
             let is_raw = match un.un_command.node with RawCode _ -> true | _ -> false in
             let has_self_ref = List.exists (fun v -> v = name) fv in
             if has_self_ref && not is_raw then
               Error (Error.value_error (Printf.sprintf
                 "Self-referential node detected in command for node: `%s`." name))
             else
               let node_deps = List.filter (fun v ->
                 v <> name && (
                   (* Always: sibling node in the same pipeline *)
                   List.mem v node_names ||
                   (* T expressions only: unresolved names are cross-pipeline deps (chain).
                      For RawCode (R/Python), we can't distinguish foreign identifiers from
                      intended cross-pipeline refs, so we conservatively exclude them. *)
                   (not is_raw && not (Env.mem v !env_ref))
                 )
               ) fv in
               compute_deps ((name, node_deps) :: acc) rest)
  in
  match compute_deps [] desugared_nodes with
  | Error e -> e
  | Ok deps ->

  (* No-op propagation: if a node is noop, all its transitive dependents are noop *)
  let desugared_nodes =
    let rec propagate current =
      let changed = ref false in
      let next = List.map (fun (name, un) ->
        if un.un_noop then (name, un)
        else
          let my_deps = match List.assoc_opt name deps with Some d -> d | None -> [] in
          let has_noop_dep = List.exists (fun d ->
            match List.find_opt (fun (dn_name, _) -> dn_name = d) current with
            | Some (_, dep_un) -> dep_un.Ast.un_noop
            | None -> false
          ) my_deps in
          if has_noop_dep then (changed := true; (name, { un with un_noop = true }))
          else (name, un)
      ) current in
      if !changed then propagate next else next
    in
    propagate desugared_nodes
  in

  (* Validation: Cross-runtime dependencies must have explicit deserializer *)
  let runtime_mapping = List.map (fun (name, un) -> (name, un.un_runtime)) desugared_nodes in
  let validation_errors = List.filter_map (fun (name, un) ->
    let my_runtime = un.un_runtime in
    let my_deps = List.assoc name deps in
    let offenders = List.filter (fun dname ->
      match List.assoc_opt dname runtime_mapping with
      | Some dep_runtime -> 
          dep_runtime <> my_runtime && 
          my_runtime <> "Quarto" && 
          my_runtime <> "sh" &&
          my_runtime <> "T" &&
          (match un.un_deserializer.node with Var "default" -> true | _ -> false)
      | None -> false (* External dependency — we don't know its runtime yet *)
    ) my_deps in
    if offenders <> [] then
      let offender = List.hd offenders in
      let offender_runtime = List.assoc offender runtime_mapping in
      Some (Printf.sprintf "Node `%s` (%s) depends on `%s` (%s) but has no explicit deserializer."
             name my_runtime offender offender_runtime)
    else None
  ) desugared_nodes in

  if validation_errors <> [] then
    Error.make_error TypeError (List.hd validation_errors)
  else

  (* Topological sort *)
  match topo_sort desugared_nodes deps with
  | Error cycle_node ->
    Error.value_error (Printf.sprintf "Pipeline has a dependency cycle involving node `%s`." cycle_node)
  | Ok exec_order ->
    let node_map = desugared_nodes in
    let eval_or_defer name un current_env_ref =
      if un.un_noop then VSymbol (Printf.sprintf "<noop:%s>" name)
      else if un.un_runtime = "T" then
        let node_deps = match List.assoc_opt name deps with Some d -> d | None -> [] in
        let is_unbuilt d = match Env.find_opt d !current_env_ref with
          | Some (VComputedNode _) -> 
              (* If the dependency is a node (built or unbuilt), we must defer local 
                 evaluation of the command, as it is a recipe for Nix. *)
              true
          | None ->
              (* Allow unknown names to be deferred for cross-pipeline or late resolution. *)
              true
          | _ -> false
        in
        let is_raw = match un.un_command.node with RawCode _ -> true | _ -> false in
        if is_raw || List.exists is_unbuilt node_deps then
          VComputedNode {
            cn_name = name;
            cn_runtime = "T";
            cn_path = "<unbuilt>";
            cn_serializer = Nix_unparse.expr_to_string un.un_serializer;
            cn_class = "Unknown";
            cn_dependencies = node_deps;
          }
        else
          let get_strategy dep_name =
            let rec lookup_in_list target = function
              | [] -> None
              | (Some n, e) :: _ when n = target -> Some e
              | _ :: rest -> lookup_in_list target rest
            in
            let rec lookup_in_dict target = function
              | [] -> None
              | (n, e) :: _ when n = target -> Some e
              | _ :: rest -> lookup_in_dict target rest
            in
            let strategy_expr = match un.un_deserializer.node with
              | Ast.ListLit items -> (match lookup_in_list dep_name items with Some e -> e | None -> un.un_deserializer)
              | Ast.DictLit items -> (match lookup_in_dict dep_name items with Some e -> e | None -> un.un_deserializer)
              | _ -> un.un_deserializer
            in
            match strategy_expr.node with
            | Ast.Value (Ast.VString s) -> s
            | Ast.Var s -> s
            | _ -> "default"
          in
          let env_with_deserialized = List.fold_left (fun acc dname ->
            let strategy = get_strategy dname in
            match Env.find_opt dname acc with
            | Some (VComputedNode cn) when strategy = "json" && cn.cn_serializer = "json" ->
                (match Serialization.read_json cn.cn_path with
                 | Ok v -> Env.add dname v acc
                 | Error msg -> 
                     Printf.eprintf "Warning: Automatic JSON deserialization failed for dependency `%s` of node `%s`: %s\n%!" dname name msg;
                     acc)
            | Some (VComputedNode cn) when strategy = "pmml" && cn.cn_serializer = "pmml" ->
                (match Pmml_utils.read_pmml cn.cn_path with
                 | Ok v -> Env.add dname (Pmml_utils.attach_source_path cn.cn_path v) acc
                 | Error msg -> 
                     Printf.eprintf "Warning: Automatic PMML deserialization failed for dependency `%s` of node `%s`: %s\n%!" dname name msg;
                     acc)
            | _ -> acc
          ) !current_env_ref node_deps in
          eval_expr (ref env_with_deserialized) un.un_command
          |> annotate_pipeline_error ~runtime:un.un_runtime name
      else VComputedNode {
        cn_name = name;
        cn_runtime = un.un_runtime;
        cn_path = "<unbuilt>";
        cn_serializer = Nix_unparse.expr_to_string un.un_serializer;
        cn_class = "Unknown";
        cn_dependencies = List.assoc name deps;
      }
    in
    let (results, _) = List.fold_left (fun (results, current_env_ref) name ->
      let un = List.assoc name node_map in
      let node_deps = List.assoc name deps in
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
                 Ast.VError { err with message = pipeline_error_message ~node_name:name ~detail:msg }
              | _ -> eval_or_defer name un current_env_ref)
        | None -> eval_or_defer name un current_env_ref
      in
      current_env_ref := Env.add name v !current_env_ref;
      ((name, v) :: results, current_env_ref)
    ) ([], ref !env_ref) exec_order in

    let p_nodes = List.rev results in
    VPipeline {
      p_nodes;
      p_exprs = List.map (fun (name, un) -> (name, un.un_command)) desugared_nodes;
      p_deps = deps;
      p_imports = !current_imports;
      p_runtimes = runtime_mapping;
      p_serializers = List.map (fun (name, un) -> (name, un.un_serializer)) desugared_nodes;
      p_deserializers = List.map (fun (name, un) -> (name, un.un_deserializer)) desugared_nodes;
      p_env_vars = List.map (fun (name, un) -> (name, un.un_env_vars)) desugared_nodes;
      p_args = List.map (fun (name, un) -> (name, un.un_args)) desugared_nodes;
      p_shells = List.map (fun (name, un) -> (name, un.un_shell)) desugared_nodes;
      p_shell_args = List.map (fun (name, un) -> (name, un.un_shell_args)) desugared_nodes;
      p_functions = List.map (fun (name, un) -> (name, un.un_functions)) desugared_nodes;
      p_includes = List.map (fun (name, un) -> (name, un.un_includes)) desugared_nodes;
      p_noops = List.map (fun (name, un) -> (name, un.un_noop)) desugared_nodes;
      p_scripts = List.map (fun (name, un) -> (name, un.un_script)) desugared_nodes;
      p_explicit_deps = List.map (fun (name, un) -> (name, un.un_dependencies)) desugared_nodes;
    }

(** Re-run a pipeline *)
and rerun_pipeline ?(strict=false) env_ref (prev : Ast.pipeline_result) : value =
  let node_names = List.map fst prev.p_exprs in
  let desugared_nodes = List.map (fun (name, expr) ->
    (name, {
      Ast.un_command = expr;
      un_script = (match List.assoc_opt name prev.p_scripts with Some s -> s | None -> None);
      un_runtime = List.assoc name prev.p_runtimes;
      un_serializer = List.assoc name prev.p_serializers;
      un_deserializer = List.assoc name prev.p_deserializers;
      un_env_vars = (match List.assoc_opt name prev.p_env_vars with Some vars -> vars | None -> []);
      un_args = (match List.assoc_opt name prev.p_args with Some runtime_args -> runtime_args | None -> []);
      un_shell = (match List.assoc_opt name prev.p_shells with Some s -> s | None -> None);
      un_shell_args = (match List.assoc_opt name prev.p_shell_args with Some s_args -> s_args | None -> []);
      un_functions = List.assoc name prev.p_functions;
      un_includes = List.assoc name prev.p_includes;
      un_noop = List.assoc name prev.p_noops;
      un_dependencies = List.assoc name prev.p_explicit_deps;
    })
  ) prev.p_exprs in

  match topo_sort desugared_nodes prev.p_deps with
  | Error cycle_node ->
    Error.value_error (Printf.sprintf "Pipeline has a dependency cycle involving node `%s`." cycle_node)
  | Ok exec_order ->
    let rerun_eval_or_defer name un _env_ref =
      if un.un_noop then VSymbol (Printf.sprintf "<noop:%s>" name)
      else 
        let node_deps = match List.assoc_opt name prev.p_deps with Some d -> d | None -> [] in
        if strict then begin
           match List.find_opt (fun d -> not (List.mem d node_names) && not (Env.mem d !env_ref)) node_deps with
           | Some missing -> 
               Error.make_error NameError (Printf.sprintf "Pipeline node `%s` depends on unknown identifier `%s`." name missing)
           | None ->
              VComputedNode {
                cn_name = name;
                cn_runtime = un.un_runtime;
                cn_path = "<unbuilt>";
                cn_serializer = (match un.un_serializer.node with Ast.Value (Ast.VString s) -> s | _ -> Nix_unparse.unparse_expr un.un_serializer);
                cn_class = "Unknown";
                cn_dependencies = node_deps;
              }
        end else
          VComputedNode {
            cn_name = name;
            cn_runtime = un.un_runtime;
            cn_path = "<unbuilt>";
            cn_serializer = (match un.un_serializer.node with Ast.Value (Ast.VString s) -> s | _ -> Nix_unparse.unparse_expr un.un_serializer);
            cn_class = "Unknown";
            cn_dependencies = node_deps;
          }
    in
    let (results, _, _) = List.fold_left (fun (results, current_env_ref, changed) name ->
      let un = List.assoc name desugared_nodes in
      let node_deps = match List.assoc_opt name prev.p_deps with Some d -> d | None -> [] in
      let deps_changed = List.exists (fun d -> List.mem d changed) node_deps in
      let fv = free_vars un.un_command in
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
                   let runtime = match List.assoc_opt "runtime" err.context with Some (VString r) -> Some r | _ -> None in
                  Ast.VError { err with message = pipeline_error_message ~node_name:name ~detail:msg;
                                        context = (match runtime with Some r -> if List.mem_assoc "runtime" err.context then err.context else ("runtime", VString r) :: err.context | None -> err.context) }
                | _ -> rerun_eval_or_defer name un current_env_ref)
          | None -> rerun_eval_or_defer name un current_env_ref
        in
        current_env_ref := Env.add name v !current_env_ref;
        ((name, v) :: results, current_env_ref, name :: changed)
      end else begin
        let cached = List.assoc name prev.p_nodes in
        current_env_ref := Env.add name cached !current_env_ref;
        ((name, cached) :: results, current_env_ref, changed)
      end
    ) ([], ref !env_ref, []) exec_order in
    VPipeline { prev with p_nodes = List.rev results }

(** Evaluate a splice operand (!!!) and expand its elements as named pairs.
    Used by quote_expr in Call args, ListLit items, and DictLit pairs. *)
and splice_into_named_pairs env_ref fallback_name e =
  match eval_expr env_ref e with
  | VList items  -> List.map (fun (n, v) -> (n, vexpr v)) items
  | VDict items  -> List.map (fun (k, v) -> (Some k, vexpr v)) items
  | VVector arr  -> Array.to_list arr |> List.map (fun v -> (None, vexpr v))
  | other ->
      let msg = "!!! operand must evaluate to a List, Vector, or Dict, got "
                ^ Utils.type_name other in
      [(fallback_name, vexpr (make_error TypeError msg))]

(** Evaluate a splice operand for DictLit pairs (string-keyed). *)
and splice_into_dict_pairs env_ref fallback_key e =
  match eval_expr env_ref e with
  | VDict items -> List.map (fun (k, v) -> (k, vexpr v)) items
  | VList items ->
      List.map (fun (name, v) ->
        let key = match name with Some n -> n | None -> fallback_key in
        (key, vexpr v)
      ) items
  | other ->
      let msg = "!!! operand must evaluate to a List, Vector, or Dict, got "
                ^ Utils.type_name other in
      [(fallback_key, vexpr (make_error TypeError msg))]

and extract_name_opt v =
  let strip_dollar s =
    if String.length s > 0 && s.[0] = '$' then String.sub s 1 (String.length s - 1) else s
  in
  match v with
  | VString s -> Some s
  | VSymbol s -> Some (strip_dollar s)
  | VExpr e ->
      (match e.node with
       | Var s -> Some s
       | ColumnRef s -> Some s
       | Value (VString s) -> Some s
       | Value (VSymbol s) -> Some (strip_dollar s)
       | _ -> Some (Nix_unparse.unparse_expr e))
  | VQuo { q_expr = e; _ } ->
      (match e.node with
       | Var s -> Some s
       | ColumnRef s -> Some s
       | Value (VString s) -> Some s
       | Value (VSymbol s) -> Some (strip_dollar s)
       | _ -> Some (Nix_unparse.unparse_expr e))
  | _ -> None

(** Expand a !!name := value dynamic argument inside a quoting context.
    @param env_ref  The current evaluation environment reference (for evaluating n_expr).
    @param loc      Source location to attach to any generated error expressions.
    @param n_expr   The expression for the left-hand name (must eval to String/Symbol).
    @param v_expr   The expression for the right-hand value.
    @return A pair of type [(string option * Ast.expr)]:
            [(Some name_str, quoted_value)] on success, or
            [(None, error_expression)] when the name does not evaluate to a
            String or Symbol. The caller should propagate the error expression
            so it surfaces at evaluation time. *)
and quote_dyn_arg env_ref loc n_expr v_expr =
  let q = quote_expr env_ref in
  let name_val = eval_expr env_ref n_expr in
  match extract_name_opt name_val with
  | Some name_str -> (Some name_str, q v_expr)
  | None ->
      (None, Ast.mk_expr ?loc (Value (make_error TypeError
        (Printf.sprintf "!! := requires a String or Symbol as the left-hand name, got %s"
           (Utils.type_name name_val)))))

(** Quote an expression: recursively walk the AST, leaving it unevaluated
    except where !! (unquote) and !!! (unquote-splice) request evaluation. *)
and quote_expr (env_ref : environment ref) (expr : Ast.expr) : Ast.expr =
  let q  = quote_expr env_ref in
  let qs = quote_stmt env_ref in
  let qpair (n, e) = (n, q e) in
  let loc = expr.loc in
  match expr.node with
  (* ── Unquoting ─────────────────────────────────────────────── *)
  | Unquote e ->
      (match eval_expr env_ref e with
       | VExpr ex -> ex
       | VQuo { q_expr; _ } -> q_expr   (* strip env: !! injects just the expression *)
       | v -> Ast.mk_expr ?loc (Value v))

  | UnquoteSplice _ ->
      Ast.mk_expr ?loc (Value (make_error TypeError
        "!!! can only be used inside a Call, List, or Dict literal within expr()"))

  (* ── Compound forms that support !!! splicing and !! dynamic names ── *)
  | Call { fn; args } ->
      let quoted_args = List.concat_map (fun (name, arg) ->
        match name, arg.node with
        | None, Call { fn = { node = Var "__dynamic_arg__"; _ }; args = [(_, n_expr); (_, v_expr)] } ->
            [quote_dyn_arg env_ref loc n_expr v_expr]
        | _, UnquoteSplice e -> splice_into_named_pairs env_ref name e
        | _               -> [(name, q arg)]
      ) args in
      Ast.mk_expr ?loc (Call { fn = q fn; args = quoted_args })

  | ListLit items ->
      let quoted = List.concat_map (fun (name, item) ->
        match name, item.node with
        | None, Call { fn = { node = Var "__dynamic_arg__"; _ }; args = [(_, n_expr); (_, v_expr)] } ->
            [quote_dyn_arg env_ref loc n_expr v_expr]
        | _, UnquoteSplice e -> splice_into_named_pairs env_ref name e
        | _               -> [(name, q item)]
      ) items in
      Ast.mk_expr ?loc (ListLit quoted)

  | DictLit pairs ->
      let quoted = List.concat_map (fun (k, v) ->
        match v.node with
        | UnquoteSplice e -> splice_into_dict_pairs env_ref k e
        | Call { fn = { node = Var "__dynamic_arg__"; _ }; args = [(_, n_expr); (_, v_expr)] } ->
            let (opt_name, qv) = quote_dyn_arg env_ref loc n_expr v_expr in
            (* When name extraction failed, opt_name is None and qv is a VError expression.
               Use "__dyn_error__" as the placeholder key so the dict stays structurally valid
               and the error is unambiguous when the dict is evaluated. *)
            let name_str = match opt_name with Some n -> n | None -> "__dyn_error__" in
            [(name_str, qv)]
        | _               -> [(k, q v)]
      ) pairs in
      Ast.mk_expr ?loc (DictLit quoted)

  (* ── Binary / unary operators ──────────────────────────────── *)
  | BinOp { op; left; right }      -> Ast.mk_expr ?loc (BinOp { op; left = q left; right = q right })
  | BroadcastOp { op; left; right } -> Ast.mk_expr ?loc (BroadcastOp { op; left = q left; right = q right })
  | UnOp { op; operand }            -> Ast.mk_expr ?loc (UnOp { op; operand = q operand })

  (* ── Control flow / structure ───────────────────────────────── *)
  | IfElse { cond; then_; else_ } ->
      Ast.mk_expr ?loc (IfElse { cond = q cond; then_ = q then_; else_ = q else_ })
  | Match { scrutinee; cases } ->
      Ast.mk_expr ?loc (Match {
        scrutinee = q scrutinee;
        cases = List.map (fun (pattern, body) -> (pattern, q body)) cases;
      })
  | Block stmts       -> Ast.mk_expr ?loc (Block (List.map qs stmts))
  | Lambda l          -> Ast.mk_expr ?loc (Lambda { l with body = q l.body })
  | DotAccess { target; field } -> Ast.mk_expr ?loc (DotAccess { target = q target; field })

  (* ── Named-pair containers ─────────────────────────────────── *)
  | PipelineDef nodes  -> Ast.mk_expr ?loc (PipelineDef (List.map qpair nodes))
  | IntentDef fields   -> Ast.mk_expr ?loc (IntentDef (List.map qpair fields))

  (* ── List comprehension ────────────────────────────────────── *)
  | ListComp { expr = e; clauses } ->
      let qclause = function
        | CFor { var; iter }  -> CFor { var; iter = q iter }
        | CFilter filter_expr -> CFilter (q filter_expr)
      in
      Ast.mk_expr ?loc (ListComp { expr = q e; clauses = List.map qclause clauses })

  (* ── Leaves (Value, Var, ColumnRef, RawCode) pass through ── *)
  | _ -> expr

and quote_stmt (env_ref : environment ref) (stmt : Ast.stmt) : Ast.stmt =
  let q = quote_expr env_ref in
  let loc = stmt.loc in
  match stmt.node with
  | Expression e                   -> Ast.mk_stmt ?loc (Expression (q e))
  | Assignment { name; typ; expr } -> Ast.mk_stmt ?loc (Assignment { name; typ; expr = q expr })
  | Reassignment { name; expr }    -> Ast.mk_stmt ?loc (Reassignment { name; expr = q expr })
  | _ -> stmt

and eval_list_lit env_ref items =
  let rec process_items acc = function
    | [] -> VList (List.rev acc)
    | (name, e) :: rest ->
        let v = match e.node with
          | Call { fn = { node = Var "__dynamic_arg__"; _ }; args = [(_, n_expr); (_, v_expr)] } ->
              let n_val = eval_expr env_ref n_expr in
              (match extract_name_opt n_val with
               | None -> make_error TypeError (Printf.sprintf "!! := requires a String or Symbol as the left-hand name, got %s" (Utils.type_name n_val))
               | Some n -> VDynamicArg (n, eval_expr env_ref v_expr))
          | _ -> eval_expr env_ref e
        in
        match v with
        | VError _ as err -> err
        | VUnquote inner -> process_items ((name, inner) :: acc) rest
        | VUnquoteSplice sv ->
            let units = match sv with
              | VList items -> items
              | VVector vx -> Array.to_list vx |> List.map (fun x -> (None, x))
              | VDict d -> List.map (fun (k, v) -> (Some k, v)) d
              | _ -> [(name, sv)]
            in
            process_items (List.rev_append units acc) rest
        | VDynamicArg (n, v) ->
            process_items ((Some n, v) :: acc) rest
        | _ -> process_items ((name, v) :: acc) rest
  in
  process_items [] items

and eval_dict_lit env_ref items =
  let rec process_pairs acc = function
    | [] -> VDict (List.rev acc)
    | (k, e) :: rest ->
        let v = match e.node with
          | Call { fn = { node = Var "__dynamic_arg__"; _ }; args = [(_, n_expr); (_, v_expr)] } ->
              let n_val = eval_expr env_ref n_expr in
              (match extract_name_opt n_val with
               | None -> make_error TypeError (Printf.sprintf "!! := requires a String or Symbol as the left-hand name, got %s" (Utils.type_name n_val))
               | Some n -> VDynamicArg (n, eval_expr env_ref v_expr))
          | _ -> eval_expr env_ref e
        in
        match v with
        | VError _ as err -> err
        | VUnquote inner -> process_pairs ((k, inner) :: acc) rest
        | VUnquoteSplice sv ->
            let units = match sv with
              | VDict d -> d
              | VList items -> List.map (fun (n, v) -> (match n with Some name -> name | None -> "expr"), v) items
              | VVector vx -> Array.to_list vx |> List.mapi (fun i x -> (string_of_int i, x))
              | _ -> [(k, sv)]
            in
            process_pairs (List.rev_append units acc) rest
        | VDynamicArg (n, v) ->
            process_pairs ((n, v) :: acc) rest
        | _ -> process_pairs ((k, v) :: acc) rest
  in
  process_pairs [] items


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
  | VSymbol s ->
      (match field with
      | "path" ->
          (match !Ast.node_resolver s with
           | Some (VComputedNode cn) -> VString cn.cn_path
           | Some (VNode _) -> VString "<unbuilt>"
           | _ -> Error.make_error KeyError (Printf.sprintf "Symbol `%s` has no field `path` (and no built node with this name was found)." s))
      | _ -> Error.make_error Ast.KeyError (Printf.sprintf "Symbol has no field `%s`" field))
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
  | VComputedNode cn ->
      (match field with
      | "name" -> VString cn.cn_name
      | "runtime" -> VString cn.cn_runtime
      | "path" -> VString cn.cn_path
      | "serializer" -> VString cn.cn_serializer
      | "class" -> VString cn.cn_class
      | "dependencies" -> VList (List.map (fun d -> (None, VString d)) cn.cn_dependencies)
      | _ -> Error.make_error Ast.KeyError (Printf.sprintf "ComputedNode has no field `%s`" field))
  | VNode un ->
      (match field with
      | "command" -> VString (Nix_unparse.unparse_expr un.un_command)
      | "script" -> (match un.un_script with Some p -> VString p | None -> (VNA NAGeneric))
      | "runtime" -> VString un.un_runtime
      | "path" -> VString "<unbuilt>"
      | "serializer" -> VString (Nix_unparse.unparse_expr un.un_serializer)
      | "deserializer" -> VString (Nix_unparse.unparse_expr un.un_deserializer)
      | "args" -> VDict un.un_args
      | "shell" -> (match un.un_shell with Some s -> VString s | None -> (VNA NAGeneric))
      | "shell_args" -> VList (List.map (fun e -> (None, VString (Nix_unparse.unparse_expr e))) un.un_shell_args)
      | "noop" -> VBool un.un_noop
      | _ -> Error.make_error Ast.KeyError (Printf.sprintf "Node has no field `%s`" field))
  | VSerializer s ->
      (match field with
      | "writer" -> s.s_writer
      | "reader" -> s.s_reader
      | "format" -> VString s.s_format
      | "r_writer" -> (match s.s_r_writer with Some sw -> VRawCode sw | None -> (VNA NAGeneric))
      | "r_reader" -> (match s.s_r_reader with Some sr -> VRawCode sr | None -> (VNA NAGeneric))
      | "py_writer" -> (match s.s_py_writer with Some sw -> VRawCode sw | None -> (VNA NAGeneric))
      | "py_reader" -> (match s.s_py_reader with Some sr -> VRawCode sr | None -> (VNA NAGeneric))
      | _ -> Error.make_error Ast.KeyError (Printf.sprintf "Serializer has no field `%s`" field))
  | VShellResult sr ->
      (match field with
      | "stdout"    -> VString sr.sr_stdout
      | "stderr"    -> VString sr.sr_stderr
      | "exit_code" -> VInt sr.sr_exit_code
      | _ -> Error.make_error Ast.KeyError
               (Printf.sprintf "ShellResult has no field `%s`. Available fields: stdout, stderr, exit_code." field))
  | VError _ as e -> e
  | VNA _ -> Error.type_error "Cannot access field on NA."
  | other -> Error.type_error (Printf.sprintf "Cannot access field `%s` on %s." field (Utils.type_name other))

and lambda_arity_error params args =
  Error.arity_error (List.length params) (List.length args)

and eval_call env_ref fn_val raw_args =
  let current_builtin_name =
    match fn_val with
    | VBuiltin { b_name; _ } -> b_name
    | _ -> None
  in
  let make_row_lambda body =
    Ast.mk_expr (Lambda {
      params = ["row"];
      param_types = [None];
      return_type = None;
      generic_params = [];
      variadic = false;
      body;
      env = None;
    })
  in
  (* NSE auto-transformation: if an argument is a complex expression containing
     ColumnRef nodes (not a bare ColumnRef), wrap it in a lambda \(row) <desugared>
     before evaluation. Bare ColumnRef stays as-is (evaluates to VSymbol). *)
  let transform_nse_args args =
    List.map (fun (name, expr) ->
      let loc = expr.loc in
      match expr.node with
      | Call { fn = { node = Var "n"; _ }; args = [] }
        when current_builtin_name = Some "summarize" && Option.is_some name ->
          (name, make_row_lambda (Ast.mk_expr (Call { fn = varexpr "n"; args = [(None, varexpr "row")] })))
      | ColumnRef _ -> (name, expr)  (* bare $col → keep, evaluates to VSymbol *)
      | Call { fn = { node = Var "__dynamic_arg__"; _ }; args = [n_arg; (v_name, v_expr)] } ->
          (* Support NSE inside the value part of a dynamic argument (!!name := <NSE>) *)
          if uses_nse v_expr then
            let desugared = desugar_nse_expr v_expr in
            (name, Ast.mk_expr ?loc (Call { fn = Ast.mk_expr ?loc (Var "__dynamic_arg__"); 
                                           args = [n_arg; (v_name, make_row_lambda desugared)] }))
          else
            (name, expr)
      | ListLit items when List.for_all (fun (_, e) -> match e.node with ColumnRef _ -> true | _ -> false) items ->
          (name, expr) (* list of bare $cols → keep as-is *)
      | _ when uses_nse expr ->
          (* Complex expression with NSE → wrap in lambda, EXCEPT for positional (unnamed)
             Call expressions. A positional Call like select_node(p, $name, $runtime) passed
             as an argument to colnames/nrow must be evaluated directly: its own eval_call
             will handle the inner ColumnRef args as VSymbol values. Named Call expressions
             (e.g. mutate($count = nrow($dept))) still need lambda wrapping to maintain
             proper NSE row context in mutate/summarize. *)
          (match name, expr.node with
           | None, Call _ -> (name, expr)
           | None, BinOp { op = (Pipe | MaybePipe); _ } -> (name, expr)
            | _ ->
               let desugared = desugar_nse_expr expr in
               (name, make_row_lambda desugared))
      | _ -> (name, expr)
    ) args
  in
  let raw_args = transform_nse_args raw_args in

  (* Special case: rm() needs to capture symbols before evaluation to remove variables by name.
     Without this, rm(x) evaluates x to its value and then tries to remove a variable 
     named with that VALUE (e.g. if x="val", it removes variable "val", not "x").
     This also handles the R-style rm(list = ...) named argument. *)
  if current_builtin_name = Some "rm" then (
    List.iter (fun (arg_name, e) ->
      match arg_name with
      | Some "list" ->
          let v = eval_expr env_ref e in
          (match v with
           | VList items ->
               List.iter (fun (_, item) ->
                 match extract_name_opt item with
                 | Some s -> env_ref := Env.remove s !env_ref
                 | None -> ()) items
           | _ ->
               (match extract_name_opt v with
                | Some s -> env_ref := Env.remove s !env_ref
                | None -> ()))
      | _ ->
          match e.node with
          | Var s -> env_ref := Env.remove s !env_ref
          | ColumnRef s -> env_ref := Env.remove ("$" ^ s) !env_ref
          | _ ->
              let v = eval_expr env_ref e in
              (match extract_name_opt v with
               | Some s -> env_ref := Env.remove s !env_ref
               | None -> ())
    ) raw_args;
    (VNA NAGeneric)
  ) else begin

  let rec process_args_spliced acc = function
    | [] -> acc
    | (name, e) :: rest ->
        let v = match e.node with
          | Call { fn = { node = Var "__dynamic_arg__"; _ }; args = [(_, name_expr); (_, value_expr)] } ->
              let n_val = eval_expr env_ref name_expr in
              (match extract_name_opt n_val with
               | None -> make_error TypeError (Printf.sprintf "!! := requires a String or Symbol as the left-hand name, got %s" (Utils.type_name n_val))
               | Some n -> VDynamicArg (n, eval_expr env_ref value_expr))
          | _ -> eval_expr env_ref e
        in
        match v with
        | VUnquote inner -> process_args_spliced (acc @ [(name, inner)]) rest
        | VUnquoteSplice sv ->
            let units = match sv with
              | VList items -> items
              | VVector vx -> Array.to_list vx |> List.map (fun x -> (None, x))
              | VDict d -> List.map (fun (k, v) -> (Some k, v)) d
              | _ -> [(name, sv)]
            in
            process_args_spliced (acc @ units) rest
        | VDynamicArg (n, v) ->
            process_args_spliced (acc @ [(Some n, v)]) rest
        | _ -> process_args_spliced (acc @ [(name, v)]) rest
  in

  let named_args = process_args_spliced [] raw_args in

  match fn_val with
  | VBuiltin { b_arity; b_variadic; b_func; _ } ->
      let arg_count = List.length named_args in
      if not b_variadic && arg_count <> b_arity then
        Error.arity_error b_arity arg_count
      else
        b_func named_args env_ref

  | VLambda { params; param_types; return_type; variadic; body; env = Some closure_env; _ } ->
      let args_vals = List.map snd named_args in
      let n_params = List.length params in
      let n_args = List.length args_vals in
      if (not variadic && n_params <> n_args) || (variadic && n_args < n_params) then
        lambda_arity_error params args_vals
      else
        (* Runtime Type Check: Arguments (fixed-arity part) *)
        let fixed_args = if n_args > n_params then List.filteri (fun i _ -> i < n_params) args_vals else args_vals in
        let type_errors = List.filter_map (fun (v, t_opt) ->
          match t_opt with
          | Some t when not (Ast.is_compatible v t) ->
              let expected = Ast.Utils.typ_to_string t in
              let got = Ast.Utils.type_name v in
              Some (Printf.sprintf "Expected %s, got %s" expected got)
          | _ -> None
        ) (List.combine fixed_args param_types) in

        if type_errors <> [] then
          Error.type_error (String.concat "; " type_errors)
        else
          let call_env =
            List.fold_left2
              (fun current_env name value -> Env.add name value current_env)
              closure_env params fixed_args
          in
          (* Bind expressions for enquo() — also store the caller's env for quosure capture *)
          let caller_env = !env_ref in
          let call_raw_args = List.map snd raw_args in
          let call_env = List.fold_left2 (fun acc name e ->
            Env.add ("__q_" ^ name) (VExpr e) acc
          ) call_env params (if List.length call_raw_args > n_params then List.filteri (fun i _ -> i < n_params) call_raw_args else call_raw_args) in
          let call_env = Env.add "__q_caller_env__" (VEnv caller_env) call_env in

          (* Handle variadic ... *)
          let call_env = if variadic then
             let dots_vals = if n_args > n_params then List.filteri (fun i _ -> i >= n_params) args_vals |> List.map (fun v -> (None, v)) else [] in
             let dots_exprs = if n_args > n_params then List.filteri (fun i _ -> i >= n_params) raw_args |> List.map (fun (n, e) -> (n, VExpr e)) else [] in
             let env = Env.add "..." (VList dots_vals) call_env in
             Env.add "__q_dots" (VList dots_exprs) env
          else call_env in

          let call_env_ref = ref call_env in
          let result = eval_expr call_env_ref body in
          (* Runtime Type Check: Return Value *)
          (match return_type with
           | Some t when not (Error.is_error_value result) && not (Ast.is_compatible result t) ->
               let expected = Ast.Utils.typ_to_string t in
               let got = Ast.Utils.type_name result in
               Error.type_error (Printf.sprintf "Function returned %s, but expected %s" got expected)
           | _ -> result)

  | VLambda { params; param_types; return_type; variadic; body; env = None; _ } ->
      (* Lambda without closure — use current env *)
      let args_vals = List.map snd named_args in
      let n_params = List.length params in
      let n_args = List.length args_vals in
      if (not variadic && n_params <> n_args) || (variadic && n_args < n_params) then
        lambda_arity_error params args_vals
      else
        (* Runtime Type Check: Arguments (fixed-arity part) *)
        let fixed_args = if n_args > n_params then List.filteri (fun i _ -> i < n_params) args_vals else args_vals in
        let type_errors = List.filter_map (fun (v, t_opt) ->
          match t_opt with
          | Some t when not (Ast.is_compatible v t) ->
              let expected = Ast.Utils.typ_to_string t in
              let got = Ast.Utils.type_name v in
              Some (Printf.sprintf "Expected %s, got %s" expected got)
          | _ -> None
        ) (List.combine fixed_args param_types) in

        if type_errors <> [] then
          Error.type_error (String.concat "; " type_errors)
        else
          let call_env =
            List.fold_left2
              (fun current_env name value -> Env.add name value current_env)
              !env_ref params fixed_args
          in
          (* Bind expressions for enquo() — also store the caller's env for quosure capture *)
          let caller_env = !env_ref in
          let call_raw_args = List.map snd raw_args in
          let call_env = List.fold_left2 (fun acc name e ->
            Env.add ("__q_" ^ name) (VExpr e) acc
          ) call_env params (if List.length call_raw_args > n_params then List.filteri (fun i _ -> i < n_params) call_raw_args else call_raw_args) in
          let call_env = Env.add "__q_caller_env__" (VEnv caller_env) call_env in

          (* Handle variadic ... *)
          let call_env = if variadic then
             let dots_vals = if n_args > n_params then List.filteri (fun i _ -> i >= n_params) args_vals |> List.map (fun v -> (None, v)) else [] in
             let dots_exprs = if n_args > n_params then List.filteri (fun i _ -> i >= n_params) raw_args |> List.map (fun (n, e) -> (n, VExpr e)) else [] in
             let env = Env.add "..." (VList dots_vals) call_env in
             Env.add "__q_dots" (VList dots_exprs) env
          else call_env in

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
           (* Special case: symbols starting with $ are column references.
              Wrap them in a row-accessor lambda so they are callable by verbs (NSE). *)
           if String.length s > 0 && s.[0] = '$' then
             let field = String.sub s 1 (String.length s - 1) in
             let fn = VLambda { params = ["row"]; param_types = [None]; return_type = None; generic_params = []; variadic = false;
                               body = Ast.mk_expr (DotAccess { target = Ast.mk_expr (Var "row"); field }); env = Some !env_ref } in
             eval_call env_ref fn raw_args
           else
             let names = 
               Env.bindings !env_ref 
               |> List.filter (fun (name, v) -> 
                   match v with 
                   | VSymbol _ -> false 
                   | _ -> not (String.starts_with ~prefix:"__" name)
               )
               |> List.map fst 
             in
             match Ast.suggest_name s names with
               | Some suggestion -> Error.name_error_with_suggestion s suggestion
               | None -> Error.name_error s)

  (* Propagate the original error — the caller tried to invoke an error
     value as a function.  We keep the original error (not a generic
     TypeError) so that the root cause is visible.  Example:
       x = 1 / 0; x(1)  →  Error(DivisionByZero: ...) *)
  | VExpr e ->
      (* Calling an expression value: evaluate it.
         If exactly one VDict argument is provided, use it as a data mask.
         We add both the plain key and the '$'-prefixed key to support ColumnRef lookup. *)
      let env_to_use = match named_args with
        | [(_, VDict d)] -> 
            let merged = List.fold_left (fun acc (k, v) -> 
              Env.add k v (Env.add ("$" ^ k) v acc)
            ) !env_ref d in
            ref merged
        | _ -> env_ref
      in
      eval_expr env_to_use e
  | VQuo { q_expr; q_env } ->
      (* Calling a quosure: evaluate in its captured environment.
         If exactly one VDict argument is provided, use it as a data mask overlay.
         We add both the plain key and the '$'-prefixed key to support ColumnRef lookup. *)
      let env_to_use = match named_args with
        | [(_, VDict d)] -> 
            let merged = List.fold_left (fun acc (k, v) -> 
              Env.add k v (Env.add ("$" ^ k) v acc)
            ) q_env d in
            ref merged
        | _ -> ref q_env
      in
      eval_expr env_to_use q_expr
  | VError _ as e -> e
  | VNA _ -> Error.type_error "Cannot call NA as a function."
  | _ -> Error.not_callable_error (Utils.type_name fn_val)
  end

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
         match right.node with
         | Call { fn; args } ->
             (* Insert pipe value as first argument *)
             let fn_val = eval_expr env_ref fn in
             eval_call env_ref fn_val ((None, vexpr lval) :: args)
         | _ ->
             (* RHS is a bare function name or expression *)
             let fn_val = eval_expr env_ref right in
             eval_call env_ref fn_val [(None, vexpr lval)]
      )
  | MaybePipe ->
      let lval = eval_expr env_ref left in
      (* Unconditional pipe — always forward, even errors *)
      (match right.node with
       | Call { fn; args } ->
           let fn_val = eval_expr env_ref fn in
           eval_call env_ref fn_val ((None, vexpr lval) :: args)
       | _ ->
           let fn_val = eval_expr env_ref right in
           eval_call env_ref fn_val [(None, vexpr lval)]
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
  | (Plus | Minus | Mul | Div | Mod | Lt | Gt | LtEq | GtEq), _, _ ->
      (match lval, rval with
       | VNDArray _, _ | _, VNDArray _
       | Ast.VVector _, _ | _, Ast.VVector _
       | Ast.VList _, _ | _, Ast.VList _ -> 
          let op_str = match op with
            | Plus -> "+" | Minus -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%"
            | Lt -> "<" | Gt -> ">" | LtEq -> "<=" | GtEq -> ">="
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
  let (v, env') =
    match stmt.node with
    | Expression e ->
        let env_ref = ref env in
        let v = eval_expr env_ref e in
        (match e.node with
         | ShellExpr _ ->
             (match v with
              | VShellResult sr -> print_string sr.sr_stdout; flush stdout; ((VNA NAGeneric), !env_ref)
              | _ -> (v, !env_ref))
         | _ -> (v, !env_ref))
    | Assignment { name; expr; _ } ->
        if Env.mem name env then
          let msg = Printf.sprintf "Cannot reassign immutable variable '%s'. Use ':=' to overwrite or rm() to delete the variable." name in
          (make_error NameError msg, env)
        else
          let env_ref = ref env in
          let v = eval_expr env_ref expr in
          let new_env = Env.add name v !env_ref in
          (match v with
           | VError _ -> (v, new_env)
           | _ -> ((VNA NAGeneric), new_env))
    | Reassignment { name; expr } ->
        if not (Env.mem name env) then
          let msg = Printf.sprintf "Cannot overwrite '%s': variable not defined. Use '=' for first assignment." name in
          (make_error NameError msg, env)
        else
          let env_ref = ref env in
          let v = eval_expr env_ref expr in
          if !show_warnings then begin
            Printf.eprintf "Warning: overwriting variable '%s'\n" name;
            flush stderr
          end;
          let new_env = Env.add name v !env_ref in
          (match v with
           | VError _ -> (v, new_env)
           | _ -> ((VNA NAGeneric), new_env))
    | Import filename ->
        (try
          let ch = open_in filename in
          let content = really_input_string ch (in_channel_length ch) in
          close_in ch;
          let lexbuf = Lexing.from_string content in
          lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
          (try
            let program = Parser.program Lexer.token lexbuf in
            let (_v, new_env) = eval_program program env in
            current_imports := !current_imports @ [Ast.mk_stmt (Import filename)];
            ((VNA NAGeneric), new_env)
          with
          | Lexer.SyntaxError msg ->
              let pos = Lexing.lexeme_start_p lexbuf in
              (make_error
                 ~location:(source_location ~file:filename pos)
                 SyntaxError
                 (Printf.sprintf "Import syntax error in '%s': %s" filename msg),
               env)
          | Parser.Error ->
              let pos = Lexing.lexeme_start_p lexbuf in
              (make_error
                 ~location:(source_location ~file:filename pos)
                 SyntaxError
                 (Printf.sprintf "Import parse error in '%s'" filename),
               env))
        with
        | Sys_error msg ->
            (make_error FileError (Printf.sprintf "Import failed: %s" msg), env))
    | ImportPackage pkg_name ->
        if is_standard_package pkg_name then begin
          current_imports := !current_imports @ [Ast.mk_stmt (ImportPackage pkg_name)];
          ((VNA NAGeneric), env)
        end else
        (match Package_loader.load_package ~do_eval_program:eval_program pkg_name env with
         | Ok new_env ->
              current_imports := !current_imports @ [Ast.mk_stmt (ImportPackage pkg_name)];
              ((VNA NAGeneric), new_env)
          | Error msg -> (make_error FileError msg, env))
    | ImportFrom { package; names } ->
        (match Package_loader.load_package_selective ~do_eval_program:eval_program package names env with
         | Ok new_env ->
             current_imports := !current_imports @ [Ast.mk_stmt (ImportFrom { package; names })];
             ((VNA NAGeneric), new_env)
         | Error msg -> (make_error FileError msg, env))
    | ImportFileFrom { filename; names } ->
        (try
          let ch = open_in filename in
          let content = really_input_string ch (in_channel_length ch) in
          close_in ch;
          let lexbuf = Lexing.from_string content in
          lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
          (try
            let program = Parser.program Lexer.token lexbuf in
            let (_v, temp_env) = eval_program program env in
            let new_bindings = 
              Env.fold (fun name value acc ->
                if Env.mem name env then acc
                else (name, value) :: acc
              ) temp_env []
            in
            
            let result_env_ref = ref env in
            let missing_names = ref [] in
            
            List.iter (fun (spec : Ast.import_spec) ->
              match List.assoc_opt spec.import_name new_bindings with
              | None -> missing_names := spec.import_name :: !missing_names
              | Some value ->
                  let target_name = match spec.import_alias with
                    | Some alias -> alias
                    | None -> spec.import_name
                  in
                  result_env_ref := Env.add target_name value !result_env_ref
            ) names;
            
            if !missing_names <> [] then
              let msg = Printf.sprintf "Name(s) not found in '%s': %s" filename (String.concat ", " (List.rev !missing_names)) in
              (make_error NameError msg, env)
            else begin
              current_imports := !current_imports @ [Ast.mk_stmt (ImportFileFrom { filename; names })];
              ((VNA NAGeneric), !result_env_ref)
            end
          with
          | Lexer.SyntaxError msg ->
              let pos = Lexing.lexeme_start_p lexbuf in
              (make_error
                 ~location:(source_location ~file:filename pos)
                 SyntaxError
                 (Printf.sprintf "Import syntax error in '%s': %s" filename msg),
               env)
          | Parser.Error ->
              let pos = Lexing.lexeme_start_p lexbuf in
              (make_error
                 ~location:(source_location ~file:filename pos)
                 SyntaxError
                 (Printf.sprintf "Import parse error in '%s'" filename),
               env))
        with
        | Sys_error msg ->
            (make_error FileError (Printf.sprintf "Import failed: %s" msg), env))
  in
  (attach_stmt_location stmt v, env')

and eval_program (program : program) (env : environment) : value * environment =
  let rec go env = function
    | [] -> ((VNA NAGeneric), env)
    | [stmt] -> eval_statement env stmt
    | stmt :: rest ->
        let (v, new_env) = eval_statement env stmt in
        (match v with
         | VError _ -> (v, new_env)
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
