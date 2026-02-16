open Ast

(*
--# Normalize values
--#
--# Min-max normalize values to [0, 1].
--#
--# @name normalize
--# @param x :: Vector | List Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family stats
--# @export
*)

let vecf xs = VVector (Array.of_list (List.map (fun x -> VFloat x) xs))

let register env =
  Env.add "normalize" (make_builtin ~name:"normalize" 1 (fun args _ ->
    let numeric_values v =
      let vals =
        match v with
        | VVector arr -> Ok (Array.to_list arr)
        | VList items -> Ok (List.map snd items)
        | VNA _ -> Error (Error.type_error "Function `normalize` encountered NA value. Handle missingness explicitly.")
        | _ -> Error (Error.type_error "Function `normalize` expects a numeric List or Vector.")
      in
      match vals with
      | Error e -> Error e
      | Ok vals ->
          let rec go acc = function
            | [] -> Ok (List.rev acc)
            | VInt n :: tl -> go (float_of_int n :: acc) tl
            | VFloat f :: tl -> go (f :: acc) tl
            | VNA _ :: _ -> Error (Error.type_error "Function `normalize` encountered NA value. Handle missingness explicitly.")
            | _ -> Error (Error.type_error "Function `normalize` requires numeric values.")
          in
          go [] vals
    in
    match args with
    | [x] ->
        (match numeric_values x with
         | Error e -> e
         | Ok [] -> VNA NAFloat
         | Ok xs ->
             let mn = List.fold_left min infinity xs in
             let mx = List.fold_left max neg_infinity xs in
             if mx = mn then Error.value_error "Function `normalize` undefined when min equals max."
             else vecf (List.map (fun v -> (v -. mn) /. (mx -. mn)) xs))
    | _ -> Error.arity_error_named "normalize" ~expected:1 ~received:(List.length args))) env
