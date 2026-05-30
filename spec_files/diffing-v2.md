# `node_diff` — Specification and Implementation


---

## 1. Motivation

When a T pipeline is iterated on — columns are dropped, filter predicates tighten, a model is retrained — there is currently no way to ask *what actually changed* between two builds of the same node, or between two different nodes that produce the same type. The user must manually load both artifacts and write ad-hoc comparison code.

`node_diff` fills that gap. It takes two `ComputedNode` references and two build-log selectors, loads the corresponding artifacts, and returns a structured `VDiff` value describing what changed. The diff adapts to the value type: DataFrames get row- and column-level comparison, Models get coefficient and fit-stat deltas, scalars get a before/after record, and anything else falls back to a generic structural comparison.

---

## 2. Interface

### 2.1 Signature

```t
node_diff(
  node_a    :: ComputedNode,
  node_b    :: ComputedNode,
  log_a     :: String = "latest",
  log_b     :: String = "latest",
  key       :: List[Symbol] = [],
  context   :: Int = 3
) :: VDiff
```

All four positional and optional arguments are described below.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `node_a` | `ComputedNode` | — | The "before" node, e.g. `p.clean_data` |
| `node_b` | `ComputedNode` | — | The "after" node, e.g. `p.clean_data` |
| `log_a` | `String` | `"latest"` | Build log selector for `node_a`. Accepts a timestamp prefix (`"20260510_120000"`) or a regex matched against filenames in `_pipeline/`. |
| `log_b` | `String` | `"latest"` | Build log selector for `node_b`. Same format as `log_a`. |
| `key` | `List[Symbol]` | `[]` | For DataFrames: the natural key column(s) used to align rows before diffing. If empty, rows are aligned by position (integer index). |
| `context` | `Int` | `3` | Number of unchanged rows shown above and below each changed hunk, mirroring `diff -U`. |

### 2.2 Typical call patterns

```t
-- Compare the same node across two historical builds
d = node_diff(p.clean_data, p.clean_data,
      log_a = "20260510_120000",
      log_b = "20260515_090000")

-- Compare two different nodes in the current build
d = node_diff(p.clean_data, p.validated_data)

-- Same node, latest vs a named earlier run, keyed on an id column
d = node_diff(p.customers, p.customers,
      log_a = "20260501",
      log_b = "latest",
      key = [$customer_id])

-- Model comparison
d = node_diff(p.model_v1, p.model_v2)
```

---

## 3. Return value — `VDiff`

`node_diff` always returns a `VDiff` dictionary. The top-level fields are common to all diff types; the `detail` field is type-specific.

### 3.1 Common envelope

```t
{
  kind        :: String,   -- "dataframe_diff" | "model_diff" | "scalar_diff" | "generic_diff"
  node_a      :: String,   -- name of node_a
  node_b      :: String,   -- name of node_b
  log_a       :: String,   -- resolved log filename used for node_a
  log_b       :: String,   -- resolved log filename used for node_b
  value_type  :: String,   -- T type name of the diffed values
  identical   :: Bool,     -- true iff no differences were found
  summary     :: Dict,     -- type-specific summary counts (see below)
  detail      :: Any,      -- type-specific detail (see below)
  hunks       :: List[Dict] -- patience-diff hunks (always present, format below)
}
```

### 3.2 DataFrame diff

`summary`:

```t
{
  rows_added    :: Int,
  rows_removed  :: Int,
  rows_changed  :: Int,
  rows_unchanged :: Int,
  cols_added    :: List[String],
  cols_removed  :: List[String],
  cols_type_changed :: List[Dict]   -- [{col, from_type, to_type}]
}
```

`detail`:

```t
{
  schema_diff :: Dict,           -- {added, removed, type_changed}
  added       :: DataFrame,      -- rows present only in node_b
  removed     :: DataFrame,      -- rows present only in node_a
  changed     :: DataFrame,      -- rows present in both, with differences
                                 --   columns: key cols + _col__before + _col__after
                                 --   for every column that changed
  unchanged_count :: Int
}
```

The `changed` DataFrame uses a double-underscore naming convention so that column names never collide with the key columns. For example, if `salary` changed, the output contains `salary__before` and `salary__after`.

