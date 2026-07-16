open Ast

(*
--# Fetch a URL
--#
--# Downloads a file from a URL. In the REPL, wraps curl. In a pipeline,
--# creates a node that uses Nix's builtins.fetchurl to fetch the asset
--# into the Nix store, making it available downstream.
--#
--# @name fetchurl
--# @param url :: String The URL to download.
--# @param sha256 :: String (Optional) Expected SHA-256 hash (required in pipeline mode).
--# @param serializer :: String (Optional) Serializer format for pipeline mode. Defaults to "bin". Use "text" for plain text files.
--# @param output :: String (Optional) Output file path (REPL mode only). Defaults to the basename of the URL.
--# @param dest :: String (Optional) Output directory (REPL mode only). Defaults to the current directory.
--# @return :: String | Node In REPL mode, returns the file path as a String. In pipeline mode, returns a Node value.
--# @example
--#   data = fetchurl("https://example.com/data.csv", output = "data.csv")
--#   p = pipeline {
--#     data = fetchurl("https://example.com/data.csv", sha256 = "abc123...")
--#   }
--# @family base
--# @export
*)
let register env =
  let url_from_args args =
    match List.find_opt (fun (n, _) -> n = None || n = Some "url") args with
    | Some (_, VString u) -> Ok u
    | Some (_, VSymbol u) -> Ok u
    | Some (_, other) ->
        Error (Error.type_error
          (Printf.sprintf "Function `fetchurl` expects a String URL as first argument, got %s."
             (Ast.Utils.type_name other)))
    | None ->
        Error (Error.arity_error_named "fetchurl" 1 (List.length args))
  in
  let sha256_from_args args =
    match List.find_opt (fun (n, _) -> n = Some "sha256") args with
    | Some (_, VString s) -> Ok s
    | Some (_, VSymbol s) -> Ok s
    | Some (_, other) ->
        Error (Error.type_error
          (Printf.sprintf "Function `fetchurl`: `sha256` expects a String, got %s."
             (Ast.Utils.type_name other)))
    | None -> Ok ""
  in
  let serializer_from_args args =
    match List.find_opt (fun (n, _) -> n = Some "serializer") args with
    | Some (_, VSymbol s) -> Ok ("^" ^ s)
    | Some (_, VString s) -> Ok ("^" ^ s)
    | Some (_, VSerializer s) -> Ok ("^" ^ s.s_format)
    | Some (_, other) ->
        Error (Error.type_error
          (Printf.sprintf "Function `fetchurl`: `serializer` expects a Symbol or String, got %s."
             (Ast.Utils.type_name other)))
    | None -> Ok "^bin"
  in
  let escape_shell s =
    "'" ^ String.concat "'\\''" (String.split_on_char '\'' s) ^ "'"
  in
  Env.add "fetchurl"
    (make_builtin_named ~name:"fetchurl" ~variadic:true 1 (fun args _env ->
      match url_from_args args with
      | Error e -> e
      | Ok url ->
      (match sha256_from_args args with
       | Error e -> e
       | Ok sha256 ->
       (match serializer_from_args args with
        | Error e -> e
        | Ok serializer_str ->
          if !Eval.pipeline_construction_mode then begin
            if sha256 = "" then
              Error.make_error TypeError
                "Function `fetchurl`: `sha256` is required in pipeline mode."
            else
              VNode {
                un_command = mk_expr (Value (VString url));
                un_script = None;
                un_runtime = "fetchurl";
                un_serializer = mk_expr (Value (VSymbol serializer_str));
                un_deserializer = mk_expr (Var "default");
                un_env_vars = [];
                un_args = [("url", VString url); ("sha256", VString sha256); ("serializer", VSymbol (String.sub serializer_str 1 (String.length serializer_str - 1)))];
                un_shell = None;
                un_shell_args = [];
                un_functions = [];
                un_includes = [];
                un_noop = false;
                un_dependencies = None;
                un_pattern = None;
                un_iteration = "vector";
                un_flake = None;
                un_contract = None;
              }
          end else
           let output_name = match
             List.find_opt (fun (n, _) -> n = Some "output") args,
             List.find_opt (fun (n, _) -> n = Some "dest") args
           with
           | Some (_, VString o), _ -> o
           | _, Some (_, VString d) -> Filename.concat d (Filename.basename url)
           | _ -> Filename.basename url
           in
           let cmd = Printf.sprintf "curl -f -L -o %s %s" (escape_shell output_name) (escape_shell url) in
           (match Sys.command cmd with
            | 0 -> VString output_name
            | n ->
                Error.make_error ShellError
                   (Printf.sprintf "Function `fetchurl`: curl failed with exit code %d when fetching %s" n url))
       )
      )
    ))
    env
