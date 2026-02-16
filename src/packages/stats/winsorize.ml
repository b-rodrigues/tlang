open Ast

(*
--# Winsorize values
--#
--# Clamp tails to specified quantile limits.
--#
--# @name winsorize
--# @param x :: Vector | List Numeric input.
--# @param limits :: Float | Vector[Float] One-sided or (lo, hi) limits in [0, 0.5).
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
    | VNA _ -> Error (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
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
        | VNA _ :: _ -> Error (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
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
  Env.add "winsorize" (make_builtin ~name:"winsorize" 2 (fun args _ ->
    let limits_of = function
      | VFloat f when f >= 0.0 && f < 0.5 -> Some (f, f)
      | VInt i when i >= 0 -> let f = float_of_int i in if f < 0.5 then Some (f, f) else None
      | VList [(_, VFloat lo); (_, VFloat hi)] when lo >= 0.0 && hi >= 0.0 && lo < 0.5 && hi < 0.5 -> Some (lo, hi)
      | VVector [|VFloat lo; VFloat hi|] when lo >= 0.0 && hi >= 0.0 && lo < 0.5 && hi < 0.5 -> Some (lo, hi)
      | _ -> None
    in
    match args with
    | [x; limits] ->
        (match numeric_values ~label:"winsorize" ~na_rm:false x, limits_of limits with
         | Error e, _ -> e
         | _, None -> Error.value_error "Function `winsorize` expects limits in [0, 0.5)."
         | Ok [], _ -> VNA NAFloat
         | Ok xs, Some (lo, hi) ->
             let lq = Option.get (quantile xs lo) in
             let uq = Option.get (quantile xs (1.0 -. hi)) in
             vecf (List.map (fun v -> if v < lq then lq else if v > uq then uq else v) xs))
    | _ -> Error.arity_error_named "winsorize" ~expected:2 ~received:(List.length args))) env