### 3.3 Model diff

`summary`:

```t
{
  coef_changed  :: Int,
  coef_added    :: Int,    -- terms present in model_b but not model_a
  coef_removed  :: Int,    -- terms present in model_a but not model_b
  r2_delta      :: Float,
  aic_delta     :: Float
}
```

`detail`:

```t
{
  coef_diff     :: DataFrame,  -- term, estimate_a, estimate_b, delta, pct_change
  fit_stats_a   :: DataFrame,
  fit_stats_b   :: DataFrame,
  fit_stats_diff :: DataFrame  -- metric, value_a, value_b, delta
}
```

### 3.4 Scalar diff

`summary`:

```t
{
  changed :: Bool,
  value_a :: Any,
  value_b :: Any,
  delta   :: Any    -- value_b - value_a for numerics, NA otherwise
}
```

`detail`: same as `summary`.

### 3.5 Generic diff

Used for values with no specific handler (Lists, Dicts, Errors, Intents, etc.).

`summary`:

```t
{
  changed :: Bool
}
```

`detail`:

```t
{
  value_a :: Any,
  value_b :: Any,
  repr_diff :: List[Dict]   -- patience-diff hunks over string representations
}
```

### 3.6 Hunk format

`hunks` is always populated and contains patience-diff output normalized into T dicts. Each hunk represents a contiguous region of change:

```t
{
  kind    :: String,   -- "equal" | "replace" | "insert" | "delete"
  a_start :: Int,      -- 0-based start index in sequence_a
  a_end   :: Int,
  b_start :: Int,
  b_end   :: Int,
  lines_a :: List[String],   -- string representations of the a-side lines/rows
  lines_b :: List[String]    -- string representations of the b-side lines/rows
}
```

For DataFrames, each "line" is a JSON-serialized row. For Models, each "line" is a coefficient record. For scalars and generics, each "line" is `to_string(value)`.

---

## 4. Interaction with `explain()`

`explain(d)` where `d` is a `VDiff` renders a structured summary rather than a raw dict dump:

```
VDiff (dataframe_diff)
  nodes:     clean_data → clean_data
  builds:    20260510_120000 → 20260515_090000
  identical: false

  schema
    added:   region
    removed: (none)
    changed: (none)

  rows
    added:      12
    removed:     3
    changed:    47
    unchanged: 938

  hunks: 6 (use d.hunks to inspect)
```

---

## 5. OCaml implementation

### 5.1 New file: `src/diff.ml`

This module owns all diff logic. It is imported by `eval.ml` and exposed as the `node_diff` builtin.

