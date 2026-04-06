open Ast

let copy_pmml_file src dst =
  match (try Ok (open_in_bin src) with Sys_error msg -> Error msg) with
  | Error msg ->
      Error (Printf.sprintf "could not open source PMML path `%s`: %s" src msg)
  | Ok ic ->
      Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
        match (try Ok (open_out_bin dst) with Sys_error msg -> Error msg) with
        | Error msg ->
            Error (Printf.sprintf "could not open destination PMML path `%s`: %s" dst msg)
        | Ok oc ->
            Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
              let buffer = Bytes.create 65536 in
              let rec loop () =
                try
                  match input ic buffer 0 (Bytes.length buffer) with
                  | 0 -> Ok ()
                  | read ->
                      output oc buffer 0 read;
                      loop ()
                with
                | Sys_error msg ->
                    Error
                      (Printf.sprintf
                         "failed while copying `%s` to `%s`: %s"
                         src dst msg)
              in
              loop ()))

let pmml_source_path = function
  | VDict pairs ->
      (match List.assoc_opt "_pmml_path" pairs with
       | Some (VString path) -> Some path
       | _ -> None)
  | _ -> None

(*
--# Read a PMML model file
--#
--# Loads a PMML file from disk and returns its parsed model representation.
--#
--# @name t_read_pmml
--# @family stats
--# @export
*)
let register env =
  let env = 
    Env.add "t_read_pmml"
      (make_builtin ~name:"t_read_pmml" 1 (fun args _env ->
        match args with
        | [VString path] ->
            (match Pmml_utils.read_pmml path with
             | Ok v -> Pmml_utils.attach_source_path path v
             | Error msg -> Error.make_error FileError msg)
        | [VError _ as e] -> e
        | _ -> Error.type_error "t_read_pmml expects a single String argument.")
      )
      env
  in
  (*
  --# Write a PMML model file
  --#
  --# Copies a PMML artifact previously loaded with `t_read_pmml()` or `read_node()`
  --# to a new path. Native T-to-PMML export is not implemented yet.
  --#
  --# @name t_write_pmml
  --# @family stats
  --# @export
  *)
  Env.add "t_write_pmml"
    (make_builtin ~name:"t_write_pmml" 2 (fun args _env ->
      match args with
      | [VError _ as e; _] | [_; VError _ as e] -> e
      | [VDict _ as model; VString path] ->
          (match pmml_source_path model with
           | Some src_path ->
               if not (Sys.file_exists src_path) then
                  Error.make_error FileError
                    (Printf.sprintf
                       "Function `t_write_pmml`: source PMML artifact `%s` no longer exists, so the pass-through copy cannot be written."
                       src_path)
                else
                  (match copy_pmml_file src_path path with
                  | Ok () -> VString path
                  | Error msg ->
                      Error.make_error FileError
                        (Printf.sprintf "Function `t_write_pmml` failed to write `%s`: %s" path msg))
           | None ->
               Error.make_error RuntimeError
                 "Function `t_write_pmml` currently supports only PMML models loaded via `t_read_pmml()` or `read_node()`. Exporting native T models to PMML is not implemented yet.")
      | [_; VString _] ->
          Error.type_error "Function `t_write_pmml` expects a PMML model Dict as first argument."
      | [VDict _; _] ->
          Error.type_error "Function `t_write_pmml` expects a String path as second argument."
      | [_; _] ->
          Error.type_error "Function `t_write_pmml` expects (Dict, String)."
      | _ ->
          Error.arity_error_named "t_write_pmml" 2 (List.length args)
    ))
    env
