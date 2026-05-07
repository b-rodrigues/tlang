open Ast

(*
--# Excess kurtosis
--#
--# Compute fourth standardized moment minus 3.
--#
--# @name kurtosis
--# @param x :: Vector | List Numeric input.
--# @param na_rm :: Bool = false Remove NA values first.
--# @param weight :: Vector[Float] | List[Float] = NA Optional non-negative observation weights.
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
  Env.add "kurtosis" (make_builtin_named ~name:"kurtosis" ~variadic:true 1 (fun named_args _ ->
    let na_rm = has_na_rm named_args in
    let weight_arg = List.assoc_opt (Some "weight") named_args in
    let args =
      named_args
      |> List.filter (fun (name, _) -> name <> Some "na_rm" && name <> Some "weight")
      |> List.map snd
    in
    match args with
    | [x] ->
        (match weight_arg with
         | Some weight_v ->
             (match Math_utils.extract_numeric_array_with_weights ~label:"kurtosis" ~na_rm x weight_v with
              | Error e -> e
              | Ok (xs, ws) ->
                  if Array.length xs < 4 then Error.value_error "Function `kurtosis` requires at least 4 values."
                  else
                    (match (Math_utils.weighted_central_moment xs ws 2.0, Math_utils.weighted_central_moment xs ws 4.0) with
                     | Some m2, Some _ when m2 = 0.0 -> VFloat (-3.0)
                     | Some m2, Some m4 -> VFloat (m4 /. (m2 *. m2) -. 3.0)
                     | _ -> Error.make_error RuntimeError "Function `kurtosis` internal error: weighted moments could not be computed."))
         | None ->
             (match numeric_values ~label:"kurtosis" ~na_rm x with
              | Error e -> e
              | Ok xs ->
                  let n = List.length xs in
                  if n < 4 then Error.value_error "Function `kurtosis` requires at least 4 values."
                  else
                    match mean xs with
                    | None -> Error.make_error RuntimeError "Function `kurtosis` internal error: mean returned None for non-empty list."
                    | Some m ->
                    let m2 = List.fold_left (fun a v -> let d = v -. m in a +. d *. d) 0.0 xs /. float_of_int n in
                    if m2 = 0.0 then VFloat (-3.0)
                    else
                      let m4 = List.fold_left (fun a v -> let d = v -. m in a +. d *. d *. d *. d) 0.0 xs /. float_of_int n in
                      VFloat (m4 /. (m2 *. m2) -. 3.0)))
    | args -> Error.arity_error_named "kurtosis" 1 (List.length args))) env
