(*
--# Strict boolean true assertion
--#
--# Passes only if `x` is `VBool true`. For a looser truthiness check,
--# use `expect_truthy` instead.
--#
--# @name expect_true
--# @param x :: Any The value to check.
--# @return :: Expect `Expect_pass` only when `x` is `true`; `Expect_hold` on NA; `Expect_stop` on errors or non-true values.
--# @example
--#   assert(expect_true(true))
--#   assert(expect_true(1 < 2))
--# @family testcraft
--# @seealso expect_false, expect_truthy, expect_falsy
--# @export
*)

(*
--# Strict boolean false assertion
--#
--# Passes only if `x` is `VBool false`. For a looser falsiness check,
--# use `expect_falsy` instead.
--#
--# @name expect_false
--# @param x :: Any The value to check.
--# @return :: Expect `Expect_pass` only when `x` is `false`; `Expect_hold` on NA; `Expect_stop` on errors or non-false values.
--# @example
--#   assert(expect_false(false))
--#   assert(expect_false(2 < 1))
--# @family testcraft
--# @seealso expect_true, expect_truthy, expect_falsy
--# @export
*)

(*
--# Loose truthiness assertion
--#
--# Passes if `x` is truthy per `is_truthy` (non-zero numbers, non-empty
--# strings, non-empty containers, etc.).
--#
--# @name expect_truthy
--# @param x :: Any The value to check.
--# @return :: Expect `Expect_pass` when `x` is truthy; `Expect_hold` on NA; `Expect_stop` on errors or falsy values.
--# @example
--#   assert(expect_truthy(42))
--#   assert(expect_truthy("hello"))
--# @family testcraft
--# @seealso expect_true, expect_false, expect_falsy
--# @export
*)

(*
--# Loose falsiness assertion
--#
--# Passes if `x` is falsy per `is_truthy` (`0`, `false`, `VNullNode`,
--# empty containers, etc.). NA produces `Expect_hold`.
--#
--# @name expect_falsy
--# @param x :: Any The value to check.
--# @return :: Expect `Expect_pass` when `x` is falsy; `Expect_hold` on NA; `Expect_stop` on errors or truthy values.
--# @example
--#   assert(expect_falsy(0))
--#   assert(expect_falsy(false))
--# @family testcraft
--# @seealso expect_true, expect_false, expect_truthy
--# @export
*)

(*
--# Type name assertion
--#
--# Passes if the runtime type name of `x` matches the given string
--# (e.g. `"Int"`, `"String"`, `"DataFrame"`).
--#
--# @name expect_type
--# @param x :: Any The value to inspect.
--# @param type_name :: String Expected type name.
--# @return :: Expect `Expect_pass` when types match; `Expect_hold` on NA; `Expect_stop` on errors or type mismatch.
--# @example
--#   assert(expect_type(42, "Int"))
--#   assert(expect_type("hello", "String"))
--# @family testcraft
--# @seealso expect_true, expect_error
--# @export
*)

(*
--# Error assertion with optional class and message filtering
--#
--# Passes if `expr` is a `VError`. Optionally verifies the error class
--# string and/or applies a regex pattern match against the error message.
--#
--# @name expect_error
--# @param expr :: Any The value to check (typically the result of an expression that may error).
--# @param class :: String = "" Optional error class to match (e.g. `"TypeError"`, `"RuntimeError"`).
--# @param message :: String = "" Optional regex pattern to match against the error message.
--# @return :: Expect `Expect_pass` when all checks pass; `Expect_stop` otherwise.
--# @example
--#   assert(expect_error(error("boom")))
--#   assert(expect_error(error("boom"), class = "GenericError"))
--#   assert(expect_error(error("invalid value"), message = "invalid"))
--# @family testcraft
--# @seealso expect_type, expect_true
--# @export
*)

(*
--# Container length assertion
--#
--# Passes if the length/size/row-count of `x` equals `n`. Supports
--# Vector, List, String, DataFrame (row count), and Dict (entry count).
--#
--# @name expect_length
--# @param x :: Vector | List | String | DataFrame | Dict The container to measure.
--# @param n :: Int Expected length.
--# @return :: Expect `Expect_pass` when length matches; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.
--# @example
--#   assert(expect_length([1, 2, 3], 3))
--#   assert(expect_length("hello", 5))
--# @family testcraft
--# @seealso expect_nrow, expect_ncol
--# @export
*)

open Ast
open Testcraft_utils

let register env =
  (* expect_true: only VBool true passes *)
  let env =
    Env.add "expect_true"
      (make_builtin ~name:"expect_true" 1 (fun args _env ->
         match args with
         | [VBool true] -> VExpect Expect_pass
         | [VNA _] -> VExpect (Expect_hold "`actual` is NA, cannot check truth")
         | [VError err] ->
             VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
         | [VError err] ->
             VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
         | [VError err] ->
             VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
         | [VError err] ->
             VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check type")
         | [VError err; _] ->
             VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
                      | [VNA _] ->
                          VExpect (Expect_hold "`actual` is NA, cannot check for error")
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
                                           ignore (Str.search_forward (Str.regexp pat) err.message 0);
                                           VExpect Expect_pass
                                         with
                                         | Not_found ->
                                             VExpect
                                               (Expect_stop
                                                  (Printf.sprintf
                                                     "Expected error message matching /%s/, got: %s"
                                                     pat err.message))
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
         | [VError err; _] ->
             VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
