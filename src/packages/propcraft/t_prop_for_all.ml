open Ast
open Propcraft_utils

(* prop_for_all: interpret a generator spec against the shared seeded
   RNG, evaluate a property over drawn values, and report failures with
   a (deterministic) shrunk counterexample. *)

let default_size = 30

let effective_size spec size =
  match int_field "n" spec with
  | Some n when n >= 0 -> n
  | _ -> size

let take_prefix k items =
  let rec go i acc = function
    | _ when i >= k -> List.rev acc
    | x :: rest -> go (i + 1) (x :: acc) rest
    | [] -> List.rev acc
  in
  go 0 [] items

let rec draw_many ~eval_call ~env ~size elem n acc =
  if n <= 0 then Ok (List.rev acc)
  else
    match draw_value ~eval_call ~env ~size elem with
    | Ok v -> draw_many ~eval_call ~env ~size elem (n - 1) (v :: acc)
    | Error err -> Error err

(* Draw a single value from a generator spec. *)
and draw_value ~eval_call ~env ~size (spec : value) : (value, value) result =
  match spec_gen spec with
  | None ->
      Error (Error.type_error "prop_for_all: invalid generator spec (missing `gen` field).")
  | Some "int" ->
      let min = match int_field "min" spec with Some m -> m | None -> -10 in
      let max = match int_field "max" spec with Some m -> m | None -> 10 in
      Ok (VInt (Rng.uniform_int_range ~min ~max))
  | Some "int_range" ->
      (match int_field "min" spec, int_field "max" spec with
       | Some min, Some max -> Ok (VInt (Rng.uniform_int_range ~min ~max))
       | _ ->
           Error (Error.type_error
                    "prop_for_all: int_range spec requires `min` and `max` Int fields."))
  | Some "float_range" ->
      (match float_field "min" spec, float_field "max" spec with
       | Some min, Some max -> Ok (VFloat (Rng.uniform_float_range ~min ~max))
       | _ ->
           Error (Error.type_error
                    "prop_for_all: float_range spec requires `min` and `max` numeric fields."))
  | Some "bool" -> Ok (VBool (Rng.uniform_bool ()))
  | Some "string" ->
      (match field "chars" spec, int_field "min_len" spec, int_field "max_len" spec with
       | Some chars_value, Some min_len, Some max_len ->
           (match string_list_field "chars" (VDict [("chars", chars_value)]) with
            | Some char_set when char_set <> [] ->
                let len = Rng.uniform_int_range ~min:min_len ~max:max_len in
                let arr = Array.of_list char_set in
                let buf = Buffer.create len in
                for _ = 1 to len do
                  match Rng.uniform_pick arr with
                  | Some c -> Buffer.add_string buf c
                  | None -> ()
                done;
                Ok (VString (Buffer.contents buf))
            | _ ->
                Error (Error.type_error
                         "prop_for_all: string spec requires a non-empty `chars` field."))
       | _ ->
           Error (Error.type_error
                    "prop_for_all: string spec requires `chars`, `min_len`, and `max_len` fields."))
  | Some "choice" ->
      (match field "gens" spec with
       | Some (VList gens) when gens <> [] ->
           (match Rng.uniform_pick (Array.of_list gens) with
            | Some (_, g) -> draw_value ~eval_call ~env ~size g
            | None ->
                Error (Error.value_error "prop_for_all: choice spec has no generators."))
       | _ ->
           Error (Error.type_error
                    "prop_for_all: choice spec requires a non-empty `gens` list."))
  | Some "frequency" ->
      (match field "weights" spec, field "gens" spec with
       | Some (VVector weights), Some (VList gens)
         when Array.length weights = List.length gens && Array.length weights > 0 ->
           let total =
             Array.fold_left
               (fun acc w -> match w with VInt i -> acc + max 0 i | _ -> acc)
               0 weights
           in
           if total <= 0 then
             Error (Error.value_error
                      "prop_for_all: frequency spec requires at least one positive weight.")
           else
             let r = Rng.uniform_int_range ~min:0 ~max:(total - 1) in
             let rec pick acc ws gs =
               match ws, gs with
               | w :: ws_rest, g :: gs_rest ->
                   let acc' = acc + (match w with VInt i -> max 0 i | _ -> 0) in
                   if r < acc' then Some g else pick acc' ws_rest gs_rest
               | [], _ | _, [] -> None
             in
             (match pick 0 (Array.to_list weights) gens with
              | Some (_, g) -> draw_value ~eval_call ~env ~size g
              | None ->
                  Error (Error.value_error
                           "prop_for_all: frequency spec weights are all zero."))
       | _ ->
           Error (Error.type_error
                    "prop_for_all: frequency spec requires matching `weights` and `gens`."))
  | Some ("vector" | "list") as kind ->
      let is_vector = kind = Some "vector" in
      (match field "elem" spec with
       | Some elem ->
           let n = effective_size spec size in
           (match draw_many ~eval_call ~env ~size elem n [] with
            | Error err -> Error err
            | Ok vals ->
                if is_vector then Ok (VVector (Array.of_list vals))
                else Ok (VList (List.map (fun v -> (None, v)) vals)))
       | None ->
           Error (Error.type_error "prop_for_all: vector/list spec requires an `elem` field."))
  | Some "factor" ->
      (match field "levels" spec with
       | Some levels_value ->
           (match string_list_field "levels" (VDict [("levels", levels_value)]) with
            | Some levels when levels <> [] ->
                let idx = Rng.uniform_int_range ~min:0 ~max:(List.length levels - 1) in
                Ok (VFactor (idx, levels, false))
            | _ ->
                Error (Error.type_error
                         "prop_for_all: factor spec requires a non-empty `levels` list."))
       | None ->
           Error (Error.type_error "prop_for_all: factor spec requires a `levels` field."))
  | Some "df" ->
      (match field "columns" spec with
       | Some (VDict columns) when columns <> [] ->
           let nrows =
             match int_field "nrows" spec with
             | Some n when n >= 0 -> n
             | _ -> effective_size spec size
           in
           let na_prob =
             match float_field "na_prob" spec with
             | Some p -> max 0.0 (min 1.0 p)
             | None -> 0.1
           in
           (match draw_columns ~eval_call ~env ~size ~nrows ~na_prob columns with
            | Error err -> Error err
            | Ok cols ->
                (match Arrow_bridge.table_from_value_columns cols nrows with
                 | Ok table -> Ok (VDataFrame { arrow_table = table; group_keys = [] })
                 | Error err -> Error err))
       | _ ->
           Error (Error.type_error
                    "prop_for_all: df spec requires a non-empty `columns` Dict."))
  | Some "map" ->
      (match field "source" spec, field "fn" spec with
       | Some src, Some fn ->
           (match draw_value ~eval_call ~env ~size src with
            | Error err -> Error err
            | Ok v -> Ok (eval_call env fn [(None, Ast.mk_expr (Value v))]))
       | _ ->
           Error (Error.type_error "prop_for_all: map spec requires `source` and `fn` fields."))
  | Some "such_that" ->
      (match field "source" spec, field "pred" spec with
       | Some src, Some pred ->
           let max_tries = match int_field "max_tries" spec with Some t when t > 0 -> t | _ -> 100 in
           let rec try_n remaining =
             if remaining <= 0 then
               Error
                 (Error.value_error
                    (Printf.sprintf
                       "prop_such_that: predicate could not be satisfied after %d tries."
                       max_tries))
             else
               match draw_value ~eval_call ~env ~size src with
               | Error err -> Error err
               | Ok v ->
                   (match eval_call env pred [(None, Ast.mk_expr (Value v))] with
                    | VBool true -> Ok v
                    | _ -> try_n (remaining - 1))
           in
           try_n max_tries
       | _ ->
           Error (Error.type_error
                    "prop_for_all: such_that spec requires `source` and `pred` fields."))
  | Some "resize" ->
      (match field "source" spec with
       | Some src ->
           let n = match int_field "n" spec with Some n when n >= 0 -> n | _ -> size in
           draw_value ~eval_call ~env ~size:n src
       | None ->
           Error (Error.type_error "prop_for_all: resize spec requires a `source` field."))
  | Some other ->
      Error (Error.type_error
               (Printf.sprintf "prop_for_all: unknown generator kind `%s`." other))

