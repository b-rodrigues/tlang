open Ast

(*
--# Median
--#
--# Compute median of numeric values.
--#
--# @name median
--# @param x :: Vector | List Numeric input.
--# @param na_rm :: Bool = false Remove NA values first.
--# @param weights :: Vector[Float] | List[Float] = NA Optional non-negative observation weights.
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

let register env =
  Env.add "median" (make_builtin_named ~name:"median" ~variadic:true 1 (fun named_args _ ->
    match Math_common.get_bool_flag "na_rm" false named_args with
    | Error e -> e
    | Ok na_rm ->
    let args = Math_common.positional_args_without ["na_rm"; "weights"] named_args in
    let weight_arg = List.assoc_opt (Some "weights") named_args in
    match args with
    | [x] ->
        (match weight_arg with
         | Some weight_v ->
             (match Math_utils.extract_numeric_array_with_weights ~label:"median" ~na_rm x weight_v with
              | Error e -> e
              | Ok (xs, ws) ->
                  (match Math_utils.weighted_quantile_array xs ws 0.5 with
                   | Some v -> VFloat v
                   | None -> VNA NAFloat))
         | None ->
             (match numeric_values ~label:"median" ~na_rm x with
              | Error e -> e
              | Ok [] -> VNA NAFloat
              | Ok xs ->
                  (match quantile xs 0.5 with
                   | Some v -> VFloat v
                   | None -> VNA NAFloat)))
    | args -> Error.arity_error_named "median" 1 (List.length args))) env
