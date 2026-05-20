open Ast

(*
--# Get error code
--#
--# Returns the error code as a string (e.g., "TypeError", "ValueError").
--#
--# @name error_code
--# @param x :: Error The error value to inspect.
--# @return :: String The error code as a string.
--# @family base
--# @export
*)
let register env =
  let env = Env.add "error_code"
    (make_builtin ~name:"error_code" 1 (fun args _env ->
      match args with
      | [VError { code; _ }] -> VString (Utils.error_code_to_string code)
      | [_] -> Error.type_error "Function `error_code` expects an Error value."
      | _ -> Error.arity_error_named "error_code" 1 (List.length args)
    ))
    env in
  
  (*
  --# Get error message
  --#
  --# Returns the human-readable message associated with an error.
  --#
  --# @name error_message
  --# @param x :: Error The error value to inspect.
  --# @return :: String The error message.
  --# @family base
  --# @export
  *)
  let env = Env.add "error_message"
    (make_builtin ~name:"error_message" 1 (fun args _env ->
      match args with
      | [VError { message; _ }] -> VString message
      | [_] -> Error.type_error "Function `error_message` expects an Error value."
      | _ -> Error.arity_error_named "error_message" 1 (List.length args)
    ))
    env in
  
  (*
  --# Get error context
  --#
  --# Returns a dictionary containing contextual information about where and why
  --# the error occurred.
  --#
  --# @name error_context
  --# @param x :: Error The error value to inspect.
  --# @return :: Dict A dictionary of related context data.
  --# @family base
  --# @export
  *)
  let env = Env.add "error_context"
    (make_builtin ~name:"error_context" 1 (fun args _env ->
      match args with
      | [VError { context; _ }] ->
          VDict context
      | [_] -> Error.type_error "Function `error_context` expects an Error value."
      | _ -> Error.arity_error_named "error_context" 1 (List.length args)
    ))
    env in

  (*
  --# Tabulate pipeline errors
  --#
  --# Converts a list of Error values into a DataFrame with columns `node`, `code`,
  --# `message`, and `runtime` for easier inspection and composition.
  --#
  --# @name error_summary
  --# @param errors :: List The list of Error values.
  --# @return :: DataFrame A DataFrame summarizing the errors.
  --# @family base
  --# @export
  *)
  let extract_node_name err =
    match List.assoc_opt "node" err.context with
    | Some (VString s) -> s
    | _ ->
        (match List.assoc_opt "node_name" err.context with
         | Some (VString s) -> s
         | _ ->
             let prefix = "Pipeline node `" in
             let prefix_len = String.length prefix in
             let len = String.length err.message in
             if len > prefix_len && String.sub err.message 0 prefix_len = prefix then
               (match String.index_from_opt err.message prefix_len '`' with
                | Some stop when stop > prefix_len -> String.sub err.message prefix_len (stop - prefix_len)
                | _ -> "")
             else "")
  in
  let error_summary_fn args _env =
    match args with
    | [VList items] ->
        let rec get_verror = function
          | VError err -> Some err
          | VNodeResult { v = inner; _ } -> get_verror inner
          | _ -> None
        in
        let errors = List.filter_map (fun (_, v) -> get_verror v) items in
        let nrows = List.length errors in
        let arr_node = Array.make nrows None in
        let arr_code = Array.make nrows None in
        let arr_message = Array.make nrows None in
        let arr_runtime = Array.make nrows None in
        List.iteri (fun i err ->
          let node_val = extract_node_name err in
          let code_val = Utils.error_code_to_string err.code in
          let message_val = err.message in
          let runtime_val =
            match List.assoc_opt "runtime" err.context with
            | Some (VString s) -> s
            | _ -> "T"
          in
          arr_node.(i) <- Some node_val;
          arr_code.(i) <- Some code_val;
          arr_message.(i) <- Some message_val;
          arr_runtime.(i) <- Some runtime_val;
        ) errors;
        let columns = [
          ("node", Arrow_table.StringColumn arr_node);
          ("code", Arrow_table.StringColumn arr_code);
          ("message", Arrow_table.StringColumn arr_message);
          ("runtime", Arrow_table.StringColumn arr_runtime);
        ] in
        let arrow_table = Arrow_table.create columns nrows in
        VDataFrame { arrow_table; group_keys = [] }
    | [_] -> Error.type_error "Function `error_summary` expects a List."
    | _ -> Error.arity_error_named "error_summary" 1 (List.length args)
  in
  let env = Env.add "error_summary" (make_builtin ~name:"error_summary" 1 error_summary_fn) env in

  (*
  --# Chain errors to preserve provenance
  --#
  --# Explicitly chains two errors together by setting the second error as the cause
  --# of the first error.
  --#
  --# @name error_chain
  --# @param err1 :: Error The primary or outer Error.
  --# @param err2 :: Error The underlying cause Error.
  --# @return :: Error The chained Error value.
  --# @family base
  --# @export
  *)
  let error_chain_fn args _env =
    match args with
    | [VError err1; VError err2] ->
        let new_context = ("cause", VError err2) :: (List.filter (fun (k, _) -> k <> "cause") err1.context) in
        VError { err1 with context = new_context }
    | [VError _; other] ->
        Error.type_error (Printf.sprintf "Function `error_chain` expects the second argument to be an Error, got %s." (Utils.type_name other))
    | [other; _] ->
        Error.type_error (Printf.sprintf "Function `error_chain` expects the first argument to be an Error, got %s." (Utils.type_name other))
    | _ -> Error.arity_error_named "error_chain" 2 (List.length args)
  in
  let env = Env.add "error_chain" (make_builtin ~name:"error_chain" 2 error_chain_fn) env in
  env
