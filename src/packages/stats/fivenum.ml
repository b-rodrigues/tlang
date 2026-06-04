open Ast

(*
--# Five-number summary
--#
--# Return min, Q1, median, Q3, max.
--#
--# @name fivenum
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

let mean xs =
  let n = List.length xs in
  if n = 0 then None else Some (List.fold_left ( +. ) 0.0 xs /. float_of_int n)

let fivenum_tukey xs =
  let arr = Array.of_list xs in
  Array.sort compare arr;
  let n = Array.length arr in
  if n = 0 then None
  else if n = 1 then Some (arr.(0), arr.(0), arr.(0), arr.(0), arr.(0))
  else
    let get_val depth =
      let floor_d = int_of_float (Float.floor depth) in
      let ceil_d = int_of_float (Float.ceil depth) in
      let idx_lo = max 0 (floor_d - 1) in
      let idx_hi = min (n - 1) (ceil_d - 1) in
      0.5 *. (arr.(idx_lo) +. arr.(idx_hi))
    in
    let d2 = float_of_int (n + 1) /. 2.0 in
    let d1 = (Float.floor d2 +. 1.0) /. 2.0 in
    let mn = arr.(0) in
    let mx = arr.(n - 1) in
    let med = get_val d2 in
    let lh = get_val d1 in
    let uh = get_val (float_of_int (n + 1) -. d1) in
    Some (mn, lh, med, uh, mx)

let vecf xs = VVector (Array.of_list (List.map (fun x -> VFloat x) xs))

let register env =
  Env.add "fivenum" (make_builtin_named ~name:"fivenum" ~variadic:true 1 (fun named_args _ ->
    let na_rm = has_na_rm named_args in
    let weight_arg = Math_common.optional_named_arg "weights" named_args in
    let args =
      named_args
      |> List.filter (fun (name, _) -> name <> Some "na_rm" && name <> Some "weights")
      |> List.map snd
    in
    match args with
    | [x] ->
        (match weight_arg with
         | Some weight_v ->
             (match Math_utils.extract_numeric_array_with_weights ~label:"fivenum" ~na_rm x weight_v with
              | Error e -> e
              | Ok (xs, ws) ->
                  let mn = Array.fold_left min infinity xs in
                  let mx = Array.fold_left max neg_infinity xs in
                  (match Math_utils.weighted_quantile_array xs ws 0.25,
                         Math_utils.weighted_quantile_array xs ws 0.5,
                         Math_utils.weighted_quantile_array xs ws 0.75 with
                    | Some q1, Some med, Some q3 -> vecf [mn; q1; med; q3; mx]
                    | _ -> VNA NAFloat))
         | None ->
             (match numeric_values ~label:"fivenum" ~na_rm x with
              | Error e -> e
              | Ok [] -> VNA NAFloat
              | Ok xs ->
                  (match fivenum_tukey xs with
                   | Some (mn, lh, med, uh, mx) -> vecf [mn; lh; med; uh; mx]
                   | None -> VNA NAFloat)))
    | args -> Error.arity_error_named "fivenum" 1 (List.length args))) env
