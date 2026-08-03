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

(* Rewrite a generator spec so that container sizes (vector/list length,
   df row count) are forced to `n`. This is what makes prop_resize
   override the source's own `n`/`nrows` instead of silently doing
   nothing. Container specs are rewritten directly; wrapper specs
   (map/such_that/resize/choice/frequency) are recursed into so the size
   propagates through composition. *)
let rec force_size_in_spec spec n =
  match spec with
  | VDict pairs ->
      (match field "gen" spec with
       | Some (VString ("vector" | "list")) ->
           VDict
             (List.map
                (fun (k, v) -> if String.equal k "n" then (k, VInt n) else (k, v))
                pairs)
       | Some (VString "df") ->
           VDict
             (List.map
                (fun (k, v) ->
                  if String.equal k "nrows" then (k, VInt n) else (k, v))
                pairs)
       | Some (VString ("map" | "such_that" | "resize")) ->
           VDict
             (List.map
                (fun (k, v) ->
                  if String.equal k "source" then (k, force_size_in_spec v n)
                  else (k, v))
                pairs)
       | Some (VString ("choice" | "frequency")) ->
           (match field "gens" spec with
            | Some (VList items) ->
                VDict
                  (List.map
                     (fun (k, v) ->
                       if String.equal k "gens" then
                         (k, VList (List.map (fun (name, g) -> (name, force_size_in_spec g n)) items))
                       else (k, v))
                     pairs)
            | _ -> spec)
       | _ -> spec)
  | _ -> spec

let rec draw_many ~eval_call ~env ~size elem n acc =
  if n <= 0 then Ok (List.rev acc)
  else
    match draw_value ~eval_call ~env ~size elem with
    | Ok v -> draw_many ~eval_call ~env ~size elem (n - 1) (v :: acc)
    | Error err -> Error err

(* Fast path for per-cell drawing inside [prop_gen_df]: leaf scalar specs
   (int/int_range/float_range/bool/string/factor/one_of/date_range) have
   all their parameters known up front, so draw_column can close over them
   and emit nrows cells with a tight loop instead of re-dispatching through
   draw_value per cell. Returns None for container/wrapper specs, which keep
   the generic draw_many path. Draw order and RNG consumption are identical
   to the generic path, so seeded runs stay reproducible. *)
