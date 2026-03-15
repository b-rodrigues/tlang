open Ast

let matcher_of name pred =
  VBuiltin {
    b_name = Some name;
    b_arity = 1;
    b_variadic = false;
    b_func = (fun args _env_ref ->
      match args with
      | [(_, VDataFrame df)] ->
          let names = Arrow_table.column_names df.arrow_table in
          VList (List.filter pred names |> List.map (fun n -> (None, VString n)))
      | [(_, VVector arr)] ->
          (* Also support matching against a vector of names if needed *)
          let names = Array.to_list arr |> List.filter_map (function VString s -> Some s | _ -> None) in
          VList (List.filter pred names |> List.map (fun n -> (None, VString n)))
      | _ -> Error.type_error (Printf.sprintf "Selection helper `%s` expects a DataFrame or Vector of names." name)
    )
  }

let starts_with_impl args env =
  match args with
  | [VString prefix] -> matcher_of "starts_with" (fun n -> String.starts_with ~prefix n)
  | _ when List.length args >= 2 -> String_ops.starts_with_impl args env
  | _ -> Error.arity_error_named "starts_with" 1 (List.length args)

let ends_with_impl args env =
  match args with
  | [VString suffix] -> matcher_of "ends_with" (fun n -> String.ends_with ~suffix n)
  | _ when List.length args >= 2 -> String_ops.ends_with_impl args env
  | _ -> Error.arity_error_named "ends_with" 1 (List.length args)

let contains_impl args env =
  match args with
  | [VString pattern] -> matcher_of "contains" (fun n -> 
      match Str.search_forward (Str.regexp_string pattern) n 0 with
      | _ -> true
      | exception Not_found -> false)
  | _ when List.length args >= 2 -> String_ops.contains_impl args env
  | _ -> Error.arity_error_named "contains" 1 (List.length args)

let everything_impl args _env =
  match args with
  | [] -> matcher_of "everything" (fun _ -> true)
  | _ -> Error.arity_error_named "everything" 0 (List.length args)

let bool_of_type_predicate predicate_name col_value =
  let all_non_na satisfy values =
    let saw_value = ref false in
    let ok = ref true in
    Array.iter (function
      | VNA _ -> ()
      | value ->
          saw_value := true;
          if not (satisfy value) then ok := false
    ) values;
    !saw_value && !ok
  in
  match predicate_name, col_value with
  | "is_numeric", VVector values ->
      all_non_na (function VInt _ | VFloat _ -> true | _ -> false) values
  | "is_character", VVector values ->
      all_non_na (function VString _ -> true | _ -> false) values
  | "is_logical", VVector values ->
      all_non_na (function VBool _ -> true | _ -> false) values
  | "is_factor", VVector values ->
      all_non_na (function VFactor _ -> true | _ -> false) values
  | "is_date", VVector values ->
      all_non_na (function VDate _ -> true | _ -> false) values
  | "is_datetime", VVector values ->
      all_non_na (function VDatetime _ -> true | _ -> false) values
  | _ -> false

let type_predicate_impl name satisfy args _env =
  match args with
  | [VVector values] ->
      let saw_value = ref false in
      let ok = ref true in
      Array.iter (function
        | VNA _ -> ()
        | value ->
            saw_value := true;
            if not (satisfy value) then ok := false
      ) values;
      VBool (!saw_value && !ok)
  | [value] -> VBool (satisfy value)
  | _ -> Error.arity_error_named name 1 (List.length args)

let matcher_builtin ?(compute_names=(fun names -> names)) name compute =
  VBuiltin {
    b_name = Some name;
    b_arity = 1;
    b_variadic = false;
    b_func = (fun args _env_ref ->
      match args with
      | [(_, VDataFrame df)] ->
          let names = compute df in
          VList (List.map (fun n -> (None, VString n)) names)
      | [(_, VVector arr)] ->
          let names =
            Array.to_list arr |> List.filter_map (function VString s -> Some s | _ -> None)
          in
          VList (List.map (fun n -> (None, VString n)) (compute_names names))
      | _ ->
          Error.type_error
            (Printf.sprintf "Selection helper `%s` expects a DataFrame or Vector of names." name)
    )
  }

let matches_impl args _env =
  match args with
  | [VString pattern] ->
      let regex =
        try Ok (Str.regexp pattern)
        with Failure msg ->
          Error (Error.value_error (Printf.sprintf "Function `matches` received an invalid regex: %s" msg))
      in
      (match regex with
       | Error err -> err
       | Ok re ->
           matcher_builtin
             ~compute_names:(fun names ->
               List.filter (fun name ->
                 match Str.search_forward re name 0 with
                 | _ -> true
                 | exception Not_found -> false) names)
             "matches" (fun df ->
             Arrow_table.column_names df.arrow_table
             |> List.filter (fun name ->
                  match Str.search_forward re name 0 with
                  | _ -> true
                  | exception Not_found -> false)))
  | _ -> Error.arity_error_named "matches" 1 (List.length args)

let string_names_of_value function_name = function
  | VString s -> Ok [s]
  | VVector arr ->
      Array.fold_right (fun value acc ->
        match value, acc with
        | VString s, Ok values -> Ok (s :: values)
        | _, Ok _ ->
            Error
              (Error.type_error
                 (Printf.sprintf "Function `%s` expects only string column names." function_name))
        | _, Error err -> Error err
      ) arr (Ok [])
  | VList items ->
      List.fold_right (fun (_, value) acc ->
        match value, acc with
        | VString s, Ok values -> Ok (s :: values)
        | _, Ok _ ->
            Error
              (Error.type_error
                 (Printf.sprintf "Function `%s` expects only string column names." function_name))
        | _, Error err -> Error err
      ) items (Ok [])
  | _ ->
      Error
        (Error.type_error
           (Printf.sprintf "Function `%s` expects a string, List[String], or Vector[String]." function_name))

