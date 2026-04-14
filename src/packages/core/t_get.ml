open Ast

(*
--# Get variable or element
--#
--# If called with one argument, retrieves a variable's value from the environment 
--# by name (String or Symbol). Matches R's `get()` semantics for variable lookup.
--#
--# If called with two arguments, retrieves an element from a List, Vector, or 
--# NDArray at the specified index (0-based).
--#
--# @name get
--# @param x :: String | Symbol | List | Vector | NDArray The variable name or collection.
--# @param index :: Int (Optional) The index to retrieve if `x` is a collection.
--# @return :: Any The variable value or collection element.
--# @example
--#   salary = 50000
--#   get("salary")
--#   -- Returns = 50000
--#
--#   col_name = "salary"
--#   get(sym(col_name))
--#   -- Returns = 50000
--#
--#   get([10, 20, 30], 1)
--#   -- Returns = 20
--# @family core
--# @export
*)
let register env =
  Env.add "get"
    (make_builtin ~name:"get" ~variadic:true 1 (fun args env ->
      match args with
      (* Variable Lookup Case *)
      | [VString name] | [VSymbol name] ->
          (match Env.find_opt name env with
           | Some v -> v
           | None -> Error.name_error name)

      (* Collection Indexing Case *)
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

      | _ -> Error.type_error "Function `get` expects (1) a variable name [String/Symbol] or (2) a collection and integer index."
    ))
    env
