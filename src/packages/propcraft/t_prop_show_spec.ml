open Ast
open Propcraft_utils

(* prop_show_spec: render an inspectable generator spec Dict back to T
   source code that rebuilds an equivalent generator. The round-trip
   contract is behavioral equivalence, not structural identity: e.g. a
   `one_of` spec built from a Vector literal re-parses to a List, which
   draws identically. Specs that capture closures (map/such_that/fn) or
   use an unknown generator kind cannot be rendered and return an error. *)

let is_valid_ident s =
  let n = String.length s in
  n > 0
  && (let c0 = s.[0] in
      (c0 >= 'a' && c0 <= 'z') || (c0 >= 'A' && c0 <= 'Z') || c0 = '_')
  && (let rec go i =
        if i >= n then true
        else
          let c = s.[i] in
          if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
             || (c >= '0' && c <= '9') || c = '_'
          then go (i + 1)
          else false
      in
      go 1)

let quote s = "\"" ^ Ast.Utils.escape_string_utf8 s ^ "\""

let render_date days =
  let year, month, day = Chrono.civil_from_days days in
  Printf.sprintf "%04d-%02d-%02d" year month day

let render_datetime_string micros =
  let year, month, day, hour, minute, second, micros_part =
    Chrono.split_datetime_micros micros
  in
  Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d.%06d"
    year month day hour minute second micros_part

(* Render a scalar literal value as T source. Returns an error message for
   values that cannot be re-expressed as literals (closures, DataFrames,
   pipelines, ...). *)
let rec t_literal (v : value) : (string, string) result =
  match v with
  | VInt i -> Ok (string_of_int i)
  | VFloat f -> Ok (string_of_float f)
  | VBool b -> Ok (string_of_bool b)
  | VString s -> Ok (quote s)
  | VDate days ->
      Ok (Printf.sprintf "parse_date(%s, \"%s\")" (quote (render_date days)) "%Y-%m-%d")
  | VDatetime (micros, tz) ->
      let args = Printf.sprintf "%s, \"%s\"" (quote (render_datetime_string micros)) "%Y-%m-%d %H:%M:%S" in
      let args = match tz with Some name -> args ^ Printf.sprintf ", tz = %s" (quote name) | None -> args in
      Ok (Printf.sprintf "parse_datetime(%s)" args)
  | VFactor (idx, levels, _ordered) ->
      (match List.nth_opt levels idx with
       | Some level -> Ok (Printf.sprintf "to_factor([%s])" (quote level))
       | None -> Error "cannot render a Factor with an out-of-range level index.")
  | VList items ->
      (match List.map (fun (_, v) -> t_literal v) items |> collect with
       | Error e -> Error e
       | Ok parts -> Ok ("[" ^ String.concat ", " parts ^ "]"))
  | VVector arr ->
      let parts = List.map t_literal (Array.to_list arr) |> collect in
      (match parts with
       | Error e -> Error e
       | Ok parts -> Ok ("[" ^ String.concat ", " parts ^ "]"))
  | VDict pairs ->
      (match List.map (fun (k, v) ->
               if not (is_valid_ident k) then
                 Error (Printf.sprintf "cannot render Dict key `%s` as a bare identifier." k)
               else
                 match t_literal v with
                 | Error e -> Error e
                 | Ok vs -> Ok (k ^ ": " ^ vs))
             pairs
           |> collect with
       | Error e -> Error e
       | Ok parts -> Ok ("[" ^ String.concat ", " parts ^ "]"))
  | _ ->
      Error (Printf.sprintf "cannot render a %s value as a literal." (Utils.type_name v))

and collect results =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | Error e :: _ -> Error e
    | Ok s :: rest -> go (s :: acc) rest
  in
  go [] results

(* Render a generator spec into T source. Closure-carrying kinds and
   unknown kinds are explicit errors. *)
