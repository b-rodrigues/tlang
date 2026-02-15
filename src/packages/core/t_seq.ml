open Ast

(*
--# Generate a sequence of integers
--#
--# Creates a list of integers from start to end (inclusive).
--#
--# @name seq
--# @param start :: Int Starting value.
--# @param end :: Int Ending value.
--# @return :: List[Int] List of integers.
--# @example
--#   seq(1, 5)
--#   -- Returns: [1, 2, 3, 4, 5]
--# @family core
--# @export
*)
let register env =
  Env.add "seq"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VInt a; VInt b] ->
          let items = List.init (b - a + 1) (fun i -> (None, VInt (a + i))) in
          VList items
      | _ -> Error.type_error "Function `seq` expects two Int arguments."
    ))
    env
