open Ast

(*
--# Read an ONNX model file
--#
--# Loads an ONNX model file from disk and returns a model dictionary.
--# The resulting dictionary contains the model type identifier (^onnx),
--# the file path, input/output names, and model-level metadata.
--# This model object can be passed to `predict()` for native T-side inference.
--#
--# @name t_read_onnx
--# @param path :: String The file path to the .onnx model.
--# @return :: Dict A model dictionary containing:
--#   - `model_type` :: Symbol (^onnx)
--#   - `path` :: String
--#   - `inputs` :: List[String]
--#   - `outputs` :: List[String]
--#   - `input_width` :: Int
--#   - `metadata` :: Dict Model-level custom properties (producer, description, etc.)
--# @family stats
--# @export
*)
let t_read_onnx_builtin =
  make_builtin ~name:"t_read_onnx" 1 (fun args _env ->
    match args with
    | [VString path] ->
        if not (Sys.file_exists path) then
          Error.make_error FileError (Printf.sprintf "Function `t_read_onnx`: ONNX model file not found: %s" path)
        else begin
          try
            let session = Onnx_ffi.get_session path in
            let input_names = Onnx_ffi.session_input_names session in
            let output_names = Onnx_ffi.session_output_names session in
            let input_width = Onnx_ffi.session_input_width session in
            let meta = Onnx_ffi.session_metadata session in
            VDict [
              "model_type", VSymbol "^onnx";
              "path", VString path;
              "inputs", VList (Array.to_list input_names |> List.map (fun s -> (None, VString s)));
              "outputs", VList (Array.to_list output_names |> List.map (fun s -> (None, VString s)));
              "input_width", VInt input_width;
              "metadata", VDict (List.map (fun (k, v) -> (k, VString v)) meta);
            ]
          with Failure msg ->
            Error.make_error RuntimeError (Printf.sprintf "Function `t_read_onnx` failed to load model: %s" msg)
        end
    | [VError _ as e] -> e
    | _ -> Error.type_error "t_read_onnx expects a single String argument (file path).")

let register env =
  Serialization_registry.update_native "onnx" ~reader:t_read_onnx_builtin ();
  let env = Env.add "t_read_onnx" t_read_onnx_builtin env in
  let env = Env.add "t_write_onnx"
    (make_builtin ~name:"t_write_onnx" 2 (fun _args _env ->
      Error.make_error RuntimeError "Serializer ^onnx does not have a T-native writer implementation yet. Use ^onnx within R or Python nodes to export models."
    ))
    env
  in
  env
