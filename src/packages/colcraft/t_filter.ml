open Ast

(** Try to vectorize a filter predicate.
    Detects simple patterns like \(row) row.col > scalar and uses
    Arrow_compute.compare_column_scalar for zero-copy filtering. *)
let try_vectorize_filter (table : Arrow_table.t) (fn : value) : bool array option =
  match fn with
  | VLambda { params = [param]; body; _ } ->
    let extract_scalar = function
      | VInt i -> Some (float_of_int i)
      | VFloat f -> Some f
      | _ -> None
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
    (match body with
     | BinOp { op; left; right } -> try_cmp op left right
     | _ -> None)
  | _ -> None

let register ~eval_call env =
  Env.add "filter"
    (make_builtin 2 (fun args env ->
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
      | [VDataFrame _] -> make_error ArityError "filter() requires a DataFrame and a predicate function"
      | [_; _] -> make_error TypeError "filter() expects a DataFrame as first argument"
      | _ -> make_error ArityError "filter() takes exactly 2 arguments"
    ))
    env
