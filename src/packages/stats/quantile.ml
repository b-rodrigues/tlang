open Ast

let register ~make_builtin ~make_error env =
  Env.add "quantile"
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
      let get_p = function
        | VFloat f -> if f < 0.0 || f > 1.0 then None else Some f
        | VInt 0 -> Some 0.0
        | VInt 1 -> Some 1.0
        | _ -> None
      in
      let compute_quantile nums p =
        let n = Array.length nums in
        if n = 0 then make_error ValueError "quantile() called on empty data"
        else begin
          let sorted = Array.copy nums in
          Array.sort compare sorted;
          let h = p *. float_of_int (n - 1) in
          let lo = int_of_float (Float.floor h) in
          let hi = min (lo + 1) (n - 1) in
          let frac = h -. float_of_int lo in
          VFloat (sorted.(lo) +. frac *. (sorted.(hi) -. sorted.(lo)))
        end
      in
      match args with
      | [VVector arr; p_val] ->
          (match get_p p_val with
           | None -> make_error ValueError "quantile() expects a probability between 0 and 1"
           | Some p ->
             (match extract_nums_arr "quantile" arr with
              | Error e -> e
              | Ok nums -> compute_quantile nums p))
      | [VList items; p_val] ->
          (match get_p p_val with
           | None -> make_error ValueError "quantile() expects a probability between 0 and 1"
           | Some p ->
             let arr = Array.of_list (List.map snd items) in
             (match extract_nums_arr "quantile" arr with
              | Error e -> e
              | Ok nums -> compute_quantile nums p))
      | [VNA _; _] | [_; VNA _] -> make_error TypeError "quantile() encountered NA value. Handle missingness explicitly."
      | [_; _] -> make_error TypeError "quantile() expects a numeric List or Vector as first argument"
      | _ -> make_error ArityError "quantile() takes exactly 2 arguments"
    ))
    env
