(*
--# DataFrame row count assertion
--#
--# Passes if the DataFrame has exactly `n` rows.
--#
--# @name expect_nrow
--# @param df :: DataFrame The DataFrame to check.
--# @param n :: Int Expected row count.
--# @return :: Expect `Expect_pass` when row count matches; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.
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
--# @return :: Expect `Expect_pass` when column count matches; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.
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
--# @return :: Expect `Expect_pass` when names match; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.
--# @example
--#   assert(expect_colnames(to_dataframe([x: [1], y: [2]]), ["x", "y"]))
--# @family testcraft
--# @seealso expect_nrow, expect_ncol, expect_has_colnames, expect_fields
--# @export
*)

(*
--# DataFrame / Dict subset column names assertion
--#
--# Passes if the DataFrame, Dict, or named List contains at least all of the expected column/field names.
--# Order is not required, and additional columns/fields are permitted.
--#
--# @name expect_has_colnames
--# @param data :: DataFrame | Dict | List The container to check.
--# @param names :: String | List | Vector The required column/field name or list/vector of required names.
--# @return :: Expect `Expect_pass` when all expected columns exist; `Expect_hold` on NA; `Expect_stop` on missing columns.
--# @example
--#   assert(expect_has_colnames(to_dataframe([x: [1], y: [2]]), ["x"]))
--#   assert(expect_has_colnames(to_dataframe([x: [1], y: [2]]), "y"))
--# @family testcraft
--# @seealso expect_colnames, expect_fields, expect_nrow, expect_ncol
--# @export
*)

