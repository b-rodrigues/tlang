open Ast

(*
--# Quote a custom strategy function name
--#
--# Strategies are a closed set: `default`, `^csv`, `^json`, `^ipc`,
--# `^parquet`, `^pmml`, `^onnx`, `^bin`, `^text`, and `^tlang`. A bare
--# name outside that set is rejected where a strategy is expected.
--# Quote a custom reader/writer with `custom("name")` and declare it in
--# the node's `functions` files; it resolves against those files at
--# build time.
--#
--# @name custom
--# @param name :: String The custom reader/writer function name.
--# @return :: Symbol The quoted name, usable in `serializer` and `deserializer` positions.
--# @example
--#   node(serializer = custom("write_pkl"), functions = ["my_serializer.py"])
--# @family pipeline
--# @seealso node
--# @export
*)
let register env =
  Env.add "custom"
    (make_builtin ~name:"custom" 1 (fun args _env ->
      match args with
      | [VString name] -> VSymbol name
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `custom` expects a String function name, but got %s."
              (Utils.type_name other))
      | _ -> Error.arity_error_named "custom" 1 (List.length args)
    ))
    env
