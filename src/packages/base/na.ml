open Ast

let register env =
  (*
  --# Generic NA
  --#
  --# Represents a missing value of generic type.
  --#
  --# @name na
  --# @return :: NA
  --# @family base
  --# @seealso is_na
  --# @export
  *)
  let env = Env.add "na"
    (make_builtin ~name:"na" 0 (fun _args _env -> VNA NAGeneric))
    env in
  (*
  --# Boolean NA
  --#
  --# Represents a missing boolean value.
  --#
  --# @name na_bool
  --# @return :: NA
  --# @family base
  --# @seealso na
  --# @export
  *)
  let env = Env.add "na_bool"
    (make_builtin ~name:"na_bool" 0 (fun _args _env -> VNA NABool))
    env in
  (*
  --# Integer NA
  --#
  --# Represents a missing integer value.
  --#
  --# @name na_int
  --# @return :: NA
  --# @family base
  --# @seealso na
  --# @export
  *)
  let env = Env.add "na_int"
    (make_builtin ~name:"na_int" 0 (fun _args _env -> VNA NAInt))
    env in
  (*
  --# Float NA
  --#
  --# Represents a missing float value.
  --#
  --# @name na_float
  --# @return :: NA
  --# @family base
  --# @seealso na
  --# @export
  *)
  let env = Env.add "na_float"
    (make_builtin ~name:"na_float" 0 (fun _args _env -> VNA NAFloat))
    env in
  (*
  --# String NA
  --#
  --# Represents a missing string value.
  --#
  --# @name na_string
  --# @return :: NA
  --# @family base
  --# @seealso na
  --# @export
  *)
  let env = Env.add "na_string"
    (make_builtin ~name:"na_string" 0 (fun _args _env -> VNA NAString))
    env in
  env
