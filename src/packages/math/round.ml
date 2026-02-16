open Ast

(*
--# Round values
--#
--# Round numbers to a specified number of decimal digits.
--#
--# @name round
--# @param x :: Number | Vector | NDArray Numeric input.
--# @param digits :: Int = 0 Decimal digits.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let map_numeric_unary ~fname f = function
  | [VInt n] -> VFloat (f (float_of_int n))
  | [VFloat x] -> VFloat (f x)
  | [VVector arr] ->
      let out = Array.make (Array.length arr) VNull in
      let err = ref None in
      Array.iteri (fun i v ->
        if !err = None then
          match v with
          | VInt n -> out.(i) <- VFloat (f (float_of_int n))
          | VFloat x -> out.(i) <- VFloat (f x)
          | VNA _ -> err := Some (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." fname))
          | _ -> err := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." fname))
      ) arr;
      (match !err with Some e -> e | None -> VVector out)
  | [VNDArray arr] -> VNDArray { shape = arr.shape; data = Array.map f arr.data }
  | [VNA _] -> Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." fname)
  | [_] -> Error.type_error (Printf.sprintf "Function `%s` expects numeric input." fname)
  | args -> Error.arity_error_named fname ~expected:1 ~received:(List.length args)

let register env =
  let apply_round digits named_args =
    let args =
      List.filter (fun (n, _) -> n <> Some "digits") named_args
      |> List.map snd
    in
    let factor = Float.pow 10.0 (float_of_int digits) in
    let rf x = Float.round (x *. factor) /. factor in
    map_numeric_unary ~fname:"round" rf args
  in
  Env.add "round"
    (make_builtin_named ~name:"round" ~variadic:true 1 (fun named_args _env ->
      (* Reject unknown named arguments and enforce that `digits` is an integer. *)
      let unknown_named =
        List.filter
          (fun (n, _) ->
             match n with
             | None -> false
             | Some "digits" -> false
             | Some _ -> true)
          named_args
      in
      match unknown_named with
      | (Some arg_name, _) :: _ ->
          Error.type_error
            (Printf.sprintf "Function `round` received unknown named argument `%s`." arg_name)
      | _ ->
          let digits_opt =
            List.find_opt (fun (n, _) -> n = Some "digits") named_args
          in
          (match digits_opt with
           | Some (_, VInt n) -> apply_round n named_args
           | Some _ ->
               Error.type_error
                 "Function `round` expects the `digits` argument to be an integer."
           | None -> apply_round 0 named_args)))
    env
