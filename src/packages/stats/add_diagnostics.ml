open Ast

(** add_diagnostics(model, data = df) — adds diagnostic columns to the data.
    Equivalent to broom::augment(). Adds columns prefixed with '.' *)
let register env =
  Env.add "add_diagnostics"
    (make_builtin_named ~variadic:true 0 (fun args _env ->
      let named = List.filter_map (fun (n, v) ->
        match n with Some name -> Some (name, v) | None -> None
      ) args in
      let positional = List.filter_map (fun (n, v) ->
        match n with None -> Some v | Some _ -> None
      ) args in
      (* First positional or named "model" *)
      let model_val = match List.assoc_opt "model" named with
        | Some v -> Some v
        | None -> (match positional with v :: _ -> Some v | [] -> None)
      in
      (* Second positional or named "data" — optional, falls back to _original_data *)
      let data_val = match List.assoc_opt "data" named with
        | Some v -> Some v
        | None -> (match positional with _ :: v :: _ -> Some v | _ -> None)
      in
      match model_val with
      | None -> Error.make_error ArityError "Function `add_diagnostics` missing required argument 'model'."
      | Some (VDict pairs) ->
        (match List.assoc_opt "_model_data" pairs with
         | Some (VDict model) ->
           (* Get the data DataFrame *)
           let df = match data_val with
             | Some (VDataFrame df) -> Some df
             | None ->
               (match List.assoc_opt "_original_data" pairs with
                | Some (VDataFrame df) -> Some df
                | _ -> None)
             | _ -> None
           in
           (match df with
            | None -> Error.type_error "Function `add_diagnostics` requires a DataFrame for 'data'."
            | Some data_df ->
              let nrows = Arrow_table.num_rows data_df.arrow_table in
              (* Extract diagnostic arrays from model_data *)
              let extract_float_array key =
                match List.assoc_opt key model with
                | Some (VVector arr) ->
                  Array.map (fun v -> match v with VFloat f -> Some f | _ -> None) arr
                | _ -> Array.make nrows None
              in
              let fitted_arr = extract_float_array "fitted_values" in
              let resid_arr = extract_float_array "residuals" in
              let hat_arr = extract_float_array "hat_values" in
              let cooksd_arr = extract_float_array "cooks_distance" in
              let std_resid_arr = extract_float_array "std_residuals" in
              let sigma_arr = extract_float_array "leave_one_out_sigma" in
              (* Add columns to the DataFrame *)
              let table = data_df.arrow_table in
              let table = Arrow_table.add_column table ".fitted"
                (Arrow_table.FloatColumn fitted_arr) in
              let table = Arrow_table.add_column table ".resid"
                (Arrow_table.FloatColumn resid_arr) in
              let table = Arrow_table.add_column table ".hat"
                (Arrow_table.FloatColumn hat_arr) in
              let table = Arrow_table.add_column table ".sigma"
                (Arrow_table.FloatColumn sigma_arr) in
              let table = Arrow_table.add_column table ".cooksd"
                (Arrow_table.FloatColumn cooksd_arr) in
              let table = Arrow_table.add_column table ".std_resid"
                (Arrow_table.FloatColumn std_resid_arr) in
              VDataFrame { arrow_table = table; group_keys = data_df.group_keys })
         | _ ->
           Error.type_error "Function `add_diagnostics` expects a model returned by `lm`.")
      | Some _ ->
        Error.type_error "Function `add_diagnostics` expects a model returned by `lm`."
    ))
    env
