open Ast

let register env =
  Env.add "sd"
    (make_builtin 1 (fun args _env ->
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
      let compute_sd nums n =
        if n < 2 then make_error ValueError "sd() requires at least 2 values"
        else
          let mean = Array.fold_left ( +. ) 0.0 nums /. float_of_int n in
          let sum_sq = Array.fold_left (fun acc x -> acc +. (x -. mean) *. (x -. mean)) 0.0 nums in
          VFloat (Float.sqrt (sum_sq /. float_of_int (n - 1)))
      in
      match args with
      | [VList items] ->
          let arr = Array.of_list (List.map snd items) in
          (match extract_nums_arr "sd" arr with
           | Error e -> e
           | Ok nums -> compute_sd nums (Array.length nums))
      | [VVector arr] ->
          (match extract_nums_arr "sd" arr with
           | Error e -> e
           | Ok nums -> compute_sd nums (Array.length nums))
      | [VNA _] -> make_error TypeError "sd() encountered NA value. Handle missingness explicitly."
      | [_] -> make_error TypeError "sd() expects a numeric List or Vector"
      | _ -> make_error ArityError "sd() takes exactly 1 argument"
    ))
    env
