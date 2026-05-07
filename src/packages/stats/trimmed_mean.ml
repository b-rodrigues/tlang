open Ast

(*
--# Trimmed mean
--#
--# Compute mean after trimming both tails by fraction.
--#
--# @name trimmed_mean
--# @param x :: Vector | List Numeric input.
--# @param trim :: Float Trim proportion in [0, 0.5).
--# @param na_rm :: Bool = false Remove NA values first.
--# @param weight :: Vector[Float] | List[Float] = NA Optional non-negative observation weights.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family stats
--# @export
*)

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

let register env =
  Env.add "trimmed_mean" (make_builtin_named ~name:"trimmed_mean" ~variadic:true 2 (fun named_args _ ->
    match Math_common.get_bool_flag "na_rm" false named_args with
    | Error e -> e
    | Ok na_rm ->
    let weight_arg = List.assoc_opt (Some "weight") named_args in
    let args = Math_common.positional_args_without ["na_rm"; "weight"] named_args in
    let trim_of = function VFloat f -> Some f | VInt i -> Some (float_of_int i) | _ -> None in
    match args with
    | [x; t] ->
        (match trim_of t with
         | None -> Error.type_error "Function `trimmed_mean` expects (x, trim) where trim is numeric."
         | Some trim when trim < 0.0 || trim >= 0.5 -> Error.value_error "Function `trimmed_mean` expects trim in [0, 0.5)."
         | Some trim ->
             (match weight_arg with
              | Some weight_v ->
                  (match Math_utils.extract_numeric_array_with_weights ~label:"trimmed_mean" ~na_rm x weight_v with
                   | Error e -> e
                   | Ok (xs, ws) ->
                       (match Math_utils.weighted_quantile_array xs ws trim,
                              Math_utils.weighted_quantile_array xs ws (1.0 -. trim) with
                        | Some lo, Some hi ->
                            let kept = ref [] in
                            let kept_w = ref [] in
                            for i = 0 to Array.length xs - 1 do
                              if xs.(i) >= lo && xs.(i) <= hi then begin
                                kept := xs.(i) :: !kept;
                                kept_w := ws.(i) :: !kept_w
                              end
                            done;
                            let kept = Array.of_list (List.rev !kept) in
                            let kept_w = Array.of_list (List.rev !kept_w) in
                            if Array.length kept = 0 then VNA NAFloat
                            else
                              (match Math_utils.weighted_mean_array kept kept_w with
                               | Some v -> VFloat v
                               | None -> VNA NAFloat)
                        | _ -> VNA NAFloat))
              | None ->
                  (match numeric_values ~label:"trimmed_mean" ~na_rm x with
                   | Error e -> e
                   | Ok [] -> VNA NAFloat
                   | Ok xs ->
                       let arr = Array.of_list xs in
                       let n = Array.length arr in
                       let k = int_of_float (Float.floor (trim *. float_of_int n)) in
                       Array.sort compare arr;
                       let kept = Array.sub arr k (n - (2 * k)) in
                       VFloat (Array.fold_left ( +. ) 0.0 kept /. float_of_int (Array.length kept)))))
    | _ -> Error.arity_error_named "trimmed_mean" 2 (List.length args)))) env
