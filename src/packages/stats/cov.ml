open Ast

(*
--# Covariance
--#
--# Compute sample covariance of two numeric vectors.
--#
--# @name cov
--# @param x :: Vector | List First numeric input.
--# @param y :: Vector | List Second numeric input.
--# @param na_rm :: Bool = false Pairwise remove NA values.
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

let paired_numeric_values ~label ~na_rm x y =
  let to_arr = function
    | VVector arr -> Ok arr
    | VList items -> Ok (Array.of_list (List.map snd items))
    | VNA _ -> Error (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
    | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` expects two numeric Vectors or Lists." label))
  in
  match (to_arr x, to_arr y) with
  | Ok ax, Ok ay ->
      if Array.length ax <> Array.length ay then Error (Error.value_error (Printf.sprintf "Function `%s` requires vectors of equal length." label))
      else
        let rec loop i xs ys =
          if i = Array.length ax then Ok (List.rev xs, List.rev ys)
          else
            match (ax.(i), ay.(i)) with
            | VInt a, VInt b -> loop (i + 1) (float_of_int a :: xs) (float_of_int b :: ys)
            | VInt a, VFloat b -> loop (i + 1) (float_of_int a :: xs) (b :: ys)
            | VFloat a, VInt b -> loop (i + 1) (a :: xs) (float_of_int b :: ys)
            | VFloat a, VFloat b -> loop (i + 1) (a :: xs) (b :: ys)
            | (VNA _, _) | (_, VNA _) when na_rm -> loop (i + 1) xs ys
            | (VNA _, _) | (_, VNA _) -> Error (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
            | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        in
        loop 0 [] []
  | Error e, _ | _, Error e -> Error e

let register env =
  Env.add "cov" (make_builtin_named ~name:"cov" ~variadic:true 2 (fun named_args _ ->
    let na_rm = has_na_rm named_args in
    match strip_na_rm named_args with
    | [x; y] ->
        (match paired_numeric_values ~label:"cov" ~na_rm x y with
         | Error e -> e
         | Ok (xs, ys) ->
             let n = List.length xs in
             if n = 0 then VNA NAFloat
             else if n < 2 then Error.value_error "Function `cov` requires at least 2 paired values."
             else
               let mx = Option.get (mean xs) in
               let my = Option.get (mean ys) in
               VFloat (List.fold_left2 (fun a xv yv -> a +. (xv -. mx) *. (yv -. my)) 0.0 xs ys /. float_of_int (n - 1)))
    | args -> Error.arity_error_named "cov" ~expected:2 ~received:(List.length args))) env
