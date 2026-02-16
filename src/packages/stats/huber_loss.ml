open Ast

(*
--# Huber loss
--#
--# Compute Huber loss for residuals and positive delta.
--#
--# @name huber_loss
--# @param x :: Number | Vector | List Residual value(s).
--# @param delta :: Number Positive threshold.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family stats
--# @export
*)

let register env =
  Env.add "huber_loss" (make_builtin ~name:"huber_loss" 2 (fun args _ ->
    let delta_of = function VFloat f when f > 0.0 -> Some f | VInt i when i > 0 -> Some (float_of_int i) | _ -> None in
    let huber x d = let ax = Float.abs x in if ax <= d then 0.5 *. x *. x else d *. (ax -. (0.5 *. d)) in
    let map_val d = function VInt n -> Some (VFloat (huber (float_of_int n) d)) | VFloat f -> Some (VFloat (huber f d)) | _ -> None in
    match args with
    | [x; d] ->
        (match delta_of d with
         | None -> Error.value_error "Function `huber_loss` expects positive delta."
         | Some delta ->
             (match x with
              | VInt n -> VFloat (huber (float_of_int n) delta)
              | VFloat f -> VFloat (huber f delta)
              | VVector arr ->
                  let out = Array.map (fun v -> Option.value ~default:VNull (map_val delta v)) arr in
                  if Array.exists (fun v -> v = VNull) out then Error.type_error "Function `huber_loss` requires numeric values." else VVector out
              | VList items ->
                  let out = List.map (fun (_, v) -> Option.value ~default:VNull (map_val delta v)) items in
                  if List.exists (fun v -> v = VNull) out then Error.type_error "Function `huber_loss` requires numeric values." else VVector (Array.of_list out)
              | _ -> Error.type_error "Function `huber_loss` expects numeric input."))
    | _ -> Error.arity_error_named "huber_loss" ~expected:2 ~received:(List.length args))) env
