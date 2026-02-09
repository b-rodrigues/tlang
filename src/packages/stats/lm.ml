open Ast

let register env =
  Env.add "lm"
    (make_builtin 3 (fun args _env ->
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
          (match (Arrow_table.get_column df.arrow_table y_col, Arrow_table.get_column df.arrow_table x_col) with
           | (None, _) -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" y_col)
           | (_, None) -> make_error KeyError (Printf.sprintf "Column '%s' not found in DataFrame" x_col)
           | (Some y_col_data, Some x_col_data) ->
             let y_arr = Arrow_bridge.column_to_values y_col_data in
             let x_arr = Arrow_bridge.column_to_values x_col_data in
             let nrows = Arrow_table.num_rows df.arrow_table in
             if nrows < 2 then
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
    ))
    env
