open Ast

(** Try to vectorize a filter predicate.
    Detects simple patterns like \(row) row.col > scalar and uses
    Arrow_compute.compare_column_scalar for zero-copy filtering.
    Also handles AND/OR combinations of simple comparisons. *)
let try_vectorize_filter (table : Arrow_table.t) (fn : value) : bool array option =
  match fn with
  | VLambda { params = [param]; body; _ } ->
    let extract_scalar = function
      | VInt i -> Some (float_of_int i)
      | VFloat f -> Some f
      | _ -> None
    in
    let null_mask field =
      match Arrow_table.get_column table field with
      | Some (Arrow_table.IntColumn a) ->
          Some (Array.map (function None -> true | Some _ -> false) a)
      | Some (Arrow_table.FloatColumn a) ->
          Some (Array.map (function None -> true | Some _ -> false) a)
      | Some (Arrow_table.BoolColumn a) ->
          Some (Array.map (function None -> true | Some _ -> false) a)
      | Some (Arrow_table.StringColumn a) ->
          Some (Array.map (function None -> true | Some _ -> false) a)
      | Some (Arrow_table.DateColumn a) ->
          Some (Array.map (function None -> true | Some _ -> false) a)
      | Some (Arrow_table.DatetimeColumn (a, _)) ->
          Some (Array.map (function None -> true | Some _ -> false) a)
      | Some (Arrow_table.DictionaryColumn (a, _, _)) ->
          Some (Array.map (function None -> true | Some _ -> false) a)
      | Some (Arrow_table.ListColumn a) ->
          Some (Array.map (function None -> true | Some _ -> false) a)
      | Some (Arrow_table.NullColumn n) ->
          Some (Array.make n true)
      | None -> None
    in
    let try_cmp op left right =
      let op_name = match op with
        | Gt -> Some "gt" | Lt -> Some "lt" | GtEq -> Some "ge"
        | LtEq -> Some "le" | Eq -> Some "eq" | _ -> None
      in
      match op_name with
      | None -> None
      | Some op_s ->
        (* Pattern: row.field op scalar *)
        (match left, right with
         | DotAccess { target = Var p; field }, Value scalar when p = param ->
           (match extract_scalar scalar with
            | Some sf -> Arrow_compute.compare_column_scalar table field sf op_s
            | None -> None)
         (* Pattern: scalar op row.field → flip comparison *)
         | Value scalar, DotAccess { target = Var p; field } when p = param ->
           let flipped_op = match op_s with
             | "gt" -> "lt" | "lt" -> "gt" | "ge" -> "le" | "le" -> "ge"
             | other -> other
           in
           (match extract_scalar scalar with
            | Some sf -> Arrow_compute.compare_column_scalar table field sf flipped_op
            | None -> None)
         | _ -> None)
    in
    (* Recursively try to vectorize an expression, handling AND/OR *)
    let rec try_vectorize_expr expr =
      match expr with
      | UnOp { op = Not; operand } ->
        (match try_vectorize_expr operand with
         | Some mask ->
           let n = Array.length mask in
           Some (Array.init n (fun i -> not mask.(i)))
         | None -> None)
      | Call { fn = Var "is_na";
               args = [(None, DotAccess { target = Var p; field })] }
          when p = param ->
        null_mask field
      | BinOp { op; left; right } ->
        (match op with
         | And ->
            (* Pattern: predA && predB — intersect boolean masks *)
            (match try_vectorize_expr left, try_vectorize_expr right with
            | Some mask_l, Some mask_r ->
              let n = min (Array.length mask_l) (Array.length mask_r) in
              Some (Array.init n (fun i -> mask_l.(i) && mask_r.(i)))
            | _ -> None)
         | Or ->
           (* Pattern: predA || predB — union boolean masks *)
           (match try_vectorize_expr left, try_vectorize_expr right with
            | Some mask_l, Some mask_r ->
              let n = min (Array.length mask_l) (Array.length mask_r) in
              Some (Array.init n (fun i -> mask_l.(i) || mask_r.(i)))
            | _ -> None)
         | _ -> try_cmp op left right)
      | _ -> None
    in
    try_vectorize_expr body
  | _ -> None

let register ~eval_call ~eval_expr:(_eval_expr : Ast.value Ast.Env.t -> Ast.expr -> Ast.value) ~uses_nse:(_uses_nse : Ast.expr -> bool) ~desugar_nse_expr:(_desugar_nse_expr : Ast.expr -> Ast.expr) env =
  (*
  --# Filter rows
  --#
  --# Retains rows that satisfy the predicate function.
  --#
  --# @name filter
  --# @param df :: DataFrame The input DataFrame.
  --# @param predicate :: Function A function returning Bool for each row.
  --# @return :: DataFrame The filtered DataFrame.
  --# @example
  --#   filter(mtcars, \(row) -> row.mpg > 20)
  --# @family colcraft
  --# @seealso select, arrange
  --# @export
  *)
  Env.add "filter"
    (make_builtin ~name:"filter" 2 (fun args env ->
      match args with
      | [VDataFrame df; fn] ->
          (* Try vectorized path first for simple predicates *)
          (match try_vectorize_filter df.arrow_table fn with
           | Some keep ->
             let new_table = Arrow_compute.filter df.arrow_table keep in
             VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
           | None ->
             (* Fall back to row-by-row evaluation *)
             let nrows = Arrow_table.num_rows df.arrow_table in
             let keep = Array.make nrows false in
             let had_error = ref None in
             for i = 0 to nrows - 1 do
               if !had_error = None then begin
                 let row_dict = VDict (Arrow_bridge.row_to_dict df.arrow_table i) in
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
                let new_table = Arrow_compute.filter df.arrow_table keep in
                VDataFrame { arrow_table = new_table; group_keys = df.group_keys }))
      | [VDataFrame _] -> make_error ArityError "Function `filter` requires a DataFrame and a predicate function."
      | [_; _] -> make_error TypeError "Function `filter` expects a DataFrame as first argument."
      | _ -> make_error ArityError "Function `filter` takes exactly 2 arguments."
    ))
    env
