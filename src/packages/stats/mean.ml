open Ast

let register ~make_builtin ~make_error env =
  Env.add "mean"
    (make_builtin 1 (fun args _env ->
      let extract_nums label vals =
        let rec go acc = function
          | [] -> Ok (List.rev acc)
          | (_, VInt n) :: rest -> go (float_of_int n :: acc) rest
          | (_, VFloat f) :: rest -> go (f :: acc) rest
          | (_, VNA _) :: _ -> Error (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
          | _ -> Error (make_error TypeError (label ^ "() requires numeric values"))
        in go [] vals
      in
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
      | [VList []] -> make_error ValueError "mean() called on empty list"
      | [VList items] ->
          (match extract_nums "mean" items with
           | Error e -> e
           | Ok nums ->
             let sum = List.fold_left ( +. ) 0.0 nums in
             VFloat (sum /. float_of_int (List.length nums)))
      | [VVector arr] when Array.length arr = 0 -> make_error ValueError "mean() called on empty vector"
      | [VVector arr] ->
          (match extract_nums_arr "mean" arr with
           | Error e -> e
           | Ok nums ->
             let sum = Array.fold_left ( +. ) 0.0 nums in
             VFloat (sum /. float_of_int (Array.length nums)))
      | [VNA _] -> make_error TypeError "mean() encountered NA value. Handle missingness explicitly."
      | [_] -> make_error TypeError "mean() expects a numeric List or Vector"
      | _ -> make_error ArityError "mean() takes exactly 1 argument"
    ))
    env
