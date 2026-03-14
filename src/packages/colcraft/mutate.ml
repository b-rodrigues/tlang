open Ast

(** Scalar literals extracted from AST nodes for vectorized mutate lowering.
    Keeping integer and float literals distinct preserves integer arithmetic
    semantics for operations like Int column + Int scalar. *)
type scalar_literal =
  | IntScalar of int
  | FloatScalar of float

let extract_scalar expr =
  match expr.node with
  | Value (VInt i) -> Some (IntScalar i)
  | Value (VFloat f) -> Some (FloatScalar f)
  | _ -> None

let is_col_ref param expr =
  match expr.node with
  | DotAccess { target = { node = Var p; _ }; field } when p = param -> Some field
  | ColumnRef field -> Some field
  | _ -> None

let binary_col_op_fn = function
  | Plus -> Some Arrow_compute.add_columns_to_table
  | Mul ->  Some Arrow_compute.multiply_columns_to_table
  | Minus -> Some Arrow_compute.subtract_columns_to_table
  | Div ->  Some Arrow_compute.divide_columns_to_table
  | _ -> None

let scalar_op_fn = function
  | Plus -> Some Arrow_compute.add_scalar
  | Mul ->  Some Arrow_compute.multiply_scalar
  | Minus -> Some Arrow_compute.subtract_scalar
  | Div ->  Some Arrow_compute.divide_scalar
  | _ -> None

let try_vectorize_mutate (table : Arrow_table.t) (fn : value)
    (col_name : string) : Arrow_table.t option =
  match fn with
  | VLambda { params = [param]; body; _ } ->
    (* Temporary names must be unique across recursive subexpressions within a
       single mutate call so nested Arrow kernel results do not overwrite each
       other while the expression tree is being lowered. *)
    let temp_counter = ref 0 in
    let next_temp_column current_table =
      let rec find_unused idx =
        let candidate = Printf.sprintf "_mutate_tmp_%s_%d" col_name idx in
        if List.mem_assoc candidate current_table.Arrow_table.schema then
          find_unused (idx + 1)
        else begin
          temp_counter := idx + 1;
          candidate
        end
      in
      find_unused !temp_counter
    in
    let rec vectorize_expr current_table expr =
      match is_col_ref param expr with
      | Some col -> Some (current_table, col)
      | None ->
        match expr.node with
        | BinOp { op; left; right } ->
          let try_col_scalar source_table source_col scalar =
            let apply_table_result = function
              | Some result_table -> Some (result_table, source_col)
              | None -> None
            in
            match scalar with
            | IntScalar scalar_value ->
              (match op with
               | Plus -> apply_table_result (Arrow_compute.add_int_scalar source_table source_col scalar_value)
               | Mul -> apply_table_result (Arrow_compute.multiply_int_scalar source_table source_col scalar_value)
               | Minus -> apply_table_result (Arrow_compute.subtract_int_scalar source_table source_col scalar_value)
               | Div ->
                 (match scalar_op_fn op with
                  | Some f -> apply_table_result (f source_table source_col (float_of_int scalar_value))
                  | None -> None)
               | _ -> None)
            | FloatScalar scalar_value ->
              (match scalar_op_fn op with
               | Some f -> apply_table_result (f source_table source_col scalar_value)
               | None -> None)
          in
          (match is_col_ref param left, is_col_ref param right with
           | Some c1, Some c2 ->
             (match binary_col_op_fn op with
              | Some f ->
                let temp_col = next_temp_column current_table in
                (match f current_table c1 c2 temp_col with
                 | Some result_table -> Some (result_table, temp_col)
                 | None -> None)
              | None -> None)
           | Some src_col, None ->
             (match extract_scalar right with
              | Some scalar -> try_col_scalar current_table src_col scalar
              | None -> None)
           | None, Some src_col ->
             (match extract_scalar left with
              | Some scalar ->
                (match op with
                 | Plus | Mul -> try_col_scalar current_table src_col scalar
                 | _ -> None)
              | None -> None)
           | None, None ->
             (match vectorize_expr current_table left with
              | Some (left_table, left_col) ->
                (match extract_scalar right with
                 | Some scalar -> try_col_scalar left_table left_col scalar
                 | None ->
                   match vectorize_expr left_table right with
                   | Some (both_table, right_col) ->
                     (match binary_col_op_fn op with
                      | Some f ->
                        let temp_col = next_temp_column both_table in
                        (match f both_table left_col right_col temp_col with
                         | Some result_table -> Some (result_table, temp_col)
                         | None -> None)
                      | None -> None)
                   | None -> None)
              | None ->
                match extract_scalar left with
                | Some scalar ->
                  (match vectorize_expr current_table right with
                   | Some (right_table, right_col) ->
                     (match op with
                      | Plus | Mul -> try_col_scalar right_table right_col scalar
                      | _ -> None)
                   | None -> None)
                 | None -> None))
        | _ -> None
    in
    (match vectorize_expr table body with
     | Some (result_table, result_col) ->
       if result_col = col_name then Some result_table
       else
         Some (Arrow_table.add_column_from_table table col_name result_table result_col)
     | None ->
       None)
  | _ -> None

