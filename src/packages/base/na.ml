open Ast

let register ~make_builtin env =
  let env = Env.add "na"
    (make_builtin 0 (fun _args _env -> VNA NAGeneric))
    env in
  let env = Env.add "na_bool"
    (make_builtin 0 (fun _args _env -> VNA NABool))
    env in
  let env = Env.add "na_int"
    (make_builtin 0 (fun _args _env -> VNA NAInt))
    env in
  let env = Env.add "na_float"
    (make_builtin 0 (fun _args _env -> VNA NAFloat))
    env in
  let env = Env.add "na_string"
    (make_builtin 0 (fun _args _env -> VNA NAString))
    env in
  env
