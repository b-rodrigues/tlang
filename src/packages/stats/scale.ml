open Ast

(*
--# Scale values
--#
--# Standardize to z-scores using sample standard deviation.
--#
--# @name scale
--# @param x :: Vector | List Numeric input.
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
  Env.add "scale" (make_builtin ~name:"scale" 1 (fun args _ ->
    match args with
    | [x] ->
        (match numeric_values ~label:"scale" ~na_rm:false x with
         | Error e -> e
         | Ok xs ->
             let n = List.length xs in
             if n < 2 then Error.value_error "Function `scale` requires at least 2 values."
             else
               let m = Option.get (mean xs) in
               let s = Float.sqrt (List.fold_left (fun a v -> let d = v -. m in a +. d *. d) 0.0 xs /. float_of_int (n - 1)) in
               if s = 0.0 then Error.value_error "Function `scale` undefined for zero-variance data."
               else vecf (List.map (fun v -> (v -. m) /. s) xs))
    | _ -> Error.arity_error_named "scale" ~expected:1 ~received:(List.length args))) env
