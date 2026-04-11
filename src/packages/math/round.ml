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

let register env =
  let apply_round digits named_args =
    let na_ignore = Math_common.named_flag_true "na_ignore" named_args in
    let args = Math_common.positional_args_without [ "digits"; "na_ignore" ] named_args in
    let factor = Float.pow 10.0 (float_of_int digits) in
    let rf x = Float.round (x *. factor) /. factor in
    Math_common.map_numeric_unary ~fname:"round" ~na_ignore rf args
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
              | Some "na_ignore" -> false
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
