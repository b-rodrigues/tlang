(* src/diff.ml — Node diffing logic (spec: diffing-v2.md)

   Provides type-dispatched diffing for node artifacts:
     - DataFrame: row-/column-level comparison with key-based alignment
     - Model (PMML): coefficient deltas and fit-stat comparison
     - Scalar: before/after with numeric delta
     - Generic: structural comparison over string representations

   All four paths produce a VDiff envelope (a VDict with a fixed set of
   top-level keys) and patience-diff hunks.
*)

open Ast

(* ------------------------------------------------------------------ *)
(* Row representation for patience diff                                *)
(* ------------------------------------------------------------------ *)

(** Serialize one row (assoc list of column→value) to a stable string
    suitable for the patience algorithm. *)
let row_to_string (row : (string * value) list) : string =
  let kvs = List.map (fun (k, v) ->
    Printf.sprintf "%s:%s" k (Utils.value_to_string v)
  ) row in
  "{" ^ String.concat "," kvs ^ "}"

(* ------------------------------------------------------------------ *)
(* Patience diff over string arrays                                    *)
(* ------------------------------------------------------------------ *)

(** Run patience diff on two string arrays and return a list of VDict
    hunks.  Each hunk carries kind, a_start/a_end, b_start/b_end, and
    lines_a/lines_b fields as specified in the VDiff envelope.

    Uses Patience_diff from Jane Street. *)
let string_hunks ~(mine : string array) ~(other : string array) ~(context : int) : value list =
  let module P = Patience_diff in
  let hunks =
    P.get_hunks
      ~transform:(fun s -> s)
      ~context
      ~prev:mine
      ~next:other
  in
  List.map (fun (h : _ P.Hunk.t) ->
    let a_start = h.prev_start - 1 in  (* 0-based *)
    let b_start = h.next_start - 1 in
    let lines_a = ref [] and lines_b = ref [] and kind = ref "equal" in
    List.iter (fun r ->
      match r with
      | P.Range.Same xs ->
          Array.iter (fun (s, _) -> lines_a := s :: !lines_a; lines_b := s :: !lines_b) xs
      | P.Range.Replace (xs, ys) ->
          kind := "replace";
          Array.iter (fun s -> lines_a := s :: !lines_a) xs;
          Array.iter (fun s -> lines_b := s :: !lines_b) ys
      | P.Range.Next ys ->
          kind := "insert";
          Array.iter (fun s -> lines_b := s :: !lines_b) ys
      | P.Range.Prev xs ->
          kind := "delete";
          Array.iter (fun s -> lines_a := s :: !lines_a) xs
      | P.Range.Unified _ -> ()
    ) h.ranges;
    VDict [
      "kind",    VString !kind;
      "a_start", VInt a_start;
      "a_end",   VInt (a_start + List.length !lines_a);
      "b_start", VInt b_start;
      "b_end",   VInt (b_start + List.length !lines_b);
      "lines_a", VList (List.rev_map (fun s -> (None, VString s)) !lines_a);
      "lines_b", VList (List.rev_map (fun s -> (None, VString s)) !lines_b);
    ]
  ) hunks

(* ------------------------------------------------------------------ *)
(* Helper: make_vdiff                                                  *)
(* ------------------------------------------------------------------ *)

(** Assemble the common VDiff envelope. *)
let make_vdiff ~kind ~node_a ~node_b ~log_a ~log_b
               ~value_type ~identical ~summary ~detail ~hunks =
  VDict [
    "kind",       VString kind;
    "node_a",     VString node_a;
    "node_b",     VString node_b;
    "log_a",      VString log_a;
    "log_b",      VString log_b;
    "value_type", VString value_type;
    "identical",  VBool   identical;
    "summary",    summary;
    "detail",     detail;
    "hunks",      VList (List.map (fun v -> (None, v)) hunks);
  ]

(* ------------------------------------------------------------------ *)
(* Arrow helpers                                                       *)
(* ------------------------------------------------------------------ *)

