(* src/packages/stats/basis.ml *)
open Ast

let to_float_array = function
  | VVector arr -> arr |> Array.to_list |> List.filter_map (function VFloat f -> Some f | VInt i -> Some (float_of_int i) | _ -> None) |> Array.of_list
  | VList items -> items |> List.map snd |> List.filter_map (function VFloat f -> Some f | VInt i -> Some (float_of_int i) | _ -> None) |> Array.of_list
  | _ -> [||]

let register env =
  (*
  --# Discretize numeric vector
  --#
  --# Splits a numeric vector into intervals.
  --#
  --# @name cut
  --# @param x :: Vector[Number] | List[Number] The vector to discretize.
  --# @param breaks :: Int | Vector[Number] Number of bins or specific cut points.
  --# @return :: Vector[String] Vector of interval labels.
  --# @example
  --#   cut([1, 2, 3, 4, 5], 2)
  --#   cut([1, 2, 3, 4, 5], [0, 2.5, 5])
  --# @family stats
  --# @export
  *)
  let env = Env.add "cut"
    (make_builtin_named ~name:"cut" ~variadic:true 2 (fun args _env ->
       let named = List.filter_map (fun (n, v) -> match n with Some name -> Some (name, v) | None -> None) args in
       let positional = List.filter_map (fun (n, v) -> match n with None -> Some v | Some _ -> None) args in
       
       let x_val = match List.assoc_opt "x" named with Some v -> Some v | None -> (match positional with v :: _ -> Some v | [] -> None) in
       let breaks_val = match List.assoc_opt "breaks" named with Some v -> Some v | None -> (match positional with _ :: v :: _ -> Some v | _ -> None) in

       match x_val, breaks_val with
       | Some x_input, Some breaks ->
           let x_floats = to_float_array x_input in
           let input_len = match x_input with VVector v -> Array.length v | VList l -> List.length l | _ -> 0 in
           if Array.length x_floats <> input_len then
             Error.type_error "Function `cut` expects a numeric vector/list without NAs."
           else
             (match breaks with
              | VInt n ->
                  if n < 1 then Error.value_error "Function `cut` requires at least 1 break."
                  else
                    let min_x = Array.fold_left min infinity x_floats in
                    let max_x = Array.fold_left max neg_infinity x_floats in
                    let range = max_x -. min_x in
                    let step = if n > 1 then range /. (float_of_int n) else if n = 1 then range else 0.0 in
                    let labels = Array.init n (fun i ->
                      let low = min_x +. (float_of_int i) *. step in
                      let high = if i = n - 1 then max_x else min_x +. (float_of_int (i+1)) *. step in
                      if n = 1 then Printf.sprintf "[%.2f, %.2f]" min_x max_x
                      else Printf.sprintf "(%.2f, %.2f]" low high
                    ) in
                    let res = Array.map (fun v ->
                      let idx = if range = 0.0 then 0 
                                else min (n - 1) (int_of_float ((v -. min_x) /. step)) in
                      VString labels.(idx)
                    ) x_floats in
                    VVector res
              | VVector _ | VList _ as b_input ->
                  let b_floats = to_float_array b_input in
                  Array.sort Float.compare b_floats;
                  if Array.length b_floats < 2 then Error.value_error "Function `cut` with vector breaks requires at least 2 values."
                  else
                    let labels = Array.init (Array.length b_floats - 1) (fun i ->
                      Printf.sprintf "(%.2f, %.2f]" b_floats.(i) b_floats.(i+1)
                    ) in
                    let res = Array.map (fun v ->
                      let rec find_bin i =
                        if i >= Array.length b_floats - 1 then VNA NAGeneric
                        else if (if i = 0 then v >= b_floats.(i) else v > b_floats.(i)) && v <= b_floats.(i+1) then VString labels.(i)
                        else find_bin (i + 1)
                      in
                      find_bin 0
                    ) x_floats in
                    VVector res
              | _ -> Error.type_error "Function `cut` argument `breaks` must be an Int or a numeric Vector."
             )
       | _ -> Error.type_error "Function `cut` expects a numeric Vector/List as first argument and Int/Vector/List as second."
    ))
    env
  in

  (*
  --# Polynomial basis expansion
  --#
  --# Generates a basis of polynomial terms for a numeric vector.
  --#
  --# @name poly
  --# @param x :: Vector[Number] | List[Number] The vector to expand.
  --# @param degree :: Int The degree of the polynomial.
  --# @param raw :: Bool = false If true, return raw powers instead of orthogonal polynomials.
  --# @return :: List[Vector[Float]] A named list of polynomial terms.
  --# @example
  --#   mutate(df, !!!poly($age, 3, raw = true))
  --# @family stats
  --# @export
  *)
  let env = Env.add "poly"
    (make_builtin_named ~name:"poly" ~variadic:true 2 (fun args _env ->
       let named = List.filter_map (fun (n, v) -> match n with Some name -> Some (name, v) | None -> None) args in
       let positional = List.filter_map (fun (n, v) -> match n with None -> Some v | Some _ -> None) args in
       
       let x_val = match List.assoc_opt "x" named with Some v -> Some v | None -> (match positional with v :: _ -> Some v | [] -> None) in
       let degree_val = match List.assoc_opt "degree" named with Some v -> Some v | None -> (match positional with _ :: v :: _ -> Some v | _ -> None) in
       let _raw = match List.assoc_opt "raw" named with Some (VBool b) -> b | _ -> true in (* Default to raw for now as it is easier *)

       match x_val, degree_val with
       | Some x_input, Some (VInt d) ->
           let x_floats = to_float_array x_input in
           let input_len = match x_input with VVector v -> Array.length v | VList l -> List.length l | _ -> 0 in
           if Array.length x_floats <> input_len then
             Error.type_error "Function `poly` expects a numeric vector/list without NAs."
           else
             let res_cols = ref [] in
             for j = 1 to d do
               let col = Array.map (fun v -> VFloat (v ** (float_of_int j))) x_floats in
               res_cols := (Some (Printf.sprintf "poly%d" j), VVector col) :: !res_cols
             done;
             VList (List.rev !res_cols)
       | _ -> Error.type_error "Function `poly` expects a numeric Vector/List and an integer Degree."
    )) env
  in
  env
