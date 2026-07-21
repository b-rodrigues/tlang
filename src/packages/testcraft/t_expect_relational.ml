open Ast

let fmt v = "`" ^ Utils.value_to_string v ^ "`"

let expect_binop name op_str op actual expected =
  match actual, expected with
  | VError _, _ ->
      Expect_hold (Printf.sprintf "`actual` is an error, cannot compare")
  | _, VError _ ->
      Expect_hold (Printf.sprintf "`expected` is an error, cannot compare")
  | VNA _, _ | _, VNA _ ->
      Expect_hold "One of the arguments is NA."
  | VInt a, VInt b ->
      if op (float_of_int a) (float_of_int b) then Expect_pass
      else Expect_stop (Printf.sprintf "%s %s %s" (fmt actual) op_str (fmt expected))
  | VFloat a, VFloat b ->
      if op a b then Expect_pass
      else Expect_stop (Printf.sprintf "%s %s %s" (fmt actual) op_str (fmt expected))
  | VInt a, VFloat b ->
      if op (float_of_int a) b then Expect_pass
      else Expect_stop (Printf.sprintf "%s %s %s" (fmt actual) op_str (fmt expected))
  | VFloat a, VInt b ->
      if op a (float_of_int b) then Expect_pass
      else Expect_stop (Printf.sprintf "%s %s %s" (fmt actual) op_str (fmt expected))
  | _ ->
      Expect_stop
        (Printf.sprintf "Function `%s` expects numeric arguments, got %s and %s."
           name (Utils.type_name actual) (Utils.type_name expected))

let register env =
  let env =
    Env.add "expect_lt"
      (make_builtin ~name:"expect_lt" 2 (fun args _env ->
         match args with
         | [actual; expected] -> VExpect (expect_binop "expect_lt" "<" (<) actual expected)
         | args -> Error.arity_error_named "expect_lt" 2 (List.length args)))
      env
  in
  let env =
    Env.add "expect_lte"
      (make_builtin ~name:"expect_lte" 2 (fun args _env ->
         match args with
         | [actual; expected] -> VExpect (expect_binop "expect_lte" "<=" (<=) actual expected)
         | args -> Error.arity_error_named "expect_lte" 2 (List.length args)))
      env
  in
  let env =
    Env.add "expect_gt"
      (make_builtin ~name:"expect_gt" 2 (fun args _env ->
         match args with
         | [actual; expected] -> VExpect (expect_binop "expect_gt" ">" (>) actual expected)
         | args -> Error.arity_error_named "expect_gt" 2 (List.length args)))
      env
  in
  let env =
    Env.add "expect_gte"
      (make_builtin ~name:"expect_gte" 2 (fun args _env ->
         match args with
         | [actual; expected] -> VExpect (expect_binop "expect_gte" ">=" (>=) actual expected)
         | args -> Error.arity_error_named "expect_gte" 2 (List.length args)))
      env
  in
  env
