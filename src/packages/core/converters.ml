open Ast

let parse_numeric_string s =
  let upper = String.uppercase_ascii (String.trim s) in
  match upper with
  | "TRUE" | "T" -> Some 1.0
  | "FALSE" | "F" -> Some 0.0
  | _ ->
      let s1 = Str.global_replace (Str.regexp_string "%") "" upper in
      let s2 = Str.global_replace (Str.regexp_string " ") "" s1 in
      let s3 = Str.global_replace (Str.regexp_string ",") "." s2 in
      let s4 = Str.global_replace (Str.regexp_string ";") "." s3 in
      try Some (float_of_string s4)
      with Failure _ -> None

(*
--# Convert to Integer
--#
--# Coerces a value to an integer robustly. Handles strings with
--# spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'.
--#
--# @name to_integer
--# @param x :: Any The value to convert.
--# @return :: Int | NA The converted integer.
--# @example
--#   to_integer("12 300")
--#   to_integer("TRUE")
--#   to_integer(3.14)
--# @family core
--# @export
*)
let register_integer env =
  Env.add "to_integer"
    (make_builtin ~name:"to_integer" 1 (fun args _env ->
      let convert v = match v with
        | VInt i -> VInt i
        | VFloat f -> VInt (int_of_float f)
        | VBool b -> VInt (if b then 1 else 0)
        | VString s ->
            (match parse_numeric_string s with
             | Some f -> VInt (int_of_float f)
             | None -> VNA NAGeneric)
        | VNA _ -> VNA NAGeneric
        | _ -> Error.type_error (Printf.sprintf "Cannot coerce %s to integer" (Utils.type_name v))
      in
      match args with
      | [VVector arr] ->
          let had_error = ref None in
          let res = Array.map (fun v -> 
            let converted = convert v in
            (match converted with VError _ as e -> had_error := Some e | _ -> ());
            converted
          ) arr in
          (match !had_error with Some e -> e | None -> VVector res)
      | [VList items] ->
          let had_error = ref None in
          let res = List.map (fun (n, v) -> 
            let converted = convert v in
            (match converted with VError _ as e -> had_error := Some e | _ -> ());
            (n, converted)
          ) items in
          (match !had_error with Some e -> e | None -> VList res)
      | [v] -> convert v
      | _ -> Error.arity_error_named "to_integer" ~expected:1 ~received:(List.length args)
    ))
    env

(*
--# Convert to Float
--#
--# Coerces a value to a float robustly. Handles strings with
--# spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'.
--#
--# @name to_float
--# @param x :: Any The value to convert.
--# @return :: Float | NA The converted float.
--# @example
--#   to_float("3,14")
--#   to_float("15%")
--#   to_float(42)
--# @family core
--# @export
*)
let register_float env =
  Env.add "to_float"
    (make_builtin ~name:"to_float" 1 (fun args _env ->
      let convert v = match v with
        | VFloat f -> VFloat f
        | VInt i -> VFloat (float_of_int i)
        | VBool b -> VFloat (if b then 1.0 else 0.0)
        | VString s ->
            (match parse_numeric_string s with
             | Some f -> VFloat f
             | None -> VNA NAGeneric)
        | VNA _ -> VNA NAGeneric
        | _ -> Error.type_error (Printf.sprintf "Cannot coerce %s to float" (Utils.type_name v))
      in
      match args with
      | [VVector arr] ->
          let had_error = ref None in
          let res = Array.map (fun v -> 
            let converted = convert v in
            (match converted with VError _ as e -> had_error := Some e | _ -> ());
            converted
          ) arr in
          (match !had_error with Some e -> e | None -> VVector res)
      | [VList items] ->
          let had_error = ref None in
          let res = List.map (fun (n, v) -> 
            let converted = convert v in
            (match converted with VError _ as e -> had_error := Some e | _ -> ());
            (n, converted)
          ) items in
          (match !had_error with Some e -> e | None -> VList res)
      | [v] -> convert v
      | _ -> Error.arity_error_named "to_float" ~expected:1 ~received:(List.length args)
    ))
    env

(*
--# Convert to Numeric
--#
--# Alias for `to_float`. Coerces a value to a numeric (float) robustly.
--#
--# @name to_numeric
--# @param x :: Any The value to convert.
--# @return :: Float | NA The converted float.
--# @family core
--# @export
*)
let register_numeric env =
  Env.add "to_numeric"
    (make_builtin ~name:"to_numeric" 1 (fun args _env ->
      let convert v = match v with
        | VFloat f -> VFloat f
        | VInt i -> VFloat (float_of_int i)
        | VBool b -> VFloat (if b then 1.0 else 0.0)
        | VString s ->
            (match parse_numeric_string s with
             | Some f -> VFloat f
             | None -> VNA NAGeneric)
        | VNA _ -> VNA NAGeneric
        | _ -> Error.type_error (Printf.sprintf "Cannot coerce %s to numeric" (Utils.type_name v))
      in
      match args with
      | [VVector arr] ->
          let had_error = ref None in
          let res = Array.map (fun v -> 
            let converted = convert v in
            (match converted with VError _ as e -> had_error := Some e | _ -> ());
            converted
          ) arr in
          (match !had_error with Some e -> e | None -> VVector res)
      | [VList items] ->
          let had_error = ref None in
          let res = List.map (fun (n, v) -> 
            let converted = convert v in
            (match converted with VError _ as e -> had_error := Some e | _ -> ());
            (n, converted)
          ) items in
          (match !had_error with Some e -> e | None -> VList res)
      | [v] -> convert v
      | _ -> Error.arity_error_named "to_numeric" ~expected:1 ~received:(List.length args)
    ))
    env

let register env =
  env |> register_integer |> register_float |> register_numeric