let rec render_spec (spec : value) : (string, string) result =
  match spec_gen spec with
  | None -> Error "invalid generator spec (missing `gen` field)."
  | Some "int" ->
      let min = match int_field "min" spec with Some m -> m | None -> -10 in
      let max = match int_field "max" spec with Some m -> m | None -> 10 in
      Ok (Printf.sprintf "prop_gen_int(min = %d, max = %d)" min max)
  | Some "int_range" ->
      (match int_field "min" spec, int_field "max" spec with
       | Some min, Some max -> Ok (Printf.sprintf "prop_gen_int_range(%d, %d)" min max)
       | _ -> Error "int_range spec is missing `min` or `max`.")
  | Some "between" ->
      (match int_field "min" spec, int_field "max" spec with
       | Some min, Some max -> Ok (Printf.sprintf "prop_between(%d, %d)" min max)
       | _ -> Error "between spec is missing `min` or `max`.")
  | Some "float_range" ->
      (match float_field "min" spec, float_field "max" spec with
       | Some min, Some max ->
           Ok (Printf.sprintf "prop_gen_float_range(%s, %s)"
                 (string_of_float min) (string_of_float max))
       | _ -> Error "float_range spec is missing `min` or `max`.")
  | Some "bool" -> Ok "prop_gen_bool()"
  | Some "string" ->
      (match field "chars" spec, int_field "min_len" spec, int_field "max_len" spec with
       | Some chars_value, Some min_len, Some max_len ->
           (match string_list_field "chars" (VDict [ ("chars", chars_value) ]) with
            | Some chars ->
                (match List.map (fun c -> Ok (quote c)) chars |> collect with
                 | Error e -> Error e
                 | Ok parts ->
                     Ok
                       (Printf.sprintf "prop_gen_string_from([%s], %d, %d)"
                          (String.concat ", " parts) min_len max_len))
            | None -> Error "string spec has a non-renderable `chars` field.")
       | _ -> Error "string spec is missing `chars`, `min_len`, or `max_len`.")
  | Some "factor" ->
      (match field "levels" spec with
       | Some levels_value ->
           (match string_list_field "levels" (VDict [ ("levels", levels_value) ]) with
            | Some levels ->
                (match List.map (fun l -> Ok (quote l)) levels |> collect with
                 | Error e -> Error e
                 | Ok parts ->
                     Ok (Printf.sprintf "prop_gen_factor([%s])" (String.concat ", " parts)))
            | None -> Error "factor spec has a non-renderable `levels` field.")
       | None -> Error "factor spec is missing `levels`.")
  | Some "one_of" ->
      (match field "values" spec with
       | Some (VList items) ->
           (match List.map (fun (_, v) -> t_literal v) items |> collect with
            | Error e -> Error e
            | Ok parts -> Ok (Printf.sprintf "prop_gen_one_of([%s])" (String.concat ", " parts)))
       | Some (VVector arr) ->
           let parts = List.map t_literal (Array.to_list arr) |> collect in
           (match parts with
            | Error e -> Error e
            | Ok parts -> Ok (Printf.sprintf "prop_gen_one_of([%s])" (String.concat ", " parts)))
       | _ -> Error "one_of spec is missing `values`.")
  | Some "choice" ->
      (match field "gens" spec with
       | Some (VList gens) ->
           (match List.map (fun (_, g) -> render_spec g) gens |> collect with
            | Error e -> Error e
            | Ok parts -> Ok (Printf.sprintf "prop_gen_choice([%s])" (String.concat ", " parts)))
       | _ -> Error "choice spec is missing `gens`.")
  | Some "frequency" ->
      (match field "weights" spec, field "gens" spec with
       | Some (VVector weights), Some (VList gens)
         when Array.length weights = List.length gens ->
           let parts =
             List.map2
               (fun w g ->
                 match w, g with
                 | VInt w, (_, g) ->
                     (match render_spec g with
                      | Error e -> Error e
                      | Ok gs -> Ok (Printf.sprintf "[%d, %s]" w gs))
                 | _ -> Error "frequency spec has a non-Int weight.")
               (Array.to_list weights) gens
             |> collect
           in
           (match parts with
            | Error e -> Error e
            | Ok parts -> Ok (Printf.sprintf "prop_gen_frequency([%s])" (String.concat ", " parts)))
       | _ -> Error "frequency spec requires matching `weights` and `gens`.")
  | Some "vector" | Some "list" as kind ->
      let name = if kind = Some "vector" then "prop_gen_vector" else "prop_gen_list" in
      (match field "elem" spec, int_field "n" spec with
       | Some elem, Some n ->
           (match render_spec elem with
            | Error e -> Error e
            | Ok es -> Ok (Printf.sprintf "%s(%s, %d)" name es n))
       | _ -> Error (Printf.sprintf "%s spec requires `elem` and `n`." name))
  | Some "date_range" ->
      (match field "mode" spec with
       | Some (VString "date") ->
           (match int_field "start_day" spec, int_field "end_day" spec with
            | Some start_day, Some end_day ->
                Ok
                  (Printf.sprintf
                     "prop_gen_date_range(parse_date(%s, \"%s\"), parse_date(%s, \"%s\"))"
                     (quote (render_date start_day)) "%Y-%m-%d"
                     (quote (render_date end_day)) "%Y-%m-%d")
            | _ -> Error "date_range date spec requires `start_day` and `end_day`.")
       | Some (VString "datetime") ->
           (match int_field "start_micros" spec, int_field "end_micros" spec with
            | Some start_m, Some end_m ->
                let tz = match field "tz" spec with Some (VString s) -> Some s | _ -> None in
                let bound micros =
                  let args =
                    Printf.sprintf "%s, \"%s\""
                      (quote (render_datetime_string (Int64.of_int micros))) "%Y-%m-%d %H:%M:%S"
                  in
                  let args =
                    match tz with
                    | Some name -> args ^ Printf.sprintf ", tz = %s" (quote name)
                    | None -> args
                  in
                  Printf.sprintf "parse_datetime(%s)" args
                in
                Ok
                  (Printf.sprintf "prop_gen_date_range(%s, %s)"
                     (bound start_m) (bound end_m))
            | _ -> Error "date_range datetime spec requires `start_micros` and `end_micros`.")
       | _ -> Error "date_range spec requires a `mode` field.")
  | Some "df" ->
      (match field "columns" spec, int_field "nrows" spec with
       | Some (VDict columns), Some nrows ->
           let na_prob = match float_field "na_prob" spec with Some p -> p | None -> 0.1 in
           (match
              List.map
                (fun (name, g) ->
                  if not (is_valid_ident name) then
                    Error (Printf.sprintf "cannot render column name `%s` as a bare identifier." name)
                  else
                    match render_spec g with
                    | Error e -> Error e
                    | Ok gs -> Ok (Printf.sprintf "%s: %s" name gs))
                columns
              |> collect
            with
            | Error e -> Error e
            | Ok parts ->
                Ok
                  (Printf.sprintf "prop_gen_df([%s], nrows = %d, na_prob = %s)"
                     (String.concat ", " parts) nrows (string_of_float na_prob)))
       | _ -> Error "df spec requires a non-empty `columns` Dict and `nrows`.")
  | Some "resize" ->
      (match field "source" spec, int_field "n" spec with
       | Some source, Some n ->
           (match render_spec source with
            | Error e -> Error e
            | Ok ss -> Ok (Printf.sprintf "prop_resize(%s, %d)" ss n))
       | _ -> Error "resize spec requires `source` and `n`.")
  | Some ("map" | "such_that" | "fn") as kind ->
      let name = match kind with Some "map" -> "map" | Some "such_that" -> "such_that" | _ -> "fn" in
      Error (Printf.sprintf "cannot render a `%s` generator spec: it captures a closure." name)
  | Some other -> Error (Printf.sprintf "unknown generator kind `%s`." other)

