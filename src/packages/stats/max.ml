open Ast

(*
--# Maximum value
--#
--# Returns the maximum value in a vector or list.
--#
--# @name max
--# @param x :: Vector | List The numeric data.
--# @param na_rm :: Bool Whether to remove NA values. Default is false.
--# @return :: Float The maximum value.
--# @example
--#   max([1, 2, 3])
--#   -- Returns = 3.0
--# @family stats
--# @seealso min
--# @export
*)
let register env =
  Env.add "max"
    (make_builtin_named ~name:"max" ~variadic:true 1 (fun named_args _env ->
      match Math_common.get_bool_flag "na_rm" false named_args with
      | Error e -> e
      | Ok na_rm ->
      let args = Math_common.positional_args_without ["na_rm"] named_args in
      let find_max label items =
        let max_val = ref Float.neg_infinity in
        let has_values = ref false in
        let had_error = ref None in
        let process_value v =
          if !had_error = None then
            match v with
            | VInt n ->
                let f = float_of_int n in
                if f > !max_val then max_val := f;
                has_values := true
            | VFloat f ->
                if f > !max_val then max_val := f;
                has_values := true
            | VNA _ when na_rm -> ()
            | VNA _ -> had_error := Some (Error.na_value_error ~na_rm:true label)
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        in
        List.iter process_value items;
        match !had_error with
        | Some e -> e
        | None -> if !has_values then VFloat !max_val else VNA NAFloat
      in
      let find_max_arr label arr =
        let max_val = ref Float.neg_infinity in
        let has_values = ref false in
        let had_error = ref None in
        for i = 0 to Array.length arr - 1 do
          if !had_error = None then
            match arr.(i) with
            | VInt n ->
                let f = float_of_int n in
                if f > !max_val then max_val := f;
                has_values := true
            | VFloat f ->
                if f > !max_val then max_val := f;
                has_values := true
            | VNA _ when na_rm -> ()
            | VNA _ -> had_error := Some (Error.na_value_error ~na_rm:true label)
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        done;
        match !had_error with
        | Some e -> e
        | None -> if !has_values then VFloat !max_val else VNA NAFloat
      in
      match args with
      | [VList []] -> Error.value_error "Function `max` called on empty List."
      | [VList items] -> find_max "max" (List.map snd items)
      | [VVector arr] when Array.length arr = 0 -> Error.value_error "Function `max` called on empty Vector."
      | [VVector arr] -> find_max_arr "max" arr
      | [VNA _] -> Error.na_value_error ~na_rm:true "max"
      | [val_] -> Error.type_error (Printf.sprintf "Function `max` expects a numeric List or Vector, but received %s." (Utils.type_name val_))
      | _ -> Error.arity_error_named "max" 1 (List.length args)))
    env
