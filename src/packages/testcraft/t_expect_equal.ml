open Ast

(* Default absolute tolerance used for Float comparisons when the caller
   does not supply one explicitly. *)
let default_tolerance = 1e-9

(* Render a scalar value for diagnostic messages, backtick-quoted in the
   style of R's testthat. *)
let fmt v = "`" ^ Utils.value_to_string v ^ "`"

let scalar_mismatch actual expected =
  Expect_stop (Printf.sprintf "%s != %s" (fmt actual) (fmt expected))

let type_mismatch actual expected =
  Expect_stop
    (Printf.sprintf "%s (%s) != %s (%s)"
       (fmt actual) (Utils.type_name actual)
       (fmt expected) (Utils.type_name expected))

(* Recursively compare two T-Lang values, returning an [expect_kind]
   describing the first point of difference (if any). Collections
   (DataFrame, Vector, List) report the location of their first differing
   element so failures are actionable without dumping the whole value. *)
let rec compare_values ~tolerance (actual : value) (expected : value) : expect_kind =
  match actual, expected with
  | VError err, _ ->
      Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message)
  | _, VError err ->
      Expect_stop (Printf.sprintf "`expected` is an error: %s" err.message)
  | VNA _, _ ->
      Expect_hold "`actual` is NA, cannot compare `actual` != `expected`"
  | _, VNA _ ->
      Expect_hold "`expected` is NA, cannot compare `actual` != `expected`"
  | VInt a, VInt b ->
      if a = b then Expect_pass else scalar_mismatch actual expected
  | VFloat a, VFloat b ->
      if Float.abs (a -. b) < tolerance then Expect_pass
      else scalar_mismatch actual expected
  | VInt a, VFloat b ->
      if Float.abs (float_of_int a -. b) < tolerance then Expect_pass
      else scalar_mismatch actual expected
  | VFloat a, VInt b ->
      if Float.abs (a -. float_of_int b) < tolerance then Expect_pass
      else scalar_mismatch actual expected
  | VBool a, VBool b ->
      if a = b then Expect_pass else scalar_mismatch actual expected
  | VString a, VString b ->
      if a = b then Expect_pass else scalar_mismatch actual expected
  | VDate a, VDate b ->
      if a = b then Expect_pass else scalar_mismatch actual expected
  | VDatetime (a, tz_a), VDatetime (b, tz_b) ->
      if a = b && tz_a = tz_b then Expect_pass else scalar_mismatch actual expected
  | VFactor (idx, levels, _), VString s ->
      let level = match List.nth_opt levels idx with Some l -> l | None -> "NA" in
      if level = s then Expect_pass else scalar_mismatch actual expected
  | VFactor (idx_a, levels_a, _), VFactor (idx_b, levels_b, _) ->
      let level_a = match List.nth_opt levels_a idx_a with Some l -> l | None -> "NA" in
      let level_b = match List.nth_opt levels_b idx_b with Some l -> l | None -> "NA" in
      if level_a = level_b then Expect_pass else scalar_mismatch actual expected
  | VDataFrame df_a, VDataFrame df_b ->
      compare_dataframes ~tolerance df_a df_b
  | VVector arr_a, VVector arr_b ->
      compare_vectors ~tolerance arr_a arr_b
  | VList list_a, VList list_b ->
      compare_lists ~tolerance list_a list_b
  | VDict dict_a, VDict dict_b ->
      compare_dicts ~tolerance dict_a dict_b
  | VLambda _, _ | _, VLambda _
  | VBuiltin _, _ | _, VBuiltin _
  | VLens _, _ | _, VLens _ ->
      Expect_stop "Cannot compare functional values (Lambdas, Builtins, or Lenses)"
  | _ when Utils.type_name actual <> Utils.type_name expected ->
      type_mismatch actual expected
  | _ ->
      (* Other same-type constructors (VPeriod, VDuration, VInterval,
         VSymbol, VRawCode, ...) contain only plain OCaml data, so
         structural equality is safe here. *)
      if actual = expected then Expect_pass else scalar_mismatch actual expected


and compare_vectors ~tolerance (arr_a : value array) (arr_b : value array) : expect_kind =
  let len_a = Array.length arr_a and len_b = Array.length arr_b in
  if len_a <> len_b then
    Expect_stop
      (Printf.sprintf "Vector: length mismatch (%d != %d)" len_a len_b)
  else
    let rec scan i =
      if i >= len_a then Expect_pass
      else
        match compare_values ~tolerance arr_a.(i) arr_b.(i) with
        | Expect_pass -> scan (i + 1)
        | Expect_stop msg ->
            Expect_stop (Printf.sprintf "Vector: element at index %d differs: %s" i msg)
        | Expect_hold msg ->
            Expect_hold (Printf.sprintf "Vector: element at index %d could not be compared: %s" i msg)
    in
    scan 0

and compare_lists ~tolerance
    (list_a : (string option * value) list) (list_b : (string option * value) list) : expect_kind =
  let len_a = List.length list_a and len_b = List.length list_b in
  if len_a <> len_b then
    Expect_stop
      (Printf.sprintf "List: length mismatch (%d != %d)" len_a len_b)
  else
    let rec scan i la lb =
      match la, lb with
      | [], [] -> Expect_pass
      | (label, va) :: rest_a, (_, vb) :: rest_b ->
          let location =
            match label with
            | Some name -> Printf.sprintf "`%s`" name
            | None -> Printf.sprintf "at index %d" i
          in
          (match compare_values ~tolerance va vb with
           | Expect_pass -> scan (i + 1) rest_a rest_b
           | Expect_stop msg ->
               Expect_stop (Printf.sprintf "List: element %s differs: %s" location msg)
           | Expect_hold msg ->
               Expect_hold (Printf.sprintf "List: element %s could not be compared: %s" location msg))
      | _ -> Expect_pass (* unreachable: lengths already checked equal *)
    in
    scan 0 list_a list_b

