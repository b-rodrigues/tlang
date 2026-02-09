open Ast

let register env =
  Env.add "max"
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
      match args with
      | [VList []] -> make_error ValueError "max() called on empty list"
      | [VList items] ->
          let arr = Array.of_list (List.map snd items) in
          (match extract_nums_arr "max" arr with
           | Error e -> e
           | Ok nums ->
             VFloat (Array.fold_left Float.max Float.neg_infinity nums))
      | [VVector arr] when Array.length arr = 0 -> make_error ValueError "max() called on empty vector"
      | [VVector arr] ->
          (match extract_nums_arr "max" arr with
           | Error e -> e
           | Ok nums ->
             VFloat (Array.fold_left Float.max Float.neg_infinity nums))
      | [VNA _] -> make_error TypeError "max() encountered NA value. Handle missingness explicitly."
      | [_] -> make_error TypeError "max() expects a numeric List or Vector"
      | _ -> make_error ArityError "max() takes exactly 1 argument"
    ))
    env
