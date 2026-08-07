open Ast

(** Extract the generator kind tag from a generator spec value. *)
let spec_gen = function
  | VDict pairs ->
      (match List.assoc_opt "gen" pairs with
       | Some (VString g) -> Some g
       | _ -> None)
  | _ -> None

(** Extract a named field from a generator spec value. *)
let field name = function
  | VDict pairs -> List.assoc_opt name pairs
  | _ -> None

let int_field name spec =
  match field name spec with
  | Some (VInt i) -> Some i
  | _ -> None

let to_float = function
  | VFloat f -> Some f
  | VInt i -> Some (float_of_int i)
  | _ -> None

let float_field name spec =
  match field name spec with
  | Some v -> to_float v
  | None -> None

(** Pick the typed NA that matches a generator's value type. Used for
    NA injection inside [prop_gen_df]. *)
let na_of_value = function
  | VInt _ -> NAInt
  | VFloat _ -> NAFloat
  | VBool _ -> NABool
  | VString _ -> NAString
  | VDate _ -> NADate
  | VDatetime _ -> NADatetime
  | VFactor _ -> NAString
  | _ -> NAGeneric

let rec na_for_spec spec =
  match spec_gen spec with
  | Some ("int" | "int_range" | "between") -> NAInt
  | Some "float_range" -> NAFloat
  | Some "bool" -> NABool
  | Some "string" -> NAString
  | Some "factor" -> NAString
  | Some "one_of" ->
      (match field "values" spec with
       | Some (VList items) ->
           (match
              List.find_opt
                (fun (_, v) -> match v with VNA _ -> false | _ -> true)
                items
            with
            | Some (_, v) -> na_of_value v
            | None -> NAGeneric)
       | Some (VVector arr) ->
           (match
              Array.to_list arr
              |> List.find_opt (fun v -> match v with VNA _ -> false | _ -> true)
            with
            | Some v -> na_of_value v
            | None -> NAGeneric)
       | _ -> NAGeneric)
  | Some "date_range" ->
      (match field "mode" spec with
       | Some (VString "datetime") -> NADatetime
       | _ -> NADate)
  | Some "ymd_range" -> NADate
  | Some ("map" | "such_that" | "resize") ->
      (match field "source" spec with
       | Some src -> na_for_spec src
       | None -> NAGeneric)
  | Some ("choice" | "frequency") ->
      (match field "gens" spec with
       | Some (VList items) ->
           (match List.map (fun (_, g) -> na_for_spec g) items with
            | [] -> NAGeneric
            | first :: rest when List.for_all (fun x -> x = first) rest -> first
            | _ -> NAGeneric)
       | _ -> NAGeneric)
  | _ -> NAGeneric

(** Split a string into UTF-8 characters. Continuation bytes (0x80-0xBF)
    are merged into the preceding lead byte, so multi-byte characters are
    preserved intact. *)
let utf8_chars s =
  let n = String.length s in
  let char_length c =
    let c = Char.code c in
    if c land 0x80 = 0x00 then 1
    else if c land 0xE0 = 0xC0 then 2
    else if c land 0xF0 = 0xE0 then 3
    else if c land 0xF8 = 0xF0 then 4
    else 1
  in
  let rec go i acc =
    if i >= n then List.rev acc
    else
      let len = min n (i + char_length s.[i]) in
      go len (String.sub s i (len - i) :: acc)
  in
  go 0 []

(** Extract a list of strings from a "chars"-style field. Accepts a
    VString (each character is a candidate) or a List/Vector of
    VStrings. Returns None if any element is not a VString. *)
let string_list_field name spec =
  match field name spec with
  | Some (VString s) -> Some (utf8_chars s)
  | Some (VList items) ->
      let rec go acc = function
        | [] -> Some (List.rev acc)
        | (_, VString c) :: rest -> go (c :: acc) rest
        | _ :: _ -> None
      in
      go [] items
  | Some (VVector arr) ->
      let rec go i acc =
        if i >= Array.length arr then Some (List.rev acc)
        else
          match arr.(i) with
          | VString c -> go (i + 1) (c :: acc)
          | _ -> None
      in
      go 0 []
  | _ -> None

