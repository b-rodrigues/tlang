open Ast

(*
--# Mode
--#
--# Return most frequent value.
--#
--# @name mode
--# @param x :: Vector | List Input values.
--# @return :: Any The most frequent value from the input (or NA if empty).
--# @family stats
--# @export
*)

let register env =
  Env.add "mode" (make_builtin ~name:"mode" 1 (fun args _ ->
    let calc vals =
      if vals = [] then VNA NAFloat else
      (* Typed keys (NaN-aware, type-sensitive) so values of different types
         never collide; ties are broken by first occurrence in input order,
         making the result deterministic. *)
      let tbl = Value_hash.ValueHash.create 16 in
      let order = ref [] in
      List.iter (fun v ->
        match Value_hash.ValueHash.find_opt tbl v with
        | Some (fv, n) -> Value_hash.ValueHash.replace tbl v (fv, n + 1)
        | None ->
            Value_hash.ValueHash.add tbl v (v, 1);
            order := v :: !order
      ) vals;
      let best = ref None in
      List.iter (fun v ->
        match Value_hash.ValueHash.find_opt tbl v with
        | Some (fv, c) ->
            (match !best with
             | None -> best := Some (fv, c)
             | Some (_, bc) when c > bc -> best := Some (fv, c)
             | _ -> ())
        | None -> ()
      ) (List.rev !order);
      match !best with Some (v, _) -> v | None -> VNA NAFloat
    in
    match args with
    | [VVector arr] -> calc (Array.to_list arr)
    | [VList items] -> calc (List.map snd items)
    | [_] -> Error.type_error "Function `mode` expects a List or Vector."
    | _ -> Error.arity_error_named "mode" 1 (List.length args))) env
