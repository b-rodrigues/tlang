(* src/packages/pipeline/t_fmt.ml *)

open Ast

(*
--# Format T Source File
--#
--# Formats a `.t` file using the canonical T formatter, preserving comments
--# and `<{ ... }>` raw foreign code blocks. By default returns the formatted
--# source string without modifying the file; pass `write = true` to update
--# the file in place, or `check = true` to return a Bool indicating whether
--# the file is already formatted.
--#
--# @name t_fmt
--# @param path :: String Path to the `.t` file to format.
--# @param write :: Bool = false When true, write formatted output back to `path`.
--# @param check :: Bool = false When true, return `true` if already formatted, `false` otherwise.
--# @return :: String | Bool Formatted source string, or Bool when `check = true`.
--# @example
--#   t_fmt("src/pipeline.t")
--#   t_fmt("src/pipeline.t", write = true)
--#   t_fmt("src/pipeline.t", check = true)
--# @family pipeline
--# @seealso t_check, t_fix
--# @export
*)

let allowed_args = ["path"; "write"; "check"]

let t_fmt_fn named_args _env =
  let unknown =
    List.find_map (fun (k, _) ->
      match k with
      | Some n when not (List.mem n allowed_args) -> Some n
      | _ -> None
    ) named_args
  in
  match unknown with
  | Some name ->
      Error.type_error
        (Printf.sprintf "Function `t_fmt` got an unknown argument `%s`. Supported arguments: path, write, check." name)
  | None ->
      (match Pipeline_args.get_arg "path" 1 (VNA NAGeneric) named_args with
       | (_, VString path) ->
           let get_bool key =
             match List.find_map (fun (k, v) -> if k = Some key then Some v else None) named_args with
             | None | Some (VNA _) -> Ok false
             | Some (VBool b) -> Ok b
             | Some v ->
                 Error (Error.type_error
                   (Printf.sprintf "Function `t_fmt` argument `%s` must be a Bool, but got %s."
                      key (Utils.type_name v)))
           in
           (match get_bool "write", get_bool "check" with
            | Error e, _ | _, Error e -> e
            | Ok write, Ok check ->
                (match T_formatter.format_file ~check ~write path with
                 | Error msg -> Error.make_error FileError (Printf.sprintf "t_fmt: %s" msg)
                 | Ok (changed, formatted) ->
                     if check then VBool (not changed)
                     else VString formatted))
       | (_, other) ->
           Error.type_error
             (Printf.sprintf "Function `t_fmt` expects a String file path, but got %s."
                (Utils.type_name other)))

let register env =
  Env.add "t_fmt"
    (make_builtin_named ~name:"t_fmt" ~variadic:true 1 t_fmt_fn)
    env
