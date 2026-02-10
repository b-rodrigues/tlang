open Ast

let register env =
  Env.add "sd"
    (make_builtin_named ~variadic:true 1 (fun named_args _env ->
      let na_rm = List.exists (fun (name, v) ->
        name = Some "na_rm" && (match v with VBool true -> true | _ -> false)
      ) named_args in
      let args = List.filter (fun (name, _) -> name <> Some "na_rm") named_args |> List.map snd in
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
      let extract_nums_arr_na_rm label arr =
        let nums = ref [] in
        let had_error = ref None in
        for i = 0 to Array.length arr - 1 do
          if !had_error = None then
            match arr.(i) with
            | VInt n -> nums := float_of_int n :: !nums
            | VFloat f -> nums := f :: !nums
            | VNA _ -> ()
            | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values"))
        done;
        match !had_error with Some e -> Error e | None -> Ok (Array.of_list (List.rev !nums))
      in
      let compute_sd nums n =
        if n < 2 then make_error ValueError "sd() requires at least 2 values"
        else
          let mean = Array.fold_left ( +. ) 0.0 nums /. float_of_int n in
          let sum_sq = Array.fold_left (fun acc x -> acc +. (x -. mean) *. (x -. mean)) 0.0 nums in
          VFloat (Float.sqrt (sum_sq /. float_of_int (n - 1)))
      in
      let first_arg = match args with a :: _ -> Some a | [] -> None in
      match first_arg with
      | Some (VList items) ->
          let arr = Array.of_list (List.map snd items) in
          if na_rm then
            (match extract_nums_arr_na_rm "sd" arr with
             | Error e -> e
             | Ok nums when Array.length nums = 0 -> VNA NAFloat
             | Ok nums -> compute_sd nums (Array.length nums))
          else
            (match extract_nums_arr "sd" arr with
             | Error e -> e
             | Ok nums -> compute_sd nums (Array.length nums))
      | Some (VVector arr) ->
          if na_rm then
            (match extract_nums_arr_na_rm "sd" arr with
             | Error e -> e
             | Ok nums when Array.length nums = 0 -> VNA NAFloat
             | Ok nums -> compute_sd nums (Array.length nums))
          else
            (match extract_nums_arr "sd" arr with
             | Error e -> e
             | Ok nums -> compute_sd nums (Array.length nums))
      | Some (VNA _) -> make_error TypeError "sd() encountered NA value. Handle missingness explicitly."
      | Some _ -> make_error TypeError "sd() expects a numeric List or Vector"
      | None -> make_error ArityError "sd() takes exactly 1 argument"
    ))
    env