let register ~eval_call ~eval_expr:(_eval_expr : Ast.value Ast.Env.t -> Ast.expr -> Ast.value) ~uses_nse:(_uses_nse : Ast.expr -> bool) ~desugar_nse_expr:(_desugar_nse_expr : Ast.expr -> Ast.expr) env =
  (*
  --# Mutate DataFrame
  --#
  --# Adds new columns or modifies existing ones.
  --#
  --# @name mutate
  --# @param df :: DataFrame The input DataFrame.
  --# @param ... :: Expressions Key-value pairs of new columns.
  --# @return :: DataFrame The mutated DataFrame.
  --# @example
  --#   mutate(mtcars, $ratio = $mpg / $hp)
  --# @family colcraft
  --# @seealso summarize, select
  --# @export
  *)
  Env.add "mutate"
    (make_builtin_named ~name:"mutate" ~variadic:true 1 (fun named_args env ->
      let apply_mutation df col_name fn =
        let nrows = Arrow_table.num_rows df.arrow_table in
        if df.group_keys <> [] then
          let grouped = Arrow_compute.group_by df.arrow_table df.group_keys in
          let groups = Arrow_compute.get_ocaml_groups grouped in
          let new_col = Array.make nrows VNull in
          let had_error = ref None in
          List.iter (fun (_, row_indices) ->
            if !had_error = None then begin
              let sub_table = Arrow_compute.take_rows df.arrow_table row_indices in
              let sub_df = VDataFrame { arrow_table = sub_table; group_keys = [] } in
              let result = eval_call env fn [(None, Ast.mk_expr (Value sub_df))] in
              match result with
              | VError _ -> had_error := Some result
              | VVector vec when Array.length vec = List.length row_indices ->
                List.iteri (fun i idx -> new_col.(idx) <- vec.(i)) row_indices
              | _ ->
                List.iter (fun idx -> new_col.(idx) <- result) row_indices
            end
          ) groups;
          (match !had_error with
           | Some e -> e
           | None ->
             let arrow_col = Arrow_bridge.values_to_column new_col in
             let new_table = Arrow_table.add_column df.arrow_table col_name arrow_col in
             VDataFrame { arrow_table = new_table; group_keys = df.group_keys })
        else (
          match try_vectorize_mutate df.arrow_table fn col_name with
          | Some new_table ->
            VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
          | None ->
            let whole_result = eval_call env fn [(None, Ast.mk_expr (Value (VDataFrame df)))] in
            (match whole_result with
             | VVector vec when Array.length vec = nrows ->
               let arrow_col = Arrow_bridge.values_to_column vec in
               let new_table = Arrow_table.add_column df.arrow_table col_name arrow_col in
               VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
             | VList items when List.length items = nrows ->
               let vec = Array.of_list (List.map snd items) in
               let arrow_col = Arrow_bridge.values_to_column vec in
               let new_table = Arrow_table.add_column df.arrow_table col_name arrow_col in
               VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
             | res when not (is_na_value res) && (match res with VVector _ | VList _ | VNDArray _ | VError _ -> false | _ -> true) ->
               let vec = Array.make nrows res in
               let arrow_col = Arrow_bridge.values_to_column vec in
               let new_table = Arrow_table.add_column df.arrow_table col_name arrow_col in
               VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
             | _ ->
               let new_col = Array.init nrows (fun i ->
                 let row_dict = VDict (Arrow_bridge.row_to_dict df.arrow_table i) in
                 eval_call env fn [(None, Ast.mk_expr (Value row_dict))]
               ) in
               let first_error = ref None in
               Array.iter (fun v ->
                 if !first_error = None then
                   match v with VError _ -> first_error := Some v | _ -> ()
               ) new_col;
               (match !first_error with
                | Some e -> e
                | None ->
                  let arrow_col = Arrow_bridge.values_to_column new_col in
                  let new_table = Arrow_table.add_column df.arrow_table col_name arrow_col in
                  VDataFrame { arrow_table = new_table; group_keys = df.group_keys }))
        )
      in
      let apply_vector_mutation df col_name vec =
        let nrows = Arrow_table.num_rows df.arrow_table in
        if Array.length vec <> nrows then
          Error.value_error
            (Printf.sprintf "Function `mutate` vector length %d does not match DataFrame row count %d."
               (Array.length vec) nrows)
        else
          let arrow_col = Arrow_bridge.values_to_column vec in
          let new_table = Arrow_table.add_column df.arrow_table col_name arrow_col in
          VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
      in
      match named_args with
      | [] ->
          Error.arity_error_named "mutate" ~expected:2 ~received:0
      | (None, VDataFrame df) :: rest when rest <> [] ->
          let rec apply_named_mutations current_df = function
            | [] -> VDataFrame current_df
            | (Some col_name, VVector vec) :: rest_mutations ->
                (match apply_vector_mutation current_df col_name vec with
                 | VDataFrame new_df -> apply_named_mutations new_df rest_mutations
                 | err -> err)
            | (Some col_name, VList items) :: rest_mutations ->
                let vec = Array.of_list (List.map snd items) in
                (match apply_vector_mutation current_df col_name vec with
                 | VDataFrame new_df -> apply_named_mutations new_df rest_mutations
                 | err -> err)
            | (Some col_name, fn) :: rest_mutations ->
                (match apply_mutation current_df col_name fn with
                 | VDataFrame new_df -> apply_named_mutations new_df rest_mutations
                 | err -> err)
            | (None, _) :: _ ->
                Error.type_error "Function `mutate` expects $column = expr syntax."
          in
          apply_named_mutations df rest

      | [(None, VDataFrame _)] ->
          Error.arity_error_named "mutate" ~expected:2 ~received:1
      | (None, VDataFrame _) :: (None, _) :: _ ->
          Error.type_error "Function `mutate` expects named arguments for new columns (e.g. $col = expr)."
      | _ ->
          Error.type_error "Function `mutate` expects a DataFrame as first argument."
    ))
    env
