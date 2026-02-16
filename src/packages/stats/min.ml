open Ast

(*
--# Minimum value
--#
--# Returns the minimum value in a vector or list.
--#
--# @name min
--# @param x :: Vector | List The numeric data.
--# @return :: Float The minimum value.
--# @example
--#   min([1, 2, 3])
--#   -- Returns: 1.0
--# @family stats
--# @seealso max
--# @export
*)
let register env =
  Env.add "min"
    (make_builtin ~name:"min" 1 (fun args _env ->
      let extract_nums_arr label arr =
        let len = Array.length arr in
        let had_error = ref None in
        let result = Array.make len 0.0 in
        for i = 0 to len - 1 do
          if !had_error = None then
            match arr.(i) with
            | VInt n -> result.(i) <- float_of_int n
            | VFloat f -> result.(i) <- f
            | VNA _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        done;
        match !had_error with Some e -> Error e | None -> Ok result
      in
      match args with
      | [VList []] -> Error.value_error "Function `min` called on empty List."
      | [VList items] ->
          let arr = Array.of_list (List.map snd items) in
          (match extract_nums_arr "min" arr with
           | Error e -> e
           | Ok nums ->
             VFloat (Array.fold_left Float.min Float.infinity nums))
      | [VVector arr] when Array.length arr = 0 -> Error.value_error "Function `min` called on empty Vector."
      | [VVector arr] ->
          (match extract_nums_arr "min" arr with
           | Error e -> e
           | Ok nums ->
             VFloat (Array.fold_left Float.min Float.infinity nums))
      | [VNA _] -> Error.type_error "Function `min` encountered NA value. Handle missingness explicitly."
      | [_] -> Error.type_error "Function `min` expects a numeric List or Vector."
      | _ -> Error.arity_error_named "min" ~expected:1 ~received:(List.length args)
    ))
    env
