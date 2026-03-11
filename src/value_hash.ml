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