(*
--# Render a generator spec back to T source
--#
--# Inspects the `gen` Dict (as built by prop_gen_int, prop_gen_df, ...)
--# and returns the T source that rebuilds a behaviorally equivalent
--# generator: both produce identical values under the same seed.
--# Closure-carrying generators (prop_map_gen, prop_such_that,
--# prop_gen_fn) and unknown generator kinds cannot be rendered and raise
--# an error.
--#
--# @name prop_show_spec
--# @param spec :: Dict A generator spec (see prop_gen_int, prop_gen_df, ...).
--# @return :: String T source that rebuilds the generator.
--# @example
--#   prop_show_spec(prop_gen_int_range(0, 100))
--#   # "prop_gen_int_range(0, 100)"
--# @family propcraft
--# @seealso prop_for_all, prop_gen_int
--# @export
*)
let prop_show_spec =
  make_builtin ~name:"prop_show_spec" 1 (fun args _env ->
    match args with
    | [spec] ->
        (match render_spec spec with
         | Ok src -> VString src
         | Error msg ->
             Error.type_error
               (Printf.sprintf "Function `prop_show_spec` cannot render the generator spec: %s" msg))
    | _ -> Error.arity_error_named "prop_show_spec" 1 (List.length args))

let register env = Env.add "prop_show_spec" prop_show_spec env
