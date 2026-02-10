open Ast

(** Extract single variable name from formula side *)
let extract_single_var (vars : string list) (side : string) (fn : string)
    : (string, value) result =
  match vars with
  | [v] -> Ok v
  | [] -> Error (make_error ValueError
      (Printf.sprintf "%s() %s side of formula is empty" fn side))
  | _ -> Error (make_error ValueError
      (Printf.sprintf "%s() only supports single-variable formulas, got: %s"
        fn (String.concat " + " vars)))

let register env =
  Env.add "lm"
    (make_builtin_named ~variadic:true 0 (fun args _env ->
      let named = List.filter_map (fun (n, v) ->
        match n with Some name -> Some (name, v) | None -> None
      ) args in
      let positional = List.filter_map (fun (n, v) ->
        match n with None -> Some v | Some _ -> None
      ) args in
      (* Get required arguments: try named first, fall back to positional *)
      let data_val = match List.assoc_opt "data" named with
        | Some v -> Some v
        | None -> (match positional with v :: _ -> Some v | [] -> None)
      in
      let formula_val = match List.assoc_opt "formula" named with
        | Some v -> Some v
        | None -> (match positional with _ :: v :: _ -> Some v | _ -> None)
      in
      match (data_val, formula_val) with
      | (None, _) -> make_error ArityError "lm() missing required argument 'data'"
      | (_, None) -> make_error ArityError "lm() missing required argument 'formula'"
      | (Some data_v, Some formula_v) ->
        match (data_v, formula_v) with
        | (VDataFrame df, VFormula { response; predictors; _ }) ->
          (match (extract_single_var response "left" "lm",
                  extract_single_var predictors "right" "lm") with
           | (Error e, _) | (_, Error e) -> e
           | (Ok y_col, Ok x_col) ->
             (* Check columns exist *)
             (match (Arrow_table.get_column df.arrow_table y_col,
                     Arrow_table.get_column df.arrow_table x_col) with
              | (None, _) ->
                  make_error KeyError
                    (Printf.sprintf "Column '%s' not found in DataFrame" y_col)
              | (_, None) ->
                  make_error KeyError
                    (Printf.sprintf "Column '%s' not found in DataFrame" x_col)
              | (Some _, Some _) ->
                let nrows = Arrow_table.num_rows df.arrow_table in
                if nrows < 2 then
                  make_error ValueError "lm() requires at least 2 observations"
                else
                  (* Use Arrow-Owl bridge for numeric column extraction *)
                  match (Arrow_owl_bridge.numeric_column_to_owl df.arrow_table y_col,
                         Arrow_owl_bridge.numeric_column_to_owl df.arrow_table x_col) with
                  | (None, _) | (_, None) ->
                    make_error TypeError
                      "lm() requires numeric columns without NA values"
                  | (Some y_view, Some x_view) ->
                    let ys = y_view.arr in
                    let xs = x_view.arr in
                    (* Delegate computation to Arrow_owl_bridge *)
                    (match Arrow_owl_bridge.linreg xs ys with
                     | None ->
                       make_error ValueError
                         "lm() cannot fit model: predictor has zero variance"
                     | Some (intercept, slope, r_squared) ->
                       let resid = Arrow_owl_bridge.residuals xs ys intercept slope in
                       let n = Array.length xs in
                       VDict [
                         ("formula", formula_v);
                         ("intercept", VFloat intercept);
                         ("slope", VFloat slope);
                         ("r_squared", VFloat r_squared);
                         ("residuals", VVector (Array.map (fun r -> VFloat r) resid));
                         ("n", VInt n);
                         ("response", VString y_col);
                         ("predictor", VString x_col);
                       ])))
        | (VDataFrame _, _) ->
            make_error TypeError "lm() 'formula' must be a Formula (use ~ operator)"
        | (_, _) ->
            make_error TypeError "lm() 'data' must be a DataFrame"
    ))
    env