and draw_column ~eval_call ~env ~size ~nrows ~na_prob gen_spec =
  match draw_many ~eval_call ~env ~size gen_spec nrows [] with
  | Error err -> Error err
  | Ok vals ->
      let na = na_for_spec gen_spec in
      let col =
        Array.of_list
          (List.map
             (fun v ->
               if na_prob > 0.0 && Rng.uniform_float_range ~min:0.0 ~max:1.0 < na_prob
               then VNA na
               else v)
             vals)
      in
      Ok col

and draw_columns ~eval_call ~env ~size ~nrows ~na_prob columns =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | (name, gen_spec) :: rest ->
        (match draw_column ~eval_call ~env ~size ~nrows ~na_prob gen_spec with
         | Ok col -> go ((name, col) :: acc) rest
         | Error err -> Error err)
  in
  go [] columns

(* ---- Shrinking ---------------------------------------------------- *)

let half_toward_zero i =
  if i = 0 then 0
  else if i > 0 then i / 2
  else -((-i) / 2)

let shrink_int i =
  if i = 0 then []
  else
    List.sort_uniq compare [ 0; half_toward_zero i ]
    |> List.filter (fun c -> c <> i)

let shrink_float f =
  if f = 0.0 then []
  else List.sort_uniq compare [ 0.0; f /. 2.0 ] |> List.filter (fun c -> c <> f)

