open Ast

(*
--# Read an ONNX model file
--#
--# Loads an ONNX model file from disk and returns a dictionary containing 
--# model metadata and the file path.
--# Actual ONNX inference is performed by R or Python runtimes using their
--# respective ONNX Runtime bindings. The T-native reader stores the model
--# path for downstream use in polyglot pipeline nodes.
--#
--# @name t_read_onnx
--# @param path :: String The file path to the .onnx model.
--# @return :: Dict A dictionary with format metadata and the model path.
--# @family stats
--# @export
*)
let register env =
  Env.add "t_read_onnx"
    (make_builtin ~name:"t_read_onnx" 1 (fun args _env ->
      match args with
      | [VString path] ->
          if not (Sys.file_exists path) then
            Error.make_error FileError (Printf.sprintf "Function `t_read_onnx`: ONNX model file not found: %s" path)
          else
            VDict [
              "model_type", VString "onnx";
              "path", VString path;
            ]
      | [VError _ as e] -> e
      | _ -> Error.type_error "t_read_onnx expects a single String argument (file path).")
    )
    env