let render_dataframe arrow_table group_keys =
  let nrows = Arrow_table.num_rows arrow_table in
  let ncols = Arrow_table.num_columns arrow_table in
  let value_columns = Arrow_bridge.table_to_value_columns arrow_table in
  let buf = Buffer.create 256 in
  Printf.bprintf buf "DataFrame(%d rows x %d cols)" nrows ncols;
  List.iter
    (fun (name, col) ->
      let col_type =
        let found = ref None in
        let i = ref 0 in
        while !found = None && !i < Array.length col do
          (match col.(!i) with
           | VNA _ -> ()
           | v -> found := Some (Utils.type_name v));
          incr i
        done;
        match !found with Some t -> t | None -> "NA"
      in
      let truncate s =
        if String.length s > 22 then String.sub s 0 19 ^ "..." else s
      in
      let shown = min 8 (Array.length col) in
      let examples = List.init shown (fun i -> truncate (Utils.value_to_string col.(i))) in
      let suffix = if Array.length col > shown then ", ..." else "" in
      Printf.bprintf buf "\n  $%-10s <%s> %s%s" name col_type
        (String.concat ", " examples) suffix)
    value_columns;
  if group_keys <> [] then
    Printf.bprintf buf "\n  grouped by [%s]" (String.concat ", " group_keys);
  Buffer.contents buf

(** Render a value for a counterexample message. DataFrames get a
    glimpse-style summary; other values use the default printer. *)
let render_value v =
  match v with
  | VDataFrame { arrow_table; group_keys } ->
      render_dataframe arrow_table group_keys
  | VVector arr ->
      let items = Array.to_list arr |> List.map Utils.value_to_string in
      "Vector[" ^ String.concat ", " items ^ "]"
  | VList items ->
      let item_to_string = function
        | (Some name, x) -> name ^ ": " ^ Utils.value_to_string x
        | (None, x) -> Utils.value_to_string x
      in
      "[" ^ (items |> List.map item_to_string |> String.concat ", ") ^ "]"
  | VDict pairs ->
      let pair_to_string (k, x) = "`" ^ k ^ "`: " ^ Utils.value_to_string x in
      "{" ^ (pairs |> List.map pair_to_string |> String.concat ", ") ^ "}"
  | other -> Utils.value_to_string other

(** Whether polymorphic `=`/`compare` is safe on a value. Structural
    comparison raises `Invalid_argument` on functional values (lambdas,
    builtins, quosures) and is unreliable on opaque/native-handle
    containers (DataFrames, computed nodes, environments). Such values
    must be excluded before any `compare`/`sort_uniq` over generated
    data. *)
let rec is_compare_safe v =
  match v with
  | VLambda _ | VBuiltin _ | VQuo _ -> false
  | VDataFrame _ | VComputedNode _ | VNodeResult _ -> false
  | VPipeline _ | VMetaPipeline _ | VNode _ | VEnv _ -> false
  | VExpr _ -> false
  | VList items -> List.for_all (fun (_, x) -> is_compare_safe x) items
  | VVector arr -> Array.for_all is_compare_safe arr
  | VDict pairs -> List.for_all (fun (_, x) -> is_compare_safe x) pairs
  | VBuildLog bl -> List.for_all is_compare_safe bl.bl_nodes
  | VError e -> List.for_all (fun (_, x) -> is_compare_safe x) e.context
  | VUnquote v -> is_compare_safe v
  | VUnquoteSplice v -> is_compare_safe v
  | VDynamicArg (_, v) -> is_compare_safe v
  | _ -> true

(** Index of [needle] in [items], found with structural equality. Returns
    [None] if any element is not structurally comparable (see
    [is_compare_safe]), since the comparison could raise. *)
let find_index_plain items needle =
  if List.for_all (fun x -> is_compare_safe x) items && is_compare_safe needle then
    let rec go i = function
      | [] -> None
      | x :: rest -> if x = needle then Some i else go (i + 1) rest
    in
    go 0 items
  else
    None

(** Sort and deduplicate shrink candidates by a total render function.
    Polymorphic `compare` cannot be used on arbitrary generated values
    (it raises on functions and is unreliable on DataFrames), and the
    rendered form is exactly what the user sees in a counterexample, so
    two candidates rendering identically are indistinguishable anyway. *)
let sort_uniq_by_render render candidates =
  let keyed = List.map (fun c -> (render c, c)) candidates in
  let sorted = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) keyed in
  let rec dedup acc = function
    | [] -> List.rev acc
    | (k, c) :: rest ->
        (match acc with
         | (k', _) :: _ when k' = k -> dedup acc rest
         | _ -> dedup ((k, c) :: acc) rest)
  in
  List.map snd (dedup [] sorted)

(** Sort and deduplicate shrink candidates using polymorphic `compare`
    when every candidate is structurally comparable (no closures or other
    values that make `compare` raise), falling back to render-based
    ordering otherwise. The structural path preserves the historical
    candidate ordering exactly; the render fallback keeps shrinking safe
    for generator images containing functions. [is_safe] decides
    comparability for the candidate type (candidates may be pairs lists
    rather than [value]s). *)
let sort_uniq_safe is_safe render candidates =
  if List.for_all is_safe candidates then
    List.sort_uniq compare candidates
  else sort_uniq_by_render render candidates
