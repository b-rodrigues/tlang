open Ast

let register env =
  Env.add "mean"
    (make_builtin_named ~variadic:true 1 (fun named_args _env ->
      (* Extract na_rm flag from named arguments *)
      let na_rm = List.exists (fun (name, v) ->
        name = Some "na_rm" && (match v with VBool true -> true | _ -> false)
      ) named_args in
      let args = List.filter (fun (name, _) -> name <> Some "na_rm") named_args |> List.map snd in
      let extract_nums label vals =
        let rec go acc = function
          | [] -> Ok (List.rev acc)
          | (_, VInt n) :: rest -> go (float_of_int n :: acc) rest
          | (_, VFloat f) :: rest -> go (f :: acc) rest
          | (_, VNA _) :: rest when na_rm -> go acc rest
          | (_, VNA _) :: _ -> Error (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
          | _ -> Error (make_error TypeError (label ^ "() requires numeric values"))
        in go [] vals
      in
      let extract_nums_arr_na_rm label arr =
        let nums = ref [] in
        let had_error = ref None in
        for i = 0 to Array.length arr - 1 do
          if !had_error = None then
            match arr.(i) with
            | VInt n -> nums := float_of_int n :: !nums
            | VFloat f -> nums := f :: !nums
            | VNA _ when na_rm -> ()
            | VNA _ -> had_error := Some (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
            | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values"))
        done;
        match !had_error with Some e -> Error e | None -> Ok (Array.of_list (List.rev !nums))
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
      let first_arg = match args with a :: _ -> Some a | [] -> None in
      match first_arg with
      | Some (VList []) -> make_error ValueError "mean() called on empty list"
      | Some (VList items) ->
          (match extract_nums "mean" items with
           | Error e -> e
           | Ok [] -> VNA NAFloat
           | Ok nums ->
             let sum = List.fold_left ( +. ) 0.0 nums in
             VFloat (sum /. float_of_int (List.length nums)))
      | Some (VVector arr) when Array.length arr = 0 -> make_error ValueError "mean() called on empty vector"
      | Some (VVector arr) ->
          if na_rm then
            (match extract_nums_arr_na_rm "mean" arr with
             | Error e -> e
             | Ok nums when Array.length nums = 0 -> VNA NAFloat
             | Ok nums ->
               let sum = Array.fold_left ( +. ) 0.0 nums in
               VFloat (sum /. float_of_int (Array.length nums)))
          else
            (match extract_nums_arr "mean" arr with
             | Error e -> e
             | Ok nums ->
               let sum = Array.fold_left ( +. ) 0.0 nums in
               VFloat (sum /. float_of_int (Array.length nums)))
      | Some (VNA _) -> make_error TypeError "mean() encountered NA value. Handle missingness explicitly."
      | Some _ -> make_error TypeError "mean() expects a numeric List or Vector"
      | None -> make_error ArityError "mean() takes exactly 1 argument"
    ))
    env
