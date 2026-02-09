open Ast

let register env =
  Env.add "cor"
    (make_builtin 2 (fun args _env ->
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
            | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values"))
        done;
        match !had_error with Some e -> Error e | None -> Ok result
      in
      let to_arr = function
        | VVector arr -> Some arr
        | VList items -> Some (Array.of_list (List.map snd items))
        | _ -> None
      in
      match args with
      | [v1; v2] ->
          (match (to_arr v1, to_arr v2) with
           | (None, _) | (_, None) ->
               (match (v1, v2) with
                | (VNA _, _) | (_, VNA _) -> make_error TypeError "cor() encountered NA value. Handle missingness explicitly."
                | _ -> make_error TypeError "cor() expects two numeric Vectors or Lists")
           | (Some arr1, Some arr2) ->
             if Array.length arr1 <> Array.length arr2 then
               make_error ValueError "cor() requires vectors of equal length"
             else if Array.length arr1 < 2 then
               make_error ValueError "cor() requires at least 2 values"
             else
               (match (extract_nums_arr "cor" arr1, extract_nums_arr "cor" arr2) with
                | (Error e, _) | (_, Error e) -> e
                | (Ok xs, Ok ys) ->
                  (* Delegate computation to Arrow_owl_bridge *)
                  match Arrow_owl_bridge.pearson_cor xs ys with
                  | None ->
                    make_error ValueError "cor() undefined: one or both vectors have zero variance"
                  | Some r -> VFloat r))
      | _ -> make_error ArityError "cor() takes exactly 2 arguments"
    ))
    env