(** Get the T type name of a column *)
let col_type_name = function
  | Arrow_table.IntColumn _      -> "Int"
  | Arrow_table.FloatColumn _    -> "Float"
  | Arrow_table.BoolColumn _     -> "Bool"
  | Arrow_table.StringColumn _   -> "String"
  | Arrow_table.DateColumn _     -> "Date"
  | Arrow_table.DatetimeColumn _ -> "Datetime"
  | Arrow_table.DictionaryColumn _ -> "Factor"
  | Arrow_table.NAColumn _       -> "NA"
  | Arrow_table.ListColumn _     -> "List"

(** Extract a single cell value from an Arrow table. *)
let get_cell (t : Arrow_table.t) (name : string) (row : int) : value =
  match Arrow_table.get_column t name with
  | None -> VNA NAGeneric
  | Some col ->
      (match col with
       | Arrow_table.IntColumn a ->
           if row < Array.length a then
             (match a.(row) with Some i -> VInt i | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.FloatColumn a ->
           if row < Array.length a then
             (match a.(row) with Some f -> VFloat f | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.BoolColumn a ->
           if row < Array.length a then
             (match a.(row) with Some b -> VBool b | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.StringColumn a ->
           if row < Array.length a then
             (match a.(row) with Some s -> VString s | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.DateColumn a ->
           if row < Array.length a then
             (match a.(row) with Some d -> VDate d | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.DatetimeColumn (a, tz) ->
           if row < Array.length a then
             (match a.(row) with Some dt -> VDatetime (dt, tz) | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.DictionaryColumn (indices, levels, _) ->
           if row < Array.length indices then
             (match indices.(row) with
              | Some idx ->
                  (match List.nth_opt levels idx with
                   | Some s -> VString s
                   | None -> VNA NAGeneric)
              | None -> VNA NAGeneric)
           else VNA NAGeneric
       | Arrow_table.NAColumn _ -> VNA NAGeneric
       | Arrow_table.ListColumn _ -> VNA NAGeneric)

(** Convert a DataFrame row at index [row] to an assoc list of (col_name, value). *)
let row_of_table (t : Arrow_table.t) (cols : string list) (row : int) : (string * value) list =
  List.map (fun col -> (col, get_cell t col row)) cols

(** Convert an assoc-list row list into a DataFrame value.
    All rows must share the same column set.  If [rows] is empty, returns
    an empty DataFrame. *)
let rows_to_dataframe (cols : string list) (rows : (string * value) list list) : value =
  let nrows = List.length rows in
  if nrows = 0 || cols = [] then
    VDataFrame { arrow_table = Arrow_table.create [] 0; group_keys = [] }
  else
    (* Build columns *)
    let columns = List.map (fun col ->
      (* Collect all values for this column *)
      let vals = List.map (fun row ->
        match List.assoc_opt col row with Some v -> v | None -> VNA NAGeneric
      ) rows in
      (* Determine column type from first non-NA value *)
      let first_non_na = List.find_opt (fun v -> match v with VNA _ -> false | _ -> true) vals in
      match first_non_na with
      | Some (VInt _) | None ->
          let arr = Array.of_list (List.map (fun v -> match v with VInt i -> Some i | _ -> None) vals) in
          (col, Arrow_table.IntColumn arr)
      | Some (VFloat _) ->
          let arr = Array.of_list (List.map (fun v -> match v with VFloat f -> Some f | VInt i -> Some (float_of_int i) | _ -> None) vals) in
          (col, Arrow_table.FloatColumn arr)
      | Some (VBool _) ->
          let arr = Array.of_list (List.map (fun v -> match v with VBool b -> Some b | _ -> None) vals) in
          (col, Arrow_table.BoolColumn arr)
      | Some _ ->
          let arr = Array.of_list (List.map (fun v -> match v with VNA _ -> None | _ -> Some (Utils.value_to_string v)) vals) in
          (col, Arrow_table.StringColumn arr)
    ) cols in
    let tbl = Arrow_table.create columns nrows in
    VDataFrame { arrow_table = tbl; group_keys = [] }

(* ------------------------------------------------------------------ *)
(* DataFrame diff                                                      *)
(* ------------------------------------------------------------------ *)

let diff_dataframes
    ~(df_a : dataframe)
    ~(df_b : dataframe)
    ~(key  : string list)
    ~(context : int)
    ~(node_a_name : string)
    ~(node_b_name : string)
    ~(log_a : string)
    ~(log_b : string)
  : value =

  (* 1. Schema diff *)
  let cols_a = Arrow_table.column_names df_a.arrow_table in
  let cols_b = Arrow_table.column_names df_b.arrow_table in
  let set_a = String_set.of_list cols_a in
  let set_b = String_set.of_list cols_b in
  let cols_added   = String_set.diff set_b set_a |> String_set.elements in
  let cols_removed = String_set.diff set_a set_b |> String_set.elements in
  let cols_shared  = String_set.inter set_a set_b |> String_set.elements in

  let type_changed =
    List.filter_map (fun col ->
      match Arrow_table.get_column df_a.arrow_table col,
            Arrow_table.get_column df_b.arrow_table col with
      | Some ca, Some cb ->
          let ta = col_type_name ca in
          let tb = col_type_name cb in
          if ta <> tb then
            Some (VDict [
              "col", VString col; "from_type", VString ta; "to_type", VString tb
            ])
          else None
      | _ -> None
    ) cols_shared
  in

  let nrows_a = Arrow_table.num_rows df_a.arrow_table in
  let nrows_b = Arrow_table.num_rows df_b.arrow_table in

  (* 2. Row alignment *)
  let all_cols_a = cols_a in
  let all_cols_b = cols_b in

  let aligned =
    if key = [] then begin
      (* Positional alignment *)
      let len = max nrows_a nrows_b in
      List.init len (fun i ->
        let a = if i < nrows_a then Some (row_of_table df_a.arrow_table all_cols_a i) else None in
        let b = if i < nrows_b then Some (row_of_table df_b.arrow_table all_cols_b i) else None in
        (a, b)
      )
    end else begin
      (* Key-based alignment *)
      let key_of row =
        List.filter_map (fun k ->
          match List.assoc_opt k row with
          | Some v -> Some (k, v)
          | None -> None
        ) key
      in
      let tbl_a = Hashtbl.create 256 in
      for i = 0 to nrows_a - 1 do
        let row = row_of_table df_a.arrow_table all_cols_a i in
        Hashtbl.replace tbl_a (key_of row) row
      done;
      let tbl_b = Hashtbl.create 256 in
      for i = 0 to nrows_b - 1 do
        let row = row_of_table df_b.arrow_table all_cols_b i in
        Hashtbl.replace tbl_b (key_of row) row
      done;
      let all_keys =
        let ka = Hashtbl.fold (fun k _ acc -> k :: acc) tbl_a [] in
        let kb = Hashtbl.fold (fun k _ acc -> k :: acc) tbl_b [] in
        (ka @ kb) |> List.sort_uniq compare
      in
      List.map (fun k ->
        (Hashtbl.find_opt tbl_a k, Hashtbl.find_opt tbl_b k)
      ) all_keys
    end
  in

  (* 3. Classify rows *)
  let added = ref [] and removed = ref [] and changed = ref [] and unchanged_count = ref 0 in
  List.iter (fun (a_opt, b_opt) ->
    match a_opt, b_opt with
    | None, Some row_b -> added := row_b :: !added
    | Some row_a, None -> removed := row_a :: !removed
    | Some row_a, Some row_b ->
        let diff_cols =
          List.filter_map (fun col ->
            let va = List.assoc_opt col row_a in
            let vb = List.assoc_opt col row_b in
            match va, vb with
            | Some va', Some vb' when va' <> vb' ->
                Some (col, va', vb')
            | _ -> None
          ) cols_shared
        in
        if diff_cols = [] then incr unchanged_count
        else begin
          (* Build a changed row: key cols + col__before + col__after for each diff *)
          let key_part = List.filter_map (fun k ->
            List.assoc_opt k row_a |> Option.map (fun v -> (k, v))
          ) key in
          let delta_part =
            List.concat_map (fun (col, va, vb) ->
              [(col ^ "__before", va); (col ^ "__after", vb)]
            ) diff_cols
          in
          changed := (key_part @ delta_part) :: !changed
        end
    | None, None -> ()
  ) aligned;

  (* 4. Patience diff on string representations *)
  let str_rows_a = Array.of_list (List.filter_map (fun (a_opt, _) ->
    match a_opt with Some r -> Some (row_to_string r) | None -> None
  ) aligned) in
  let str_rows_b = Array.of_list (List.filter_map (fun (_, b_opt) ->
    match b_opt with Some r -> Some (row_to_string r) | None -> None
  ) aligned) in
  let hunks = string_hunks ~mine:str_rows_a ~other:str_rows_b ~context in

  (* 5. Assemble VDiff *)
  let n_added   = List.length !added in
  let n_removed = List.length !removed in
  let n_changed = List.length !changed in

  (* Determine column sets for rows_to_dataframe *)
  let added_cols_all = all_cols_b in
  let removed_cols_all = all_cols_a in
  let changed_cols =
    match !changed with
    | [] -> []
    | first :: _ -> List.map fst first
  in

  let summary = VDict [
    "rows_added",        VInt n_added;
    "rows_removed",      VInt n_removed;
    "rows_changed",      VInt n_changed;
    "rows_unchanged",    VInt !unchanged_count;
    "cols_added",        VList (List.map (fun s -> (None, VString s)) cols_added);
    "cols_removed",      VList (List.map (fun s -> (None, VString s)) cols_removed);
    "cols_type_changed", VList (List.map (fun v -> (None, v)) type_changed);
  ] in

  let detail = VDict [
    "schema_diff", VDict [
      "added",        VList (List.map (fun s -> (None, VString s)) cols_added);
      "removed",      VList (List.map (fun s -> (None, VString s)) cols_removed);
      "type_changed", VList (List.map (fun v -> (None, v)) type_changed);
    ];
    "added",            rows_to_dataframe added_cols_all (List.rev !added);
    "removed",          rows_to_dataframe removed_cols_all (List.rev !removed);
    "changed",          rows_to_dataframe changed_cols (List.rev !changed);
    "unchanged_count",  VInt !unchanged_count;
  ] in

  let identical = n_added = 0 && n_removed = 0 && n_changed = 0
                  && cols_added = [] && cols_removed = [] && type_changed = [] in

  make_vdiff
    ~kind:"dataframe_diff"
    ~node_a:node_a_name ~node_b:node_b_name
    ~log_a ~log_b
    ~value_type:"DataFrame"
    ~identical ~summary ~detail ~hunks

(* ------------------------------------------------------------------ *)
(* Model diff                                                          *)
(* ------------------------------------------------------------------ *)

(** Extract coefficient name→float pairs from a PMML model dict. *)
let extract_coef_dict (model : value) : (string * float) list =
  match model with
  | VDict pairs ->
      (match List.assoc_opt "coefficients" pairs with
       | Some (VDict cpairs) ->
           List.filter_map (fun (k, v) ->
             match v with
             | VFloat f -> Some (k, f)
             | VInt n   -> Some (k, float_of_int n)
             | _ -> None
           ) cpairs
       | _ -> [])
  | _ -> []

(** Extract fit statistics as (name, value) pairs. *)
let extract_fit_stats (model : value) : (string * value) list =
  match model with
  | VDict pairs ->
      List.filter (fun (k, _) ->
        k <> "coefficients" && k <> "model_type" && k <> "path"
        && k <> "source_path"
      ) pairs
  | _ -> []

(** Compute delta between named float stats. *)
let float_diff stats_a stats_b name =
  let get_float stats =
    match List.assoc_opt name stats with
    | Some (VFloat f) -> f
    | Some (VInt n) -> float_of_int n
    | _ -> 0.0
  in
  get_float stats_b -. get_float stats_a

(** Build a fit_stats_diff DataFrame from two stat lists. *)
let fit_stats_diff stats_a stats_b =
  let all_names =
    (List.map fst stats_a @ List.map fst stats_b)
    |> List.sort_uniq String.compare
  in
  let rows = List.filter_map (fun metric ->
    let va = List.assoc_opt metric stats_a in
    let vb = List.assoc_opt metric stats_b in
    match va, vb with
    | Some (VFloat fa), Some (VFloat fb) ->
        Some [("metric", VString metric); ("value_a", VFloat fa);
              ("value_b", VFloat fb); ("delta", VFloat (fb -. fa))]
    | Some (VInt ia), Some (VInt ib) ->
        let fa = float_of_int ia and fb = float_of_int ib in
        Some [("metric", VString metric); ("value_a", VFloat fa);
              ("value_b", VFloat fb); ("delta", VFloat (fb -. fa))]
    | _ -> None
  ) all_names in
  rows_to_dataframe ["metric"; "value_a"; "value_b"; "delta"] rows

let diff_models
    ~(model_a : value)
    ~(model_b : value)
    ~(context : int)
    ~(node_a_name : string)
    ~(node_b_name : string)
    ~(log_a : string)
    ~(log_b : string)
  : value =

  let coefs_a = extract_coef_dict model_a in
  let coefs_b = extract_coef_dict model_b in
  let names_a = List.map fst coefs_a |> String_set.of_list in
  let names_b = List.map fst coefs_b |> String_set.of_list in
  let added_terms   = String_set.diff names_b names_a |> String_set.elements in
  let removed_terms = String_set.diff names_a names_b |> String_set.elements in
  let shared_terms  = String_set.inter names_a names_b |> String_set.elements in

  let coef_diff_rows =
    List.filter_map (fun term ->
      let a = List.assoc_opt term coefs_a in
      let b = List.assoc_opt term coefs_b in
      match a, b with
      | Some va, Some vb ->
          let delta = vb -. va in
          let pct   = if va <> 0.0 then 100.0 *. delta /. va else Float.infinity in
          if Float.abs delta > 1e-10 then
            Some [("term", VString term); ("estimate_a", VFloat va); ("estimate_b", VFloat vb);
                  ("delta", VFloat delta); ("pct_change", VFloat pct)]
          else None
      | _ -> None
    ) shared_terms
  in

  let stats_a = extract_fit_stats model_a in
  let stats_b = extract_fit_stats model_b in
  let r2_delta  = float_diff stats_a stats_b "r_squared" in
  let aic_delta = float_diff stats_a stats_b "aic" in

  let n_changed = List.length coef_diff_rows in
  let summary = VDict [
    "coef_changed",  VInt n_changed;
    "coef_added",    VInt (List.length added_terms);
    "coef_removed",  VInt (List.length removed_terms);
    "r2_delta",      VFloat r2_delta;
    "aic_delta",     VFloat aic_delta;
  ] in

  (* Patience diff over coefficient string representations *)
  let coef_strs_a = Array.of_list (List.map (fun (k, v) -> Printf.sprintf "%s:%.6g" k v) coefs_a) in
  let coef_strs_b = Array.of_list (List.map (fun (k, v) -> Printf.sprintf "%s:%.6g" k v) coefs_b) in
  let hunks = string_hunks ~mine:coef_strs_a ~other:coef_strs_b ~context in

  let detail = VDict [
    "coef_diff",      rows_to_dataframe ["term"; "estimate_a"; "estimate_b"; "delta"; "pct_change"] coef_diff_rows;
    "fit_stats_a",    rows_to_dataframe (List.map fst stats_a) [stats_a];
    "fit_stats_b",    rows_to_dataframe (List.map fst stats_b) [stats_b];
    "fit_stats_diff", fit_stats_diff stats_a stats_b;
  ] in

  let identical = n_changed = 0 && added_terms = [] && removed_terms = [] in

  make_vdiff
    ~kind:"model_diff"
    ~node_a:node_a_name ~node_b:node_b_name
    ~log_a ~log_b
    ~value_type:"Model"
    ~identical ~summary ~detail ~hunks

(* ------------------------------------------------------------------ *)
(* Scalar diff                                                         *)
(* ------------------------------------------------------------------ *)

let diff_scalars
    ~(va : value) ~(vb : value)
    ~(node_a_name : string) ~(node_b_name : string)
    ~(log_a : string) ~(log_b : string)
  : value =
  let changed = va <> vb in
  let delta =
    match va, vb with
    | VInt a,   VInt b   -> VInt   (b - a)
    | VFloat a, VFloat b -> VFloat (b -. a)
    | VInt a,   VFloat b -> VFloat (b -. float_of_int a)
    | VFloat a, VInt b   -> VFloat (float_of_int b -. a)
    | _ -> VNA NAGeneric
  in
  let summary = VDict [
    "changed", VBool changed; "value_a", va; "value_b", vb; "delta", delta
  ] in
  let type_name = Utils.type_name va in
  let hunks = string_hunks
    ~mine:[| Utils.value_to_string va |]
    ~other:[| Utils.value_to_string vb |]
    ~context:0
  in
  make_vdiff
    ~kind:"scalar_diff"
    ~node_a:node_a_name ~node_b:node_b_name
    ~log_a ~log_b
    ~value_type:type_name
    ~identical:(not changed) ~summary ~detail:summary ~hunks

(* ------------------------------------------------------------------ *)
(* Generic diff (fallback)                                             *)
(* ------------------------------------------------------------------ *)

let diff_generic
    ~(va : value) ~(vb : value)
    ~(node_a_name : string) ~(node_b_name : string)
    ~(log_a : string) ~(log_b : string)
  : value =
  let changed = va <> vb in
  let repr_a = Utils.value_to_string va |> String.split_on_char '\n' |> Array.of_list in
  let repr_b = Utils.value_to_string vb |> String.split_on_char '\n' |> Array.of_list in
  let hunks  = string_hunks ~mine:repr_a ~other:repr_b ~context:3 in
  let summary = VDict ["changed", VBool changed] in
  let detail  = VDict [
    "value_a", va; "value_b", vb;
    "repr_diff", VList (List.map (fun v -> (None, v)) hunks)
  ] in
  make_vdiff
    ~kind:"generic_diff"
    ~node_a:node_a_name ~node_b:node_b_name
    ~log_a ~log_b
    ~value_type:(Utils.type_name va)
    ~identical:(not changed) ~summary ~detail ~hunks

(* ------------------------------------------------------------------ *)
(* Dispatch                                                            *)
(* ------------------------------------------------------------------ *)

(** Top-level diff dispatch.  Takes two loaded artifact values and their
    metadata, picks the right type-specific diff, and returns a VDiff
    envelope. *)
let node_diff_values
    ~(va : value) ~(vb : value)
    ~(node_a_name : string) ~(node_b_name : string)
    ~(log_a : string) ~(log_b : string)
    ~(key : string list) ~(context : int)
  : value =
  match va, vb with
  | VDataFrame dfa, VDataFrame dfb ->
      diff_dataframes ~df_a:dfa ~df_b:dfb ~key ~context
        ~node_a_name ~node_b_name ~log_a ~log_b

  | VDict pa, VDict pb
    when List.mem_assoc "coefficients" pa || List.mem_assoc "coefficients" pb
         || List.mem_assoc "model_type" pa || List.mem_assoc "model_type" pb ->
      diff_models ~model_a:va ~model_b:vb ~context
        ~node_a_name ~node_b_name ~log_a ~log_b

  | (VInt _ | VFloat _ | VBool _ | VString _), _ ->
      diff_scalars ~va ~vb
        ~node_a_name ~node_b_name ~log_a ~log_b

  | _ ->
      diff_generic ~va ~vb
        ~node_a_name ~node_b_name ~log_a ~log_b
