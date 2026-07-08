open Ast

(*
--# Prefetch a URL and compute its SHA-256 hash
--#
--# Downloads a URL via nix-prefetch-url and returns its SHA-256 hash.
--# The file is stored in the Nix store so that fetchurl in pipeline mode
--# finds it cached and does not re-download.
--#
--# @name prefetch
--# @param url :: String The URL to prefetch.
--# @return :: String The SHA-256 hash of the downloaded content.
--# @example
--#   hash = prefetch("https://example.com/data.csv")
--#   print(hash)
--# @family base
--# @seealso fetchurl
--# @export
*)
let register env =
  let escape_shell s =
    "'" ^ String.concat "'\\''" (String.split_on_char '\'' s) ^ "'"
  in
  Env.add "prefetch"
    (make_builtin ~name:"prefetch" 1 (fun args _env ->
      match args with
      | [VString url] | [VSymbol url] ->
          let cmd = Printf.sprintf "nix-prefetch-url %s 2>/dev/null" (escape_shell url) in
          let ch = Unix.open_process_in cmd in
          let hash = try
            let line = input_line ch in
            String.trim line
          with End_of_file -> "" in
          (match Unix.close_process_in ch, hash with
           | Unix.WEXITED 0, h when h <> "" -> VString h
           | Unix.WEXITED 0, _ ->
               Error.make_error ShellError
                 (Printf.sprintf "Function `prefetch`: got empty hash for %s" url)
           | Unix.WEXITED n, _ ->
               Error.make_error ShellError
                 (Printf.sprintf "Function `prefetch`: nix-prefetch-url failed with exit code %d when fetching %s" n url)
           | _, _ ->
               Error.make_error ShellError
                 (Printf.sprintf "Function `prefetch`: nix-prefetch-url terminated abnormally when fetching %s" url))
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `prefetch` expects a String URL, got %s."
               (Ast.Utils.type_name other))
      | _ -> Error.arity_error_named "prefetch" 1 (List.length args)
    ))
    env
