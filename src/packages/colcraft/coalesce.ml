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
        (* args is non-empty here and every element converted, so arrs is
           non-empty; match on it directly instead of List.hd. *)
        (match List.filter_map Fun.id arrays with
        | [] -> Error.arity_error_named "coalesce" 1 0
        | first :: _ as arrs ->
        let n = Array.length first in
        if List.exists (fun arr -> Array.length arr <> n) arrs then
          Error.value_error "Function `coalesce` requires all inputs to have equal length."
        else
          let out = Array.make n (VNA NAGeneric) in
          for i = 0 to n - 1 do
            (* Accumulates the first non-NA value; a ref loop is the
               straightforward traversal here. *)
            let found = ref None in
            let first_na = ref None in
            List.iter (fun arr ->
              match !found with
              | Some _ -> ()
              | None ->
                  (match arr.(i) with
                   | VNA _ as na -> if !first_na = None then first_na := Some na
                   | v -> found := Some v)
            ) arrs;
            out.(i) <- (match !found with
              | Some v -> v
              | None -> (match !first_na with Some na -> na | None -> VNA NAGeneric))
          done;
          VVector out)

let register env =
  Env.add "coalesce" (make_builtin ~name:"coalesce" ~variadic:true 1 coalesce_impl) env
