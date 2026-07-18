open Ast

(*
--# Schema Contract Annotation
--#
--# Declares static schema contracts for a pipeline node. Contracts are validated
--# during `t check --schema` and have no runtime effect.
--#
--# Supported contracts:
--#   expect(columns = ["id", "name"])       — column presence
--#   expect(amount ~ double())              — type contract
--#   expect(null_rate("amount") < 0.05)     — null-rate (unverifiable statically)
--#
--# @name expect
--# @param data :: DataFrame The piped data (passed through unchanged).
--# @param ... :: Any Contract expressions.
--# @return :: DataFrame The same data, unchanged.
--# @family pipeline
--# @export
*)
let register env =
  Env.add "expect"
    (make_builtin ~name:"expect" ~unwrap:false 1 (fun args _env ->
      match args with
      | data :: _ -> data
      | [] -> Error.arity_error_named "expect" 1 0
    )) env
