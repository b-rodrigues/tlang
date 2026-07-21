open Ast

let fmt v = "`" ^ Utils.value_to_string v ^ "`"

let register env =
  (* expect_true: only VBool true passes *)
  let env =
    Env.add "expect_true"
      (make_builtin ~name:"expect_true" 1 (fun args _env ->
         match args with
         | [VBool true] -> VExpect Expect_pass
         | [VNA _] -> VExpect (Expect_hold "`actual` is NA, cannot check truth")
         | [v] -> VExpect (Expect_stop (Printf.sprintf "Expected %s to be true (VBool true)" (fmt v)))
         | args -> Error.arity_error_named "expect_true" 1 (List.length args)))
      env
  in
  (* expect_false: only VBool false passes *)
  let env =
    Env.add "expect_false"
      (make_builtin ~name:"expect_false" 1 (fun args _env ->
         match args with
         | [VBool false] -> VExpect Expect_pass
         | [VNA _] -> VExpect (Expect_hold "`actual` is NA, cannot check falsity")
         | [v] -> VExpect (Expect_stop (Printf.sprintf "Expected %s to be false (VBool false)" (fmt v)))
         | args -> Error.arity_error_named "expect_false" 1 (List.length args)))
      env
  in
  (* expect_truthy: uses is_truthy *)
  let env =
    Env.add "expect_truthy"
      (make_builtin ~name:"expect_truthy" 1 (fun args _env ->
         match args with
         | [VNA _] -> VExpect (Expect_hold "`actual` is NA, cannot check truthiness")
         | [v] ->
             if Utils.is_truthy v then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "%s is not truthy" (fmt v)))
         | args -> Error.arity_error_named "expect_truthy" 1 (List.length args)))
      env
  in
  (* expect_falsy: not is_truthy *)
  let env =
    Env.add "expect_falsy"
      (make_builtin ~name:"expect_falsy" 1 (fun args _env ->
         match args with
         | [VNA _] -> VExpect (Expect_hold "`actual` is NA, cannot check falsiness")
         | [v] ->
             if not (Utils.is_truthy v) then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "%s is not falsy" (fmt v)))
         | args -> Error.arity_error_named "expect_falsy" 1 (List.length args)))
      env
  in
  (* expect_type: check type_name(x) == type_string *)
  let env =
    Env.add "expect_type"
      (make_builtin ~name:"expect_type" 2 (fun args _env ->
         match args with
         | [v; VString expected_type] ->
             let actual_type = Utils.type_name v in
             if actual_type = expected_type then VExpect Expect_pass
             else
               VExpect
                 (Expect_stop
                    (Printf.sprintf "Expected type `%s`, got type `%s`" expected_type actual_type))
         | [_; other] ->
             Error.type_error
               (Printf.sprintf
                  "Function `expect_type` expects a String as second argument, got %s."
                  (Utils.type_name other))
         | args -> Error.arity_error_named "expect_type" 2 (List.length args)))
      env
  in
  (* expect_error: passes if expr is a VError; optional class + message regex *)
  let env =
    Env.add "expect_error"
      (make_builtin_named ~name:"expect_error" ~variadic:true 1 (fun named_args _env ->
         let unknown_named =
           List.filter
             (fun (n, _) ->
               match n with
               | None -> false
               | Some "class" | Some "message" -> false
               | Some _ -> true)
             named_args
         in
         match unknown_named with
         | (Some arg_name, _) :: _ ->
             Error.type_error
               (Printf.sprintf "Function `expect_error` received unknown named argument `%s`." arg_name)
         | _ ->
             let class_opt =
               List.find_opt (fun (n, _) -> n = Some "class") named_args
             in
             let message_opt =
               List.find_opt (fun (n, _) -> n = Some "message") named_args
             in
             (match class_opt with
              | Some (_, other) when (match other with VString _ -> false | _ -> true) ->
                  Error.type_error
                    (Printf.sprintf
                       "Function `expect_error` expects the `class` argument to be a String, got %s."
                       (Utils.type_name other))
              | _ ->
                 (match message_opt with
                  | Some (_, other) when (match other with VString _ -> false | _ -> true) ->
                      Error.type_error
                        (Printf.sprintf
                           "Function `expect_error` expects the `message` argument to be a String, got %s."
                           (Utils.type_name other))
                  | _ ->
                      let expected_class =
                        match class_opt with
                        | Some (_, VString c) when c <> "" -> Some c
                        | _ -> None
                      in
                      let expected_message_pattern =
                        match message_opt with
                        | Some (_, VString m) when m <> "" -> Some m
                        | _ -> None
                      in
                      let positional =
                        let excluded = [ "class"; "message" ] in
                        named_args
                        |> List.filter (fun (n, _) ->
                             match n with
                             | Some n -> not (List.mem n excluded)
                             | None -> true)
                        |> List.map snd
                      in
                      match positional with
                      | [v] ->
                          (match v with
                           | VError err ->
                               let code_str = Utils.error_code_to_string err.code in
                               (match expected_class with
                                | Some cls when cls <> code_str ->
                                    VExpect
                                      (Expect_stop
                                         (Printf.sprintf
                                            "Expected error class `%s`, got `%s`: %s" cls code_str err.message))
                                | _ ->
                                   (match expected_message_pattern with
                                    | Some pat ->
                                        (try
                                           if Str.string_match (Str.regexp pat) err.message 0 then
                                             VExpect Expect_pass
                                           else
                                             VExpect
                                               (Expect_stop
                                                  (Printf.sprintf
                                                     "Expected error message matching /%s/, got: %s"
                                                     pat err.message))
                                         with
                                         | Failure _ ->
                                             Error.value_error
                                               (Printf.sprintf
                                                  "Function `expect_error` received invalid regex pattern: %s" pat))
                                    | None -> VExpect Expect_pass))
                           | _ ->
                               VExpect
                                 (Expect_stop
                                    (Printf.sprintf "Expected an error, got %s: %s"
                                       (Utils.type_name v) (Utils.value_to_string v))))
                      | args -> Error.arity_error_named "expect_error" 1 (List.length args)))))
      env
  in
  (* expect_length: check length of container *)
  let env =
    Env.add "expect_length"
      (make_builtin ~name:"expect_length" 2 (fun args _env ->
         match args with
         | [VVector arr; VInt n] ->
             let len = Array.length arr in
             if len = n then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "Expected length %d, got length %d" n len))
         | [VList lst; VInt n] ->
             let len = List.length lst in
             if len = n then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "Expected length %d, got length %d" n len))
         | [VString s; VInt n] ->
             let len = String.length s in
             if len = n then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "Expected length %d, got length %d" n len))
         | [VDataFrame df; VInt n] ->
             let len = Arrow_table.num_rows df.arrow_table in
             if len = n then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "Expected %d rows, got %d rows" n len))
         | [VDict entries; VInt n] ->
             let len = List.length entries in
             if len = n then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "Expected %d entries, got %d" n len))
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check length")
         | [VError _; _] -> VExpect (Expect_hold "`actual` is an error, cannot check length")
         | [VInt _; _] -> VExpect (Expect_stop "Cannot get length of an Int")
         | [VFloat _; _] -> VExpect (Expect_stop "Cannot get length of a Float")
         | [VBool _; _] -> VExpect (Expect_stop "Cannot get length of a Bool")
         | [_; other] ->
             Error.type_error
               (Printf.sprintf
                  "Function `expect_length` expects Int as second argument, got %s."
                  (Utils.type_name other))
         | args -> Error.arity_error_named "expect_length" 2 (List.length args)))
      env
  in
  env
