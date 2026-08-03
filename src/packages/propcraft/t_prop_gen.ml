open Ast
open Propcraft_utils

(* Generator spec constructors for the propcraft package.
   Generators are structured Dict values interpreted by prop_for_all;
   they do not capture closures, so they are inspectable and
   reproducible under set_seed. *)

let gen name pairs = VDict (("gen", VString name) :: pairs)

let check_unknown_named fn_name allowed named_args =
  match
    List.find_opt
      (fun (n, _) ->
        match n with
        | Some name -> not (List.mem name allowed)
        | None -> false)
      named_args
  with
  | Some (Some name, _) ->
      Error
        (Error.type_error
           (Printf.sprintf "Function `%s` received unknown named argument `%s`."
              fn_name name))
  | _ -> Ok ()

let nonneg_int_arg fn_name name default named_args =
  match Math_common.optional_named_arg name named_args with
  | Some (VInt i) when i >= 0 -> Ok i
  | Some (VInt _) ->
      Error
        (Error.value_error
           (Printf.sprintf "Function `%s` expects `%s` to be non-negative." fn_name name))
  | Some other ->
      Error
        (Error.type_error
           (Printf.sprintf "Function `%s` expects `%s` to be an Int, got %s."
              fn_name name (Utils.type_name other)))
  | None -> Ok default

let positive_int_arg fn_name name default named_args =
  match Math_common.optional_named_arg name named_args with
  | Some (VInt i) when i > 0 -> Ok i
  | Some (VInt _) ->
      Error
        (Error.value_error
           (Printf.sprintf "Function `%s` expects `%s` to be positive." fn_name name))
  | Some other ->
      Error
        (Error.type_error
           (Printf.sprintf "Function `%s` expects `%s` to be an Int, got %s."
              fn_name name (Utils.type_name other)))
  | None -> Ok default

let prob_float_arg fn_name name default named_args =
  match Math_common.optional_named_arg name named_args with
  | Some (VFloat f) -> Ok (max 0.0 (min 1.0 f))
  | Some (VInt i) -> Ok (max 0.0 (min 1.0 (float_of_int i)))
  | Some other ->
      Error
        (Error.type_error
           (Printf.sprintf "Function `%s` expects `%s` to be a Float, got %s."
              fn_name name (Utils.type_name other)))
  | None -> Ok default

(*
--# Generate a random Int
--#
--# Returns a generator spec producing Int values drawn uniformly from
--# the optional `min`/`max` range (defaults: -10 to 10, inclusive).
--#
--# @name prop_gen_int
--# @param min :: Int = -10 Lower bound (inclusive).
--# @param max :: Int = 10 Upper bound (inclusive).
--# @return :: Dict A generator spec.
--# @example
--#   assert(prop_for_all(prop_gen_int(), \(x) x == x))
--# @family propcraft
--# @seealso prop_gen_int_range, prop_gen_float_range
--# @export
*)
let prop_gen_int =
  make_builtin_named ~name:"prop_gen_int" ~variadic:true 0 (fun named_args _env ->
    match check_unknown_named "prop_gen_int" [ "min"; "max" ] named_args with
    | Error err -> err
    | Ok () ->
        let int_arg name default =
          match Math_common.optional_named_arg name named_args with
          | Some (VInt i) -> Ok i
          | Some other ->
              Error
                (Error.type_error
                   (Printf.sprintf "Function `prop_gen_int` expects `%s` to be an Int, got %s."
                      name (Utils.type_name other)))
          | None -> Ok default
        in
        (match int_arg "min" (-10), int_arg "max" 10 with
         | Error err, _ | _, Error err -> err
         | Ok min, Ok max ->
             if max < min then
               Error.value_error
                 (Printf.sprintf "Function `prop_gen_int` requires max >= min, got [%d, %d]."
                    min max)
             else
               gen "int" [ ("min", VInt min); ("max", VInt max) ]))