and leaf_drawer (spec : value) : (unit -> value) option =
  match spec_gen spec with
  | Some "int" ->
      let min = match int_field "min" spec with Some m -> m | None -> -10 in
      let max = match int_field "max" spec with Some m -> m | None -> 10 in
      Some (fun () -> VInt (Rng.uniform_int_range ~min ~max))
  | Some "int_range" ->
      (match int_field "min" spec, int_field "max" spec with
       | Some min, Some max ->
           Some (fun () -> VInt (Rng.uniform_int_range ~min ~max))
       | _ -> None)
  | Some "between" ->
      (match int_field "min" spec, int_field "max" spec with
       | Some min, Some max ->
           Some (fun () -> VInt (Rng.uniform_int_range ~min ~max))
       | _ -> None)
  | Some "float_range" ->
      (match float_field "min" spec, float_field "max" spec with
       | Some min, Some max ->
           Some (fun () -> VFloat (Rng.uniform_float_range ~min ~max))
       | _ -> None)
  | Some "bool" -> Some (fun () -> VBool (Rng.uniform_bool ()))
  | Some "string" ->
      (match field "chars" spec, int_field "min_len" spec, int_field "max_len" spec with
       | Some chars_value, Some min_len, Some max_len ->
           (match string_list_field "chars" (VDict [ ("chars", chars_value) ]) with
            | Some char_set when char_set <> [] ->
                let arr = Array.of_list char_set in
                Some (fun () ->
                    let len = Rng.uniform_int_range ~min:min_len ~max:max_len in
                    let buf = Buffer.create len in
                    for _ = 1 to len do
                      match Rng.uniform_pick arr with
                      | Some c -> Buffer.add_string buf c
                      | None -> ()
                    done;
                    VString (Buffer.contents buf))
            | _ -> None)
       | _ -> None)
  | Some "factor" ->
      (match field "levels" spec with
       | Some levels_value ->
           (match string_list_field "levels" (VDict [ ("levels", levels_value) ]) with
            | Some levels when levels <> [] ->
                let nlevels = List.length levels in
                Some
                  (fun () ->
                    VFactor
                      (Rng.uniform_int_range ~min:0 ~max:(nlevels - 1), levels, false))
            | _ -> None)
       | None -> None)
  | Some "one_of" ->
      (match field "values" spec with
       | Some (VList items) when items <> [] ->
           let arr = Array.of_list items in
           Some
             (fun () ->
               match Rng.uniform_pick arr with
               | Some (_, v) -> v
               | None -> VNA NAGeneric)
       | Some (VVector arr) when Array.length arr > 0 ->
           Some
             (fun () ->
               match Rng.uniform_pick arr with
               | Some v -> v
               | None -> VNA NAGeneric)
       | _ -> None)
  | Some "date_range" ->
      (match field "mode" spec with
       | Some (VString "date") ->
           (match int_field "start_day" spec, int_field "end_day" spec with
            | Some start_day, Some end_day ->
                Some (fun () -> VDate (Rng.uniform_int_range ~min:start_day ~max:end_day))
            | _ -> None)
       | Some (VString "datetime") ->
           (match int_field "start_micros" spec, int_field "end_micros" spec with
            | Some start_m, Some end_m ->
                let tz =
                  match field "tz" spec with
                  | Some (VString s) -> Some s
                  | _ -> None
                in
                Some
                  (fun () ->
                    VDatetime
                      ( Rng.uniform_int64_range
                          ~min:(Int64.of_int start_m)
                          ~max:(Int64.of_int end_m),
                        tz ))
            | _ -> None)
       | _ -> None)
  | _ -> None

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
  | Some "between" ->
      (match int_field "min" spec, int_field "max" spec with
       | Some min, Some max -> Ok (VInt (Rng.uniform_int_range ~min ~max))
       | _ ->
           Error (Error.type_error
                    "prop_for_all: between spec requires `min` and `max` Int fields."))
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
  | Some "one_of" ->
      (match field "values" spec with
       | Some (VList items) when items <> [] ->
           (match Rng.uniform_pick (Array.of_list items) with
            | Some (_, v) -> Ok v
            | None ->
                Error (Error.value_error "prop_for_all: one_of spec has no values."))
       | Some (VVector arr) when Array.length arr > 0 ->
           (match Rng.uniform_pick arr with
            | Some v -> Ok v
            | None ->
                Error (Error.value_error "prop_for_all: one_of spec has no values."))
       | _ ->
           Error (Error.type_error
                    "prop_for_all: one_of spec requires a non-empty `values` List or Vector."))
  | Some "date_range" ->
      (match field "mode" spec with
       | Some (VString "date") ->
           (match int_field "start_day" spec, int_field "end_day" spec with
            | Some start_day, Some end_day ->
                Ok (VDate (Rng.uniform_int_range ~min:start_day ~max:end_day))
            | _ ->
                Error (Error.type_error
                         "prop_for_all: date_range spec requires `start_day` and `end_day` Int fields."))
       | Some (VString "datetime") ->
           (match int_field "start_micros" spec, int_field "end_micros" spec with
            | Some start_m, Some end_m ->
                let tz =
                  match field "tz" spec with
                  | Some (VString s) -> Some s
                  | _ -> None
                in
                Ok
                  (VDatetime
                     ( Rng.uniform_int64_range
                         ~min:(Int64.of_int start_m)
                         ~max:(Int64.of_int end_m),
                       tz ))
            | _ ->
                Error (Error.type_error
                         "prop_for_all: date_range spec requires `start_micros` and `end_micros` Int fields."))
       | _ ->
           Error (Error.type_error
                    "prop_for_all: date_range spec requires a `mode` field."))
   | Some "fn" ->
       (match field "fn" spec with
        | Some fn ->
            Ok (eval_call env fn [(None, Ast.mk_expr (Value (VInt size)))])
        | None ->
            Error (Error.type_error "prop_for_all: fn spec requires a `fn` field."))
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
           draw_value ~eval_call ~env ~size:n (force_size_in_spec src n)
       | None ->
           Error (Error.type_error "prop_for_all: resize spec requires a `source` field."))
  | Some other ->
      Error (Error.type_error
               (Printf.sprintf "prop_for_all: unknown generator kind `%s`." other))