let all_of_impl args _env =
  match args with
  | [value] ->
      (match string_names_of_value "all_of" value with
       | Ok names -> VList (List.map (fun name -> (None, VString name)) names)
       | Error err -> err)
  | _ -> Error.arity_error_named "all_of" 1 (List.length args)

let any_of_impl args _env =
  match args with
  | [value] ->
      (match string_names_of_value "any_of" value with
       | Error err -> err
       | Ok names ->
           matcher_builtin
             ~compute_names:(fun existing -> List.filter (fun name -> List.mem name existing) names)
             "any_of" (fun df ->
             let existing = Arrow_table.column_names df.arrow_table in
             List.filter (fun name -> List.mem name existing) names))
  | _ -> Error.arity_error_named "any_of" 1 (List.length args)

let where_impl args _env =
  match args with
  | [VBuiltin predicate] ->
      matcher_builtin "where" (fun df ->
        Arrow_table.column_names df.arrow_table
        |> List.filter (fun name ->
             match Arrow_table.get_column df.arrow_table name with
             | None -> false
             | Some column ->
                 let column_value = VVector (Arrow_bridge.column_to_values column) in
                 match predicate.b_name with
                 | Some predicate_name when bool_of_type_predicate predicate_name column_value -> true
                  | _ ->
                      (match predicate.b_func [ (None, column_value) ] (ref Env.empty) with
                       | VBool ok -> ok
                       | _ -> false)))
  | [_] -> Error.type_error "Function `where` expects a builtin predicate function."
  | _ -> Error.arity_error_named "where" 1 (List.length args)

(*
--# Match columns by prefix
--#
--# Selection helper that returns columns whose names start with the supplied prefix.
--# When called with two arguments, it falls back to the string predicate of the same name.
--#
--# @name starts_with
--# @family colcraft
--# @export
*)
(*
--# Match columns by suffix
--#
--# Selection helper that returns columns whose names end with the supplied suffix.
--# When called with two arguments, it falls back to the string predicate of the same name.
--#
--# @name ends_with
--# @family colcraft
--# @export
*)
(*
--# Match columns by substring
--#
--# Selection helper that returns columns whose names contain the supplied substring.
--# When called with two arguments, it falls back to the string predicate of the same name.
--#
--# @name contains
--# @family colcraft
--# @export
*)
(*
--# Select every column
--#
--# Selection helper that returns every column name from a DataFrame.
--#
--# @name everything
--# @family colcraft
--# @export
*)
(*
--# Select columns by predicate
--#
--# Selection helper that keeps columns for which a predicate function returns true.
--#
--# @name where
--# @family colcraft
--# @export
*)
(*
--# Match columns by regex
--#
--# Selection helper that returns columns whose names match a regular expression.
--#
--# @name matches
--# @family colcraft
--# @export
*)
(*
--# Select an explicit set of columns
--#
--# Selection helper that returns the supplied column names and errors if names are malformed.
--#
--# @name all_of
--# @family colcraft
--# @export
*)
(*
--# Select columns that exist
--#
--# Selection helper that keeps the supplied column names when they are present.
--#
--# @name any_of
--# @family colcraft
--# @export
*)
(*
--# Check for numeric columns
--#
--# Predicate helper for numeric columns or numeric vectors.
--#
--# @name is_numeric
--# @family colcraft
--# @export
*)
(*
--# Check for character columns
--#
--# Predicate helper for string columns or string vectors.
--#
--# @name is_character
--# @family colcraft
--# @export
*)
(*
--# Check for logical columns
--#
--# Predicate helper for boolean columns or boolean vectors.
--#
--# @name is_logical
--# @family colcraft
--# @export
*)
(*
--# Check for factor columns
--#
--# Predicate helper for factor columns or factor vectors.
--#
--# @name is_factor
--# @family colcraft
--# @export
*)
let register env =
  let env = Env.add "starts_with" (make_builtin ~name:"starts_with" ~variadic:true 1 starts_with_impl) env in
  let env = Env.add "ends_with" (make_builtin ~name:"ends_with" ~variadic:true 1 ends_with_impl) env in
  let env = Env.add "contains" (make_builtin ~name:"contains" ~variadic:true 1 contains_impl) env in
  let env = Env.add "everything" (make_builtin ~name:"everything" 0 everything_impl) env in
  let env = Env.add "where" (make_builtin ~name:"where" 1 where_impl) env in
  let env = Env.add "matches" (make_builtin ~name:"matches" 1 matches_impl) env in
  let env = Env.add "all_of" (make_builtin ~name:"all_of" 1 all_of_impl) env in
  let env = Env.add "any_of" (make_builtin ~name:"any_of" 1 any_of_impl) env in
  let env = Env.add "is_numeric" (make_builtin ~name:"is_numeric" 1 (type_predicate_impl "is_numeric" (function VInt _ | VFloat _ -> true | _ -> false))) env in
  let env = Env.add "is_character" (make_builtin ~name:"is_character" 1 (type_predicate_impl "is_character" (function VString _ -> true | _ -> false))) env in
  let env = Env.add "is_logical" (make_builtin ~name:"is_logical" 1 (type_predicate_impl "is_logical" (function VBool _ -> true | _ -> false))) env in
  let env = Env.add "is_factor" (make_builtin ~name:"is_factor" 1 (type_predicate_impl "is_factor" (function VFactor _ -> true | _ -> false))) env in
  env
