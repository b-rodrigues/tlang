module ValueHash = Hashtbl.Make(struct
  type t = Ast.value

  let equal a b =
    match a, b with
    | Ast.VFloat fa, Ast.VFloat fb when Float.is_nan fa && Float.is_nan fb -> true
    | _ -> a = b

  let hash v =
    match v with
    | Ast.VFloat f when Float.is_nan f -> Hashtbl.hash "nan"
    | _ -> Hashtbl.hash v
end)

(* Same NaN-aware semantics, but over a list of values (used for deduplicating
   whole rows by their key-column values, e.g. distinct()). *)
module ValueListHash = Hashtbl.Make(struct
  type t = Ast.value list

  let rec equal a b =
    match a, b with
    | [], [] -> true
    | x :: xs, y :: ys ->
        (match x, y with
         | Ast.VFloat fx, Ast.VFloat fy when Float.is_nan fx && Float.is_nan fy -> true
         | _ -> x = y)
        && equal xs ys
    | _ -> false

  let hash l =
    List.fold_left
      (fun acc v ->
        let h =
          match v with
          | Ast.VFloat f when Float.is_nan f -> Hashtbl.hash "nan"
          | _ -> Hashtbl.hash v
        in
        (acc * 31) + h)
      0 l
end)
