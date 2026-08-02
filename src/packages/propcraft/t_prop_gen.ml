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
--# Returns a generator spec that draws from `source` with the default
--# size (number of rows/elements) overridden to `n`.
--#
--# @name prop_resize
--# @param source :: Dict The generator to resize.
--# @param n :: Int New size for nested vector/list/factor/df generators.
--# @return :: Dict A generator spec.
--# @example
--#   g = prop_resize(prop_gen_vector(prop_gen_int()), 20)
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
  let env = Env.add "prop_gen_float_range" prop_gen_float_range env in
  let env = Env.add "prop_gen_bool" prop_gen_bool env in
  let env = Env.add "prop_gen_string_from" prop_gen_string_from env in
  let env = Env.add "prop_gen_choice" prop_gen_choice env in
  let env = Env.add "prop_gen_frequency" prop_gen_frequency env in
  let env = Env.add "prop_gen_vector" prop_gen_vector env in
  let env = Env.add "prop_gen_list" prop_gen_list env in
  let env = Env.add "prop_gen_factor" prop_gen_factor env in
  let env = Env.add "prop_gen_df" prop_gen_df env in
  let env = Env.add "prop_map_gen" prop_map_gen env in
  let env = Env.add "prop_such_that" prop_such_that env in
  let env = Env.add "prop_resize" prop_resize env in
  env
