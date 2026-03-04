open Ast

(*
--# Path manipulation builtins
--#
--# Pure string operations that delegate to OCaml's Filename module.
--# No filesystem IO is performed — these are purely lexical path operations.
--#
--# @family core
*)

(** Extract a single string argument from a named-args list. *)
let get_path_arg fname args =
  match args with
  | [(_, VString s)] -> Ok s
  | [(_, VSymbol s)] -> Ok s
  | [(_, other)] ->
      Error (Printf.sprintf "Function `%s` expects a String path, got %s." fname (Utils.type_name other))
  | [] -> Error (Printf.sprintf "Function `%s` expects a String path argument." fname)
  | _  -> Error (Printf.sprintf "Function `%s` expects exactly one path argument, got %d." fname (List.length args))

(** Normalize a path by resolving . and .. segments.
    Does not access the filesystem — purely lexical. *)
let normalize_path path =
  let parts = String.split_on_char '/' path in
  let rec go acc = function
    | [] -> List.rev acc
    | "." :: rest -> go acc rest
    | ".." :: rest ->
        (match acc with
         | [] | [""] -> go acc rest
         | _ :: parent -> go parent rest)
    | "" :: rest when acc <> [] -> go acc rest
    | part :: rest -> go (part :: acc) rest
  in
  let normalized = go [] parts in
  match normalized with
  | [] -> "/"
  | [""] -> "/"
  | parts -> String.concat "/" parts

(*
--# @name path_join
--# @param ... :: String One or more path segments to join.
--# @return :: String The joined path.
--# @example
--#   path_join("/home/user", "project", "data.csv")  # => "/home/user/project/data.csv"
*)
let builtin_path_join =
  make_builtin_named ~name:"path_join" ~variadic:true 1 (fun args _env ->
    let parts = List.map (fun (_, v) -> match v with
      | VString s -> Ok s
      | VSymbol s -> Ok s
      | other -> Error (Utils.type_name other)
    ) args in
    match List.find_opt (function Error _ -> true | Ok _ -> false) parts with
    | Some (Error t) ->
        Error.make_error TypeError
          (Printf.sprintf "path_join: all arguments must be String, got %s" t)
    | _ ->
        let strings = List.filter_map (function Ok s -> Some s | Error _ -> None) parts in
        (match strings with
        | [] -> Error.make_error ArityError "path_join requires at least one argument"
        | first :: rest ->
            let result = List.fold_left Filename.concat first rest in
            VString result)
  )

(*
--# @name path_basename
--# @param path :: String A file path.
--# @return :: String The final component of the path.
--# @example
--#   path_basename("/home/user/data.csv")  # => "data.csv"
*)
let builtin_path_basename =
  make_builtin_named ~name:"path_basename" 1 (fun args _env ->
    match get_path_arg "path_basename" args with
    | Error msg -> Error.make_error TypeError msg
    | Ok path -> VString (Filename.basename path)
  )

(*
--# @name path_dirname
--# @param path :: String A file path.
--# @return :: String The directory portion of the path.
--# @example
--#   path_dirname("/home/user/data.csv")  # => "/home/user"
*)
let builtin_path_dirname =
  make_builtin_named ~name:"path_dirname" 1 (fun args _env ->
    match get_path_arg "path_dirname" args with
    | Error msg -> Error.make_error TypeError msg
    | Ok path -> VString (Filename.dirname path)
  )

(*
--# @name path_ext
--# @param path :: String A file path.
--# @return :: String | Null The file extension including the leading dot, or null if none.
--# @example
--#   path_ext("data.csv")    # => ".csv"
--#   path_ext("Makefile")    # => null
*)
let builtin_path_ext =
  make_builtin_named ~name:"path_ext" 1 (fun args _env ->
    match get_path_arg "path_ext" args with
    | Error msg -> Error.make_error TypeError msg
    | Ok path ->
        (match Filename.extension path with
        | "" -> VNull
        | ext -> VString ext)
  )

(*
--# @name path_stem
--# @param path :: String A file path.
--# @return :: String The filename without its extension.
--# @example
--#   path_stem("data.csv")        # => "data"
--#   path_stem("archive.tar.gz")  # => "archive.tar"
*)
let builtin_path_stem =
  make_builtin_named ~name:"path_stem" 1 (fun args _env ->
    match get_path_arg "path_stem" args with
    | Error msg -> Error.make_error TypeError msg
    | Ok path ->
        let base = Filename.basename path in
        VString (Filename.remove_extension base)
  )

(*
--# @name path_abs
--# @param path :: String A relative or absolute path.
--# @return :: String The absolute path resolved against the current working directory.
--# @example
--#   path_abs("data.csv")          # => "/cwd/data.csv"
--#   path_abs("/already/absolute") # => "/already/absolute"
*)
let builtin_path_abs =
  make_builtin_named ~name:"path_abs" 1 (fun args _env ->
    match get_path_arg "path_abs" args with
    | Error msg -> Error.make_error TypeError msg
    | Ok path ->
        if not (Filename.is_relative path) then
          VString (normalize_path path)
        else
          match (try Ok (Sys.getcwd ()) with Sys_error msg -> Error msg) with
          | Error msg ->
              Error.make_error RuntimeError
                (Printf.sprintf "path_abs: cannot get working directory: %s" msg)
          | Ok cwd ->
              VString (normalize_path (Filename.concat cwd path))
  )

let register env =
  let env = Env.add "path_join"     builtin_path_join     env in
  let env = Env.add "path_basename" builtin_path_basename env in
  let env = Env.add "path_dirname"  builtin_path_dirname  env in
  let env = Env.add "path_ext"      builtin_path_ext      env in
  let env = Env.add "path_stem"     builtin_path_stem     env in
  let env = Env.add "path_abs"      builtin_path_abs      env in
  env
