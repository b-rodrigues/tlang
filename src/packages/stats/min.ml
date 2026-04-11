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
--#   -- Returns = 1.0
--# @family stats
--# @seealso max
--# @export
*)
let register env =
  Env.add "min"
    (make_builtin_named ~name:"min" ~variadic:true 1 (fun named_args _env ->
      let na_rm =
        List.exists (fun (name, v) ->
          name = Some "na_rm" && (match v with VBool true -> true | _ -> false)
        ) named_args
      in
      let args =
        List.filter (fun (name, _) -> name <> Some "na_rm") named_args |> List.map snd
      in
      let extract_nums_arr label arr =
        let nums = ref [] in
        let had_error = ref None in
        for i = 0 to Array.length arr - 1 do
          if !had_error = None then
            match arr.(i) with
            | VInt n -> nums := float_of_int n :: !nums
            | VFloat f -> nums := f :: !nums
            | VNA _ when na_rm -> ()
            | VNA _ -> had_error := Some (Error.na_value_error ~na_rm:true label)
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        done;
        match !had_error with Some e -> Error e | None -> Ok (Array.of_list (List.rev !nums))
      in
      match args with
      | [VList []] -> Error.value_error "Function `min` called on empty List."
      | [VList items] ->
          let arr = Array.of_list (List.map snd items) in
          (match extract_nums_arr "min" arr with
            | Error e -> e
            | Ok nums when Array.length nums = 0 -> VNA NAFloat
            | Ok nums ->
              VFloat (Array.fold_left Float.min Float.infinity nums))
      | [VVector arr] when Array.length arr = 0 -> Error.value_error "Function `min` called on empty Vector."
      | [VVector arr] ->
          (match extract_nums_arr "min" arr with
            | Error e -> e
            | Ok nums when Array.length nums = 0 -> VNA NAFloat
            | Ok nums ->
              VFloat (Array.fold_left Float.min Float.infinity nums))
      | [VNA _] -> Error.na_value_error ~na_rm:true "min"
      | [_] -> Error.type_error "Function `min` expects a numeric List or Vector."
      | _ -> Error.arity_error_named "min" 1 (List.length args)
    ))
    env