(*
--# Generate a random Int in a fixed range
--#
--# Returns a generator spec producing Int values drawn uniformly from
--# [min, max] inclusive.
--#
--# @name prop_gen_int_range
--# @param min :: Int Lower bound (inclusive).
--# @param max :: Int Upper bound (inclusive).
--# @return :: Dict A generator spec.
--# @example
--#   assert(prop_for_all(prop_gen_int_range(0, 5), \(x) x >= 0 && x <= 5))
--# @family propcraft
--# @seealso prop_gen_int, prop_gen_float_range
--# @export
*)
let prop_gen_int_range =
  make_builtin ~name:"prop_gen_int_range" 2 (fun args _env ->
    match args with
    | [VInt min; VInt max] ->
        if max < min then
          Error.value_error
            (Printf.sprintf "Function `prop_gen_int_range` requires max >= min, got [%d, %d]."
               min max)
        else
          gen "int_range" [ ("min", VInt min); ("max", VInt max) ]
    | [other; _] ->
        Error.type_error
          (Printf.sprintf "Function `prop_gen_int_range` expects Int bounds, got %s."
             (Utils.type_name other))
    | _ -> Error.arity_error_named "prop_gen_int_range" 2 (List.length args))

(*
--# Generate a random Int within domain bounds
--#
--# Returns a generator spec producing Int values drawn uniformly from
--# [min, max] inclusive. Shrinking stays inside the domain: counterexamples
--# shrink toward `min` (e.g. 137 -> 118 -> ... -> 101), never below it.
--#
--# @name prop_between
--# @param min :: Int Lower bound (inclusive).
--# @param max :: Int Upper bound (inclusive).
--# @return :: Dict A generator spec.
--# @example
--#   assert(prop_for_all(prop_between(100, 200), \(x) x >= 100 && x <= 200))
--# @family propcraft
--# @seealso prop_gen_int, prop_gen_int_range
--# @export
*)
let prop_between =
  make_builtin ~name:"prop_between" 2 (fun args _env ->
    match args with
    | [VInt min; VInt max] ->
        if max < min then
          Error.value_error
            (Printf.sprintf "Function `prop_between` requires max >= min, got [%d, %d]."
               min max)
        else
          gen "between" [ ("min", VInt min); ("max", VInt max) ]
    | [other; _] ->
        Error.type_error
          (Printf.sprintf "Function `prop_between` expects Int bounds, got %s."
             (Utils.type_name other))
    | _ -> Error.arity_error_named "prop_between" 2 (List.length args))

(*
--# Generate a random Float in a range
--#
--# Returns a generator spec producing Float values drawn uniformly from
--# [min, max).
--#
--# @name prop_gen_float_range
--# @param min :: Float Lower bound (inclusive).
--# @param max :: Float Upper bound (exclusive).
--# @return :: Dict A generator spec.
--# @example
--#   assert(prop_for_all(prop_gen_float_range(0.0, 1.0), \(x) x >= 0.0))
--# @family propcraft
--# @seealso prop_gen_int_range
--# @export
*)
let prop_gen_float_range =
  make_builtin ~name:"prop_gen_float_range" 2 (fun args _env ->
    match args with
    | [a; b] ->
        (match to_float a, to_float b with
         | Some min, Some max ->
             if max <= min then
               Error.value_error
                 (Printf.sprintf "Function `prop_gen_float_range` requires max > min, got [%g, %g]."
                    min max)
             else
               gen "float_range" [ ("min", VFloat min); ("max", VFloat max) ]
         | _ ->
             Error.type_error
               "Function `prop_gen_float_range` expects numeric bounds, got a non-numeric value.")
    | _ -> Error.arity_error_named "prop_gen_float_range" 2 (List.length args))

(*
--# Generate a random Bool
--#
--# Returns a generator spec producing Bool values (true or false).
--#
--# @name prop_gen_bool
--# @return :: Dict A generator spec.
--# @example
--#   assert(prop_for_all(prop_gen_bool(), \(x) x == true || x == false))
--# @family propcraft
--# @seealso prop_gen_int
--# @export
*)
let prop_gen_bool =
  make_builtin ~name:"prop_gen_bool" 0 (fun _args _env ->
    gen "bool" [])