```ocaml
(* src/diff.ml *)

open Ast
open Patience_diff

(* ------------------------------------------------------------------ *)
(* Row representation for patience diff                                *)
(* ------------------------------------------------------------------ *)

(* A row is represented as a string for the patience algorithm.        *)
(* We use JSON serialization so the representation is stable and       *)
(* unambiguous across types.                                            *)

let row_to_string (row : (string * value) list) : string =
  let kvs = List.map (fun (k, v) -> Printf.sprintf "%s:%s" k (value_to_json_string v)) row in
  "{" ^ String.concat "," kvs ^ "}"

(* ------------------------------------------------------------------ *)
(* Patience diff over string arrays                                    *)
(* ------------------------------------------------------------------ *)

(* patience_diff operates on 'a Plain_diff.t arrays (Mine/Other/Same). *)
(* We use String as the element type and convert back to VDiff hunks.  *)

let string_hunks ~mine ~other ~context : value list =
  let hunks =
    Patience_diff.String.get_hunks
      ~mine
      ~other
      ~context
      ~keep_all:false
  in
  List.map (fun (h : string Hunk.t) ->
    let ranges = Hunk.ranges h in
    let a_start = Hunk.prev_start h - 1 in  (* 0-based *)
    let b_start = Hunk.next_start h - 1 in
    let lines_a = ref [] and lines_b = ref [] and kind = ref "equal" in
    List.iter (fun r ->
      match r with
      | Range.Same xs ->
          kind := "equal";
          Array.iter (fun s -> lines_a := s :: !lines_a; lines_b := s :: !lines_b) xs
      | Range.Replace (xs, ys) ->
          kind := "replace";
          Array.iter (fun s -> lines_a := s :: !lines_a) xs;
          Array.iter (fun s -> lines_b := s :: !lines_b) ys
      | Range.Insert ys ->
          kind := "insert";
          Array.iter (fun s -> lines_b := s :: !lines_b) ys
      | Range.Delete xs ->
          kind := "delete";
          Array.iter (fun s -> lines_a := s :: !lines_a) xs
      | Range.Unified _ -> ()
    ) ranges;
    VDict (Hashtbl.of_seq (List.to_seq [
      "kind",    VString !kind;
      "a_start", VInt a_start;
      "a_end",   VInt (a_start + List.length !lines_a);
      "b_start", VInt b_start;
      "b_end",   VInt (b_start + List.length !lines_b);
      "lines_a", VList (List.rev_map (fun s -> VString s) !lines_a);
      "lines_b", VList (List.rev_map (fun s -> VString s) !lines_b);
    ]))
  ) hunks

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
  let cols_a = Set.of_list (dataframe_colnames df_a) in
  let cols_b = Set.of_list (dataframe_colnames df_b) in
  let cols_added   = Set.diff cols_b cols_a |> Set.to_list in
  let cols_removed = Set.diff cols_a cols_b |> Set.to_list in
  let cols_shared  = Set.inter cols_a cols_b |> Set.to_list in

  let type_changed =
    List.filter_map (fun col ->
      let ta = dataframe_col_type df_a col in
      let tb = dataframe_col_type df_b col in
      if ta <> tb then
        Some (VDict (Hashtbl.of_seq (List.to_seq [
          "col", VString col; "from_type", VString ta; "to_type", VString tb
        ])))
      else None
    ) cols_shared
  in

  (* 2. Row alignment *)
  (* If key columns supplied, do a hash join; otherwise use row index. *)
  let rows_a = dataframe_to_rows df_a in   (* (string * value) list list *)
  let rows_b = dataframe_to_rows df_b in

  let aligned =
    if key = [] then
      (* positional alignment — zip, with Add/Remove for length mismatch *)
      let len = max (List.length rows_a) (List.length rows_b) in
      let arr_a = Array.of_list rows_a in
      let arr_b = Array.of_list rows_b in
      Array.init len (fun i ->
        let a = if i < Array.length arr_a then Some arr_a.(i) else None in
        let b = if i < Array.length arr_b then Some arr_b.(i) else None in
        (a, b)
      ) |> Array.to_list
    else
      (* key-based alignment *)
      let key_of row =
        List.filter_map (fun k ->
          match List.assoc_opt k row with
          | Some v -> Some (k, v)
          | None -> None
        ) key
      in
      let tbl_a = Hashtbl.create 256 in
      List.iter (fun row -> Hashtbl.replace tbl_a (key_of row) row) rows_a;
      let tbl_b = Hashtbl.create 256 in
      List.iter (fun row -> Hashtbl.replace tbl_b (key_of row) row) rows_b;
      let all_keys =
        (Hashtbl.keys tbl_a |> List.of_seq) @
        (Hashtbl.keys tbl_b |> List.of_seq)
        |> List.sort_uniq compare
      in
      List.map (fun k ->
        (Hashtbl.find_opt tbl_a k, Hashtbl.find_opt tbl_b k)
      ) all_keys
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
            | Some va', Some vb' when not (values_equal va' vb') ->
                Some (col, va', vb')
            | Some _, None | None, Some _ ->
                None  (* schema diff already captured above *)
            | _ -> None
          ) cols_shared
        in
        if diff_cols = [] then incr unchanged_count
        else begin
          (* Build a changed row: key cols + col__before + col__after for each diff *)
          let key_part = List.filter_map (fun k -> List.assoc_opt k row_a |> Option.map (fun v -> (k, v))) key in
          let delta_part =
            List.concat_map (fun (col, va, vb) ->
              [(col ^ "__before", va); (col ^ "__after", vb)]
            ) diff_cols
          in
          changed := (key_part @ delta_part) :: !changed
        end
    | None, None -> ()
  ) aligned;

  (* 4. Patience diff on string representations of shared rows *)
  let str_rows_a = Array.of_list (List.filter_map (fun (a_opt, b_opt) ->
    match a_opt, b_opt with
    | Some r, Some _ -> Some (row_to_string r)
    | Some r, None   -> Some (row_to_string r)
    | _ -> None
  ) aligned) in
  let str_rows_b = Array.of_list (List.filter_map (fun (a_opt, b_opt) ->
    match a_opt, b_opt with
    | Some _, Some r -> Some (row_to_string r)
    | None,   Some r -> Some (row_to_string r)
    | _ -> None
  ) aligned) in
  let hunks = string_hunks ~mine:str_rows_a ~other:str_rows_b ~context in

  (* 5. Assemble VDiff *)
  let n_added   = List.length !added in
  let n_removed = List.length !removed in
  let n_changed = List.length !changed in

  let summary = VDict (Hashtbl.of_seq (List.to_seq [
    "rows_added",        VInt n_added;
    "rows_removed",      VInt n_removed;
    "rows_changed",      VInt n_changed;
    "rows_unchanged",    VInt !unchanged_count;
    "cols_added",        VList (List.map (fun s -> VString s) cols_added);
    "cols_removed",      VList (List.map (fun s -> VString s) cols_removed);
    "cols_type_changed", VList type_changed;
  ])) in

  let detail = VDict (Hashtbl.of_seq (List.to_seq [
    "schema_diff", VDict (Hashtbl.of_seq (List.to_seq [
      "added",        VList (List.map (fun s -> VString s) cols_added);
      "removed",      VList (List.map (fun s -> VString s) cols_removed);
      "type_changed", VList type_changed;
    ]));
    "added",            rows_to_dataframe !added;
    "removed",          rows_to_dataframe !removed;
    "changed",          rows_to_dataframe !changed;
    "unchanged_count",  VInt !unchanged_count;
  ])) in

  let identical = n_added = 0 && n_removed = 0 && n_changed = 0 && cols_added = [] && cols_removed = [] && type_changed = [] in

  make_vdiff
    ~kind:"dataframe_diff"
    ~node_a:node_a_name ~node_b:node_b_name
    ~log_a ~log_b
    ~value_type:"DataFrame"
    ~identical ~summary ~detail ~hunks

(* ------------------------------------------------------------------ *)
(* Model diff                                                          *)
(* ------------------------------------------------------------------ *)

let diff_models
    ~(model_a : value)
    ~(model_b : value)
    ~(context : int)
    ~(node_a_name : string)
    ~(node_b_name : string)
    ~(log_a : string)
    ~(log_b : string)
  : value =

  let coefs_a = extract_coef_dict model_a in  (* (string * float) list *)
  let coefs_b = extract_coef_dict model_b in
  let names_a = List.map fst coefs_a |> Set.of_list in
  let names_b = List.map fst coefs_b |> Set.of_list in
  let added_terms   = Set.diff names_b names_a |> Set.to_list in
  let removed_terms = Set.diff names_a names_b |> Set.to_list in
  let shared_terms  = Set.inter names_a names_b |> Set.to_list in

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

  let stats_a = extract_fit_stats model_a in  (* (string * value) list *)
  let stats_b = extract_fit_stats model_b in
  let r2_delta  = float_diff stats_a stats_b "r_squared" in
  let aic_delta = float_diff stats_a stats_b "aic" in

  let n_changed = List.length coef_diff_rows in
  let summary = VDict (Hashtbl.of_seq (List.to_seq [
    "coef_changed",  VInt n_changed;
    "coef_added",    VInt (List.length added_terms);
    "coef_removed",  VInt (List.length removed_terms);
    "r2_delta",      VFloat r2_delta;
    "aic_delta",     VFloat aic_delta;
  ])) in

  (* Patience diff over coefficient string representations *)
  let coef_strs_a = Array.of_list (List.map (fun (k, v) -> Printf.sprintf "%s:%.6g" k v) coefs_a) in
  let coef_strs_b = Array.of_list (List.map (fun (k, v) -> Printf.sprintf "%s:%.6g" k v) coefs_b) in
  let hunks = string_hunks ~mine:coef_strs_a ~other:coef_strs_b ~context in

  let detail = VDict (Hashtbl.of_seq (List.to_seq [
    "coef_diff",      rows_to_dataframe coef_diff_rows;
    "fit_stats_a",    rows_to_dataframe [stats_a];
    "fit_stats_b",    rows_to_dataframe [stats_b];
    "fit_stats_diff", fit_stats_diff stats_a stats_b;
  ])) in

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
  let changed = not (values_equal va vb) in
  let delta =
    match va, vb with
    | VInt a,   VInt b   -> VInt   (b - a)
    | VFloat a, VFloat b -> VFloat (b -. a)
    | VInt a,   VFloat b -> VFloat (b -. float_of_int a)
    | VFloat a, VInt b   -> VFloat (float_of_int b -. a)
    | _ -> VNA NAGeneric
  in
  let summary = VDict (Hashtbl.of_seq (List.to_seq [
    "changed", VBool changed; "value_a", va; "value_b", vb; "delta", delta
  ])) in
  let type_name = value_type_name va in
  let hunks = string_hunks
    ~mine:[| value_to_display_string va |]
    ~other:[| value_to_display_string vb |]
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
  let changed = not (values_equal va vb) in
  let repr_a  = value_to_display_string va |> String.split_on_char '\n' |> Array.of_list in
  let repr_b  = value_to_display_string vb |> String.split_on_char '\n' |> Array.of_list in
  let hunks   = string_hunks ~mine:repr_a ~other:repr_b ~context:3 in
  let summary = VDict (Hashtbl.of_seq (List.to_seq ["changed", VBool changed])) in
  let detail  = VDict (Hashtbl.of_seq (List.to_seq [
    "value_a", va; "value_b", vb; "repr_diff", VList hunks
  ])) in
  make_vdiff
    ~kind:"generic_diff"
    ~node_a:node_a_name ~node_b:node_b_name
    ~log_a ~log_b
    ~value_type:(value_type_name va)
    ~identical:(not changed) ~summary ~detail ~hunks

(* ------------------------------------------------------------------ *)
(* Dispatch                                                            *)
(* ------------------------------------------------------------------ *)

let node_diff
    ~(node_a  : value)          (* ComputedNode *)
    ~(node_b  : value)
    ~(log_a   : string)
    ~(log_b   : string)
    ~(key     : string list)
    ~(context : int)
  : value =

  let na_name = computed_node_name node_a in
  let nb_name = computed_node_name node_b in

  (* Resolve artifacts through the build log system *)
  let resolved_log_a, va = resolve_node_artifact node_a log_a in
  let resolved_log_b, vb = resolve_node_artifact node_b log_b in

  match va, vb with
  | VDataFrame dfa, VDataFrame dfb ->
      diff_dataframes ~df_a:dfa ~df_b:dfb ~key ~context
        ~node_a_name:na_name ~node_b_name:nb_name
        ~log_a:resolved_log_a ~log_b:resolved_log_b

  | VModel _, VModel _ ->
      diff_models ~model_a:va ~model_b:vb ~context
        ~node_a_name:na_name ~node_b_name:nb_name
        ~log_a:resolved_log_a ~log_b:resolved_log_b

  | (VInt _ | VFloat _ | VBool _ | VString _), _ ->
      diff_scalars ~va ~vb
        ~node_a_name:na_name ~node_b_name:nb_name
        ~log_a:resolved_log_a ~log_b:resolved_log_b

  | _ ->
      diff_generic ~va ~vb
        ~node_a_name:na_name ~node_b_name:nb_name
        ~log_a:resolved_log_a ~log_b:resolved_log_b

(* ------------------------------------------------------------------ *)
(* Helper: make_vdiff                                                  *)
(* ------------------------------------------------------------------ *)

let make_vdiff ~kind ~node_a ~node_b ~log_a ~log_b
               ~value_type ~identical ~summary ~detail ~hunks =
  VDict (Hashtbl.of_seq (List.to_seq [
    "kind",       VString kind;
    "node_a",     VString node_a;
    "node_b",     VString node_b;
    "log_a",      VString log_a;
    "log_b",      VString log_b;
    "value_type", VString value_type;
    "identical",  VBool   identical;
    "summary",    summary;
    "detail",     detail;
    "hunks",      VList hunks;
  ]))
```

