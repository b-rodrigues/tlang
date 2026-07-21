(*
--# DataFrame row count assertion
--#
--# Passes if the DataFrame has exactly `n` rows.
--#
--# @name expect_nrow
--# @param df :: DataFrame The DataFrame to check.
--# @param n :: Int Expected row count.
--# @return :: Expect `Expect_pass` when row count matches; `Expect_hold` on NA/Error; `Expect_stop` otherwise.
--# @example
--#   assert(expect_nrow(to_dataframe([x: [1, 2, 3]]), 3))
--# @family testcraft
--# @seealso expect_ncol, expect_colnames, expect_length
--# @export
*)

(*
--# DataFrame column count assertion
--#
--# Passes if the DataFrame has exactly `n` columns.
--#
--# @name expect_ncol
--# @param df :: DataFrame The DataFrame to check.
--# @param n :: Int Expected column count.
--# @return :: Expect `Expect_pass` when column count matches; `Expect_hold` on NA/Error; `Expect_stop` otherwise.
--# @example
--#   assert(expect_ncol(to_dataframe([x: [1], y: [2]]), 2))
--# @family testcraft
--# @seealso expect_nrow, expect_colnames, expect_length
--# @export
*)

(*
--# DataFrame column names assertion
--#
--# Passes if the DataFrame column names match the given list of strings
--# exactly (order-sensitive).
--#
--# @name expect_colnames
--# @param df :: DataFrame The DataFrame to check.
--# @param names :: List | Vector A list or vector of expected column name strings.
--# @return :: Expect `Expect_pass` when names match; `Expect_hold` on NA/Error; `Expect_stop` otherwise.
--# @example
--#   assert(expect_colnames(to_dataframe([x: [1], y: [2]]), ["x", "y"]))
--# @family testcraft
--# @seealso expect_nrow, expect_ncol, expect_fields
--# @export
*)

(*
--# Dict key / named List label assertion
--#
--# Passes if a Dict's keys or a named List's labels match the given list
--# of strings exactly (order-sensitive).
--#
--# @name expect_fields
--# @param x :: Dict | List The Dict or named List to inspect.
--# @param names :: List | Vector A list or vector of expected field name strings.
--# @return :: Expect `Expect_pass` when fields match; `Expect_hold` on NA/Error; `Expect_stop` otherwise.
--# @example
--#   assert(expect_fields([a: 1, b: 2], ["a", "b"]))
--# @family testcraft
--# @seealso expect_colnames, expect_in
--# @export
*)

(*
--# Set membership assertion
--#
--# Passes if `x` (or every element of a Vector/List `x`) is present in
--# `values`. Checks each element of collections individually.
--#
--# @name expect_in
--# @param x :: Any A scalar value, Vector, or List to look for.
--# @param values :: Vector | List The haystack collection to search in.
--# @return :: Expect `Expect_pass` when all elements are found; `Expect_hold` on NA/Error; `Expect_stop` otherwise.
--# @example
--#   assert(expect_in(3, [1, 2, 3, 4, 5]))
--# @family testcraft
--# @seealso expect_fields, expect_equal
--# @export
*)

open Ast

let fmt v = "`" ^ Utils.value_to_string v ^ "`"

(* Extract a list of strings from a VList or VVector. Returns None if
   any element is not a VString. Unlike the previous implementation,
   this correctly handles empty strings as valid elements. *)
let extract_string_list = function
  | VList items ->
      let rec go acc = function
        | [] -> Some (List.rev acc)
        | (_, VString s) :: rest -> go (s :: acc) rest
        | (_, _) :: _ -> None
      in
      go [] items
  | VVector arr ->
      let rec go i acc =
        if i >= Array.length arr then Some (List.rev acc)
        else match arr.(i) with
          | VString s -> go (i + 1) (s :: acc)
          | _ -> None
      in
      go 0 []
  | VString s -> Some [s]
  | _ -> None

let list_of_strings_to_string items =
  "[" ^ String.concat ", " (List.map (fun s -> "\"" ^ s ^ "\"") items) ^ "]"

let names_error () =
  Error.type_error "Expected a list or vector of strings for the names argument."