(*
--# Generate a random String
--#
--# Returns a generator spec producing Strings whose characters are
--# drawn from `chars` (a String, List, or Vector of Strings) with
--# lengths between `min_len` and `max_len` inclusive.
--#
--# @name prop_gen_string_from
--# @param chars :: String|List[String] Candidate characters.
--# @param min_len :: Int Minimum length (inclusive).
--# @param max_len :: Int Maximum length (inclusive).
--# @return :: Dict A generator spec.
--# @example
--#   assert(prop_for_all(prop_gen_string_from("ab", 1, 3), \(s) length(s) <= 3))
--# @family propcraft
--# @seealso prop_gen_int
--# @export
*)
let prop_gen_string_from =
  make_builtin ~name:"prop_gen_string_from" 3 (fun args _env ->
    match args with
    | [chars_value; a; b] ->
        (match a, b with
         | VInt min_len, VInt max_len ->
             if min_len < 0 || max_len < 0 then
               Error.value_error
                 "Function `prop_gen_string_from` expects non-negative length bounds."
             else if max_len < min_len then
               Error.value_error
                 (Printf.sprintf
                    "Function `prop_gen_string_from` requires max_len >= min_len, got [%d, %d]."
                    min_len max_len)
             else
               (match string_list_field "chars" (VDict [("chars", chars_value)]) with
                | None ->
                    Error.type_error
                      "Function `prop_gen_string_from` expects `chars` to be a String, List, or Vector of Strings."
                | Some chars when chars = [] ->
                    Error.value_error
                      "Function `prop_gen_string_from` expects a non-empty set of characters."
                | Some chars ->
                    let chars_list = List.map (fun c -> (None, VString c)) chars in
                    gen "string"
                      [ ("chars", VList chars_list);
                        ("min_len", VInt min_len);
                        ("max_len", VInt max_len) ])
         | _ ->
             Error.type_error
               (Printf.sprintf
                  "Function `prop_gen_string_from` expects Int length bounds, got %s and %s."
                  (Utils.type_name a) (Utils.type_name b)))
    | _ -> Error.arity_error_named "prop_gen_string_from" 3 (List.length args))

(*
--# Generate a value chosen from several generators
--#
--# Returns a generator spec that picks one of the supplied generators
--# uniformly at random on each draw.
--#
--# @name prop_gen_choice
--# @param gens :: List[Dict] The candidate generator specs.
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_gen_choice([prop_gen_int(), prop_gen_bool()])
--# @family propcraft
--# @seealso prop_gen_frequency
--# @export
*)
let prop_gen_choice =
  make_builtin ~name:"prop_gen_choice" 1 (fun args _env ->
    match args with
    | [VList items] ->
        if items = [] then
          Error.value_error "Function `prop_gen_choice` expects a non-empty list of generators."
        else
          gen "choice" [ ("gens", VList items) ]
    | [VVector arr] ->
        if Array.length arr = 0 then
          Error.value_error "Function `prop_gen_choice` expects a non-empty list of generators."
        else
          let items = List.init (Array.length arr) (fun i -> (None, arr.(i))) in
          gen "choice" [ ("gens", VList items) ]
    | [other] ->
        Error.type_error
          (Printf.sprintf "Function `prop_gen_choice` expects a List of generators, got %s."
             (Utils.type_name other))
    | _ -> Error.arity_error_named "prop_gen_choice" 1 (List.length args))

(*
--# Generate a value from weighted generators
--#
--# Returns a generator spec that picks one of the supplied generators
--# with probability proportional to its weight.
--#
--# @name prop_gen_frequency
--# @param pairs :: List[[Int, Dict]] A list of `[weight, generator]` pairs.
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_gen_frequency([[5, prop_gen_int()], [1, prop_gen_bool()]])
--# @family propcraft
--# @seealso prop_gen_choice
--# @export
*)
let prop_gen_frequency =
  make_builtin ~name:"prop_gen_frequency" 1 (fun args _env ->
    match args with
    | [VList items] ->
        let rec parse acc = function
          | [] -> Some (List.rev acc)
          | (_, VList [ (_, weight); (_, g) ]) :: rest ->
              (match weight, g with
               | VInt w, g -> parse ((w, g) :: acc) rest
               | _ -> None)
          | _ :: _ -> None
        in
        (match parse [] items with
         | None ->
             Error.type_error
               "Function `prop_gen_frequency` expects a list of `[weight, generator]` pairs."
         | Some pairs when pairs = [] ->
             Error.value_error
               "Function `prop_gen_frequency` expects a non-empty list of pairs."
         | Some pairs ->
             let total = List.fold_left (fun acc (w, _) -> acc + max 0 w) 0 pairs in
             if total <= 0 then
               Error.value_error
                 "Function `prop_gen_frequency` expects at least one positive weight."
             else
               let weights = List.map (fun (w, _) -> VInt w) pairs in
               let gens = List.map (fun (_, g) -> (None, g)) pairs in
               gen "frequency"
                 [ ("weights", VVector (Array.of_list weights));
                   ("gens", VList gens) ])
    | [other] ->
        Error.type_error
          (Printf.sprintf "Function `prop_gen_frequency` expects a List of pairs, got %s."
             (Utils.type_name other))
    | _ -> Error.arity_error_named "prop_gen_frequency" 1 (List.length args))

