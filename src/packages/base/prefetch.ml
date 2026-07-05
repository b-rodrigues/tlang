open Ast

(*
--# Prefetch a URL and compute its SHA-256 hash
--#
--# Downloads a URL and computes its SHA-256 hash, printing the result.
--# Useful for obtaining the hash needed by `fetchurl` in pipeline mode.
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
          let tmpfile = Filename.temp_file "t_prefetch_" ".tmp" in
          let dl_cmd = Printf.sprintf "curl -sfL -o %s %s" (escape_shell tmpfile) (escape_shell url) in
          (match Sys.command dl_cmd with
           | 0 ->
               let hash_cmd = Printf.sprintf "sha256sum %s | cut -d' ' -f1" (escape_shell tmpfile) in
               let hash_channel = Unix.open_process_in hash_cmd in
               let hash = try
                 let line = input_line hash_channel in
                 String.trim line
               with End_of_file -> "" in
               (match Unix.close_process_in hash_channel, hash with
                | Unix.WEXITED 0, h when h <> "" ->
                    Sys.remove tmpfile;
                    VString h
                | Unix.WEXITED 0, _ ->
                    Sys.remove tmpfile;
                    Error.make_error ShellError
                      (Printf.sprintf "Function `prefetch`: computed empty SHA-256 hash for %s" url)
                | _ ->
                    Sys.remove tmpfile;
                    Error.make_error ShellError
                      (Printf.sprintf "Function `prefetch`: failed to compute SHA-256 hash for %s" url))
           | n ->
               Sys.remove tmpfile;
               Error.make_error ShellError
                 (Printf.sprintf "Function `prefetch`: curl failed with exit code %d when fetching %s" n url))
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `prefetch` expects a String URL, got %s."
               (Ast.Utils.type_name other))
      | _ -> Error.arity_error_named "prefetch" 1 (List.length args)
    ))
    env