and compare_dicts ~tolerance
    (dict_a : (string * value) list) (dict_b : (string * value) list) : expect_kind =
  let len_a = List.length dict_a and len_b = List.length dict_b in
  if len_a <> len_b then
    Expect_stop
      (Printf.sprintf "Dict: size mismatch (%d != %d)" len_a len_b)
  else
    let cmp_key (k1, _) (k2, _) = String.compare k1 k2 in
    let da = List.sort cmp_key dict_a in
    let db = List.sort cmp_key dict_b in
    let rec scan i la lb =
      match la, lb with
      | [], [] -> Expect_pass
      | (k1, v1) :: rest_a, (k2, v2) :: rest_b ->
          if k1 <> k2 then
            Expect_stop (Printf.sprintf "Dict: key names differ: `%s` != `%s`" k1 k2)
          else
            (match compare_values ~tolerance v1 v2 with
             | Expect_pass -> scan (i + 1) rest_a rest_b
             | Expect_stop msg ->
                 Expect_stop (Printf.sprintf "Dict: key `%s` value differs: %s" k1 msg)
             | Expect_hold msg ->
                 Expect_hold (Printf.sprintf "Dict: key `%s` value could not be compared: %s" k1 msg))
      | _ -> Expect_pass (* unreachable: lengths already checked equal *)
    in
    scan 0 da db

and compare_dataframes ~tolerance (df_a : dataframe) (df_b : dataframe) : expect_kind =
  if Utils.dataframe_equal df_a df_b then Expect_pass
  else
    let table_a = df_a.arrow_table and table_b = df_b.arrow_table in
    let cols_a = Arrow_table.column_names table_a in
    let cols_b = Arrow_table.column_names table_b in
    if cols_a <> cols_b then
      Expect_stop
        (Printf.sprintf "DataFrame: column names differ: [%s] != [%s]"
           (String.concat ", " cols_a) (String.concat ", " cols_b))
    else
      let nrows_a = Arrow_table.num_rows table_a in
      let nrows_b = Arrow_table.num_rows table_b in
      if nrows_a <> nrows_b then
        Expect_stop
          (Printf.sprintf "DataFrame: row count differs: %d != %d" nrows_a nrows_b)
      else
        let rec scan_columns = function
          | [] -> Expect_pass (* unreachable: dataframe_equal already returned false *)
          | col_name :: rest ->
              (match Arrow_table.get_column table_a col_name, Arrow_table.get_column table_b col_name with
               | Some col_a, Some col_b ->
                   let rec scan_rows row =
                     if row >= nrows_a then scan_columns rest
                     else
                       let va = Arrow_bridge.value_at col_a row in
                       let vb = Arrow_bridge.value_at col_b row in
                       match compare_values ~tolerance va vb with
                       | Expect_pass -> scan_rows (row + 1)
                       | Expect_stop msg ->
                           Expect_stop
                             (Printf.sprintf "DataFrame: column `%s` differs at row %d: %s" col_name row msg)
                       | Expect_hold msg ->
                           Expect_hold
                             (Printf.sprintf "DataFrame: column `%s` at row %d could not be compared: %s" col_name row msg)
                   in
                   scan_rows 0
               | _ -> scan_columns rest)
        in
        scan_columns cols_a

(*
--# Compare two values for testing
--#
--# Compares `actual` against `expected` and returns a testcraft Expect
--# value (`Expect_pass`, `Expect_stop`, or `Expect_hold`) describing the
--# outcome. Designed to be used with `assert()`: `assert(expect_equal(a, b))`.
--#
--# @name expect_equal
--# @param actual :: Any The computed value to check.
--# @param expected :: Any The value `actual` is expected to equal.
--# @param tolerance :: Float = 1e-9 Absolute tolerance used for Float comparisons.
--# @return :: Expect A `VExpect` value: passing, stopping, or holding (on NA).
--# @example
--#   expect_equal(1, 1)
--#   assert(expect_equal(0.1 + 0.2, 0.3, tolerance = 1e-9))
--# @family testcraft
--# @seealso expect_pass, expect_fail, expect_msg, assert
--# @export
*)
let register env =
  Env.add "expect_equal"
    (make_builtin_named ~name:"expect_equal" ~variadic:true 2 (fun named_args _env ->
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
             (Printf.sprintf "Function `expect_equal` received unknown named argument `%s`." arg_name)
       | _ ->
           let tolerance_opt = List.find_opt (fun (n, _) -> n = Some "tolerance") named_args in
           (match tolerance_opt with
            | Some (_, other) when (match other with VFloat _ | VInt _ -> false | _ -> true) ->
                Error.type_error
                  (Printf.sprintf
                     "Function `expect_equal` expects the `tolerance` argument to be numeric, got %s."
                     (Utils.type_name other))
            | _ ->
                let tolerance =
                  match tolerance_opt with
                  | Some (_, VFloat f) -> f
                  | Some (_, VInt i) -> float_of_int i
                  | _ -> default_tolerance
                in
                (match Math_common.positional_args_without [ "tolerance" ] named_args with
                 | [ actual; expected ] -> VExpect (compare_values ~tolerance actual expected)
                 | args -> Error.arity_error_named "expect_equal" 2 (List.length args)))))
    env