(*
--# Generate a random Vector
--#
--# Returns a generator spec producing a Vector of `n` elements drawn
--# from the `elem` generator.
--#
--# @name prop_gen_vector
--# @param elem :: Dict The element generator.
--# @param n :: Int The vector length.
--# @return :: Dict A generator spec.
--# @example
--#   assert(prop_for_all(prop_gen_vector(prop_gen_int(), 10), \(v) length(v) == 10))
--# @family propcraft
--# @seealso prop_gen_list
--# @export
*)
let prop_gen_vector =
  make_builtin ~name:"prop_gen_vector" 2 (fun args _env ->
    match args with
    | [elem; VInt n] when n >= 0 ->
        gen "vector" [ ("elem", elem); ("n", VInt n) ]
    | [_; VInt _] ->
        Error.value_error "Function `prop_gen_vector` expects `n` to be non-negative."
    | [_; other] ->
        Error.type_error
          (Printf.sprintf "Function `prop_gen_vector` expects `n` to be an Int, got %s."
             (Utils.type_name other))
    | _ -> Error.arity_error_named "prop_gen_vector" 2 (List.length args))

(*
--# Generate a random List
--#
--# Returns a generator spec producing a List of `n` elements drawn
--# from the `elem` generator.
--#
--# @name prop_gen_list
--# @param elem :: Dict The element generator.
--# @param n :: Int The list length.
--# @return :: Dict A generator spec.
--# @example
--#   assert(prop_for_all(prop_gen_list(prop_gen_int(), 4), \(xs) length(xs) == 4))
--# @family propcraft
--# @seealso prop_gen_vector
--# @export
*)
let prop_gen_list =
  make_builtin ~name:"prop_gen_list" 2 (fun args _env ->
    match args with
    | [elem; VInt n] when n >= 0 ->
        gen "list" [ ("elem", elem); ("n", VInt n) ]
    | [_; VInt _] ->
        Error.value_error "Function `prop_gen_list` expects `n` to be non-negative."
    | [_; other] ->
        Error.type_error
          (Printf.sprintf "Function `prop_gen_list` expects `n` to be an Int, got %s."
             (Utils.type_name other))
    | _ -> Error.arity_error_named "prop_gen_list" 2 (List.length args))

(*
--# Generate a random Factor
--#
--# Returns a generator spec producing a Factor value whose level is
--# chosen uniformly from `levels`. When used as a column in
--# prop_gen_df, one level is drawn per row.
--#
--# @name prop_gen_factor
--# @param levels :: List[String]|String The factor levels.
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_gen_factor(["low", "medium", "high"])
--# @family propcraft
--# @seealso prop_gen_df
--# @export
*)
let prop_gen_factor =
  make_builtin ~name:"prop_gen_factor" 1 (fun args _env ->
    match args with
    | [levels_value] ->
        (match string_list_field "levels" (VDict [("levels", levels_value)]) with
         | None ->
             Error.type_error
               "Function `prop_gen_factor` expects `levels` to be a List or Vector of Strings, or a String."
         | Some levels when levels = [] ->
             Error.value_error "Function `prop_gen_factor` expects at least one level."
         | Some levels ->
             let levels_list = List.map (fun l -> (None, VString l)) levels in
             gen "factor" [ ("levels", VList levels_list) ])
    | _ -> Error.arity_error_named "prop_gen_factor" 1 (List.length args))

