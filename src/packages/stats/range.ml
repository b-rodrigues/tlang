open Ast

(*
--# Range
--#
--# Return min and max as a length-2 vector.
--#
--# @name range
--# @param x :: Vector | List Numeric input.
--# @param na_rm :: Bool = false Remove NA values first.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family stats
--# @export
*)

let has_na_rm named_args =
  List.exists (fun (name, v) -> name = Some "na_rm" && match v with VBool true -> true | _ -> false) named_args

let strip_na_rm named_args =
  List.filter (fun (name, _) -> name <> Some "na_rm") named_args |> List.map snd

let numeric_values ~label ~na_rm v =
  let vals =
    match v with
    | VVector arr -> Ok (Array.to_list arr)
    | VList items -> Ok (List.map snd items)
    | VNA _ -> Error (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
    | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` expects a numeric List or Vector." label))
  in
  match vals with
  | Error e -> Error e
  | Ok vals ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | VInt n :: tl -> go (float_of_int n :: acc) tl
        | VFloat f :: tl -> go (f :: acc) tl
        | VNA _ :: tl when na_rm -> go acc tl
        | VNA _ :: _ -> Error (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
        | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
      in
      go [] vals

let vecf xs = VVector (Array.of_list (List.map (fun x -> VFloat x) xs))

let register env =
  Env.add "range" (make_builtin_named ~name:"range" ~variadic:true 1 (fun named_args _ ->
    let na_rm = has_na_rm named_args in
    match strip_na_rm named_args with
    | [x] -> (match numeric_values ~label:"range" ~na_rm x with Error e -> e | Ok [] -> VNA NAFloat | Ok xs -> vecf [List.fold_left min infinity xs; List.fold_left max neg_infinity xs])
    | args -> Error.arity_error_named "range" ~expected:1 ~received:(List.length args))) env