let shrink_string s =
  let len = String.length s in
  if len = 0 then []
  else
    let rec prefixes k acc =
      if k <= 0 then String.sub s 0 0 :: acc
      else prefixes (k / 2) (String.sub s 0 k :: acc)
    in
    prefixes (len / 2) []
    |> List.sort_uniq compare
    |> List.filter (fun c -> c <> s)

let rec shrink_list items =
  let len = List.length items in
  if len = 0 then []
  else
    let prefixes =
      let rec go k acc =
        if k <= 0 then List.rev acc
        else go (k / 2) (take_prefix k items :: acc)
      in
      go (len / 2) []
    in
    let elem_wise =
      List.mapi
        (fun i (_, v) ->
          shrink_value v
          |> List.map (fun sv ->
                 List.mapi (fun j (n2, v2) -> if j = i then (n2, sv) else (n2, v2)) items))
        items
      |> List.concat
    in
    (prefixes @ elem_wise)
    |> List.filter (fun l -> l <> items)
    |> List.sort_uniq compare

and shrink_dict pairs =
  List.concat_map
    (fun (k, v) ->
      shrink_value v
      |> List.map (fun sv ->
             List.map (fun (k2, v2) -> if k2 = k then (k2, sv) else (k2, v2)) pairs))
    pairs
  |> List.filter (fun d -> d <> pairs)
  |> List.sort_uniq compare

and shrink_value v =
  match v with
  | VInt i -> List.map (fun x -> VInt x) (shrink_int i)
  | VFloat f -> List.map (fun x -> VFloat x) (shrink_float f)
  | VBool true -> [ VBool false ]
  | VBool false -> []
  | VString s -> List.map (fun x -> VString x) (shrink_string s)
  | VFactor (i, levels, ordered) ->
      List.map (fun x -> VFactor (x, levels, ordered)) (shrink_int i)
  | VList items -> List.map (fun l -> VList l) (shrink_list items)
  | VVector arr ->
      shrink_list (Array.to_list arr |> List.map (fun v -> (None, v)))
      |> List.map (fun l -> VVector (Array.of_list (List.map snd l)))
  | VDict pairs -> List.map (fun d -> VDict d) (shrink_dict pairs)
  | _ -> []

let cap_candidates candidates =
  let rec take i acc = function
    | _ when i >= 32 -> List.rev acc
    | x :: rest -> take (i + 1) (x :: acc) rest
    | [] -> List.rev acc
  in
  take 0 [] candidates

(* ---- Property evaluation ------------------------------------------ *)

let outcome_of = function
  | VBool true -> `Pass
  | VExpect Expect_pass -> `Pass
  | VExpect (Expect_hold _) -> `Hold
  | VBool false -> `False
  | VExpect (Expect_stop msg) -> `Stop msg
  | VNA _ -> `NA
  | VError err -> `Error err
  | other -> `Other other

let is_failure = function
  | `Pass | `Hold -> false
  | _ -> true

let shrink_minimal ~eval_call ~env property input =
  let fails v =
    outcome_of (eval_call env property [(None, Ast.mk_expr (Value v))])
    |> is_failure
  in
  let rec go v =
    let candidates = cap_candidates (shrink_value v) in
    match List.find_opt fails candidates with
    | Some c -> go c
    | None -> v
  in
  go input

let failure_message ~n ~i ~input ~shrunk ~reason =
  let input_s = render_value input in
  let shrunk_s =
    if shrunk = input then input_s else render_value shrunk
  in
  VExpect
    (Expect_stop
       (Printf.sprintf
          "Property failed after %d of %d runs.\n  counterexample: %s\n  (shrunk): %s\n  predicate: %s"
          i n input_s shrunk_s reason))