### 5.2 Changes to `eval.ml`

Register `node_diff` in the builtin table alongside the other pipeline inspection builtins:

```ocaml
(* In the builtin dispatch section of eval.ml *)

| "node_diff" ->
    (match args with
    | [node_a; node_b] ->
        Diff.node_diff ~node_a ~node_b
          ~log_a:"latest" ~log_b:"latest"
          ~key:[] ~context:3
    | [node_a; node_b; VString log_a; VString log_b] ->
        Diff.node_diff ~node_a ~node_b
          ~log_a ~log_b ~key:[] ~context:3
    | _ ->
        (* Full named-argument form — extract from kwargs dict *)
        let get_str d k def = match Dict.find_opt k d with Some (VString s) -> s | _ -> def in
        let get_int d k def = match Dict.find_opt k d with Some (VInt n) -> n | _ -> def in
        let get_key d =
          match Dict.find_opt "key" d with
          | Some (VList syms) ->
              List.filter_map (function VString s -> Some s | _ -> None) syms
          | _ -> []
        in
        match kwargs with
        | Some kw ->
            let node_a  = Dict.find "node_a" kw in
            let node_b  = Dict.find "node_b" kw in
            let log_a   = get_str kw "log_a"   "latest" in
            let log_b   = get_str kw "log_b"   "latest" in
            let key     = get_key kw in
            let context = get_int kw "context" 3 in
            Diff.node_diff ~node_a ~node_b ~log_a ~log_b ~key ~context
        | None ->
            type_error "node_diff: invalid arguments")
```

