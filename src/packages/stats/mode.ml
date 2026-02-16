open Ast

(*
--# Mode
--#
--# Return most frequent value.
--#
--# @name mode
--# @param x :: Vector | List Input values.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family stats
--# @export
*)

let register env =
  Env.add "mode" (make_builtin ~name:"mode" 1 (fun args _ ->
    let calc vals =
      if vals = [] then VNA NAFloat else
      let tbl = Hashtbl.create 16 in
      List.iter (fun v ->
        let k = Ast.Utils.value_to_string v in
        let count = match Hashtbl.find_opt tbl k with Some (_, n) -> n + 1 | None -> 1 in
        Hashtbl.replace tbl k (v, count)
      ) vals;
      let best = ref None in
      Hashtbl.iter (fun _ (v, c) -> match !best with None -> best := Some (v, c) | Some (_, bc) when c > bc -> best := Some (v, c) | _ -> ()) tbl;
      match !best with Some (v, _) -> v | None -> VNA NAFloat
    in
    match args with
    | [VVector arr] -> calc (Array.to_list arr)
    | [VList items] -> calc (List.map snd items)
    | [_] -> Error.type_error "Function `mode` expects a List or Vector."
    | _ -> Error.arity_error_named "mode" ~expected:1 ~received:(List.length args))) env