and draw_column ~eval_call ~env ~size ~nrows ~na_prob gen_spec =
  match leaf_drawer gen_spec with
  | Some draw ->
      let na = na_for_spec gen_spec in
      let col = Array.make nrows (VNA na) in
      for i = 0 to nrows - 1 do
        col.(i) <- draw ()
      done;
      if na_prob > 0.0 then
        for i = 0 to nrows - 1 do
          if Rng.uniform_float_range ~min:0.0 ~max:1.0 < na_prob then col.(i) <- VNA na
        done;
      Ok col
  | None ->
      (match draw_many ~eval_call ~env ~size gen_spec nrows [] with
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
           Ok col)

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

(* Shrink an Int toward a domain floor instead of toward zero. Halving
   from [i] toward [min] (inclusive) guarantees the shrink sequence stays
   inside [min, i] and eventually reaches [min]. *)
let shrink_toward_min min i =
  if i <= min then []
  else
    let mid = min + ((i - min) / 2) in
    List.sort_uniq compare [ min; mid ] |> List.filter (fun c -> c <> i)

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
  | VDataFrame df -> shrink_dataframe ~cell_min:(fun _ -> None) df
  | _ -> []

(* Shrink a DataFrame counterexample: first reduce the row count by
   taking halving row prefixes (down to the empty frame), then minimize
   individual cells to canonical values derived from the column's own
   values (Int -> 0, Float -> 0.0, Bool -> false, String -> "", Factor ->
   first level). A `between` column canonicalizes to its `min` instead of
   0, so its shrunk cells stay in-domain. NA cells are left untouched.
   Candidate frames are rebuilt through Arrow_bridge, so column types are
   preserved. *)
and shrink_dataframe ~cell_min df =
  let arrow_table = df.arrow_table in
  let group_keys = df.group_keys in
  let nrows = Arrow_table.num_rows arrow_table in
  let columns = Arrow_bridge.table_to_value_columns arrow_table in
  let rebuild cols n =
    match Arrow_bridge.table_from_value_columns cols n with
    | Ok table -> Some (VDataFrame { df with arrow_table = table })
    | Error _ -> None
  in
  let row_candidates =
    let rec go k acc =
      if k <= 0 then List.rev acc
      else
        let cols = List.map (fun (name, col) -> (name, Array.sub col 0 k)) columns in
        let acc' = match rebuild cols k with Some v -> v :: acc | None -> acc in
        go (k / 2) acc'
    in
    let halves = go (nrows / 2) [] in
    match rebuild (List.map (fun (name, col) -> (name, Array.sub col 0 0)) columns) 0 with
    | Some empty -> empty :: halves
    | None -> halves
  in
  let cell_candidates =
    let minimal_of name = function
      | VInt _ ->
          (match cell_min name with
           | Some m -> Some (VInt m)
           | None -> Some (VInt 0))
      | VFloat _ -> Some (VFloat 0.0)
      | VBool _ -> Some (VBool false)
      | VString _ -> Some (VString "")
      | VFactor (_, levels, ordered) -> Some (VFactor (0, levels, ordered))
      | v -> Some v
    in
    List.concat_map
      (fun (name, col) ->
        Array.to_list
          (Array.mapi
             (fun i cell ->
               match cell with
               | VNA _ -> []
               | _ ->
                   (match minimal_of name cell with
                    | Some minimal when minimal = cell -> []
                    | Some minimal ->
                        let new_col = Array.copy col in
                        new_col.(i) <- minimal;
                        (match
                           rebuild
                             (List.map
                                (fun (n2, c2) -> if n2 = name then (n2, new_col) else (n2, c2))
                                columns)
                             nrows
                         with
                        | Some v -> [ v ]
                        | None -> [])
                    | None -> []))
             col)
          |> List.concat)
      columns
  in
  let current_s = render_dataframe arrow_table group_keys in
  (row_candidates @ cell_candidates)
  |> List.filter (fun c -> render_value c <> current_s)
  |> List.sort_uniq compare

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
  | VExpect (Expect_hold msg) -> `Hold msg
  | VBool false -> `False
  | VExpect (Expect_stop msg) -> `Stop msg
  | VNA _ -> `NA
  | VError err -> `Error err
  | other -> `Other other