### 5.3 Changes to `src/dune`

```
(libraries
  ...
  patience_diff)
```

### 5.4 Changes to `flake.nix`

```nix
buildInputs = with ocamlPackages; [
  ...
  patience_diff
];
```

`patience_diff` is available in nixpkgs under `ocamlPackages.patience_diff` — no custom packaging required.

---

## 6. `resolve_node_artifact`

This helper is the bridge between `node_diff` and the existing build-log infrastructure in `src/pipeline/builder_read_node.ml`. It accepts a `ComputedNode` and a log selector string and returns `(resolved_log_filename, value)`.

```ocaml
(* In src/pipeline/builder_read_node.ml — extend existing read_node logic *)

let resolve_node_artifact (node : value) (log_selector : string)
    : string * value =
  let node_name = computed_node_name node in
  let log_file =
    if log_selector = "latest" then
      find_latest_log "_pipeline/"
    else
      (* Match log_selector as a prefix or regex against filenames in _pipeline/ *)
      find_log_matching "_pipeline/" log_selector
  in
  let artifact_path = resolve_path_from_log log_file node_name in
  let value = deserialize_artifact artifact_path in
  (Filename.basename log_file, value)
```

`find_log_matching` tries:
1. Exact filename match.
2. Prefix match against the timestamp portion of `build_log_YYYYMMDD_HHMMSS_hash.json`.
3. Regex match against the full filename.

