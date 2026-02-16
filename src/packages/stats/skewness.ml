open Ast

(*
--# Skewness
--#
--# Compute third standardized moment.
--#
--# @name skewness
--# @param x :: Vector | List Numeric input.
--# @param na_rm :: Bool = false Remove NA values first.
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
  Env.add "skewness" (make_builtin_named ~name:"skewness" ~variadic:true 1 (fun named_args _ ->
    let na_rm = has_na_rm named_args in
    match strip_na_rm named_args with
    | [x] ->
        (match numeric_values ~label:"skewness" ~na_rm x with
         | Error e -> e
         | Ok xs ->
             let n = List.length xs in
             if n < 3 then Error.value_error "Function `skewness` requires at least 3 values."
             else
               let m = Option.get (mean xs) in
               let m2 = List.fold_left (fun a v -> let d = v -. m in a +. d *. d) 0.0 xs /. float_of_int n in
               if m2 = 0.0 then VFloat 0.0
               else
                 let m3 = List.fold_left (fun a v -> let d = v -. m in a +. d *. d *. d) 0.0 xs /. float_of_int n in
                 VFloat (m3 /. Float.pow m2 1.5))
    | args -> Error.arity_error_named "skewness" ~expected:1 ~received:(List.length args))) env