let is_failure = function
  | `Pass -> false
  | _ -> true

let shrink_minimal ~eval_call ~env ~shrink_v ~verify property input =
  let fails v =
    outcome_of (eval_call env property [(None, Ast.mk_expr (Value v))])
    |> is_failure
  in
  let rec go v =
    let candidates =
      if verify then shrink_v v else cap_candidates (shrink_v v)
    in
    match List.find_opt fails candidates with
    | Some c -> go c
    | None -> v
  in
  go input

let failure_message ~name ~n ~runs ~k ~counterexamples =
  (* counterexamples are passed in discovery order (first failure first). *)
  let block i (input, shrunk, reason) =
    let input_s = render_value input in
    let shrunk_s = render_value shrunk in
    (* Compare rendered forms rather than structural equality: VDataFrame wraps
       an Arrow_table whose structural `=` is unreliable (floats, mutable native
       handles). Render-string comparison is also what shrink_dataframe uses. *)
    let shrunk_s = if shrunk_s = input_s then input_s else shrunk_s in
    if k = 1 then
      Printf.sprintf "  counterexample: %s\n  (shrunk): %s\n  predicate: %s"
        input_s shrunk_s reason
    else
      Printf.sprintf "  counterexample #%d: %s\n  (shrunk): %s\n  predicate: %s"
        (i + 1) input_s shrunk_s reason
  in
  let blocks = String.concat "\n" (List.mapi block counterexamples) in
  let shown =
    match List.length counterexamples with
    | 1 -> "1 counterexample"
    | m -> Printf.sprintf "%d counterexamples" m
  in
  let verb =
    match name with
    | Some m -> Printf.sprintf "Property %s failed" m
    | None -> "Property failed"
  in
  let header =
    if k = 1 then
      Printf.sprintf "%s after %d of %d runs." verb runs n
    else
      Printf.sprintf "%s after %d of %d runs (showing %s)."
        verb runs n shown
  in
  VExpect (Expect_stop (Printf.sprintf "%s\n%s" header blocks))

(* Derive the value-shrink function from the top-level generator spec so
   domain floors apply during shrinking: a `between` spec shrinks toward
   its `min` at every step, and a `df` spec canonicalizes `between`
   column cells to that column's `min` instead of zero. Nested values
   keep the generic structural shrink. *)
let spec_shrink_v spec =
  match spec_gen spec with
  | Some "between" ->
      let min = match int_field "min" spec with Some m -> m | None -> 0 in
      (fun v ->
        match v with
        | VInt i -> List.map (fun x -> VInt x) (shrink_toward_min min i)
        | _ -> shrink_value v)
  | Some "df" ->
      let cell_min =
        match field "columns" spec with
        | Some (VDict columns) ->
            let mins =
              List.filter_map
                (fun (cname, cspec) ->
                  match spec_gen cspec, int_field "min" cspec with
                  | Some "between", Some m -> Some (cname, m)
                  | _ -> None)
                columns
            in
            (fun cname -> List.assoc_opt cname mins)
        | _ -> fun _ -> None
      in
      (fun v ->
        match v with
        | VDataFrame df -> shrink_dataframe ~cell_min df
        | _ -> shrink_value v)
  | _ -> shrink_value

let run_property ~eval_call ~env ~n ~shrink ~shrink_verify ~max_counterexamples
    ?name spec property =
  let shrink_v = spec_shrink_v spec in
  let rec loop i counterexamples =
    if List.length counterexamples >= max_counterexamples then
      failure_message ~name ~n ~runs:(i - 1) ~k:max_counterexamples
        ~counterexamples:(List.rev counterexamples)
    else if i > n then
      (match counterexamples with
       | [] -> VExpect Expect_pass
       | _ ->
           failure_message ~name ~n ~runs:(i - 1) ~k:max_counterexamples
             ~counterexamples:(List.rev counterexamples))
    else
      match draw_value ~eval_call ~env ~size:default_size spec with
      | Error err -> err
      | Ok input ->
          let result = eval_call env property [(None, Ast.mk_expr (Value input))] in
          let record_failure reason =
            (* Count only render-distinct counterexamples; shrink only the ones
               we actually keep, so duplicates don't pay for shrink work. *)
            let already =
              List.exists
                (fun (inp, _, _) -> render_value inp = render_value input)
                counterexamples
            in
            if already then loop (i + 1) counterexamples
            else
              let shrunk =
                if shrink then
                  shrink_minimal ~eval_call ~env ~shrink_v ~verify:shrink_verify
                    property input
                else input
              in
              loop (i + 1) ((input, shrunk, reason) :: counterexamples)
          in
          (match outcome_of result with
           | `Pass -> loop (i + 1) counterexamples
           | `Hold msg -> record_failure (Printf.sprintf "failed: %s" msg)
           | `False -> record_failure "returned false"
           | `Stop msg -> record_failure (Printf.sprintf "failed: %s" msg)
           | `NA ->
               record_failure
                 "returned NA (property must handle missingness explicitly)"
           | `Error err -> record_failure (Printf.sprintf "raised: %s" err.message)
           | `Other other ->
               record_failure
                 (Printf.sprintf
                    "returned %s (expected Bool or an Expect value)"
                    (Utils.type_name other)))
  in
  loop 1 []