let register env =
  (* expect_nrow: check DataFrame row count *)
  let env =
    Env.add "expect_nrow"
      (make_builtin ~name:"expect_nrow" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check row count")
         | [VError _; _] -> VExpect (Expect_hold "`actual` is an error, cannot check row count")
         | [VDataFrame df; VInt n] ->
             let rows = Arrow_table.num_rows df.arrow_table in
             if rows = n then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "Expected %d rows, got %d" n rows))
         | [VDataFrame _; other] ->
             Error.type_error
               (Printf.sprintf
                  "Function `expect_nrow` expects Int as second argument, got %s."
                  (Utils.type_name other))
         | [other; _] ->
             Error.type_error
               (Printf.sprintf "Function `expect_nrow` expects a DataFrame as first argument, got %s."
                  (Utils.type_name other))
         | args -> Error.arity_error_named "expect_nrow" 2 (List.length args)))
      env
  in
  (* expect_ncol: check DataFrame column count *)
  let env =
    Env.add "expect_ncol"
      (make_builtin ~name:"expect_ncol" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check column count")
         | [VError _; _] -> VExpect (Expect_hold "`actual` is an error, cannot check column count")
         | [VDataFrame df; VInt n] ->
             let cols = Arrow_table.num_columns df.arrow_table in
             if cols = n then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "Expected %d columns, got %d" n cols))
         | [VDataFrame _; other] ->
             Error.type_error
               (Printf.sprintf
                  "Function `expect_ncol` expects Int as second argument, got %s."
                  (Utils.type_name other))
         | [other; _] ->
             Error.type_error
               (Printf.sprintf "Function `expect_ncol` expects a DataFrame as first argument, got %s."
                  (Utils.type_name other))
         | args -> Error.arity_error_named "expect_ncol" 2 (List.length args)))
      env
  in
  (* expect_colnames: check DataFrame column names *)
  let env =
    Env.add "expect_colnames"
      (make_builtin ~name:"expect_colnames" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check column names")
         | [VError _; _] -> VExpect (Expect_hold "`actual` is an error, cannot check column names")
         | [VDataFrame df; names_val] ->
             (match extract_string_list names_val with
              | Some expected_names ->
                  let actual_names = Arrow_table.column_names df.arrow_table in
                  if actual_names = expected_names then VExpect Expect_pass
                  else
                    let actual_s = list_of_strings_to_string actual_names in
                    let expected_s = list_of_strings_to_string expected_names in
                    VExpect
                      (Expect_stop
                         (Printf.sprintf "Expected columns %s, got %s" expected_s actual_s))
              | None -> names_error ())
         | [other; _] ->
             Error.type_error
               (Printf.sprintf "Function `expect_colnames` expects a DataFrame as first argument, got %s."
                  (Utils.type_name other))
         | args -> Error.arity_error_named "expect_colnames" 2 (List.length args)))
      env
  in
  (* expect_fields: check keys/labels of Dict or named List *)
  let env =
    Env.add "expect_fields"
      (make_builtin ~name:"expect_fields" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check fields")
         | [VError _; _] -> VExpect (Expect_hold "`actual` is an error, cannot check fields")
         | [VDict entries; names_val] ->
             (match extract_string_list names_val with
              | Some expected_names ->
                  let actual_names = List.map fst entries in
                  if actual_names = expected_names then VExpect Expect_pass
                  else
                    let actual_s = list_of_strings_to_string actual_names in
                    let expected_s = list_of_strings_to_string expected_names in
                    VExpect
                      (Expect_stop
                         (Printf.sprintf "Expected fields %s, got %s" expected_s actual_s))
              | None -> names_error ())
         | [VList items; names_val] ->
             (match extract_string_list names_val with
              | Some expected_names ->
                  let actual_names =
                    List.map (fun (label, _) ->
                      match label with Some l -> l | None -> "")
                      items
                  in
                  if actual_names = expected_names then VExpect Expect_pass
                  else
                    let actual_s = list_of_strings_to_string actual_names in
                    let expected_s = list_of_strings_to_string expected_names in
                    VExpect
                      (Expect_stop
                         (Printf.sprintf "Expected fields %s, got %s" expected_s actual_s))
              | None -> names_error ())
         | [other; _] ->
             Error.type_error
               (Printf.sprintf
                  "Function `expect_fields` expects a Dict or named List as first argument, got %s."
                  (Utils.type_name other))
         | args -> Error.arity_error_named "expect_fields" 2 (List.length args)))
      env
  in
  let haystack_mem v haystack = match haystack with
    | VVector arr -> Array.exists (fun h -> h = v) arr
    | VList items -> List.exists (fun (_, h) -> h = v) items
    | _ -> false
  in

  let haystack_second_arg_type other =
    Error.type_error
      (Printf.sprintf
         "Function `expect_in` expects a Vector or List as second argument, got %s."
         (Utils.type_name other))
  in

  let first_arg_type other =
    Error.type_error
      (Printf.sprintf "Function `expect_in` expects a Vector, List, or scalar as first argument, got %s."
         (Utils.type_name other))
  in

  (* expect_in: check that each value in `actual` is present in `values` *)
  let env =
    Env.add "expect_in"
      (make_builtin ~name:"expect_in" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check membership")
         | [VError _; _] -> VExpect (Expect_hold "`actual` is an error, cannot check membership")
         | [VVector elems; VVector _ as haystack] ->
             let rec scan i =
               if i >= Array.length elems then Expect_pass
               else if haystack_mem elems.(i) haystack then scan (i + 1)
               else
                 Expect_stop
                   (Printf.sprintf "%s was not found in the given set" (fmt elems.(i)))
             in
             VExpect (scan 0)
         | [VVector elems; VList _ as haystack] ->
             let rec scan i =
               if i >= Array.length elems then Expect_pass
               else if haystack_mem elems.(i) haystack then scan (i + 1)
               else
                 Expect_stop
                   (Printf.sprintf "%s was not found in the given set" (fmt elems.(i)))
             in
             VExpect (scan 0)
         | [VList elems; VVector _ as haystack] ->
             let rec scan = function
               | [] -> Expect_pass
               | (_, v) :: rest ->
                   if haystack_mem v haystack then scan rest
                   else
                     Expect_stop
                       (Printf.sprintf "%s was not found in the given set" (fmt v))
             in
             VExpect (scan elems)
         | [VList elems; VList _ as haystack] ->
             let rec scan = function
               | [] -> Expect_pass
               | (_, v) :: rest ->
                   if haystack_mem v haystack then scan rest
                   else
                     Expect_stop
                       (Printf.sprintf "%s was not found in the given set" (fmt v))
             in
             VExpect (scan elems)
         | [v; VVector _ as haystack] ->
             if haystack_mem v haystack then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "%s was not found in the given set" (fmt v)))
         | [v; VList _ as haystack] ->
             if haystack_mem v haystack then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "%s was not found in the given set" (fmt v)))
         | [VVector _; other] -> haystack_second_arg_type other
         | [VList _; other] -> haystack_second_arg_type other
         | [other; _] -> first_arg_type other
         | args -> Error.arity_error_named "expect_in" 2 (List.length args)))
      env
  in
  env
