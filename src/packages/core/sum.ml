open Ast

(*
--# Sum of numeric values
--#
--# Calculates the sum of values in a List or Vector.
--#
--# @name sum
--# @param x :: List[Number] | Vector[Number] The collection to sum.
--# @param na_rm :: Bool = false Remove NA values before summing.
--# @return :: Number | NA The sum of values.
--# @example
--#   sum([1, 2, 3])
--#   -- Returns = 6
--#
--#   sum([1, NA, 3], na_rm = true)
--#   -- Returns = 4
--# @family core
--# @export
*)
let register env =
  Env.add "sum"
    (make_builtin_named ~name:"sum" ~variadic:true 1 (fun named_args _env ->
      match Math_common.get_bool_flag "na_rm" false named_args with
      | Error e -> e
      | Ok na_rm ->
      let args = Math_common.positional_args_without ["na_rm"] named_args in
      let first_arg = match args with a :: _ -> Some a | [] -> None in
      (match first_arg with
      | Some (VList items) ->
          let rec add_all = function
            | [] -> VInt 0
            | (_, VInt n) :: rest ->
                (match add_all rest with
                 | VInt acc -> VInt (acc + n)
                 | VFloat acc -> VFloat (acc +. float_of_int n)
                 | e -> e)
            | (_, VFloat f) :: rest ->
                (match add_all rest with
                 | VInt acc -> VFloat (float_of_int acc +. f)
                 | VFloat acc -> VFloat (acc +. f)
                 | e -> e)
            | (_, VNA _) :: rest when na_rm -> add_all rest
            | (_, VNA _) :: _ -> Error.na_value_error ~na_rm:true "sum"
            | (_, (VError _ as e)) :: _ -> e
            | _ -> Error.type_error "Function `sum` requires a list of numbers."
          in
          add_all items
      | Some (VVector arr) ->
          let total_int = ref 0 in
          let total_float = ref 0.0 in
          let is_float = ref false in
          let type_error = ref None in
          let na_error_triggered = ref false in
          let na_count = ref 0 in
          for i = 0 to Array.length arr - 1 do
            match arr.(i) with
            | VInt n ->
                if !type_error = None && not !na_error_triggered then
                  if !is_float then total_float := !total_float +. float_of_int n
                  else total_int := !total_int + n
            | VFloat f ->
                if !type_error = None && not !na_error_triggered then
                  if not !is_float then begin
                    is_float := true;
                    total_float := float_of_int !total_int +. f
                  end else
                    total_float := !total_float +. f
            | VNA _ ->
                na_count := !na_count + 1;
                if not na_rm then na_error_triggered := true
            | VError _ as e ->
                if !type_error = None && not !na_error_triggered then type_error := Some e
            | _ ->
                if !type_error = None && not !na_error_triggered then
                  type_error := Some (Error.type_error "Function `sum` requires numeric values.")
          done;
          (match !type_error with
           | Some e -> e
           | None when !na_error_triggered -> Error.na_value_error ~na_rm:false ~na_count:!na_count "sum"
           | None -> if !is_float then VFloat !total_float else VInt !total_int)
      | Some (VNA _) -> Error.na_value_error ~na_rm:true "sum"
      | Some _ -> Error.type_error "Function `sum` expects a List or Vector argument."
      | None -> Error.arity_error_named "sum" 1 (List.length args))
    ))
    env
