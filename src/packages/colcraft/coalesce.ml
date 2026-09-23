open Ast

(*
--# Coalesce missing values
--#
--# Returns the first non-NA value at each position across inputs.
--# All inputs must be Vectors or Lists of equal length.
--#
--# @name coalesce
--# @param ... :: Vector | List Vectors to coalesce in priority order.
--# @return :: Vector The first non-NA value per position.
--# @example
--#   coalesce([1, NA, 3], [10, 20, 30])
--# @family colcraft
--# @export
*)
let to_array = function
  | VVector arr -> Some arr
  | VList items -> Some (Array.of_list (List.map snd items))
  | _ -> None

let coalesce_impl args _env =
  match args with
  | [] -> Error.arity_error_named "coalesce" 1 0
  | _ ->
      let arrays = List.map to_array args in
      if List.exists Option.is_none arrays then
        Error.type_error "Function `coalesce` expects only Vector or List arguments."
      else
        let arrs = List.filter_map Fun.id arrays in
        let lens = List.map Array.length arrs in
        let n = List.hd lens in
        if List.exists ((<>) n) lens then
          Error.value_error "Function `coalesce` requires all inputs to have equal length."
        else
          let out = Array.make n (VNA NAGeneric) in
          for i = 0 to n - 1 do
            let found = ref None in
            List.iter (fun arr ->
              match !found with
              | Some _ -> ()
              | None ->
                  (match arr.(i) with
                   | VNA _ -> ()
                   | v -> found := Some v)
            ) arrs;
            out.(i) <- (match !found with Some v -> v | None -> VNA NAGeneric)
          done;
          VVector out

let register env =
  Env.add "coalesce" (make_builtin ~name:"coalesce" ~variadic:true 1 coalesce_impl) env
