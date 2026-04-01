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
  let env = 
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
  in
  Env.add "t_write_pmml"
    (make_builtin ~name:"t_write_pmml" 2 (fun _args _env ->
      Error.make_error RuntimeError "Serializer ^pmml does not have a T-native implementation yet. Use ^pmml within R or Python nodes to export models."
    ))
    env
