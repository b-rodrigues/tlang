open Ast

type resolved_err = {
  re_code: string;
  re_message: string;
  re_context: (string * value) list;
}

let find_logged_error node_name =
  let logs = Builder.get_logs () in
  let rec find_in_logs = function
    | [] -> None
    | log_file :: tail ->
        let log_path = Filename.concat Builder.pipeline_dir log_file in
        (try
           let json = Yojson.Safe.from_file log_path in
           let open Yojson.Safe.Util in
           let nodes = json |> member "nodes" |> to_list in
           let found = List.find_map (fun node_json ->
             let name = node_json |> member "node" |> to_string in
             if name = node_name then
               let status = node_json |> member "status" |> to_string in
               if status = "Errored" then
                 let err_code =
                   match node_json |> member "error_code" with
                   | `String s -> s
                   | _ -> "NixError"
                 in
                 let err_message =
                   match node_json |> member "error_message" with
                   | `String s -> s
                   | _ -> "Nix build failed."
                 in
                 Some (err_code, err_message)
               else None
             else None
           ) nodes in
           match found with
           | Some res -> Some res
           | None -> find_in_logs tail
         with
         | Out_of_memory | Stack_overflow as exn -> raise exn
         | Sys_error _ | Yojson.Json_error _ | Yojson.Safe.Util.Type_error _ -> find_in_logs tail)
  in
  find_in_logs logs

let resolve_error_val = function
  | VNodeResult { diagnostics; _ } ->
      (match diagnostics.nd_error with
       | Some err ->
           Some {
             re_code = err.ne_kind;
             re_message = err.ne_message;
             re_context = [
               ("fn", VString err.ne_fn);
               ("na_count", VInt err.ne_na_count);
               ("node_status", VString "errored")
             ];
           }
       | None -> None)
  | VComputedNode cn ->
      let cn = !Ast.computed_node_resolver cn in
      if cn.cn_path = "" || cn.cn_path = "<unbuilt>" then
        (* No store path exists; must be a hard nix-build failure *)
        (match find_logged_error cn.cn_name with
         | Some (code, message) ->
             Some {
               re_code = code;
               re_message = message;
               re_context = [("node_name", VString cn.cn_name); ("node_status", VString "errored")];
             }
         | None -> None)
      else
        (* Store path exists; check for soft-fail or read standard *)
        (match Builder.logged_node_value cn.cn_name cn with
         | VError err ->
             Some {
               re_code = Utils.error_code_to_string err.code;
               re_message = err.message;
               re_context = err.context;
             }
         | _ ->
             (match find_logged_error cn.cn_name with
              | Some (code, message) ->
                  Some {
                    re_code = code;
                    re_message = message;
                    re_context = [("node_name", VString cn.cn_name); ("node_status", VString "errored")];
                  }
              | None -> None))
  | _ -> None

let resolve_warning_val = function
  | VNodeResult { diagnostics; _ } when diagnostics.nd_warnings <> [] ->
      let s = Ast.Utils.format_warning_messages diagnostics.nd_warnings in
      if s <> "" then Some s else None
  | VComputedNode cn ->
      let cn = !Ast.computed_node_resolver cn in
      (match Ast.get_in_memory_node_value_for_cn cn with
       | Some (VNodeResult { diagnostics; _ }) when diagnostics.nd_warnings <> [] ->
           let s = Ast.Utils.format_warning_messages diagnostics.nd_warnings in
           if s <> "" then Some s else None
       | _ ->
           if cn.cn_path <> "" && cn.cn_path <> "<unbuilt>" then
             let diag = Builder.logged_node_diagnostics cn.cn_name cn in
             let s = Ast.Utils.format_warning_messages diag.nd_warnings in
             if s <> "" then Some s else None
           else None)
  | _ -> None

(*
--# Get error code
--#
--# Returns the error code as a string (e.g., "TypeError", "ValueError").
--#
--# @name error_code
--# @param node_or_error :: Error The error value or computed node to inspect.
--# @return :: String The error code as a string.
--# @family base
--# @export
*)
let register env =
  let env = Env.add "error_code"
    (make_builtin ~name:"error_code" 1 (fun args _env ->
      match args with
      | [VError { code; _ }] -> VString (Utils.error_code_to_string code)
      | [(VComputedNode _ | VNodeResult _) as v] ->
          (match resolve_error_val v with
           | Some err -> VString err.re_code
           | None -> Error.type_error "Function `error_code` expects an Error value.")
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `error_code` expects an Error value or node, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "error_code" 1 (List.length args)
    ))
    env in
  
  (*
  --# Get error message
  --#
  --# Returns the human-readable message associated with an error.
  --#
  --# @name error_msg
  --# @param node_or_error :: Error The error value or computed node to inspect.
  --# @return :: String The error message.
  --# @family base
  --# @export
  *)
  let env = Env.add "error_msg"
    (make_builtin ~name:"error_msg" 1 (fun args _env ->
      match args with
      | [VError { message; _ }] -> VString message
      | [(VComputedNode _ | VNodeResult _) as v] ->
          (match resolve_error_val v with
           | Some err -> VString err.re_message
           | None -> Error.type_error "Function `error_msg` expects an Error value.")
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `error_msg` expects an Error value or node, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "error_msg" 1 (List.length args)
    ))
    env in

  (*
  --# Get warning message
  --#
  --# Returns the human-readable warning associated with a completed computed
  --# node, or an empty string if none. Upstream warnings inherited from
  --# ancestor nodes are prefixed with the source node name for clear
  --# provenance. Multiple warnings are joined with ". Furthermore, ".
  --#
  --# @name warning_msg
  --# @param node :: ComputedNode The computed node to inspect.
  --# @return :: String The formatted warning message, or "" if no warnings.
  --# @family base
  --# @export
  *)
  let env = Env.add "warning_msg"
    (make_builtin ~name:"warning_msg" 1 (fun args _env ->
      match args with
      | [(VComputedNode _ | VNodeResult _) as v] ->
          (match resolve_warning_val v with
           | Some w -> VString w
           | None -> VString "")
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `warning_msg` expects a ComputedNode or NodeResult, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "warning_msg" 1 (List.length args)
    ))
    env in
  
  (*
  --# Get error context
  --#
  --# Returns a dictionary containing contextual information about where and why
  --# the error occurred.
  --#
  --# @name error_context
  --# @param node_or_error :: Error The error value or computed node to inspect.
  --# @return :: Dict A dictionary of related context data.
  --# @family base
  --# @export
  *)
  let env = Env.add "error_context"
    (make_builtin ~name:"error_context" 1 (fun args _env ->
      match args with
      | [VError { context; _ }] ->
          VDict context
      | [(VComputedNode _ | VNodeResult _) as v] ->
          (match resolve_error_val v with
           | Some err -> VDict err.re_context
           | None -> Error.type_error "Function `error_context` expects an Error value.")
      | [other] ->
          Error.type_error
            (Printf.sprintf "Function `error_context` expects an Error value or node, but got %s."
               (Utils.type_name other))
      | _ -> Error.arity_error_named "error_context" 1 (List.length args)
    ))
    env in

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
