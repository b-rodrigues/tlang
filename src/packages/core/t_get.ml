open Ast

(*
--# Get element by index
--#
--# Retrieves an element from a List, Vector, or NDArray at the specified index (0-based).
--#
--# @name get
--# @param collection :: List | Vector | NDArray The collection to access.
--# @param index :: Int The index to retrieve.
--# @return :: Any The element at the index.
--# @example
--#   get([10, 20, 30], 1)
--#   -- Returns: 20
--# @family core
--# @export
*)
let register env =
  Env.add "get"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VList items; VInt i] ->
          let len = List.length items in
          if i < 0 || i >= len then
            Error.index_error i len
          else
            let (_, v) = List.nth items i in
            v
      | [VVector arr; VInt i] ->
          let len = Array.length arr in
          if i < 0 || i >= len then
            Error.index_error i len
          else
            arr.(i)
      | [VNDArray arr; VInt i] ->
          let len = Array.length arr.data in
          if i < 0 || i >= len then
            Error.index_error i len
          else
            VFloat arr.data.(i)
      (* NDArray 2D access could be supported here too if 3 args, but make_builtin is fixed arity per registration? *)
      | _ -> Error.type_error "Function `get` expects a List/Vector/NDArray and an Integer index."
    ))
    env