(*
--# Generate a value chosen from a fixed set
--#
--# Returns a generator spec that picks one value uniformly at random from
--# `values` on each draw.
--#
--# @name prop_gen_one_of
--# @param values :: List[Any] | Vector[Any] The candidate values.
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_gen_one_of(["red", "green", "blue"])
--# @family propcraft
--# @seealso prop_gen_choice
--# @export
*)
let prop_gen_one_of =
  make_builtin ~name:"prop_gen_one_of" 1 (fun args _env ->
    match args with
    | [values_value] ->
        (match values_value with
         | VList [] ->
             Error.value_error
               "Function `prop_gen_one_of` expects a non-empty List or Vector of values."
         | VList items ->
             gen "one_of" [ ("values", VList items) ]
         | VVector arr when Array.length arr = 0 ->
             Error.value_error
               "Function `prop_gen_one_of` expects a non-empty List or Vector of values."
         | VVector arr ->
             gen "one_of" [ ("values", VVector arr) ]
         | other ->
             Error.type_error
               (Printf.sprintf
                  "Function `prop_gen_one_of` expects a List or Vector, got %s."
                  (Utils.type_name other)))
    | _ -> Error.arity_error_named "prop_gen_one_of" 1 (List.length args))

(*
--# Generate a Date or Datetime in a range
--#
--# Returns a generator spec that draws a Date uniformly between `start`
--# and `end` (inclusive). Bounds must be both Dates or both Datetimes; a
--# Datetime range keeps the start bound's timezone. Use `parse_date`,
--# `today`, or `parse_datetime` to build bounds.
--#
--# @name prop_gen_date_range
--# @param start :: Date | Datetime Lower bound (inclusive).
--# @param end :: Date | Datetime Upper bound (inclusive).
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_gen_date_range(parse_date("2020-01-01"), parse_date("2020-12-31"))
--# @family propcraft
--# @seealso prop_gen_int_range, parse_date, today
--# @export
*)
let prop_gen_date_range =
  make_builtin ~name:"prop_gen_date_range" 2 (fun args _env ->
    match args with
    | [VDate start_day; VDate end_day] ->
        if end_day < start_day then
          Error.value_error
            "Function `prop_gen_date_range` requires `end` to be on or after `start`."
        else
          gen "date_range"
            [ ("mode", VString "date");
              ("start_day", VInt start_day);
              ("end_day", VInt end_day) ]
    | [VDatetime (start_micros, tz); VDatetime (end_micros, _)] ->
        if Int64.compare end_micros start_micros < 0 then
          Error.value_error
            "Function `prop_gen_date_range` requires `end` to be on or after `start`."
        else
          gen "date_range"
            [ ("mode", VString "datetime");
              ("start_micros", VInt (Int64.to_int start_micros));
              ("end_micros", VInt (Int64.to_int end_micros));
              ("tz",
               (match tz with
                | Some s -> VString s
                | None -> VNA NAGeneric)) ]
    | [VDate _; VDatetime _] | [VDatetime _; VDate _] ->
        Error.type_error
          "Function `prop_gen_date_range` expects both bounds to be Dates or both to be Datetimes."
    | [a; b] ->
        Error.type_error
          (Printf.sprintf
             "Function `prop_gen_date_range` expects Date or Datetime bounds, got %s and %s."
             (Utils.type_name a) (Utils.type_name b))
    | _ -> Error.arity_error_named "prop_gen_date_range" 2 (List.length args))

