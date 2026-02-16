open Ast

(*
--# Trimmed mean
--#
--# Compute mean after trimming both tails by fraction.
--#
--# @name trimmed_mean
--# @param x :: Vector | List Numeric input.
--# @param trim :: Float Trim proportion in [0, 0.5).
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family stats
--# @export
*)

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

let register env =
  Env.add "trimmed_mean" (make_builtin ~name:"trimmed_mean" 2 (fun args _ ->
    let trim_of = function VFloat f -> Some f | VInt i -> Some (float_of_int i) | _ -> None in
    match args with
    | [x; t] ->
        (match trim_of t with
         | None -> Error.type_error "Function `trimmed_mean` expects (x, trim) where trim is numeric."
         | Some trim when trim < 0.0 || trim >= 0.5 -> Error.value_error "Function `trimmed_mean` expects trim in [0, 0.5)."
         | Some trim ->
             (match numeric_values ~label:"trimmed_mean" ~na_rm:false x with
              | Error e -> e
              | Ok [] -> VNA NAFloat
              | Ok xs ->
                  let arr = Array.of_list xs in
                  let n = Array.length arr in
                  let k = int_of_float (Float.floor (trim *. float_of_int n)) in
                  Array.sort compare arr;
                  let kept = Array.sub arr k (n - (2 * k)) in
                  VFloat (Array.fold_left ( +. ) 0.0 kept /. float_of_int (Array.length kept))))
    | _ -> Error.arity_error_named "trimmed_mean" ~expected:2 ~received:(List.length args))) env
