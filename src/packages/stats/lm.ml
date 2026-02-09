open Ast

let register env =
  Env.add "lm"
    (make_builtin 3 (fun args _env ->
      match args with
      | [VDataFrame df; VString y_col; VString x_col] ->
          (* Check columns exist *)
          (match (Arrow_table.get_column df.arrow_table y_col, Arrow_table.get_column df.arrow_table x_col) with
           | (None, _) -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" y_col)
           | (_, None) -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" x_col)
           | (Some _, Some _) ->
             let nrows = Arrow_table.num_rows df.arrow_table in
             if nrows < 2 then
               make_error ValueError "lm() requires at least 2 observations"
             else
               (* Use Arrow-Owl bridge for numeric column extraction *)
               match (Arrow_owl_bridge.numeric_column_to_owl df.arrow_table y_col,
                      Arrow_owl_bridge.numeric_column_to_owl df.arrow_table x_col) with
               | (None, _) | (_, None) ->
                 make_error TypeError "lm() requires numeric columns without NA values"
               | (Some y_view, Some x_view) ->
                 let ys = y_view.arr in
                 let xs = x_view.arr in
                 (* Delegate computation to Arrow_owl_bridge *)
                 (match Arrow_owl_bridge.linreg xs ys with
                  | None ->
                    make_error ValueError "lm() cannot fit model: predictor has zero variance"
                  | Some (intercept, slope, r_squared) ->
                    let resid = Arrow_owl_bridge.residuals xs ys intercept slope in
                    let n = Array.length xs in
                    VDict [
                      ("intercept", VFloat intercept);
                      ("slope", VFloat slope);
                      ("r_squared", VFloat r_squared);
                      ("residuals", VVector (Array.map (fun r -> VFloat r) resid));
                      ("n", VInt n);
                      ("response", VString y_col);
                      ("predictor", VString x_col);
                    ]))
      | [VDataFrame _; VString _; VNA _] | [VDataFrame _; VNA _; _] | [VNA _; _; _] ->
          make_error TypeError "lm() encountered NA value. Handle missingness explicitly."
      | [VDataFrame _; _; _] -> make_error TypeError "lm() expects string column names"
      | [_; _; _] -> make_error TypeError "lm() expects a DataFrame as first argument"
      | _ -> make_error ArityError "lm() takes exactly 3 arguments (DataFrame, y_column, x_column)"
    ))
    env
