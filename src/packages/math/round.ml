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
  Env.add "round"
    (make_builtin_named ~name:"round" ~variadic:true 1 (fun named_args _env ->
      let digits =
        match List.find_opt (fun (n, _) -> n = Some "digits") named_args with
        | Some (_, VInt n) -> n
        | Some (_, VFloat f) -> int_of_float f
        | _ -> 0
      in
      let args = List.filter (fun (n, _) -> n <> Some "digits") named_args |> List.map snd in
      let factor = Float.pow 10.0 (float_of_int digits) in
      let rf x = Float.round (x *. factor) /. factor in
      map_numeric_unary ~fname:"round" rf args))
    env
