open Ast

(*
--# Read a PMML model file
--#
--# Loads a PMML file from disk and returns its parsed model representation.
--#
--# @name t_read_pmml
--# @family stats
--# @export
*)
let register env =
  Env.add "t_read_pmml"
    (make_builtin ~name:"t_read_pmml" 1 (fun args _env ->
      match args with
      | [VString path] ->
          (match Pmml_utils.read_pmml path with
           | Ok v -> v
           | Error msg -> Error.make_error FileError msg)
      | _ -> Error.type_error "t_read_pmml expects a single String argument.")
    )
    env
