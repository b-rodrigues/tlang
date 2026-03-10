(* src/packages/dataframe/t_read_arrow.ml *)
open Ast

let register env =
  (*
  --# Read Arrow IPC file
  --#
  --# Reads a DataFrame from an Apache Arrow IPC (Feather v2) file.
  --#
  --# @name read_arrow
  --# @param path :: String The path to the Arrow file.
  --# @return :: DataFrame The loaded DataFrame.
  --# @example
  --#   df = read_arrow("data.arrow")
  --# @family dataframe
  --# @seealso write_arrow
  --# @export
  *)
  Env.add "read_arrow"
    (make_builtin ~name:"read_arrow" 1 (fun args _env ->
      match args with
      | [VString path] ->
          (match Arrow_io.read_ipc path with
          | Ok table -> VDataFrame { arrow_table = table; group_keys = [] }
          | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
      | [VNA _] -> Error.type_error "Function `read_arrow` expects a String path, got NA."
      | [_] -> Error.type_error "Function `read_arrow` expects a String path."
      | _ -> Error.arity_error_named "read_arrow" ~expected:1 ~received:(List.length args)
    ))
    env