(*
--# Generate a random DataFrame
--#
--# Returns a generator spec producing a DataFrame with one column per
--# entry in `columns` (a Dict mapping column names to generator specs).
--# Each column has `nrows` rows; with probability `na_prob`, a cell is
--# replaced with a typed NA matching the column's generator.
--#
--# @name prop_gen_df
--# @param columns :: Dict[String, Dict] Column name -> generator spec.
--# @param nrows :: Int = 30 Number of rows.
--# @param na_prob :: Float = 0.1 Probability a cell is NA (0 to 1).
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_gen_df([x: prop_gen_float_range(0.0, 100.0),
--#                    grp: prop_gen_factor(["a", "b"])],
--#                   nrows = 50, na_prob = 0.05)
--# @family propcraft
--# @seealso prop_gen_factor
--# @export
*)
let prop_gen_df =
  make_builtin_named ~name:"prop_gen_df" ~variadic:true 1 (fun named_args _env ->
    match check_unknown_named "prop_gen_df" [ "nrows"; "na_prob" ] named_args with
    | Error err -> err
    | Ok () ->
        (match Math_common.positional_args_without [ "nrows"; "na_prob" ] named_args with
         | [VDict columns] ->
             if columns = [] then
               Error.value_error
                 "Function `prop_gen_df` expects a non-empty Dict of columns."
             else
               (match nonneg_int_arg "prop_gen_df" "nrows" 30 named_args,
                      prob_float_arg "prop_gen_df" "na_prob" 0.1 named_args with
                | Error err, _ | _, Error err -> err
                | Ok nrows, Ok na_prob ->
                    gen "df"
                      [ ("columns", VDict columns);
                        ("nrows", VInt nrows);
                        ("na_prob", VFloat na_prob) ])
         | [other] ->
             Error.type_error
               (Printf.sprintf "Function `prop_gen_df` expects `columns` to be a Dict, got %s."
                  (Utils.type_name other))
         | args -> Error.arity_error_named "prop_gen_df" 1 (List.length args)))

(*
--# Generate a DataFrame matching an existing sample
--#
--# Returns a generator spec producing a DataFrame with the same columns
--# as `df`, inferring a per-column generator from the sample values: Int
--# and Float bounds come from the observed min/max, Strings are drawn
--# from the observed distinct values, Factors keep their levels, and
--# Dates/Datetimes keep their observed range (and timezone).
--#
--# @name prop_gen_df_from
--# @param df :: DataFrame The sample data frame to match.
--# @param nrows :: Int = 30 Number of rows to draw.
--# @param na_prob :: Float = 0.1 Probability a cell is NA (0 to 1).
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_gen_df_from(read_csv("mtcars.csv"), nrows = 100)
--# @family propcraft
--# @seealso prop_gen_df
--# @export
*)
let prop_gen_df_from =
  make_builtin_named ~name:"prop_gen_df_from" ~variadic:true 1 (fun named_args _env ->
    match check_unknown_named "prop_gen_df_from" [ "nrows"; "na_prob" ] named_args with
    | Error err -> err
    | Ok () ->
        (match Math_common.positional_args_without [ "nrows"; "na_prob" ] named_args with
         | [VDataFrame df] ->
             let infer_column name (values : value array) =
               let non_na =
                 Array.to_list values
                 |> List.filter (function VNA _ -> false | _ -> true)
               in
               match non_na with
               | [] ->
                   Error
                     (Error.value_error
                        (Printf.sprintf
                           "Function `prop_gen_df_from` cannot infer a type for column `%s`: no non-NA values."
                           name))
               | first :: rest ->
                   let col_name type_str = Printf.sprintf "column `%s` (%s)" name type_str in
                   (match first with
                    | VInt _ ->
                        (match List.filter_map (function VInt i -> Some i | _ -> None) (first :: rest) with
                         | i :: ints ->
                             let min_v = List.fold_left min i ints in
                             let max_v = List.fold_left max i ints in
                             Ok (gen "int_range" [ ("min", VInt min_v); ("max", VInt max_v) ])
                         | [] -> Error (Error.value_error (Printf.sprintf "cannot infer a type for %s." (col_name "Int"))))
                    | VFloat _ ->
                        (match List.filter_map (function VFloat f -> Some f | _ -> None) (first :: rest) with
                         | f :: floats ->
                             let min_v = List.fold_left Float.min f floats in
                             let max_v = List.fold_left Float.max f floats in
                             if max_v > min_v then
                               Ok (gen "float_range" [ ("min", VFloat min_v); ("max", VFloat max_v) ])
                             else
                               Ok (gen "one_of" [ ("values", VList [ (None, VFloat min_v) ]) ])
                         | [] -> Error (Error.value_error (Printf.sprintf "cannot infer a type for %s." (col_name "Float"))))
                    | VBool _ -> Ok (gen "bool" [])
                    | VString _ ->
                        let distinct =
                          List.sort_uniq compare
                            (List.filter_map (function VString s -> Some s | _ -> None) (first :: rest))
                        in
                        Ok
                          (gen "one_of"
                             [ ("values", VList (List.map (fun s -> (None, VString s)) distinct)) ])
                    | VFactor (_, levels, _) ->
                        Ok
                          (gen "factor"
                             [ ("levels", VList (List.map (fun l -> (None, VString l)) levels)) ])
                    | VDate _ ->
                        (match List.filter_map (function VDate d -> Some d | _ -> None) (first :: rest) with
                         | d :: days ->
                             let min_v = List.fold_left min d days in
                             let max_v = List.fold_left max d days in
                             Ok
                               (gen "date_range"
                                  [ ("mode", VString "date");
                                    ("start_day", VInt min_v);
                                    ("end_day", VInt max_v) ])
                         | [] -> Error (Error.value_error (Printf.sprintf "cannot infer a type for %s." (col_name "Date"))))
                    | VDatetime (_, tz) ->
                        (match
                           List.filter_map
                             (function VDatetime (m, _) -> Some m | _ -> None)
                             (first :: rest)
                         with
                         | m :: micros ->
                             let min_v = List.fold_left Int64.min m micros in
                             let max_v = List.fold_left Int64.max m micros in
                             Ok
                               (gen "date_range"
                                  [ ("mode", VString "datetime");
                                    ("start_micros", VInt (Int64.to_int min_v));
                                    ("end_micros", VInt (Int64.to_int max_v));
                                    ("tz",
                                     (match tz with
                                      | Some s -> VString s
                                      | None -> VNA NAGeneric)) ])
                         | [] ->
                             Error
                               (Error.value_error
                                  (Printf.sprintf "cannot infer a type for %s." (col_name "Datetime"))))
                    | other ->
                        Error
                          (Error.type_error
                             (Printf.sprintf
                                "Function `prop_gen_df_from` cannot infer a type for column `%s`: unsupported value type %s."
                                name (Utils.type_name other))))
             in
             (match nonneg_int_arg "prop_gen_df_from" "nrows" 30 named_args,
                    prob_float_arg "prop_gen_df_from" "na_prob" 0.1 named_args with
              | Error err, _ | _, Error err -> err
              | Ok nrows, Ok na_prob ->
                  let columns = Arrow_bridge.table_to_value_columns df.arrow_table in
                  if columns = [] then
                    Error.value_error
                      "Function `prop_gen_df_from` expects a DataFrame with at least one column."
                  else
                    let specs =
                      List.map (fun (name, values) -> (name, infer_column name values)) columns
                    in
                    let rec collect_ok = function
                      | [] -> Ok []
                      | (_, Error e) :: _ -> Error e
                      | (name, Ok spec) :: rest ->
                          (match collect_ok rest with
                           | Error e -> Error e
                           | Ok specs -> Ok ((name, spec) :: specs))
                    in
                    (match collect_ok specs with
                     | Error e -> e
                     | Ok specs ->
                         gen "df"
                           [ ("columns", VDict specs);
                             ("nrows", VInt nrows);
                             ("na_prob", VFloat na_prob) ]))
         | [other] ->
             Error.type_error
               (Printf.sprintf "Function `prop_gen_df_from` expects a DataFrame, got %s."
                  (Utils.type_name other))
         | args -> Error.arity_error_named "prop_gen_df_from" 1 (List.length args)))

(*
--# Generate a value via a custom function
--#
--# Returns a generator spec that draws a value by calling `fn(size)`
--# with the current generation size, so generators can build on each
--# other or on domain logic. `fn` may be any callable value.
--#
--# @name prop_gen_fn
--# @param fn :: Function A function from the current size to a value.
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_gen_fn(\(n) n * 2)
--# @family propcraft
--# @seealso prop_map_gen
--# @export
*)
let prop_gen_fn =
  make_builtin ~name:"prop_gen_fn" 1 (fun args _env ->
    match args with
    | [fn] -> gen "fn" [ ("fn", fn) ]
    | _ -> Error.arity_error_named "prop_gen_fn" 1 (List.length args))

(*
--# Transform a generated value
--#
--# Returns a generator spec that draws a value from `source`, applies
--# `fn` to it, and yields the result.
--#
--# @name prop_map_gen
--# @param source :: Dict The source generator.
--# @param fn :: Function A function from the generated value to a new value.
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_map_gen(prop_gen_int_range(0, 10), \(v) v * 2)
--# @family propcraft
--# @seealso prop_such_that, prop_resize
--# @export
*)
let prop_map_gen =
  make_builtin ~name:"prop_map_gen" 2 (fun args _env ->
    match args with
    | [source; fn] -> gen "map" [ ("source", source); ("fn", fn) ]
    | _ -> Error.arity_error_named "prop_map_gen" 2 (List.length args))

(*
--# Filter generated values by a predicate
--#
--# Returns a generator spec that draws values from `source` and keeps
--# only those for which `pred` returns true. Gives up (with an error)
--# after `max_tries` consecutive failures.
--#
--# @name prop_such_that
--# @param source :: Dict The source generator.
--# @param pred :: Function A Bool-returning predicate on generated values.
--# @param max_tries :: Int = 100 Retry limit before giving up.
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_such_that(prop_gen_int_range(-10, 10), \(x) x != 0)
--# @family propcraft
--# @seealso prop_map_gen
--# @export
*)
let prop_such_that =
  make_builtin_named ~name:"prop_such_that" ~variadic:true 2 (fun named_args _env ->
    match check_unknown_named "prop_such_that" [ "max_tries" ] named_args with
    | Error err -> err
    | Ok () ->
        (match Math_common.positional_args_without [ "max_tries" ] named_args with
         | [source; pred] ->
             (match positive_int_arg "prop_such_that" "max_tries" 100 named_args with
              | Error err -> err
              | Ok max_tries ->
                  gen "such_that"
                    [ ("source", source); ("pred", pred); ("max_tries", VInt max_tries) ])
         | args -> Error.arity_error_named "prop_such_that" 2 (List.length args)))

(*
--# Resize a generator
--#
--# Returns a generator spec that draws from `source` with the size
--# (number of elements/rows) of nested vector, list, and df generators
--# overridden to `n`. Generators that do not carry their own size are
--# unaffected.
--#
--# @name prop_resize
--# @param source :: Dict The generator to resize.
--# @param n :: Int New size for nested vector/list/df generators.
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_resize(prop_gen_vector(prop_gen_int(), 3), 20)
--# @family propcraft
--# @seealso prop_map_gen
--# @export
*)
let prop_resize =
  make_builtin ~name:"prop_resize" 2 (fun args _env ->
    match args with
    | [source; VInt n] when n >= 0 ->
        gen "resize" [ ("source", source); ("n", VInt n) ]
    | [_; VInt _] ->
        Error.value_error "Function `prop_resize` expects `n` to be non-negative."
    | [_; other] ->
        Error.type_error
          (Printf.sprintf "Function `prop_resize` expects `n` to be an Int, got %s."
             (Utils.type_name other))
    | _ -> Error.arity_error_named "prop_resize" 2 (List.length args))

let register env =
  let env = Env.add "prop_gen_int" prop_gen_int env in
  let env = Env.add "prop_gen_int_range" prop_gen_int_range env in
  let env = Env.add "prop_between" prop_between env in
  let env = Env.add "prop_gen_float_range" prop_gen_float_range env in
  let env = Env.add "prop_gen_bool" prop_gen_bool env in
  let env = Env.add "prop_gen_string_from" prop_gen_string_from env in
  let env = Env.add "prop_gen_choice" prop_gen_choice env in
  let env = Env.add "prop_gen_frequency" prop_gen_frequency env in
  let env = Env.add "prop_gen_vector" prop_gen_vector env in
  let env = Env.add "prop_gen_list" prop_gen_list env in
  let env = Env.add "prop_gen_factor" prop_gen_factor env in
  let env = Env.add "prop_gen_one_of" prop_gen_one_of env in
  let env = Env.add "prop_gen_date_range" prop_gen_date_range env in
  let env = Env.add "prop_gen_df" prop_gen_df env in
  let env = Env.add "prop_gen_df_from" prop_gen_df_from env in
  let env = Env.add "prop_gen_fn" prop_gen_fn env in
  let env = Env.add "prop_map_gen" prop_map_gen env in
  let env = Env.add "prop_such_that" prop_such_that env in
  let env = Env.add "prop_resize" prop_resize env in
  env
