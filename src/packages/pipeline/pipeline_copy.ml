(* src/packages/pipeline/pipeline_copy.ml *)
open Ast

(*
--# Copy Pipeline Node Artifacts to Local Directory
--#
--# Copies built artifacts from the Nix store to a local directory for easier inspection.
--# By default copies all nodes from the latest build to `pipeline-output/`.
--#
--# @name pipeline_copy
--# @param node :: String (Optional) The node name to copy. If null, copies all nodes.
--# @param target_dir :: String (Optional) The destination directory. Default is "pipeline-output".
--# @param dir_mode :: String (Optional) POSIX mode for directories (e.g. "0755").
--# @param file_mode :: String (Optional) POSIX mode for files (e.g. "0644").
--# @return :: String A success message or Error.
--# @family pipeline
--# @export
-*)
let register env =
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> v
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        if List.length positionals >= pos then List.nth positionals (pos - 1)
        else default
  in

  let copy_fn named_args _env =
    match get_arg "node" 1 VNull named_args with
    | VNull ->
        (match get_arg "target_dir" 2 (VString "pipeline-output") named_args with
         | VString target_dir | VSymbol target_dir ->
             (match get_arg "dir_mode" 3 (VString "0755") named_args with
              | VString dir_mode ->
                  (match get_arg "file_mode" 4 (VString "0644") named_args with
                   | VString file_mode ->
                       Builder.pipeline_copy ~node_name:None ~target_dir ~dir_mode ~file_mode ()
                   | _ ->
                       Error.type_error "Function `pipeline_copy` expects `file_mode` to be a String.")
              | _ ->
                  Error.type_error "Function `pipeline_copy` expects `dir_mode` to be a String."))
         | _ ->
             Error.type_error "Function `pipeline_copy` expects `target_dir` to be a String or Symbol.")
    | VString node_name | VSymbol node_name ->
        (match get_arg "target_dir" 2 (VString "pipeline-output") named_args with
         | VString target_dir | VSymbol target_dir ->
             (match get_arg "dir_mode" 3 (VString "0755") named_args with
              | VString dir_mode ->
                  (match get_arg "file_mode" 4 (VString "0644") named_args with
                   | VString file_mode ->
                       Builder.pipeline_copy ~node_name:(Some node_name) ~target_dir ~dir_mode ~file_mode ()
                   | _ ->
                       Error.type_error "Function `pipeline_copy` expects `file_mode` to be a String.")
              | _ ->
                  Error.type_error "Function `pipeline_copy` expects `dir_mode` to be a String."))
         | _ ->
             Error.type_error "Function `pipeline_copy` expects `target_dir` to be a String or Symbol.")
    | _ ->
        Error.type_error "Function `pipeline_copy` expects `node` to be a String, Symbol, or Null."
  in

  env
  |> Env.add "pipeline_copy" (make_builtin_named ~name:"pipeline_copy" ~variadic:true 0 copy_fn)
