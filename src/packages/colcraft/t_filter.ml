open Ast

let is_na_predicate_error = function
  | VError { code = NAPredicateError; _ } -> true
  | _ -> false

let plural_suffix count =
  if count = 1 then "" else "s"

let emit_na_filter_warning na_indices =
  match na_indices with
  | [] -> ()
  | _ when not !Eval.show_warnings -> ()
  | _ ->
      let indices = List.rev na_indices in
      let count = List.length indices in
      let rendered =
        indices |> List.map string_of_int |> String.concat ", "
      in
      Printf.eprintf
        "Warning: filter() excluded %d row%s because the predicate evaluated to NA at row%s %s. Consider handling NAs explicitly before filtering.\n%!"
        count
        (plural_suffix count)
        (plural_suffix count)
        rendered

type vectorized_predicate = {
  keep : bool array;
  na : bool array;
}

let min_array_len a b =
  min (Array.length a) (Array.length b)

let take_bool_array len arr =
  if Array.length arr = len then arr else Array.init len (fun i -> arr.(i))

let false_mask keep na =
  let len = min_array_len keep na in
  Array.init len (fun i -> (not keep.(i)) && not na.(i))

let na_indices_of_mask mask =
  let acc = ref [] in
  Array.iteri (fun i is_na ->
    if is_na then acc := (i + 1) :: !acc
  ) mask;
  !acc

let vectorized_compare table field scalar op_s =
  match Arrow_compute.compare_column_scalar table field scalar op_s with
  | None -> None
  | Some keep ->
      let len = Array.length keep in
      let na =
        match Arrow_compute.column_null_mask table field with
        | Some mask -> take_bool_array len mask
        | None -> Array.make len false
      in
      Some { keep; na }

(** Try to vectorize a filter predicate.
    Detects simple patterns like \(row) row.col > scalar and uses
    Arrow_compute.compare_column_scalar for zero-copy filtering.
    Also handles AND/OR combinations of simple comparisons. *)
let try_vectorize_filter (table : Arrow_table.t) (fn : value)
    : vectorized_predicate option =
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
        (match left.node, right.node with
         | DotAccess { target = { node = Var p; _ }; field }, Value scalar when p = param ->
            (match extract_scalar scalar with
             | Some sf -> vectorized_compare table field sf op_s
             | None -> None)
         (* Pattern: scalar op row.field → flip comparison *)
         | Value scalar, DotAccess { target = { node = Var p; _ }; field } when p = param ->
           let flipped_op = match op_s with
             | "gt" -> "lt" | "lt" -> "gt" | "ge" -> "le" | "le" -> "ge"
             | other -> other
            in
            (match extract_scalar scalar with
             | Some sf -> vectorized_compare table field sf flipped_op
             | None -> None)
         | _ -> None)
    in
    (* Recursively try to vectorize an expression, handling AND/OR *)
    let rec try_vectorize_expr expr =
      match expr.node with
      | UnOp { op = Not; operand } ->
        (match try_vectorize_expr operand with
         | Some { keep; na } ->
           let n = min_array_len keep na in
           Some {
             keep = Array.init n (fun i -> (not keep.(i)) && not na.(i));
             na = take_bool_array n na;
           }
          | None -> None)
      | Call { fn = { node = Var "is_na"; _ };
               args = [(None, { node = DotAccess { target = { node = Var p; _ }; field }; _ })] }
           when p = param ->
        (match Arrow_compute.column_null_mask table field with
         | Some keep -> Some { keep; na = Array.make (Array.length keep) false }
         | None -> None)
      | BinOp { op; left; right } ->
        (match op with
         | And ->
             (* Pattern: predA && predB — intersect boolean masks *)
             (match try_vectorize_expr left, try_vectorize_expr right with
              | Some left_pred, Some right_pred ->
                let n = min_array_len left_pred.keep right_pred.keep in
                let left_keep = take_bool_array n left_pred.keep in
                let right_keep = take_bool_array n right_pred.keep in
                let left_na = take_bool_array n left_pred.na in
                let right_na = take_bool_array n right_pred.na in
                let right_needed =
                  Array.init n (fun i -> left_keep.(i) || left_na.(i))
                in
                Some {
                  keep = Array.init n (fun i -> left_keep.(i) && right_keep.(i));
                  na =
                    Array.init n (fun i ->
                      left_na.(i)
                      || (right_na.(i) && right_needed.(i)));
                }
             | _ -> None)
          | Or ->
            (* Pattern: predA || predB — union boolean masks *)
            (match try_vectorize_expr left, try_vectorize_expr right with
              | Some left_pred, Some right_pred ->
                let n = min_array_len left_pred.keep right_pred.keep in
                let left_keep = take_bool_array n left_pred.keep in
                let right_keep = take_bool_array n right_pred.keep in
                let left_na = take_bool_array n left_pred.na in
                let right_na = take_bool_array n right_pred.na in
                let left_false = false_mask left_keep left_na in
                Some {
                  keep = Array.init n (fun i -> left_keep.(i) || right_keep.(i));
                  na =
                    (* Matches interpreter short-circuit OR: left-side NA always
                       propagates; right-side NA only propagates when the left
                       side is false (so the right predicate would be evaluated). *)
                    Array.init n (fun i ->
                      left_na.(i) || (right_na.(i) && left_false.(i)));
                }
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
           | Some { keep; na } ->
             emit_na_filter_warning (na_indices_of_mask na);
             let new_table = Arrow_compute.filter df.arrow_table keep in
             VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
           | None ->
             (* Fall back to row-by-row evaluation *)
              let nrows = Arrow_table.num_rows df.arrow_table in
              let keep = Array.make nrows false in
              let had_error = ref None in
              let na_indices = ref [] in
              for i = 0 to nrows - 1 do
                if !had_error = None then begin
                  let row_dict = VDict (Arrow_bridge.row_to_dict df.arrow_table i) in
                  let result = eval_call env fn [(None, Ast.mk_expr (Value row_dict))] in
                  match result with
                  | VBool true -> keep.(i) <- true
                  | VBool false -> ()
                  | VNA _ ->
                      na_indices := (i + 1) :: !na_indices
                  | VError _ when is_na_predicate_error result ->
                      na_indices := (i + 1) :: !na_indices
                  | VError _ as e -> had_error := Some e
                  | _ -> had_error := Some (make_error TypeError "filter() predicate must return a Bool")
                end
              done;
              (match !had_error with
               | Some e -> e
               | None ->
                 emit_na_filter_warning !na_indices;
                 let new_table = Arrow_compute.filter df.arrow_table keep in
                 VDataFrame { arrow_table = new_table; group_keys = df.group_keys }))
      | [VDataFrame _] -> make_error ArityError "Function `filter` requires a DataFrame and a predicate function."
      | [_; _] -> make_error TypeError "Function `filter` expects a DataFrame as first argument."
      | _ -> make_error ArityError "Function `filter` takes exactly 2 arguments."
    ))
    env