It returns the most recent match if multiple candidates exist, or raises a `BuildLogError` if none is found.

---

## 7. `pipeline_diff` — pipeline-level structural diff

`pipeline_diff` uses `node_diff`'s hunk infrastructure but operates on `VPipeline` objects rather than artifact values.

```t
pipeline_diff(p_a :: Pipeline, p_b :: Pipeline) :: VDiff
```

Implementation is pure T-level — it does not need `patience_diff` directly because it can express the diff in terms of set operations and metadata comparison:

```t
-- In src/packages/pipeline/pipeline_diff.t

pipeline_diff = \(p_a, p_b) {
  nodes_a = pipeline_nodes(p_a)
  nodes_b = pipeline_nodes(p_b)

  added_nodes   = nodes_b |> filter(\(n) !(n in nodes_a))
  removed_nodes = nodes_a |> filter(\(n) !(n in nodes_b))
  shared_nodes  = nodes_a |> filter(\(n) n in nodes_b)

  frame_a = pipeline_to_frame(p_a)
  frame_b = pipeline_to_frame(p_b)

  changed_nodes = shared_nodes |> filter(\(name) {
    row_a = frame_a |> filter($name == name)
    row_b = frame_b |> filter($name == name)
    -- compare runtime, serializer, deserializer, noop, deps
    !frames_equal(row_a, row_b)
  })

  rewired_edges = shared_nodes
    |> filter(\(name) {
      deps_a = pipeline_deps(p_a) |> get(name)
      deps_b = pipeline_deps(p_b) |> get(name)
      !identical(deps_a, deps_b)
    })
    |> map(\(name) {
      [name: name,
       was:  pipeline_deps(p_a) |> get(name),
       now:  pipeline_deps(p_b) |> get(name)]
    })

  identical = length(added_nodes) == 0
           && length(removed_nodes) == 0
           && length(changed_nodes) == 0
           && length(rewired_edges) == 0

  [kind:           "pipeline_diff",
   identical:      identical,
   added_nodes:    added_nodes,
   removed_nodes:  removed_nodes,
   changed_nodes:  changed_nodes,
   rewired_edges:  rewired_edges,
   frame_a:        frame_a,
   frame_b:        frame_b]
}
```

