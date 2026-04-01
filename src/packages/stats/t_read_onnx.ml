open Ast

(*
--# Read an ONNX model file
--#
--# Loads an ONNX model file from disk and returns a model dictionary.
--# The resulting dictionary contains the model type identifier (^onnx) and the file path.
--# This model object can be passed to `predict()` for native T-side inference.
--#
--# @name t_read_onnx
--# @param path :: String The file path to the .onnx model.
--# @return :: Dict A model dictionary for native scoring.
--# @family stats
--# @export
*)
let register env =
  let env = 
    Env.add "t_read_onnx"
      (make_builtin ~name:"t_read_onnx" 1 (fun args _env ->
        match args with
        | [VString path] ->
            if not (Sys.file_exists path) then
              Error.make_error FileError (Printf.sprintf "Function `t_read_onnx`: ONNX model file not found: %s" path)
            else
              VDict [
                "model_type", VSymbol "^onnx";
                "path", VString path;
              ]
        | [VError _ as e] -> e
        | _ -> Error.type_error "t_read_onnx expects a single String argument (file path).")
      )
      env
  in
  Env.add "t_write_onnx"
    (make_builtin ~name:"t_write_onnx" 2 (fun _args _env ->
      Error.make_error RuntimeError "Serializer ^onnx does not have a T-native writer implementation yet. Use ^onnx within R or Python nodes to export models."
    ))
    env