let run_property ~eval_call ~env ~n ~shrink spec property =
  let rec loop i =
    if i > n then VExpect Expect_pass
    else
      match draw_value ~eval_call ~env ~size:default_size spec with
      | Error err -> err
      | Ok input ->
          let result = eval_call env property [(None, Ast.mk_expr (Value input))] in
          (match outcome_of result with
           | `Pass | `Hold -> loop (i + 1)
           | `False ->
               let shrunk =
                 if shrink then shrink_minimal ~eval_call ~env property input else input
               in
               failure_message ~n ~i ~input ~shrunk ~reason:"returned false"
           | `Stop msg ->
               let shrunk =
                 if shrink then shrink_minimal ~eval_call ~env property input else input
               in
               failure_message ~n ~i ~input ~shrunk ~reason:(Printf.sprintf "failed: %s" msg)
           | `NA ->
               let shrunk =
                 if shrink then shrink_minimal ~eval_call ~env property input else input
               in
               failure_message ~n ~i ~input ~shrunk
                 ~reason:"returned NA (property must handle missingness explicitly)"
           | `Error err ->
               let shrunk =
                 if shrink then shrink_minimal ~eval_call ~env property input else input
               in
               failure_message ~n ~i ~input ~shrunk
                 ~reason:(Printf.sprintf "raised: %s" err.message)
           | `Other other ->
               failure_message ~n ~i ~input ~shrunk:input
                 ~reason:(Printf.sprintf
                            "returned %s (expected Bool or an Expect value)"
                            (Utils.type_name other)))
  in
  loop 1

(*
--# Check a property over generated values
--#
--# Draws `n` values from the `gen` generator spec (using the shared
--# seeded RNG — call set_seed first for reproducible runs) and evaluates
--# `property` on each. The property may return a Bool, an Expect value
--# from testcraft (e.g. expect_equal), or an Error (treated as failure).
--# On the first failure, a deterministic shrunk counterexample is
--# reported via an Expect_stop value, so `assert(prop_for_all(...))`
--# works inside test files run by `t test`.
--#
--# @name prop_for_all
--# @param gen :: Dict A generator spec (see prop_gen_int, prop_gen_df, ...).
--# @param property :: Function A function from a generated value to Bool or Expect.
--# @param n :: Int = 100 Number of values to draw.
--# @param shrink :: Bool = true Whether to report a shrunk counterexample.
--# @return :: Expect Expect_pass on success, Expect_stop on failure.
--# @example
--#   set_seed(42)
--#   assert(prop_for_all(prop_gen_int_range(0, 100), \(x) x >= 0))
--#   assert(prop_for_all(
--#     prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.1),
--#     \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df)))
--# @family propcraft
--# @seealso expect_equal, set_seed
--# @export
*)
let register ~eval_call env =
  Env.add "prop_for_all"
    (make_builtin_named ~name:"prop_for_all" ~variadic:true 2 (fun named_args env ->
       let unknown =
         List.filter
           (fun (n, _) ->
             match n with
             | None | Some ("n" | "shrink") -> false
             | Some _ -> true)
           named_args
       in
       match unknown with
       | (Some arg_name, _) :: _ ->
           Error.type_error
             (Printf.sprintf "Function `prop_for_all` received unknown named argument `%s`."
                arg_name)
       | _ ->
           let n =
             match Math_common.optional_named_arg "n" named_args with
             | Some (VInt i) when i > 0 -> Ok i
             | Some (VInt _) ->
                 Error
                   (Error.value_error
                      "Function `prop_for_all` expects `n` to be a positive Int.")
             | Some other ->
                 Error
                   (Error.type_error
                      (Printf.sprintf "Function `prop_for_all` expects `n` to be an Int, got %s."
                         (Utils.type_name other)))
             | None -> Ok 100
           in
           let shrink =
             match Math_common.get_bool_flag "shrink" true named_args with
             | Ok b -> Ok b
             | Error err -> Error err
           in
           (match n, shrink,
                  Math_common.positional_args_without [ "n"; "shrink" ] named_args with
            | Ok n, Ok shrink, [gen; property] ->
                run_property ~eval_call ~env ~n ~shrink gen property
            | Error err, _, _ | _, Error err, _ -> err
            | _, _, args ->
                Error.arity_error_named "prop_for_all" 2 (List.length args))))
    env