(*
--# Element uniqueness assertion
--#
--# Passes if all elements in a Vector, List, or DataFrame are distinct.
--# Returns `Expect_stop` detailing duplicate values if any are found.
--#
--# @name expect_unique
--# @param x :: Vector | List | DataFrame The container or vector to check for uniqueness.
--# @return :: Expect `Expect_pass` if all elements are unique; `Expect_hold` on NA; `Expect_stop` if duplicates exist.
--# @example
--#   assert(expect_unique([1, 2, 3, 4]))
--#   assert(expect_unique(df.$id))
--# @family testcraft
--# @seealso expect_length, expect_in, expect_equal
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
--# @return :: Expect `Expect_pass` when fields match; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.
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
--# @param tolerance :: Float = 1e-9 Absolute tolerance used for Float comparisons.
--# @return :: Expect `Expect_pass` when all elements are found; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.
--# @example
--#   assert(expect_in(3, [1, 2, 3, 4, 5]))
--#   assert(expect_in(0.1 + 0.2, [0.3], tolerance = 1e-9))
--# @family testcraft
--# @seealso expect_fields, expect_equal
(*
--# Absence of NA values assertion
--#
--# Passes if the actual value, Vector, List, or DataFrame (optional column) contains zero NA values.
--#
--# @name expect_no_na
--# @param actual :: Any The value, container, or DataFrame to check.
--# @param col :: String (Optional) Column name when checking a DataFrame.
--# @return :: Expect `Expect_pass` when no NA values exist; `Expect_stop` if NA values are found.
--# @example
--#   assert(expect_no_na([1, 2, 3]))
--#   assert(expect_no_na(df, "val"))
--# @family testcraft
--# @seealso expect_type, expect_true
--# @export
*)

(*
--# Closed range numerical bounds assertion
--#
--# Passes if the numeric value or vector elements fall inside [min, max].
--#
--# @name expect_between
--# @param actual :: Int | Float | Vector The numeric value or vector to check.
--# @param min :: Int | Float Lower bound (inclusive).
--# @param max :: Int | Float Upper bound (inclusive).
--# @return :: Expect `Expect_pass` when within bounds; `Expect_hold` on NA; `Expect_stop` if out of bounds.
--# @example
--#   assert(expect_between(25.0, 10.0, 50.0))
--# @family testcraft
--# @seealso expect_gt, expect_lt
--# @export
*)

(*
--# Regex string match assertion
--#
--# Passes if the actual String matches the given regular expression pattern.
--#
--# @name expect_match
--# @param actual :: String The string value to inspect.
--# @param pattern :: String Regular expression pattern string.
--# @return :: Expect `Expect_pass` when matching; `Expect_hold` on NA; `Expect_stop` on mismatch or invalid pattern.
--# @example
--#   assert(expect_match("user@example.com", ".*@.*"))
--# @family testcraft
--# @seealso expect_str_contains, expect_type
--# @export
*)

(*
--# Substring search assertion
--#
--# Passes if the actual String contains the specified substring.
--#
--# @name expect_str_contains
--# @param actual :: String The string value to inspect.
--# @param substring :: String Substring to search for.
--# @return :: Expect `Expect_pass` when found; `Expect_hold` on NA; `Expect_stop` if missing.
--# @example
--#   assert(expect_str_contains("hello world", "world"))
--# @family testcraft
--# @seealso expect_match
--# @export
*)

(*
--# Order-independent set equality assertion
--#
--# Passes if two Lists or Vectors contain the exact same unique elements regardless of order.
--#
--# @name expect_set_equal
--# @param list1 :: List | Vector First collection.
--# @param list2 :: List | Vector Second collection.
--# @return :: Expect `Expect_pass` when sets match; `Expect_hold` on NA; `Expect_stop` if elements differ.
--# @example
--#   assert(expect_set_equal([1, 2, 3], [3, 2, 1]))
--# @family testcraft
--# @seealso expect_equal, expect_in
--# @export
*)

(*
--# Empty container / string assertion
--#
--# Passes if a List, Dict, Vector, String, or DataFrame is empty (0 elements/rows/length).
--#
--# @name expect_empty
--# @param actual :: List | Dict | Vector | String | DataFrame The container to check.
--# @return :: Expect `Expect_pass` when empty; `Expect_hold` on NA; `Expect_stop` if non-empty.
--# @example
--#   assert(expect_empty([]))
--# @family testcraft
--# @seealso expect_length, expect_nrow
--# @export
*)

(*
--# Expectation test suite summary report
--#
--# Summarizes a List or Dict of Expect values / check results into a DataFrame report table.
--#
--# @name expect_summary
--# @param checks :: Dict | List A dictionary or list of expectation check results.
--# @return :: DataFrame A DataFrame with columns `check`, `status`, and `message`.
--# @example
--#   summary_df = expect_summary([c1: expect_equal(1, 1), c2: expect_equal(2, 2)])
--# @family testcraft
--# @seealso expect_pass, expect_fail
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
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
  (* expect_has_colnames: check that DataFrame/Dict/named List contains at least expected names *)
  let env =
    Env.add "expect_has_colnames"
      (make_builtin ~name:"expect_has_colnames" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check column names")
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
         | [actual_val; names_val] ->
             let expected_names_opt =
               match names_val with
               | VString s -> Some [s]
               | VSymbol s -> Some [s]
               | other -> extract_string_list other
             in
             (match expected_names_opt with
              | None -> names_error ()
              | Some expected_names ->
                  let actual_names_opt =
                    match actual_val with
                    | VDataFrame df -> Some (Arrow_table.column_names df.arrow_table)
                    | VDict entries -> Some (List.map fst entries)
                    | VList items ->
                        Some (List.filter_map (fun (label, _) -> label) items)
                    | _ -> None
                  in
                  (match actual_names_opt with
                   | None ->
                       Error.type_error
                         (Printf.sprintf
                            "Function `expect_has_colnames` expects a DataFrame, Dict, or named List as first argument, got %s."
                            (Utils.type_name actual_val))
                   | Some actual_names ->
                       let missing = List.filter (fun name -> not (List.mem name actual_names)) expected_names in
                       if missing = [] then VExpect Expect_pass
                       else
                         let missing_s = list_of_strings_to_string missing in
                         VExpect
                           (Expect_stop
                              (Printf.sprintf "Missing expected column(s): %s" missing_s))))
         | args -> Error.arity_error_named "expect_has_colnames" 2 (List.length args)))
      env
  in
  (* expect_unique: check that elements in Vector/List/DataFrame are all distinct *)
  (* Note: Uses O(N^2) structural comparison via compare_values. Suitable for test/validation sizes.
     TODO: Implement hash-set indexing if extended to large-scale production DataFrames. *)
  let env =
    Env.add "expect_unique"
      (make_builtin ~name:"expect_unique" 1 (fun args _env ->
         match args with
         | [VNA _] -> VExpect (Expect_hold "`actual` is NA, cannot check uniqueness")
         | [VError err] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
         | [VVector elems] ->
             let rec scan i seen =
               if i >= Array.length elems then Expect_pass
               else
                 let v = elems.(i) in
                 if List.exists (fun s -> T_expect_equal.compare_values ~tolerance:1e-9 s v = Expect_pass) seen then
                   Expect_stop (Printf.sprintf "Found duplicate value %s at index %d" (fmt v) i)
                 else
                   scan (i + 1) (v :: seen)
             in
             VExpect (scan 0 [])
         | [VList items] ->
             let vals = Array.of_list (List.map snd items) in
             let rec scan i seen =
               if i >= Array.length vals then Expect_pass
               else
                 let v = vals.(i) in
                 if List.exists (fun s -> T_expect_equal.compare_values ~tolerance:1e-9 s v = Expect_pass) seen then
                   Expect_stop (Printf.sprintf "Found duplicate value %s at index %d" (fmt v) i)
                 else
                   scan (i + 1) (v :: seen)
             in
             VExpect (scan 0 [])
         | [VDataFrame df] ->
             let table = df.arrow_table in
             let nrows = Arrow_table.num_rows table in
             let cols = Arrow_table.column_names table in
             let col_arrs = List.map (fun name -> Arrow_table.get_column table name) cols in
             let get_row r =
               List.map (fun col_opt ->
                 match col_opt with
                 | Some col -> Arrow_bridge.value_at col r
                 | None -> VNA NAGeneric
               ) col_arrs
             in
             let rec scan r seen_rows =
               if r >= nrows then Expect_pass
               else
                 let row_vals = get_row r in
                 if List.exists (fun seen ->
                   List.for_all2 (fun a b -> T_expect_equal.compare_values ~tolerance:1e-9 a b = Expect_pass) seen row_vals
                 ) seen_rows then
                   Expect_stop (Printf.sprintf "DataFrame contains duplicate row at index %d" r)
                 else
                   scan (r + 1) (row_vals :: seen_rows)
             in
             VExpect (scan 0 [])
         | [other] ->
             Error.type_error
               (Printf.sprintf
                  "Function `expect_unique` expects a Vector, List, or DataFrame, got %s."
                  (Utils.type_name other))
         | args -> Error.arity_error_named "expect_unique" 1 (List.length args)))
      env
  in
  (* expect_fields: check keys/labels of Dict or named List *)
  let env =
    Env.add "expect_fields"
      (make_builtin ~name:"expect_fields" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check fields")
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
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
  let haystack_mem ~tolerance v haystack = match haystack with
    | VVector arr -> Array.exists (fun h -> T_expect_equal.compare_values ~tolerance h v = Expect_pass) arr
    | VList items -> List.exists (fun (_, h) -> T_expect_equal.compare_values ~tolerance h v = Expect_pass) items
    | _ -> false
  in

  let haystack_second_arg_type other =
    Error.type_error
      (Printf.sprintf
         "Function `expect_in` expects a Vector or List as second argument, got %s."
         (Utils.type_name other))
  in

  (* expect_in: check that each value in `actual` is present in `values` *)
  let env =
    Env.add "expect_in"
      (make_builtin_named ~name:"expect_in" ~variadic:true 2 (fun named_args _env ->
         let unknown_named =
           List.filter
             (fun (n, _) ->
               match n with
               | None -> false
               | Some "tolerance" -> false
               | Some _ -> true)
             named_args
         in
         match unknown_named with
         | (Some arg_name, _) :: _ ->
             Error.type_error
               (Printf.sprintf "Function `expect_in` received unknown named argument `%s`." arg_name)
         | _ ->
             let tolerance_opt = List.find_opt (fun (n, _) -> n = Some "tolerance") named_args in
             (match tolerance_opt with
              | Some (_, other) when (match other with VFloat _ | VInt _ -> false | _ -> true) ->
                  Error.type_error
                    (Printf.sprintf
                       "Function `expect_in` expects the `tolerance` argument to be numeric, got %s."
                       (Utils.type_name other))
              | _ ->
                  let tolerance =
                    match tolerance_opt with
                    | Some (_, VFloat f) -> f
                    | Some (_, VInt i) -> float_of_int i
                    | _ -> 1e-9
                  in
                  (match Math_common.positional_args_without [ "tolerance" ] named_args with
                   | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check membership")
                   | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
                   | [VVector elems; VVector _ as haystack] ->
                       let rec scan i =
                         if i >= Array.length elems then Expect_pass
                         else if haystack_mem ~tolerance elems.(i) haystack then scan (i + 1)
                         else
                           Expect_stop
                             (Printf.sprintf "%s was not found in the given set" (fmt elems.(i)))
                       in
                       VExpect (scan 0)
                   | [VVector elems; VList _ as haystack] ->
                       let rec scan i =
                         if i >= Array.length elems then Expect_pass
                         else if haystack_mem ~tolerance elems.(i) haystack then scan (i + 1)
                         else
                           Expect_stop
                             (Printf.sprintf "%s was not found in the given set" (fmt elems.(i)))
                       in
                       VExpect (scan 0)
                   | [VList elems; VVector _ as haystack] ->
                       let rec scan = function
                         | [] -> Expect_pass
                         | (_, v) :: rest ->
                             if haystack_mem ~tolerance v haystack then scan rest
                             else
                               Expect_stop
                                 (Printf.sprintf "%s was not found in the given set" (fmt v))
                       in
                       VExpect (scan elems)
                   | [VList elems; VList _ as haystack] ->
                       let rec scan = function
                         | [] -> Expect_pass
                         | (_, v) :: rest ->
                             if haystack_mem ~tolerance v haystack then scan rest
                             else
                               Expect_stop
                                 (Printf.sprintf "%s was not found in the given set" (fmt v))
                       in
                       VExpect (scan elems)
                   | [v; (VVector _ | VList _) as haystack] ->
                       if haystack_mem ~tolerance v haystack then VExpect Expect_pass
                       else VExpect (Expect_stop (Printf.sprintf "%s was not found in the given set" (fmt v)))
                   | [_; other] -> haystack_second_arg_type other
                   | args -> Error.arity_error_named "expect_in" 2 (List.length args)))))
      env
  in
  (* check: evaluates assert(val), prints true on success, preserves original VError on failure *)
  (* Note: Env.find_opt "assert" returns a VBuiltin whose b_func is the low-level AST dispatcher
     with signature (string option * value) list -> environment ref -> value.
     We convert positional `args` into `(None, v)` tuples and pass `ref env`. *)
  let env =
    Env.add "check"
      (make_builtin ~name:"check" ~variadic:true 1 (fun args env ->
         let assert_fn = match Env.find_opt "assert" env with
           | Some (VBuiltin { b_func; _ }) -> b_func
           | _ -> fun _ _ -> Error.make_error RuntimeError "assert function not found"
         in
         let named_args = List.map (fun a -> (None, a)) args in
         let res = assert_fn named_args (ref env) in
         match res with
         | VBool true ->
             Printf.printf "true\n";
             VBool true
         | VError _ as err -> err
         | other -> other))
      env
  in
  (* expect_no_na: check that actual value/vector/DataFrame contains no NA values *)
  let env =
    Env.add "expect_no_na"
      (make_builtin ~name:"expect_no_na" ~variadic:true 1 (fun args _env ->
         let check_col table col_name =
           match Arrow_table.get_column table col_name with
           | Some (Arrow_table.FloatColumn a) ->
               Array.exists (function None -> true | Some f -> Float.is_nan f) a
           | Some (Arrow_table.IntColumn a) ->
               Array.exists (function None -> true | _ -> false) a
           | Some (Arrow_table.StringColumn a) ->
               Array.exists (function None -> true | _ -> false) a
           | Some (Arrow_table.BoolColumn a) ->
               Array.exists (function None -> true | _ -> false) a
           | Some (Arrow_table.DateColumn a) ->
               Array.exists (function None -> true | _ -> false) a
           | Some (Arrow_table.DatetimeColumn (a, _)) ->
               Array.exists (function None -> true | _ -> false) a
           | Some (Arrow_table.NAColumn _) -> true
           (* Fail-closed fallback for complex/unrecognized column types *)
           | Some _ -> true
           | None -> true
         in
         match args with
         | [VNA _] -> VExpect (Expect_stop "Value is NA")
         | [VError err] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
         | [VVector arr] ->
             let has_na = Array.exists (function VNA _ -> true | _ -> false) arr in
             if has_na then VExpect (Expect_stop "Vector contains NA values")
             else VExpect Expect_pass
         | [VList items] ->
             let has_na = List.exists (fun (_, v) -> match v with VNA _ -> true | _ -> false) items in
             if has_na then VExpect (Expect_stop "List contains NA values")
             else VExpect Expect_pass
         | [VDataFrame df; VString col] ->
             let col_names = Arrow_table.column_names df.arrow_table in
             if not (List.mem col col_names) then
               VExpect (Expect_stop (Printf.sprintf "Column '%s' not found in DataFrame" col))
             else if check_col df.arrow_table col then
               VExpect (Expect_stop (Printf.sprintf "Column '%s' contains NA values" col))
             else
               VExpect Expect_pass
         | [VDataFrame df] ->
             let col_names = Arrow_table.column_names df.arrow_table in
             let na_cols = List.filter (check_col df.arrow_table) col_names in
             if na_cols <> [] then
               VExpect (Expect_stop (Printf.sprintf "DataFrame contains NA values in column(s): %s" (String.concat ", " na_cols)))
             else
               VExpect Expect_pass
         | [_] -> VExpect Expect_pass
         | args -> Error.arity_error_named "expect_no_na" 1 (List.length args)))
      env
  in
  (* expect_between: check that numeric actual value is within [min, max] *)
  let env =
    Env.add "expect_between"
      (make_builtin ~name:"expect_between" 3 (fun args _env ->
         match args with
         | [VNA _; _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check range")
         | [VError err; _; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
         | [v; min_v; max_v] ->
             let get_float = function
               | VInt i -> Some (float_of_int i)
               | VFloat f -> Some f
               | _ -> None
             in
             (match get_float min_v, get_float max_v with
              | Some min_f, Some max_f ->
                  let check_val x =
                    match get_float x with
                    | Some f -> f >= min_f && f <= max_f
                    | None -> false
                  in
                  (match v with
                   | VInt _ | VFloat _ ->
                       if check_val v then VExpect Expect_pass
                       else VExpect (Expect_stop (Printf.sprintf "Value %s is not between %g and %g" (fmt v) min_f max_f))
                   | VVector arr ->
                       let has_na = Array.exists (function VNA _ -> true | _ -> false) arr in
                       if has_na then VExpect (Expect_hold "`actual` vector contains NA, cannot check range")
                       else
                         let all_in = Array.for_all check_val arr in
                         if all_in then VExpect Expect_pass
                         else VExpect (Expect_stop (Printf.sprintf "Vector elements are not all between %g and %g" min_f max_f))
                   | other ->
                       Error.type_error (Printf.sprintf "Function `expect_between` expects a numeric value or vector, got %s." (Utils.type_name other)))
              | _ -> Error.type_error "Function `expect_between` expects numeric min and max bounds.")
         | args -> Error.arity_error_named "expect_between" 3 (List.length args)))
      env
  in
  (* expect_match: regex string match *)
  let env =
    Env.add "expect_match"
      (make_builtin ~name:"expect_match" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check regex match")
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
         | [VString s; VString pat] | [VSymbol s; VString pat] ->
             (try
                let re = Str.regexp pat in
                let is_match =
                  try Str.search_forward re s 0 >= 0 with Not_found -> false
                in
                if is_match then VExpect Expect_pass
                else VExpect (Expect_stop (Printf.sprintf "String \"%s\" does not match pattern \"%s\"" s pat))
              with Failure _ | Invalid_argument _ ->
                VExpect (Expect_stop (Printf.sprintf "Invalid regex pattern: \"%s\"" pat)))
         | [other; VString _] ->
             Error.type_error (Printf.sprintf "Function `expect_match` expects a String as first argument, got %s." (Utils.type_name other))
         | [_; other] ->
             Error.type_error (Printf.sprintf "Function `expect_match` expects a String regex pattern as second argument, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_match" 2 (List.length args)))
      env
  in
  (* expect_str_contains: substring search *)
  let env =
    Env.add "expect_str_contains"
      (make_builtin ~name:"expect_str_contains" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check substring")
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
         | [VString s; VString sub] | [VSymbol s; VString sub] ->
             (try
                let re = Str.regexp_string sub in
                let is_match =
                  try Str.search_forward re s 0 >= 0 with Not_found -> false
                in
                if is_match then VExpect Expect_pass
                else VExpect (Expect_stop (Printf.sprintf "String \"%s\" does not contain substring \"%s\"" s sub))
              with Failure _ | Invalid_argument _ ->
                VExpect (Expect_stop (Printf.sprintf "Invalid substring: \"%s\"" sub)))
         | [other; VString _] ->
             Error.type_error (Printf.sprintf "Function `expect_str_contains` expects a String as first argument, got %s." (Utils.type_name other))
         | [_; other] ->
             Error.type_error (Printf.sprintf "Function `expect_str_contains` expects a String substring as second argument, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_str_contains" 2 (List.length args)))
      env
  in
  (* expect_set_equal: order-independent set equality *)
  let env =
    Env.add "expect_set_equal"
      (make_builtin ~name:"expect_set_equal" 2 (fun args _env ->
         match args with
         | [VNA _; _] -> VExpect (Expect_hold "`actual` is NA, cannot check set equality")
         | [VError err; _] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
         | [actual_val; expected_val] ->
             let extract_elems = function
               | VList items -> Some (List.map snd items)
               | VVector arr -> Some (Array.to_list arr)
               | _ -> None
             in
             (match extract_elems actual_val, extract_elems expected_val with
              | Some l1, Some l2 ->
                  let in_set set v = List.exists (fun x -> T_expect_equal.compare_values ~tolerance:1e-9 x v = Expect_pass) set in
                  let all_l1_in_l2 = List.for_all (in_set l2) l1 in
                  let all_l2_in_l1 = List.for_all (in_set l1) l2 in
                  if all_l1_in_l2 && all_l2_in_l1 then VExpect Expect_pass
                  else VExpect (Expect_stop "Sets are not equal (missing or unexpected elements)")
              | None, _ ->
                  Error.type_error (Printf.sprintf "Function `expect_set_equal` expects a List or Vector as first argument, got %s." (Utils.type_name actual_val))
              | _, None ->
                  Error.type_error (Printf.sprintf "Function `expect_set_equal` expects a List or Vector as second argument, got %s." (Utils.type_name expected_val)))
         | args -> Error.arity_error_named "expect_set_equal" 2 (List.length args)))
      env
  in
  (* expect_empty: check if container/string/DataFrame is empty *)
  let env =
    Env.add "expect_empty"
      (make_builtin ~name:"expect_empty" 1 (fun args _env ->
         match args with
         | [VNA _] -> VExpect (Expect_hold "`actual` is NA, cannot check if empty")
         | [VError err] -> VExpect (Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message))
         | [VList []] | [VDict []] | [VVector [||]] | [VString ""] -> VExpect Expect_pass
         | [VDataFrame df] ->
             let rows = Arrow_table.num_rows df.arrow_table in
             if rows = 0 then VExpect Expect_pass
             else VExpect (Expect_stop (Printf.sprintf "DataFrame is not empty (%d rows)" rows))
         | [VList items] -> VExpect (Expect_stop (Printf.sprintf "List is not empty (%d items)" (List.length items)))
         | [VDict entries] -> VExpect (Expect_stop (Printf.sprintf "Dict is not empty (%d entries)" (List.length entries)))
         | [VVector arr] -> VExpect (Expect_stop (Printf.sprintf "Vector is not empty (%d items)" (Array.length arr)))
         | [VString s] -> VExpect (Expect_stop (Printf.sprintf "String is not empty (length %d)" (String.length s)))
         | [other] -> Error.type_error (Printf.sprintf "Function `expect_empty` expects a container or String, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_empty" 1 (List.length args)))
      env
  in
  (* expect_summary: summarize list/dict of expectation results into a DataFrame *)
  let env =
    Env.add "expect_summary"
      (make_builtin ~name:"expect_summary" 1 (fun args _env ->
         match args with
         | [VDict entries] ->
             let names = List.map fst entries in
             let statuses = List.map (fun (_, v) ->
               match v with
               | VBool true -> "PASS"
               | VBool false -> "FAIL"
               | VExpect Expect_pass -> "PASS"
               | VExpect (Expect_stop _) -> "FAIL"
               | VExpect (Expect_hold _) -> "HOLD"
               | VError _ -> "FAIL"
               | _ -> "UNKNOWN"
             ) entries in
             let msgs = List.map (fun (_, v) ->
               match v with
               | VExpect (Expect_stop msg) | VExpect (Expect_hold msg) -> msg
               | VError err -> err.message
               | _ -> ""
             ) entries in
             let nrows = List.length names in
             let arr_name = Array.of_list (List.map (fun s -> Some s) names) in
             let arr_status = Array.of_list (List.map (fun s -> Some s) statuses) in
             let arr_msg = Array.of_list (List.map (fun s -> Some s) msgs) in
             let columns = [
               ("check", Arrow_table.StringColumn arr_name);
               ("status", Arrow_table.StringColumn arr_status);
               ("message", Arrow_table.StringColumn arr_msg);
             ] in
             let tbl = Arrow_table.create columns nrows in
             VDataFrame { arrow_table = tbl; group_keys = [] }
         | [VList items] ->
             let names = List.mapi (fun i (lbl, _) -> match lbl with Some l -> l | None -> Printf.sprintf "check_%d" (i + 1)) items in
             let statuses = List.map (fun (_, v) ->
               match v with
               | VBool true -> "PASS"
               | VBool false -> "FAIL"
               | VExpect Expect_pass -> "PASS"
               | VExpect (Expect_stop _) -> "FAIL"
               | VExpect (Expect_hold _) -> "HOLD"
               | VError _ -> "FAIL"
               | _ -> "UNKNOWN"
             ) items in
             let msgs = List.map (fun (_, v) ->
               match v with
               | VExpect (Expect_stop msg) | VExpect (Expect_hold msg) -> msg
               | VError err -> err.message
               | _ -> ""
             ) items in
             let nrows = List.length names in
             let arr_name = Array.of_list (List.map (fun s -> Some s) names) in
             let arr_status = Array.of_list (List.map (fun s -> Some s) statuses) in
             let arr_msg = Array.of_list (List.map (fun s -> Some s) msgs) in
             let columns = [
               ("check", Arrow_table.StringColumn arr_name);
               ("status", Arrow_table.StringColumn arr_status);
               ("message", Arrow_table.StringColumn arr_msg);
             ] in
             let tbl = Arrow_table.create columns nrows in
             VDataFrame { arrow_table = tbl; group_keys = [] }
         | [other] -> Error.type_error (Printf.sprintf "Function `expect_summary` expects a Dict or List of expect results, got %s." (Utils.type_name other))
         | args -> Error.arity_error_named "expect_summary" 1 (List.length args)))
      env
  in
  env