---

## 8. Pretty-printing and REPL display

`pretty_print` is extended to recognise `VDiff` dicts by their `kind` field and render a compact colored summary rather than a raw dict dump.

The renderer follows the convention already established for `build_log`:

- One-line header with node names and build timestamps
- `identical: true` renders in green and stops there
- Otherwise: schema diff block, row-count block, list of changed column pairs
- A footer indicating how many hunks were found and how to access them

For `pipeline_diff`, the renderer lists `+added`, `-removed`, `~changed` nodes using the same `+`/`-`/`~` sigils as `git diff --stat`.

---

## 9. Test plan

New test files to add under `tests/`:

| File | Coverage |
|---|---|
| `tests/diff/test_dataframe_diff.ml` | Positional and keyed row alignment; added/removed/changed row counts; schema changes; `context` parameter; `identical = true` path |
| `tests/diff/test_model_diff.ml` | Coefficient delta, added/removed terms, fit-stat delta, `identical` path |
| `tests/diff/test_scalar_diff.ml` | Int, Float, Bool, String, NA, Error |
| `tests/diff/test_generic_diff.ml` | List, Dict, fallback for unknown types |
| `tests/diff/test_pipeline_diff.ml` | Added/removed/changed nodes, rewired edges, identical pipeline |
| `tests/golden/node_diff_golden.t` | Round-trip: write two CSV fixtures, build a minimal pipeline with two logs, call `node_diff`, assert output fields |

The golden test is the most important: it exercises the full stack from `ComputedNode` artifact resolution through `patience_diff` hunk generation to the `VDiff` assembly.

---

## 10. User-facing documentation additions

### `docs/reference/node_diff.md` (new)

Standard T-Doc reference page. Parameters, return value envelope, examples covering the four dispatch cases.

### `docs/reference/pipeline_diff.md` (new)

Same format. Notes that `pipeline_diff` operates on in-memory `Pipeline` values, not artifacts.

### `docs/pipeline_tutorial.md` — new section

Append a "Comparing builds" section after the existing "Time Travel" section (§15 in the current document), demonstrating the primary use case: compare the same node across two builds after a code change.

### `docs/reference/index.md`

Add `node_diff` and `pipeline_diff` to the function index table.

---

## 11. Summary of new symbols

| Symbol | Kind | Source |
|---|---|---|
| `node_diff` | builtin | `src/diff.ml` + `eval.ml` registration |
| `pipeline_diff` | T-level function | `src/packages/pipeline/pipeline_diff.t` |
| `Diff.node_diff` | OCaml function | `src/diff.ml` |
| `Diff.diff_dataframes` | OCaml function | `src/diff.ml` |
| `Diff.diff_models` | OCaml function | `src/diff.ml` |
| `Diff.diff_scalars` | OCaml function | `src/diff.ml` |
| `Diff.diff_generic` | OCaml function | `src/diff.ml` |
| `resolve_node_artifact` | OCaml function | `src/pipeline/builder_read_node.ml` |
| `VDiff` | value variant | `src/ast.ml` (or represented as tagged `VDict`) |
| `patience_diff` | OCaml library (opam/nixpkgs) | external dependency |
