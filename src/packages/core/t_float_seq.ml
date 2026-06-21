open Ast

(*
--# Generate a sequence of evenly-spaced floats
--#
--# Creates a list of `n` floats from `start` to `end` (inclusive),
--# evenly spaced.
--#
--# @name float_seq
--# @param start :: Float|Int Starting value.
--# @param end :: Float|Int Ending value.
--# @param n :: Int Number of values (default: 100).
--# @return :: List[Float] List of evenly-spaced floats.
--# @example
--#   float_seq(0, 1, 5)
--#   -- Returns = [0.0, 0.25, 0.5, 0.75, 1.0]
--#   float_seq(start = 0, end = 1, n = 5)
--# @family core
--# @export
*)
let register env =
  Env.add "float_seq"
    (Ast.make_builtin_named ~name:"float_seq" ~variadic:true 0 (fun named_args _env ->
      let get_named k = List.find_map (fun (nk, v) -> if nk = Some k then Some v else None) named_args in
      let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in

      let as_float v =
        match v with
        | Ast.VInt i -> float_of_int i
        | Ast.VFloat f -> f
        | _ -> raise (Failure "Function `float_seq` arguments must be numeric.")
      in

      let as_int v =
        match v with
        | Ast.VInt i -> i
        | Ast.VFloat f -> int_of_float f
        | _ -> raise (Failure "Function `float_seq` n must be numeric.")
      in

      try
        let start_val, end_val, n =
          match get_named "start", get_named "end", get_named "n", positional with
          | Some s, Some e, Some n, _ -> (as_float s, as_float e, max 2 (as_int n))
          | Some s, Some e, None, [n] -> (as_float s, as_float e, max 2 (as_int n))
          | None, None, None, [s; e] -> (as_float s, as_float e, 100)
          | None, None, None, [s; e; n] -> (as_float s, as_float e, max 2 (as_int n))
          | _ -> raise (Failure "Function `float_seq` requires at least start and end arguments.")
        in
        if n < 2 then raise (Failure "Function `float_seq` requires n >= 2.") else
        let step = (end_val -. start_val) /. float_of_int (n - 1) in
        let items = List.init n (fun i -> (None, Ast.VFloat (start_val +. float_of_int i *. step))) in
        Ast.VList items
      with Failure msg -> Error.type_error msg
    ))
    env
