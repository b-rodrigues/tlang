open Ast

let register env =
  Env.add "cor"
    (make_builtin_named ~variadic:true 2 (fun named_args _env ->
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
      let pairwise_delete arr1 arr2 =
        let n = Array.length arr1 in
        let xs = ref [] in
        let ys = ref [] in
        for i = 0 to n - 1 do
          match (arr1.(i), arr2.(i)) with
          | (VNA _, _) | (_, VNA _) -> ()
          | _ -> xs := arr1.(i) :: !xs; ys := arr2.(i) :: !ys
        done;
        (Array.of_list (List.rev !xs), Array.of_list (List.rev !ys))
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
             else if na_rm then
               let (clean1, clean2) = pairwise_delete arr1 arr2 in
               if Array.length clean1 < 2 then
                 if Array.length clean1 = 0 then VNA NAFloat
                 else make_error ValueError "cor() requires at least 2 non-NA pairs"
               else
                 (match (extract_nums_arr "cor" clean1, extract_nums_arr "cor" clean2) with
                  | (Error e, _) | (_, Error e) -> e
                  | (Ok xs, Ok ys) ->
                    match Arrow_owl_bridge.pearson_cor xs ys with
                    | None ->
                      make_error ValueError "cor() undefined: one or both vectors have zero variance"
                    | Some r -> VFloat r)
             else if Array.length arr1 < 2 then
               make_error ValueError "cor() requires at least 2 values"
             else
               (match (extract_nums_arr "cor" arr1, extract_nums_arr "cor" arr2) with
                | (Error e, _) | (_, Error e) -> e
                | (Ok xs, Ok ys) ->
                  match Arrow_owl_bridge.pearson_cor xs ys with
                  | None ->
                    make_error ValueError "cor() undefined: one or both vectors have zero variance"
                  | Some r -> VFloat r))
      | _ -> make_error ArityError "cor() takes exactly 2 arguments"
    ))
    env
