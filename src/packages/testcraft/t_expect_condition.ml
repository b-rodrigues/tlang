open Ast

let warnings_from_result = function
  | VNodeResult { diagnostics = { nd_warnings = []; _ }; _ } -> None
  | VNodeResult { diagnostics = { nd_warnings; _ }; _ } -> Some nd_warnings
  | _ -> None

let regex_matches re s =
  try ignore (Str.search_forward re s 0); true
  with Not_found -> false

let get_warnings v = match v with
  | VComputedNode cn ->
      let cn = !Ast.computed_node_resolver cn in
      (match Ast.get_in_memory_node_value_for_cn cn with
       | Some v -> warnings_from_result v
       | None -> None)
  | _ -> warnings_from_result v

(*
--# Assert that a pipeline node produced a warning
--#
--# Passes if the node's diagnostics contain at least one warning.
--# Optionally filters by warning `kind` string and/or regex on the warning `message`.
--#
--# @name expect_warning
--# @param node :: NodeResult | ComputedNode The computed node to inspect.
--# @param kind :: String = "" Optional warning kind to match exactly (e.g. "NAExcluded").
--# @param message :: String = "" Optional regex pattern to match against the warning message.
--# @return :: Expect Pass if warnings are present and match any provided filters.
--# @example
--#   assert(expect_warning(read_node(p.my_node)))
--#   assert(expect_warning(read_node(p.my_node), kind = "NAExcluded"))
--#   assert(expect_warning(read_node(p.my_node), message = "excluded"))
--# @family testcraft
--# @seealso expect_error
--# @export
*)
let register env =
  let env =
    Env.add "expect_warning"
      (make_builtin_named ~name:"expect_warning" ~variadic:true ~unwrap:false 1 (fun named_args _env ->
         let unknown_named =
           List.filter
             (function
               | (None, _) -> false
               | (Some "kind", _) | (Some "message", _) -> false
               | (Some _, _) -> true)
             named_args
         in
         match unknown_named with
         | (Some arg_name, _) :: _ ->
             Error.type_error
               (Printf.sprintf "Function `expect_warning` received unknown named argument `%s`." arg_name)
         | _ ->
             let kind_arg = List.find_opt (fun (n, _) -> n = Some "kind") named_args in
             let message_arg = List.find_opt (fun (n, _) -> n = Some "message") named_args in
             let kind_err =
               match kind_arg with
               | Some (_, v) when (match v with VString _ -> false | _ -> true) ->
                   Some (Printf.sprintf
                            "Function `expect_warning` expects the `kind` argument to be a String, got %s."
                            (Utils.type_name v))
               | _ -> None
             in
             let kind_opt =
               match kind_arg with
               | Some (_, VString k) when k <> "" -> Some k
               | _ -> None
             in
             let message_err =
               match message_arg with
               | Some (_, v) when (match v with VString _ -> false | _ -> true) ->
                   Some (Printf.sprintf
                            "Function `expect_warning` expects the `message` argument to be a String, got %s."
                            (Utils.type_name v))
               | _ -> None
             in
             let message_opt =
               match message_arg with
               | Some (_, VString m) when m <> "" -> Some m
               | _ -> None
             in
             let re =
               match message_opt with
               | Some pat ->
                    (try Ok (Some (Str.regexp pat))
                     with Failure msg ->
                       Error (Error.value_error
                                (Printf.sprintf
                                   "Invalid regex pattern `%s`: %s" pat msg)))
               | None -> Ok None
             in
             let positional =
               named_args
               |> List.filter (function
                    | (Some "kind", _) | (Some "message", _) -> false
                    | _ -> true)
               |> List.map snd
             in
             match kind_err with
             | Some err -> Error.type_error err
             | None ->
             match message_err with
             | Some err -> Error.type_error err
             | None ->
             match re with
             | Error err -> err
             | Ok re_opt ->
             match positional with
             | [v] ->
                  (match v with
                   | VNA _ -> VExpect (Expect_hold "`node` is NA, cannot check for warnings")
                   | VError err ->
                       VExpect (Expect_stop (Printf.sprintf "`node` is an error: %s" err.message))
                   | VNodeResult _ | VComputedNode _ ->
                       (match get_warnings v with
                        | None -> VExpect (Expect_stop "No warnings found on this node")
                        | Some warnings ->
                            let matches =
                              match kind_opt, re_opt with
                              | Some kind, Some re ->
                                  List.exists (fun w ->
                                    w.nw_kind = kind
                                    && regex_matches re w.nw_message
                                  ) warnings
                              | Some kind, None ->
                                  List.exists (fun w -> w.nw_kind = kind) warnings
                              | None, Some re ->
                                  List.exists (fun w -> regex_matches re w.nw_message) warnings
                              | None, None -> true
                            in
                            if matches then VExpect Expect_pass
                            else
                              let kinds =
                                warnings
                                |> List.map (fun w -> w.nw_kind)
                                |> List.sort_uniq String.compare
                                |> String.concat ", "
                              in
                              let msg =
                                match kind_opt, message_opt with
                                | Some k, Some p ->
                                    Printf.sprintf
                                      "No warning of kind `%s` matching message pattern `%s` found. Available warning kinds: [%s]"
                                      k p kinds
                                | Some k, None ->
                                    Printf.sprintf
                                      "No warning of kind `%s` found. Available warning kinds: [%s]"
                                      k kinds
                                | None, Some p ->
                                    Printf.sprintf
                                      "No warning matching message pattern `%s` found. Available warning kinds: [%s]"
                                      p kinds
                                | None, None ->
                                    Printf.sprintf
                                      "No matching warning found on node. Available warning kinds: [%s]"
                                      kinds
                              in
                              VExpect (Expect_stop msg))
                   | _ ->
                       Error.type_error
                         (Printf.sprintf
                            "Function `expect_warning` expects a NodeResult or ComputedNode, got %s."
                            (Utils.type_name v)))
             | args -> Error.arity_error_named "expect_warning" 1 (List.length args)))
      env
  in
  env
