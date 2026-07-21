open Ast

let fmt v = "`" ^ Utils.value_to_string v ^ "`"

let get_warnings = function
  | VNodeResult { diagnostics = { nd_warnings = []; _ }; _ } -> None
  | VNodeResult { diagnostics = { nd_warnings; _ }; _ } -> Some nd_warnings
  | VComputedNode cn ->
      let cn = !Ast.computed_node_resolver cn in
      (match Ast.get_in_memory_node_value_for_cn cn with
       | Some (VNodeResult { diagnostics = { nd_warnings = []; _ }; _ }) -> None
       | Some (VNodeResult { diagnostics = { nd_warnings; _ }; _ }) -> Some nd_warnings
       | _ -> None)
  | _ -> None

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
             (fun (n, _) ->
               match n with
               | None -> false
               | Some "kind" | Some "message" -> false
               | Some _ -> true)
             named_args
         in
         match unknown_named with
         | (Some arg_name, _) :: _ ->
             Error.type_error
               (Printf.sprintf "Function `expect_warning` received unknown named argument `%s`." arg_name)
         | _ ->
             let kind_opt =
               match List.find_opt (fun (n, _) -> n = Some "kind") named_args with
                | Some (_, VString k) when k <> "" -> Some k
                | Some (_, _) ->
                    Some ""
                    (* type error deferred: let positional check happen first *)
                | _ -> None
              in
              let kind_err =
               match List.find_opt (fun (n, _) -> n = Some "kind") named_args with
               | Some (_, v) when (match v with VString _ -> false | _ -> true) ->
                   Some (Printf.sprintf
                            "Function `expect_warning` expects the `kind` argument to be a String, got %s."
                            (Utils.type_name v))
               | _ -> None
             in
             let message_opt =
               match List.find_opt (fun (n, _) -> n = Some "message") named_args with
               | Some (_, VString m) when m <> "" -> Some m
               | _ -> None
             in
             let message_err =
               match List.find_opt (fun (n, _) -> n = Some "message") named_args with
               | Some (_, v) when (match v with VString _ -> false | _ -> true) ->
                   Some (Printf.sprintf
                            "Function `expect_warning` expects the `message` argument to be a String, got %s."
                            (Utils.type_name v))
               | _ -> None
             in
             let excluded = [ "kind"; "message" ] in
             let positional =
               named_args
               |> List.filter (fun (n, _) ->
                    match n with
                    | Some n -> not (List.mem n excluded)
                    | None -> true)
               |> List.map snd
             in
             match kind_err with
             | Some err -> Error.type_error err
             | None ->
             match message_err with
             | Some err -> Error.type_error err
             | None ->
             match positional with
             | [v] ->
                 (match v with
                  | VNA _ -> VExpect (Expect_hold "`node` is NA, cannot check for warnings")
                  | VError err ->
                      VExpect (Expect_stop (Printf.sprintf "`node` is an error: %s" err.message))
                  | _ ->
                      (match get_warnings v with
                       | None ->
                           VExpect (Expect_stop "No warnings found on this node")
                       | Some warnings ->
                           let matches =
                             match kind_opt, message_opt with
                              | Some kind, Some pat ->
                                  List.exists (fun w ->
                                    w.nw_kind = kind &&
                                    (try ignore (Str.search_forward (Str.regexp pat) w.nw_message 0); true
                                     with _ -> false)
                                  ) warnings
                              | Some kind, None ->
                                  List.exists (fun w -> w.nw_kind = kind) warnings
                              | None, Some pat ->
                                  List.exists (fun w ->
                                    try ignore (Str.search_forward (Str.regexp pat) w.nw_message 0); true
                                    with _ -> false
                                  ) warnings
                             | None, None -> true
                           in
                           if matches then VExpect Expect_pass
                           else
                             let kinds = warnings
                                           |> List.map (fun w -> w.nw_kind)
                                           |> List.sort_uniq String.compare
                                           |> String.concat ", "
                             in
                             VExpect (Expect_stop
                                        (Printf.sprintf
                                           "No matching warning found on node. Available warning kinds: [%s]" kinds))))
             | args -> Error.arity_error_named "expect_warning" 1 (List.length args)))
      env
  in
  env
