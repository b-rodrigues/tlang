open Ast

(*
--# Correlation
--#
--# Computes the Pearson correlation coefficient between two vectors.
--#
--# @name cor
--# @param x :: Vector | List First numeric vector.
--# @param y :: Vector | List Second numeric vector.
--# @param na_rm :: Bool (Optional) Should missing values be removed? Default is false.
--# @return :: Float The correlation coefficient (-1 to 1).
--# @example
--#   cor(mtcars["mpg"], mtcars["wt"])
--# @family stats
--# @export
*)
let register env =
  Env.add "cor"
    (make_builtin_named ~name:"cor" ~variadic:true 2 (fun named_args _env ->
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
            | VNA _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
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
                | (VNA _, _) | (_, VNA _) -> Error.type_error "Function `cor` encountered NA value. Handle missingness explicitly."
                | _ -> Error.type_error "Function `cor` expects two numeric Vectors or Lists.")
           | (Some arr1, Some arr2) ->
             if Array.length arr1 <> Array.length arr2 then
               Error.value_error "Function `cor` requires vectors of equal length."
             else if na_rm then
               let (clean1, clean2) = pairwise_delete arr1 arr2 in
               if Array.length clean1 < 2 then
                 if Array.length clean1 = 0 then VNA NAFloat
                 else Error.value_error "Function `cor` requires at least 2 non-NA pairs."
               else
                 (match (extract_nums_arr "cor" clean1, extract_nums_arr "cor" clean2) with
                  | (Error e, _) | (_, Error e) -> e
                  | (Ok xs, Ok ys) ->
                    match Arrow_owl_bridge.pearson_cor xs ys with
                    | None ->
                      Error.value_error "Function `cor` undefined: one or both vectors have zero variance."
                    | Some r -> VFloat r)
             else if Array.length arr1 < 2 then
               Error.value_error "Function `cor` requires at least 2 values."
             else
               (match (extract_nums_arr "cor" arr1, extract_nums_arr "cor" arr2) with
                | (Error e, _) | (_, Error e) -> e
                | (Ok xs, Ok ys) ->
                  match Arrow_owl_bridge.pearson_cor xs ys with
                  | None ->
                    Error.value_error "Function `cor` undefined: one or both vectors have zero variance."
                  | Some r -> VFloat r))
      | _ -> Error.arity_error_named "cor" ~expected:2 ~received:(List.length args)
    ))
    env
