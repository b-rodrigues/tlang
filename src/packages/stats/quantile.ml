open Ast

(*
--# Quantiles
--#
--# Computes the quantile of a distribution at a specified probability.
--#
--# @name quantile
--# @param x :: Vector | List The numeric data.
--# @param probs :: Float The probability (0 to 1).
--# @param na_rm :: Bool (Optional) Should missing values be removed? Default is false.
--# @return :: Float The quantile value.
--# @example
--#   quantile(x, 0.5)
--#   -- Returns median
--# @family stats
--# @seealso median, mean
--# @export
*)
let register env =
  Env.add "quantile"
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
            | VNA _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
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
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        done;
        match !had_error with Some e -> Error e | None -> Ok (Array.of_list (List.rev !nums))
      in
      let get_p = function
        | VFloat f -> if f < 0.0 || f > 1.0 then None else Some f
        | VInt 0 -> Some 0.0
        | VInt 1 -> Some 1.0
        | _ -> None
      in
      let compute_quantile nums p =
        let n = Array.length nums in
        if n = 0 then Error.value_error "Function `quantile` called on empty data."
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
           | None -> Error.value_error "Function `quantile` expects a probability between 0 and 1."
           | Some p ->
             if na_rm then
               (match extract_nums_arr_na_rm "quantile" arr with
                | Error e -> e
                | Ok nums when Array.length nums = 0 -> VNA NAFloat
                | Ok nums -> compute_quantile nums p)
             else
               (match extract_nums_arr "quantile" arr with
                | Error e -> e
                | Ok nums -> compute_quantile nums p))
      | [VList items; p_val] ->
          (match get_p p_val with
           | None -> Error.value_error "Function `quantile` expects a probability between 0 and 1."
           | Some p ->
             let arr = Array.of_list (List.map snd items) in
             if na_rm then
               (match extract_nums_arr_na_rm "quantile" arr with
                | Error e -> e
                | Ok nums when Array.length nums = 0 -> VNA NAFloat
                | Ok nums -> compute_quantile nums p)
             else
               (match extract_nums_arr "quantile" arr with
                | Error e -> e
                | Ok nums -> compute_quantile nums p))
      | [VNA _; _] | [_; VNA _] -> Error.type_error "Function `quantile` encountered NA value. Handle missingness explicitly."
      | [_; _] -> Error.type_error "Function `quantile` expects a numeric List or Vector as first argument."
      | _ -> Error.arity_error_named "quantile" ~expected:2 ~received:(List.length args)
    ))
    env