(*
--# Check a property over generated values
--#
--# Draws `n` values from the `gen` generator spec (using the shared
--# seeded RNG — call set_seed first for reproducible runs) and evaluates
--# `property` on each. The property may return a Bool, an Expect value
--# from testcraft (e.g. expect_equal), or an Error. A property passes
--# only when it returns `true` or `Expect_pass`; `false`, `Expect_stop`,
--# `Expect_hold`, NA, and Error are all treated as failures.
--# On the first failure, a deterministic shrunk counterexample is
--# reported via an Expect_stop value, so `assert(prop_for_all(...))`
--# works inside test files run by `t test`.
--#
--# @name prop_for_all
--# @param gen :: Dict A generator spec (see prop_gen_int, prop_gen_df, ...).
--# @param property :: Function A function from a generated value to Bool or Expect.
--# @param n :: Int = 100 Number of values to draw.
--# @param max_counterexamples :: Int = 1 Number of render-distinct failing inputs to report.
--# @param shrink :: Bool = true Whether to report a shrunk counterexample.
--# @param shrink_verify :: Bool = false Re-check every shrink candidate (not just the
--#   first 32) so the reported counterexample is guaranteed minimal.
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

(*
--# Probe a generator's behaviour
--#
--# Draws `n` values from `gen`, ramping the generation size from 1 to
--# `n`, and returns a Dict summarizing what was produced: run counts,
--# the value types observed, the sizes of any Vector/List/DataFrame
--# values, and the wall-clock time spent.
--#
--# @name prop_stats
--# @param gen :: Dict A generator spec (see prop_gen_int, prop_gen_df, ...).
--# @param n :: Int = 100 Number of draws (also the max size ramp).
--# @return :: Dict { n_runs, n_errors, value_types, nested_sizes, elapsed_ms }.
--# @example
--#   prop_stats(prop_gen_df([x: prop_gen_int_range(0, 10)]), n = 20)
--# @family propcraft
--# @seealso prop_for_all
--# @export
*)
let prop_stats ~eval_call =
  make_builtin_named ~name:"prop_stats" ~variadic:true 1 (fun named_args env ->
    let unknown =
      List.filter
        (fun (n, _) ->
          match n with
          | None | Some "n" -> false
          | Some _ -> true)
        named_args
    in
    match unknown with
    | (Some arg_name, _) :: _ ->
        Error.type_error
          (Printf.sprintf "Function `prop_stats` received unknown named argument `%s`."
             arg_name)
    | _ ->
        let n =
          match Math_common.optional_named_arg "n" named_args with
          | Some (VInt i) when i > 0 -> Ok i
          | Some (VInt _) ->
              Error
                (Error.value_error
                   "Function `prop_stats` expects `n` to be a positive Int.")
          | Some other ->
              Error
                (Error.type_error
                   (Printf.sprintf "Function `prop_stats` expects `n` to be an Int, got %s."
                      (Utils.type_name other)))
          | None -> Ok 100
        in
        (match n, Math_common.positional_args_without [ "n" ] named_args with
         | Ok n, [gen_spec] ->
             let start = Sys.time () in
             let n_runs = ref 0 in
             let n_errors = ref 0 in
             let type_counts = Hashtbl.create 8 in
             let sizes_by_kind = Hashtbl.create 4 in
             let bump counts key =
               let c =
                 match Hashtbl.find_opt counts key with
                 | Some c -> c
                 | None -> 0
               in
               Hashtbl.replace counts key (c + 1)
             in
             let record_size kind size =
               let sizes =
                 match Hashtbl.find_opt sizes_by_kind kind with
                 | Some sizes -> sizes
                 | None -> []
               in
               Hashtbl.replace sizes_by_kind kind (sizes @ [ size ])
             in
             for i = 1 to n do
               match draw_value ~eval_call ~env ~size:i gen_spec with
               | Error err ->
                   incr n_errors;
                   bump type_counts (Utils.type_name err)
               | Ok v ->
                   incr n_runs;
                   bump type_counts (Utils.type_name v);
                   (match v with
                    | VVector a -> record_size "vector" (Array.length a)
                    | VList l -> record_size "list" (List.length l)
                    | VDataFrame df -> record_size "df" (Arrow_table.num_rows df.arrow_table)
                    | _ -> ())
             done;
             let elapsed_ms = (Sys.time () -. start) *. 1000.0 in
             let value_types =
               VDict
                 (Hashtbl.fold (fun k c acc -> (k, VInt c) :: acc) type_counts [])
             in
             let nested_sizes =
               VDict
                 (Hashtbl.fold
                    (fun kind sizes acc ->
                      (kind, VList (List.map (fun s -> (None, VInt s)) sizes)) :: acc)
                    sizes_by_kind [])
             in
             VDict
               [ ("n_runs", VInt !n_runs);
                 ("n_errors", VInt !n_errors);
                 ("value_types", value_types);
                 ("nested_sizes", nested_sizes);
                 ("elapsed_ms", VFloat elapsed_ms) ]
         | Error err, _ -> err
         | _, args -> Error.arity_error_named "prop_stats" 1 (List.length args)))

(*
--# Name a reusable property
--#
--# Bundles a property function under a `name` into an immutable named property
--# Dict. Named properties are plain values (no global registry): pass the result
--# to prop_test to run it against a generator. Failure reports are
--# prefixed with the property's name.
--#
--# @name prop_named
--# @param name :: String The property's display name.
--# @param property :: Function A function from a generated value to Bool or Expect.
--# @return :: Dict { name, property }.
--# @example
--#   monotone = prop_named("monotone", \(x) x <= 100)
--#   assert(prop_test(monotone, prop_gen_between(0, 200)))
--# @family propcraft
--# @seealso prop_test, prop_for_all
--# @export
*)
let prop_named =
  make_builtin ~name:"prop_named" 2 (fun args _env ->
    match args with
    | [VString name; property] ->
        VDict [ ("name", VString name); ("property", property) ]
    | [other; _] ->
        Error.type_error
          (Printf.sprintf "Function `prop_named` expects `name` to be a String, got %s."
             (Utils.type_name other))
    | _ -> Error.arity_error_named "prop_named" 2 (List.length args))

(*
--# Run a named property
--#
--# Runs the property captured by a `prop_named` Dict against values
--# drawn from `gen`, mirroring prop_for_all's parameters. A failing
--# report is prefixed with the property's name.
--#
--# @name prop_test
--# @param named :: Dict A named property built by prop_named.
--# @param gen :: Dict A generator spec (see prop_gen_int, prop_gen_df, ...).
--# @param n :: Int = 100 Number of values to draw.
--# @param max_counterexamples :: Int = 1 Number of render-distinct failing inputs to report.
--# @param shrink :: Bool = true Whether to report a shrunk counterexample.
--# @param shrink_verify :: Bool = false Re-check every shrink candidate so the reported
--#   counterexample is guaranteed minimal.
--# @return :: Expect Expect_pass on success, Expect_stop on failure.
--# @example
--#   set_seed(42)
--#   monotone = prop_named("monotone", \(x) x <= 100)
--#   assert(prop_test(monotone, prop_gen_between(0, 200)))
--# @family propcraft
--# @seealso prop_named, prop_for_all
--# @export
*)
let prop_test ~eval_call =
  make_builtin_named ~name:"prop_test" ~variadic:true 2 (fun named_args env ->
    let unknown =
      List.filter
        (fun (n, _) ->
          match n with
          | None | Some ("n" | "shrink" | "shrink_verify" | "max_counterexamples") -> false
          | Some _ -> true)
        named_args
    in
    match unknown with
    | (Some arg_name, _) :: _ ->
        Error.type_error
          (Printf.sprintf "Function `prop_test` received unknown named argument `%s`."
             arg_name)
    | _ ->
        let n =
          match Math_common.optional_named_arg "n" named_args with
          | Some (VInt i) when i > 0 -> Ok i
          | Some (VInt _) ->
              Error
                (Error.value_error
                   "Function `prop_test` expects `n` to be a positive Int.")
          | Some other ->
              Error
                (Error.type_error
                   (Printf.sprintf "Function `prop_test` expects `n` to be an Int, got %s."
                      (Utils.type_name other)))
          | None -> Ok 100
        in
        let max_counterexamples =
          match Math_common.optional_named_arg "max_counterexamples" named_args with
          | Some (VInt i) when i > 0 -> Ok i
          | Some (VInt _) ->
              Error
                (Error.value_error
                   "Function `prop_test` expects `max_counterexamples` to be a positive Int.")
          | Some other ->
              Error
                (Error.type_error
                   (Printf.sprintf
                      "Function `prop_test` expects `max_counterexamples` to be an Int, got %s."
                      (Utils.type_name other)))
          | None -> Ok 1
        in
        let shrink =
          match Math_common.get_bool_flag "shrink" true named_args with
          | Ok b -> Ok b
          | Error err -> Error err
        in
        let shrink_verify =
          match Math_common.get_bool_flag "shrink_verify" false named_args with
          | Ok b -> Ok b
          | Error err -> Error err
        in
        (match n, max_counterexamples, shrink, shrink_verify,
               Math_common.positional_args_without
                 [ "n"; "shrink"; "shrink_verify"; "max_counterexamples" ] named_args with
         | Ok n, Ok max_counterexamples, Ok shrink, Ok shrink_verify, [macro; gen] ->
              (match macro with
               | VDict pairs ->
                   (match List.assoc_opt "name" pairs, List.assoc_opt "property" pairs with
                    | Some (VString name), Some property ->
                        run_property ~eval_call ~env ~n ~shrink ~shrink_verify
                          ~max_counterexamples ~name gen property
                    | _, None ->
                        Error.type_error
                           "Function `prop_test` expects a named property to have a `property` field."
                     | Some other, _ ->
                         Error.type_error
                           (Printf.sprintf
                              "Function `prop_test` expects a named property to have a String `name`, got %s."
                              (Utils.type_name other))
                     | None, _ ->
                         Error.type_error
                           "Function `prop_test` expects a named property to have a `name` field.")
                | other ->
                    Error.type_error
                      (Printf.sprintf "Function `prop_test` expects a named property Dict, got %s."
                        (Utils.type_name other)))
         | Error err, _, _, _, _ | _, Error err, _, _, _
         | _, _, Error err, _, _ | _, _, _, Error err, _ -> err
         | _, _, _, _, args ->
             Error.arity_error_named "prop_test" 2 (List.length args)))

let register ~eval_call env =
  let env = Env.add "prop_stats" (prop_stats ~eval_call) env in
  let env = Env.add "prop_test" (prop_test ~eval_call) env in
  Env.add "prop_named" prop_named env
  |> fun env ->
  Env.add "prop_for_all"
    (make_builtin_named ~name:"prop_for_all" ~variadic:true 2 (fun named_args env ->
       let unknown =
         List.filter
           (fun (n, _) ->
             match n with
             | None | Some ("n" | "shrink" | "shrink_verify" | "max_counterexamples") -> false
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
           let max_counterexamples =
             match Math_common.optional_named_arg "max_counterexamples" named_args with
             | Some (VInt i) when i > 0 -> Ok i
             | Some (VInt _) ->
                 Error
                   (Error.value_error
                      "Function `prop_for_all` expects `max_counterexamples` to be a positive Int.")
             | Some other ->
                 Error
                   (Error.type_error
                      (Printf.sprintf
                         "Function `prop_for_all` expects `max_counterexamples` to be an Int, got %s."
                         (Utils.type_name other)))
             | None -> Ok 1
           in
           let shrink =
             match Math_common.get_bool_flag "shrink" true named_args with
             | Ok b -> Ok b
             | Error err -> Error err
           in
           let shrink_verify =
             match Math_common.get_bool_flag "shrink_verify" false named_args with
             | Ok b -> Ok b
             | Error err -> Error err
           in
           (match n, max_counterexamples, shrink, shrink_verify,
                  Math_common.positional_args_without
                    [ "n"; "shrink"; "shrink_verify"; "max_counterexamples" ] named_args with
            | Ok n, Ok max_counterexamples, Ok shrink, Ok shrink_verify, [gen; property] ->
                run_property ~eval_call ~env ~n ~shrink ~shrink_verify ~max_counterexamples
                  gen property
            | Error err, _, _, _, _ | _, Error err, _, _, _
            | _, _, Error err, _, _ | _, _, _, Error err, _ -> err
            | _, _, _, _, args ->
                Error.arity_error_named "prop_for_all" 2 (List.length args))))
    env
