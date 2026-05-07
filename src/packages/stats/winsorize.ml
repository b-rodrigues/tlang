open Ast

(*
--# Winsorize values
--#
--# Clamp tails to specified quantile limits.
--#
--# @name winsorize
--# @param x :: Vector | List Numeric input.
--# @param limits :: Float | Vector[Float] One-sided or (lo, hi) limits in [0, 0.5).
--# @param na_rm :: Bool = false Remove NA values first.
--# @param weights :: Vector[Float] | List[Float] = NA Optional non-negative observation weights used to determine the cut points.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family stats
--# @export
*)

let has_na_rm named_args =
  List.exists (fun (name, v) -> name = Some "na_rm" && match v with VBool true -> true | _ -> false) named_args

let strip_na_rm named_args =
  List.filter (fun (name, _) -> name <> Some "na_rm") named_args |> List.map snd

let numeric_values ~label ~na_rm v =
  let vals =
    match v with
    | VVector arr -> Ok (Array.to_list arr)
    | VList items -> Ok (List.map snd items)
    | VNA _ -> Error (Error.na_value_error ~na_rm:true label)
    | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` expects a numeric List or Vector." label))
  in
  match vals with
  | Error e -> Error e
  | Ok vals ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | VInt n :: tl -> go (float_of_int n :: acc) tl
        | VFloat f :: tl -> go (f :: acc) tl
        | VNA _ :: tl when na_rm -> go acc tl
        | VNA _ :: _ -> Error (Error.na_value_error ~na_rm:true label)
        | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
      in
      go [] vals

let quantile xs p =
  let arr = Array.of_list xs in
  let n = Array.length arr in
  if n = 0 then None
  else (
    Array.sort compare arr;
    let h = p *. float_of_int (n - 1) in
    let lo = int_of_float (Float.floor h) in
    let hi = min (lo + 1) (n - 1) in
    let frac = h -. float_of_int lo in
    Some (arr.(lo) +. frac *. (arr.(hi) -. arr.(lo))))

let mean xs =
  let n = List.length xs in
  if n = 0 then None else Some (List.fold_left ( +. ) 0.0 xs /. float_of_int n)

let vecf xs = VVector (Array.of_list (List.map (fun x -> VFloat x) xs))

let register env =
  Env.add "winsorize" (make_builtin_named ~name:"winsorize" ~variadic:true 2 (fun named_args _ ->
    match Math_common.get_bool_flag "na_rm" false named_args with
    | Error e -> e
    | Ok na_rm ->
        let weight_arg = Math_common.optional_named_arg "weights" named_args in
        let args = Math_common.positional_args_without ["na_rm"; "weights"] named_args in
        let limits_of = function
          | VFloat f when f >= 0.0 && f < 0.5 -> Some (f, f)
          | VInt i when i >= 0 -> let f = float_of_int i in if f < 0.5 then Some (f, f) else None
          | VList [(_, VFloat lo); (_, VFloat hi)] when lo >= 0.0 && hi >= 0.0 && lo < 0.5 && hi < 0.5 -> Some (lo, hi)
          | VVector [|VFloat lo; VFloat hi|] when lo >= 0.0 && hi >= 0.0 && lo < 0.5 && hi < 0.5 -> Some (lo, hi)
          | _ -> None
        in
        match args with
        | [x; limits] ->
            (match limits_of limits with
             | None -> Error.value_error "Function `winsorize` expects limits in [0, 0.5)."
             | Some (lo, hi) ->
                 (match weight_arg with
                  | Some weight_v ->
                       (match Math_utils.extract_numeric_array_with_weights_preserve_zeros ~label:"winsorize" ~na_rm x weight_v with
                        | Error e -> e
                        | Ok (xs, ws) when Array.length xs = 0 && Array.length ws = 0 -> VNA NAFloat
                        | Ok (xs, ws) ->
                            (match Math_utils.weighted_quantile_array xs ws lo,
                                   Math_utils.weighted_quantile_array xs ws (1.0 -. hi) with
                            | Some lq, Some uq ->
                                vecf
                                  (Array.to_list
                                     (Array.map
                                        (fun v ->
                                          if v < lq then lq
                                          else if v > uq then uq
                                          else v)
                                        xs))
                            | _ ->
                                Error.value_error "Function `winsorize` could not compute quantiles for the given input."))
                  | None ->
                      (match numeric_values ~label:"winsorize" ~na_rm x with
                       | Error e -> e
                       | Ok [] -> VNA NAFloat
                       | Ok xs ->
                           (match quantile xs lo, quantile xs (1.0 -. hi) with
                            | Some lq, Some uq ->
                                vecf (List.map (fun v -> if v < lq then lq else if v > uq then uq else v) xs)
                            | _ -> Error.value_error "Function `winsorize` could not compute quantiles for the given input."))))
        | _ -> Error.arity_error_named "winsorize" 2 (List.length args))) env
