(* src/arrow/arrow_compute.ml *)
(* Arrow Compute operations for T's colcraft verbs.                      *)
(* When a table has a native_handle, delegates to Arrow Compute kernels  *)
(* via FFI for zero-copy operations and SIMD acceleration.               *)
(* Falls back to pure OCaml implementations when no native handle.       *)

(** Project (select) columns by name.
    Uses native Arrow projection (zero-copy) when available. *)
let project (t : Arrow_table.t) (names : string list) : Arrow_table.t =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_table_project handle.ptr names with
       | Some new_ptr ->
           let new_schema = List.map (fun n ->
             match List.assoc_opt n t.schema with
             | Some ty -> (n, ty)
             | None -> (n, Arrow_table.ArrowNull)
           ) names in
           Arrow_table.create_from_native new_ptr new_schema t.nrows
       | None ->
           (* Native project failed — fall back to pure OCaml *)
           Arrow_table.project t names)
  | _ ->
      Arrow_table.project t names

(** Filter rows using a boolean mask.
    Uses native Arrow filter kernel when available. *)
let filter (t : Arrow_table.t) (mask : bool array) : Arrow_table.t =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_table_filter_mask handle.ptr mask with
       | Some new_ptr ->
           let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
           Arrow_table.create_from_native new_ptr t.schema new_nrows
       | None ->
           (* Native filter failed — fall back to pure OCaml *)
           Arrow_table.filter_rows t mask)
  | _ ->
      Arrow_table.filter_rows t mask

(** Add or replace a column — delegates to Arrow_table.add_column *)
let add_column = Arrow_table.add_column

(** Take rows by index list — delegates to Arrow_table.take_rows *)
let take_rows = Arrow_table.take_rows

(** Sort table by indices — delegates to Arrow_table.sort_by_indices *)
let sort_by_indices = Arrow_table.sort_by_indices

(** Rename columns — delegates to Arrow_table.rename_columns *)
let rename_columns = Arrow_table.rename_columns

(** Sort table by column name using native Arrow sort when available.
    Returns a new table sorted by the given column.
    Falls back to None when no native handle is present. *)
let sort_by_column (t : Arrow_table.t) (col_name : string) (ascending : bool) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_table_sort handle.ptr col_name ascending with
       | Some new_ptr ->
           Some (Arrow_table.create_from_native new_ptr t.schema t.nrows)
       | None -> None)
  | _ -> None

(* ===================================================================== *)
(* Scalar Arithmetic Operations                                          *)
(* ===================================================================== *)

(** Rebuild schema from a native table pointer *)
let schema_from_native_ptr (ptr : nativeint) : Arrow_table.arrow_schema =
  Arrow_table.schema_from_native_ptr ptr

(** Add or replace a computed column while preserving the native path when
    possible. For native-backed destination tables, materialize only the new
    column into a temporary one-column native table and splice it in via the
    dedicated add-column FFI helper, avoiding full-table materialization. *)
let add_computed_column (t : Arrow_table.t) (name : string)
    (col : Arrow_table.column_data) : Arrow_table.t =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      let temp_table =
        Arrow_table.create [ (name, col) ] t.nrows |> Arrow_table.materialize in
      if Arrow_table.is_native_backed temp_table then
        Arrow_table.add_column_from_table t name temp_table name
      else
        Arrow_table.add_column t name col
  | _ ->
      Arrow_table.add_column t name col

(** Apply a scalar arithmetic operation element-wise to a named numeric column.
    Returns Some(column_data) suitable for replacing the source column. *)
let column_scalar_op (t : Arrow_table.t) (col_name : string)
    (scalar : float) (op : float -> float -> float)
    : Arrow_table.column_data option =
  match Arrow_table.get_column t col_name with
  | Some (Arrow_table.FloatColumn a) ->
      Some (Arrow_table.FloatColumn
        (Array.map (function Some f -> Some (op f scalar) | None -> None) a))
  | Some (Arrow_table.IntColumn a) ->
      Some (Arrow_table.FloatColumn
        (Array.map (function Some i -> Some (op (float_of_int i) scalar) | None -> None) a))
  | _ -> None

(** Apply a scalar arithmetic kernel and return a table with the source column
    replaced by the computed result. Uses the native Arrow implementation when
    available and falls back to a pure OCaml column operation otherwise. *)
let scalar_op_to_table (t : Arrow_table.t) (col_name : string) (scalar : float)
    (native_fn : nativeint -> string -> float -> nativeint option)
    (ocaml_fn : Arrow_table.t -> string -> float -> Arrow_table.column_data option)
    : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match native_fn handle.ptr col_name scalar with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None ->
           (match ocaml_fn t col_name scalar with
            | Some col_data -> Some (add_computed_column t col_name col_data)
            | None -> None))
  | _ ->
      (match ocaml_fn t col_name scalar with
       | Some col_data -> Some (add_computed_column t col_name col_data)
        | None -> None)

(** Apply an integer scalar arithmetic operation element-wise to a named Int64
    column while preserving integer output. Returns None for non-integer input
    columns so callers can fall back to the generic numeric path. *)
let int_column_scalar_op (t : Arrow_table.t) (col_name : string)
    (scalar : int) (op : int -> int -> int)
    : Arrow_table.column_data option =
  match Arrow_table.get_column t col_name with
  | Some (Arrow_table.IntColumn a) ->
      Some (Arrow_table.IntColumn
        (Array.map (function Some i -> Some (op i scalar) | None -> None) a))
  | _ -> None

(** Apply an integer scalar arithmetic operation to a table column.
    Preserves Int64 output for integral columns and falls back to the existing
    float-based scalar path for non-integral numeric columns. *)
let int_scalar_op_to_table (t : Arrow_table.t) (col_name : string) (scalar : int)
    (int_op : int -> int -> int)
    (native_fn : nativeint -> string -> float -> nativeint option)
    (float_ocaml_fn : Arrow_table.t -> string -> float -> Arrow_table.column_data option)
    : Arrow_table.t option =
  match int_column_scalar_op t col_name scalar int_op with
  | Some col_data -> Some (add_computed_column t col_name col_data)
  | None -> scalar_op_to_table t col_name (float_of_int scalar) native_fn float_ocaml_fn

(** Add a scalar to every element of a named column.
      Uses Arrow Compute 'add' kernel when native handle is present. *)
let add_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  scalar_op_to_table t col_name scalar
    Arrow_ffi.arrow_compute_add_scalar
    (fun table name scalar_value -> column_scalar_op table name scalar_value ( +. ))

(** Add an integer scalar to every element of a named column, preserving Int64
    output when the source column is integral. *)
let add_int_scalar (t : Arrow_table.t) (col_name : string) (scalar : int) : Arrow_table.t option =
  int_scalar_op_to_table t col_name scalar ( + )
    Arrow_ffi.arrow_compute_add_scalar
    (fun table name scalar_value -> column_scalar_op table name scalar_value ( +. ))

(** Multiply every element of a named column by a scalar.
      Uses Arrow Compute 'multiply' kernel when native handle is present. *)
let multiply_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  scalar_op_to_table t col_name scalar
    Arrow_ffi.arrow_compute_multiply_scalar
    (fun table name scalar_value -> column_scalar_op table name scalar_value ( *. ))

(** Multiply every element of a named column by an integer scalar, preserving
    Int64 output when the source column is integral. *)
let multiply_int_scalar (t : Arrow_table.t) (col_name : string) (scalar : int) : Arrow_table.t option =
  int_scalar_op_to_table t col_name scalar ( * )
    Arrow_ffi.arrow_compute_multiply_scalar
    (fun table name scalar_value -> column_scalar_op table name scalar_value ( *. ))

(** Subtract a scalar from every element of a named column.
      Uses Arrow Compute 'subtract' kernel when native handle is present. *)
let subtract_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  scalar_op_to_table t col_name scalar
    Arrow_ffi.arrow_compute_subtract_scalar
    (fun table name scalar_value -> column_scalar_op table name scalar_value ( -. ))

(** Subtract an integer scalar from every element of a named column,
    preserving Int64 output when the source column is integral. *)
let subtract_int_scalar (t : Arrow_table.t) (col_name : string) (scalar : int) : Arrow_table.t option =
  int_scalar_op_to_table t col_name scalar ( - )
    Arrow_ffi.arrow_compute_subtract_scalar
    (fun table name scalar_value -> column_scalar_op table name scalar_value ( -. ))

(** Divide every element of a named column by a scalar.
      Uses Arrow Compute 'divide' kernel when native handle is present. *)
let divide_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  scalar_op_to_table t col_name scalar
    Arrow_ffi.arrow_compute_divide_scalar
    (fun table name scalar_value -> column_scalar_op table name scalar_value ( /. ))

(* ===================================================================== *)
(* Column-to-Column Arithmetic (Vectorized Processing)                    *)
(* ===================================================================== *)

(** Apply a binary operation element-wise between two named columns.
    Operates directly on column_data arrays to avoid per-row boxing.
    Returns Some(column_data) suitable for adding to a table. *)
let column_binary_op (t : Arrow_table.t) (col1 : string) (col2 : string)
    (op : float -> float -> float) : Arrow_table.column_data option =
  match Arrow_table.get_column t col1, Arrow_table.get_column t col2 with
  | Some (Arrow_table.FloatColumn a1), Some (Arrow_table.FloatColumn a2) ->
    let n = min (Array.length a1) (Array.length a2) in
    let result = Array.init n (fun i ->
      match a1.(i), a2.(i) with
      | Some f1, Some f2 -> Some (op f1 f2)
      | _ -> None
    ) in
    Some (Arrow_table.FloatColumn result)
  | Some (Arrow_table.IntColumn a1), Some (Arrow_table.FloatColumn a2) ->
    let n = min (Array.length a1) (Array.length a2) in
    let result = Array.init n (fun i ->
      match a1.(i), a2.(i) with
      | Some i1, Some f2 -> Some (op (float_of_int i1) f2)
      | _ -> None
    ) in
    Some (Arrow_table.FloatColumn result)
  | Some (Arrow_table.FloatColumn a1), Some (Arrow_table.IntColumn a2) ->
    let n = min (Array.length a1) (Array.length a2) in
    let result = Array.init n (fun i ->
      match a1.(i), a2.(i) with
      | Some f1, Some i2 -> Some (op f1 (float_of_int i2))
      | _ -> None
    ) in
    Some (Arrow_table.FloatColumn result)
  | Some (Arrow_table.IntColumn a1), Some (Arrow_table.IntColumn a2) ->
    let n = min (Array.length a1) (Array.length a2) in
    let result = Array.init n (fun i ->
      match a1.(i), a2.(i) with
      | Some i1, Some i2 -> Some (op (float_of_int i1) (float_of_int i2))
      | _ -> None
    ) in
    Some (Arrow_table.FloatColumn result)
  | _ -> None

(** Add two columns element-wise: result[i] = col1[i] + col2[i] *)
let add_columns (t : Arrow_table.t) (col1 : string) (col2 : string) : Arrow_table.column_data option =
  column_binary_op t col1 col2 ( +. )

(** Multiply two columns element-wise: result[i] = col1[i] * col2[i] *)
let multiply_columns (t : Arrow_table.t) (col1 : string) (col2 : string) : Arrow_table.column_data option =
  column_binary_op t col1 col2 ( *. )

(** Subtract two columns element-wise: result[i] = col1[i] - col2[i] *)
let subtract_columns (t : Arrow_table.t) (col1 : string) (col2 : string) : Arrow_table.column_data option =
  column_binary_op t col1 col2 ( -. )

(** Divide two columns element-wise: result[i] = col1[i] / col2[i]
    Division by zero produces IEEE 754 infinity/NaN, consistent with
    Arrow_compute.divide_scalar and the native Arrow C stubs. *)
let divide_columns (t : Arrow_table.t) (col1 : string) (col2 : string) : Arrow_table.column_data option =
  column_binary_op t col1 col2 ( /. )

(** Apply a column-to-column arithmetic kernel and return a table with the
    computed result column appended.
    Uses the native Arrow implementation when a native handle is present,
    and falls back to the existing pure OCaml column operation otherwise. *)
let column_binary_op_to_table (t : Arrow_table.t) (col1 : string) (col2 : string)
    (result_name : string)
    (native_fn : nativeint -> string -> string -> string -> nativeint option)
    (ocaml_fn : Arrow_table.t -> string -> string -> Arrow_table.column_data option)
    : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match native_fn handle.ptr col1 col2 result_name with
       | Some new_ptr ->
            let schema = schema_from_native_ptr new_ptr in
            let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
            Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None ->
           (match ocaml_fn t col1 col2 with
            | Some col_data -> Some (add_computed_column t result_name col_data)
            | None -> None))
  | _ ->
      (match ocaml_fn t col1 col2 with
       | Some col_data -> Some (add_computed_column t result_name col_data)
       | None -> None)

let add_columns_to_table (t : Arrow_table.t) (col1 : string) (col2 : string)
    (result_name : string) : Arrow_table.t option =
  column_binary_op_to_table t col1 col2 result_name
    Arrow_ffi.arrow_compute_add_columns add_columns

let multiply_columns_to_table (t : Arrow_table.t) (col1 : string) (col2 : string)
    (result_name : string) : Arrow_table.t option =
  column_binary_op_to_table t col1 col2 result_name
    Arrow_ffi.arrow_compute_multiply_columns multiply_columns

let subtract_columns_to_table (t : Arrow_table.t) (col1 : string) (col2 : string)
    (result_name : string) : Arrow_table.t option =
  column_binary_op_to_table t col1 col2 result_name
    Arrow_ffi.arrow_compute_subtract_columns subtract_columns

let divide_columns_to_table (t : Arrow_table.t) (col1 : string) (col2 : string)
    (result_name : string) : Arrow_table.t option =
  column_binary_op_to_table t col1 col2 result_name
    Arrow_ffi.arrow_compute_divide_columns divide_columns

(* ===================================================================== *)
(* Group-By & Aggregation (Phase 3)                                      *)
(* =====================================================================  *)

(** Opaque handle to a native GroupedTable (C struct).
    Wrapped with a GC finalizer for memory safety. *)
type grouped_handle = {
  ptr : nativeint;
  mutable freed : bool;
}

(** Grouped table — stores pre-computed group information.
    When native_handle is Some, the grouping was performed natively
    via Arrow FFI. Otherwise, the pure OCaml fallback stores groups
    as (key_string, row_indices) pairs. *)
type grouped_table = {
  base_table : Arrow_table.t;
  group_keys : string list;
  native_group : grouped_handle option;
  (* Pure OCaml fallback: list of (composite_key, row_indices) *)
  ocaml_groups : ((string * int list) list) option ref;
}

(** Register a GC finalizer for a native grouped table handle *)
let register_group_finalizer (handle : grouped_handle) : unit =
  Gc.finalise (fun h ->
    if not h.freed then begin
      Arrow_ffi.arrow_grouped_table_free h.ptr;
      h.freed <- true
    end
  ) handle

(** Group a table by key columns.
    Uses native Arrow hash grouping when a native handle is present.
    Falls back to pure OCaml hash-based grouping otherwise. *)
let rec group_by (t : Arrow_table.t) (keys : string list) : grouped_table =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
       (match Arrow_ffi.arrow_table_group_by handle.ptr keys with
        | Some gptr ->
            let gh = { ptr = gptr; freed = false } in
            register_group_finalizer gh;
            { base_table = t; group_keys = keys;
              native_group = Some gh; ocaml_groups = ref None }
        | None ->
            (* Native grouping failed — use pure OCaml result *)
            group_by_ocaml t keys)
  | _ ->
      group_by_ocaml t keys

(** Pure OCaml group-by implementation *)
and group_by_ocaml (t : Arrow_table.t) (keys : string list) : grouped_table =
  let groups = build_ocaml_groups t keys in
  { base_table = t; group_keys = keys;
    native_group = None; ocaml_groups = ref (Some groups) }

(** Build the pure OCaml group list used by grouped fallbacks. *)
and build_ocaml_groups (t : Arrow_table.t) (keys : string list) : (string * int list) list =
  let nrows = Arrow_table.num_rows t in
  (* Get key column values *)
  let key_col_values = List.map (fun k ->
    match Arrow_table.get_column t k with
    | Some col -> Arrow_bridge.column_to_values col
    | None -> Array.make nrows Ast.VNull
  ) keys in
  let group_map = Hashtbl.create 16 in
  let group_order = ref [] in
  for i = 0 to nrows - 1 do
    let key_vals = List.map (fun col -> col.(i)) key_col_values in
    let key_str = String.concat "|" (List.map Ast.Utils.value_to_string key_vals) in
    let existing = try Hashtbl.find group_map key_str with Not_found -> [] in
    if existing = [] then
      group_order := key_str :: !group_order;
    (* Prepend for O(1) insertion; reverse per-group lists at the end *)
    Hashtbl.replace group_map key_str (i :: existing)
  done;
  let groups = List.rev_map (fun k ->
    (k, List.rev (Hashtbl.find group_map k))
  ) !group_order in
  (* Sort groups by key values to match R's group_by ordering *)
  let compare_value a b =
    match (a, b) with
    | (Ast.VInt x, Ast.VInt y) -> compare x y
    | (Ast.VFloat x, Ast.VFloat y) -> compare x y
    | (Ast.VInt x, Ast.VFloat y) -> compare (float_of_int x) y
    | (Ast.VFloat x, Ast.VInt y) -> compare x (float_of_int y)
    | (Ast.VString x, Ast.VString y) -> String.compare x y
    | (Ast.VBool x, Ast.VBool y) -> compare x y
    | (Ast.VNA _, _) -> 1
    | (_, Ast.VNA _) -> -1
    | _ -> 0
  in
  let sorted_groups = List.sort (fun (_, indices_a) (_, indices_b) ->
    match indices_a, indices_b with
    | (a_first :: _, b_first :: _) ->
      let rec cmp cols =
        match cols with
        | [] -> 0
        | col :: rest ->
          let c = compare_value col.(a_first) col.(b_first) in
          if c <> 0 then c else cmp rest
      in
      cmp key_col_values
    | ([], _) -> -1
    | (_, []) -> 1
  ) groups in
  sorted_groups

(** Materialize the OCaml group list on demand for grouped fallbacks.
    The current evaluator uses grouped tables on a single thread, so caching
    this fallback in-place avoids repeated regrouping without extra
    synchronization. *)
let get_ocaml_groups (grouped : grouped_table) : (string * int list) list =
  match !(grouped.ocaml_groups) with
  | Some groups -> groups
  | None ->
      let groups = build_ocaml_groups grouped.base_table grouped.group_keys in
      grouped.ocaml_groups := Some groups;
      groups

(** Whether the OCaml fallback groups have already been materialized. *)
let ocaml_groups_materialized (grouped : grouped_table) : bool =
  match !(grouped.ocaml_groups) with
  | Some _ -> true
  | None -> false

(** Apply an aggregation to a grouped table.
    agg_name: "sum", "mean", or "count"
    col_name: target column for sum/mean (ignored for count)
    Returns a new table with key columns + aggregated value column. *)
let rec group_aggregate (grouped : grouped_table) (agg_name : string) (col_name : string) : Arrow_table.t =
  match grouped.native_group with
  | Some gh when not gh.freed ->
      let result_ptr = match agg_name with
        | "sum" -> Arrow_ffi.arrow_group_sum gh.ptr col_name
        | "mean" -> Arrow_ffi.arrow_group_mean gh.ptr col_name
        | "count" -> Arrow_ffi.arrow_group_count gh.ptr
        | "min" -> Arrow_ffi.arrow_group_min gh.ptr col_name
        | "max" -> Arrow_ffi.arrow_group_max gh.ptr col_name
        | "count_distinct" -> Arrow_ffi.arrow_group_count_distinct gh.ptr col_name
        | _ -> None
      in
      (match result_ptr with
       | Some ptr ->
           let schema = schema_from_native_ptr ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows ptr in
           Arrow_table.create_from_native ptr schema nrows
       | None ->
           (* Native aggregation failed — fall back to pure OCaml *)
           group_aggregate_ocaml grouped agg_name col_name)
  | _ ->
      group_aggregate_ocaml grouped agg_name col_name

(** Pure OCaml group aggregation fallback *)
and group_aggregate_ocaml (grouped : grouped_table) (agg_name : string) (col_name : string) : Arrow_table.t =
  let ocaml_groups = get_ocaml_groups grouped in
  let n_groups = List.length ocaml_groups in
  let t = grouped.base_table in
  (* Convert to arrays for O(1) indexed access instead of O(n) List.nth *)
  let groups_array = Array.of_list ocaml_groups in
  (* Build key columns *)
  let key_col_values = List.map (fun k ->
    match Arrow_table.get_column t k with
    | Some col -> Arrow_bridge.column_to_values col
    | None -> Array.make (Arrow_table.num_rows t) Ast.VNull
  ) grouped.group_keys in
  let key_col_array = Array.of_list key_col_values in
  let key_result_cols = List.mapi (fun ki k ->
    let key_vals = key_col_array.(ki) in
    let col = Array.init n_groups (fun g_idx ->
      let (_, indices) = groups_array.(g_idx) in
      match indices with
      | first :: _ -> key_vals.(first)
      | [] -> Ast.VNull
    ) in
    (k, col)
  ) grouped.group_keys in
  (* Get target column values for aggregation *)
  let target_vals = match Arrow_table.get_column t col_name with
    | Some col -> Arrow_bridge.column_to_values col
    | None -> Array.make (Arrow_table.num_rows t) Ast.VNull
  in
  (* Compute aggregation per group *)
  let agg_col_name =
    match agg_name with
    | "count" -> "n"
    | _ -> col_name
  in
  let agg_col = Array.init n_groups (fun g_idx ->
    let (_, indices) = groups_array.(g_idx) in
    match agg_name with
    | "sum" ->
        let sum = List.fold_left (fun acc i ->
          match target_vals.(i) with
          | Ast.VFloat f -> acc +. f
          | Ast.VInt n -> acc +. float_of_int n
          | _ -> acc
        ) 0.0 indices in
        Ast.VFloat sum
    | "mean" ->
        let sum = ref 0.0 in
        let count = ref 0 in
        List.iter (fun i ->
          match target_vals.(i) with
          | Ast.VFloat f -> sum := !sum +. f; incr count
          | Ast.VInt n -> sum := !sum +. float_of_int n; incr count
          | _ -> ()
        ) indices;
        if !count > 0 then Ast.VFloat (!sum /. float_of_int !count)
        else Ast.VNA Ast.NAFloat
    | "count" ->
        Ast.VInt (List.length indices)
    | "count_distinct" ->
        let seen = Value_hash.ValueHash.create (max 1 (min 64 (List.length indices))) in
        List.iter (fun i -> Value_hash.ValueHash.replace seen target_vals.(i) ()) indices;
        Ast.VInt (Value_hash.ValueHash.length seen)
    | "min" ->
        let m = ref None in
        List.iter (fun i ->
          let v = match target_vals.(i) with
            | Ast.VFloat f -> Some f
            | Ast.VInt n -> Some (float_of_int n)
            | _ -> None
          in
          match !m, v with
          | None, Some f -> m := Some f
          | Some current, Some f -> if f < current then m := Some f
          | _ -> ()
        ) indices;
        (match !m with Some f -> Ast.VFloat f | None -> Ast.VNA Ast.NAFloat)
    | "max" ->
        let m = ref None in
        List.iter (fun i ->
          let v = match target_vals.(i) with
            | Ast.VFloat f -> Some f
            | Ast.VInt n -> Some (float_of_int n)
            | _ -> None
          in
          match !m, v with
          | None, Some f -> m := Some f
          | Some current, Some f -> if f > current then m := Some f
          | _ -> ()
        ) indices;
        (match !m with Some f -> Ast.VFloat f | None -> Ast.VNA Ast.NAFloat)
    | _ -> Ast.VNull
  ) in
  let all_columns = key_result_cols @ [(agg_col_name, agg_col)] in
  Arrow_bridge.table_from_value_columns all_columns n_groups

(** Compute multiple aggregations in a single call.
    specs: list of (agg_name, col_name, result_name) triples.
    Builds key columns only once, avoiding redundant work when the
    single-aggregate path is called N times.
    Falls back to None when the native multi_aggregate FFI is unavailable
    or fails, letting callers fall back to sequential group_aggregate. *)
let group_multi_aggregate (grouped : grouped_table)
    (specs : (string * string * string) list) : Arrow_table.t option =
  match grouped.native_group with
  | Some gh when not gh.freed ->
    let agg_types = List.map (fun (a, _, _) -> a) specs in
    let col_names = List.map (fun (_, c, _) -> c) specs in
    let result_names = List.map (fun (_, _, r) -> r) specs in
    (match Arrow_ffi.arrow_group_multi_aggregate gh.ptr agg_types col_names result_names with
     | Some ptr ->
       let schema = schema_from_native_ptr ptr in
       let nrows = Arrow_ffi.arrow_table_num_rows ptr in
       Some (Arrow_table.create_from_native ptr schema nrows)
     | None -> None)
  | _ -> None

(* ===================================================================== *)
(* Unary Math Operations (Phase 5 — Week 1)                              *)
(* ===================================================================== *)

(** Helper: apply a unary float function to every element of a named column.
    Uses native Arrow compute when available, else pure OCaml fallback. *)
let apply_unary_math_column (t : Arrow_table.t) (col_name : string)
    (native_fn : nativeint -> string -> nativeint option)
    (ocaml_fn : float -> float) : Arrow_table.t option =
  (* Try native Arrow path first *)
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
    (match native_fn handle.ptr col_name with
     | Some new_ptr ->
       let schema = schema_from_native_ptr new_ptr in
       let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
       Some (Arrow_table.create_from_native new_ptr schema nrows)
     | None -> None)
  | _ ->
    (* Pure OCaml fallback: apply function element-by-element *)
    match Arrow_table.get_column t col_name with
    | None -> None
    | Some col ->
      let values = Arrow_bridge.column_to_values col in
      let new_values = Array.map (fun v ->
        match v with
        | Ast.VFloat f -> Ast.VFloat (ocaml_fn f)
        | Ast.VInt i -> Ast.VFloat (ocaml_fn (float_of_int i))
        | Ast.VNA _ as na -> na
        | _ -> v
      ) values in
      let new_col = Arrow_bridge.values_to_column new_values in
      Some (Arrow_table.add_column t col_name new_col)

(** Apply sqrt to every element of a named numeric column. *)
let sqrt_column (t : Arrow_table.t) (col_name : string) : Arrow_table.t option =
  apply_unary_math_column t col_name Arrow_ffi.arrow_compute_sqrt_column sqrt

(** Apply abs to every element of a named numeric column. *)
let abs_column (t : Arrow_table.t) (col_name : string) : Arrow_table.t option =
  apply_unary_math_column t col_name Arrow_ffi.arrow_compute_abs_column abs_float

(** Apply natural log to every element of a named numeric column. *)
let log_column (t : Arrow_table.t) (col_name : string) : Arrow_table.t option =
  apply_unary_math_column t col_name Arrow_ffi.arrow_compute_log_column log

(** Apply exp to every element of a named numeric column. *)
let exp_column (t : Arrow_table.t) (col_name : string) : Arrow_table.t option =
  apply_unary_math_column t col_name Arrow_ffi.arrow_compute_exp_column exp

(** Raise every element of a named numeric column to a scalar power. *)
let pow_column (t : Arrow_table.t) (col_name : string) (exponent : float) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
    (match Arrow_ffi.arrow_compute_pow_column handle.ptr col_name exponent with
     | Some new_ptr ->
       let schema = schema_from_native_ptr new_ptr in
       let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
       Some (Arrow_table.create_from_native new_ptr schema nrows)
     | None -> None)
  | _ ->
    match Arrow_table.get_column t col_name with
    | None -> None
    | Some col ->
      let values = Arrow_bridge.column_to_values col in
      let new_values = Array.map (fun v ->
        match v with
        | Ast.VFloat f -> Ast.VFloat (Float.pow f exponent)
        | Ast.VInt i -> Ast.VFloat (Float.pow (float_of_int i) exponent)
        | Ast.VNA _ as na -> na
        | _ -> v
      ) values in
      let new_col = Arrow_bridge.values_to_column new_values in
      Some (Arrow_table.add_column t col_name new_col)

(* ===================================================================== *)
(* Column-Level Aggregations (Phase 5 — Week 1)                          *)
(* ===================================================================== *)

(** Helper: compute a column aggregation with native/OCaml fallback. *)
let column_agg (t : Arrow_table.t) (col_name : string)
    (native_fn : nativeint -> string -> float option)
    (ocaml_fn : float array -> float option) : float option =
  (* Try native Arrow path first *)
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
    (match native_fn handle.ptr col_name with
     | Some _ as result -> result
     | None -> None)
  | _ ->
    (* Pure OCaml fallback *)
    match Arrow_table.get_column t col_name with
    | None -> None
    | Some col ->
      let values = Arrow_bridge.column_to_values col in
      let floats = Array.to_list values |> List.filter_map (fun v ->
        match v with
        | Ast.VFloat f -> Some f
        | Ast.VInt i -> Some (float_of_int i)
        | _ -> None
      ) in
      if floats = [] then None
      else ocaml_fn (Array.of_list floats)

(** Compute the sum of a named numeric column. *)
let sum_column (t : Arrow_table.t) (col_name : string) : float option =
  column_agg t col_name Arrow_ffi.arrow_compute_sum_column
    (fun arr -> Some (Array.fold_left ( +. ) 0.0 arr))

(** Compute the mean of a named numeric column. *)
let mean_column (t : Arrow_table.t) (col_name : string) : float option =
  column_agg t col_name Arrow_ffi.arrow_compute_mean_column
    (fun arr ->
       let n = Array.length arr in
       if n = 0 then None
       else Some (Array.fold_left ( +. ) 0.0 arr /. float_of_int n))

(** Compute the minimum of a named numeric column. *)
let min_column (t : Arrow_table.t) (col_name : string) : float option =
  column_agg t col_name Arrow_ffi.arrow_compute_min_column
    (fun arr ->
       if Array.length arr = 0 then None
       else begin
         let m = ref arr.(0) in
         Array.iter (fun x -> if x < !m then m := x) arr;
         Some !m
       end)

(** Compute the maximum of a named numeric column. *)
let max_column (t : Arrow_table.t) (col_name : string) : float option =
  column_agg t col_name Arrow_ffi.arrow_compute_max_column
    (fun arr ->
       if Array.length arr = 0 then None
       else begin
         let m = ref arr.(0) in
         Array.iter (fun x -> if x > !m then m := x) arr;
         Some !m
       end)

(** Compute the number of distinct values in a named column. *)
let count_distinct_column (t : Arrow_table.t) (col_name : string) : float option =
  match Arrow_table.get_column t col_name with
  | None -> None
  | Some col ->
      let values = Arrow_bridge.column_to_values col in
      let seen = Value_hash.ValueHash.create (max 1 (min 64 (Array.length values))) in
      Array.iter (fun value -> Value_hash.ValueHash.replace seen value ()) values;
      Some (float_of_int (Value_hash.ValueHash.length seen))

(* ===================================================================== *)
(* Comparison Operations (Phase 5 — Week 1)                              *)
(* ===================================================================== *)

(** Compare each element of a named numeric column to a scalar.
    Returns a bool array suitable for use with filter.
    op: "eq", "lt", "gt", "le", "ge" *)
let compare_column_scalar (t : Arrow_table.t) (col_name : string)
    (scalar : float) (op : string) : bool array option =
  let op_code = match op with
    | "eq" -> 0 | "lt" -> 1 | "gt" -> 2 | "le" -> 3 | "ge" -> 4 | _ -> -1
  in
  if op_code < 0 then None
  else
    (* Try native Arrow path first *)
    match t.native_handle with
    | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_compare_scalar handle.ptr col_name scalar op_code with
       | Some _ as result -> result
       | None -> None)
    | _ ->
      (* Pure OCaml fallback *)
      match Arrow_table.get_column t col_name with
      | None -> None
      | Some col ->
        let values = Arrow_bridge.column_to_values col in
        let cmp_fn = match op with
          | "eq" -> ( = ) | "lt" -> ( < ) | "gt" -> ( > )
          | "le" -> ( <= ) | "ge" -> ( >= ) | _ -> ( = )
        in
        Some (Array.map (fun v ->
          match v with
          | Ast.VFloat f -> cmp_fn f scalar
          | Ast.VInt i -> cmp_fn (float_of_int i) scalar
          | _ -> false
        ) values)

(** Return a bool array mask where true means the named column value is null/NA.
    Uses native Arrow validity checks when the table is native-backed. *)
let column_null_mask (t : Arrow_table.t) (col_name : string) : bool array option =
  let is_none = function None -> true | Some _ -> false in
  let ocaml_fallback () =
    match Arrow_table.get_column t col_name with
    | Some (Arrow_table.IntColumn a) ->
        Some (Array.map is_none a)
    | Some (Arrow_table.FloatColumn a) ->
        Some (Array.map is_none a)
    | Some (Arrow_table.BoolColumn a) ->
        Some (Array.map is_none a)
    | Some (Arrow_table.StringColumn a) ->
        Some (Array.map is_none a)
    | Some (Arrow_table.DateColumn a) ->
        Some (Array.map is_none a)
    | Some (Arrow_table.DatetimeColumn (a, _)) ->
        Some (Array.map is_none a)
    | Some (Arrow_table.DictionaryColumn (a, _, _)) ->
        Some (Array.map is_none a)
    | Some (Arrow_table.ListColumn a) ->
        Some (Array.map is_none a)
    | Some (Arrow_table.NullColumn n) ->
        Some (Array.make n true)
    | None -> None
  in
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_column_null_mask handle.ptr col_name with
       | Some _ as result -> result
       | None -> ocaml_fallback ())
  | _ -> ocaml_fallback ()

(* ===================================================================== *)
(* Window Operations (Phase 6 — v0.51.1)                                  *)
(* ===================================================================== *)

(** Compute ranking for a named numeric column using Arrow native kernels.
    rank_type: 0=row_number, 1=min_rank, 2=dense_rank.
    Returns Some(int option array) where None = null position.
    Falls back to None when no native handle is present. *)
let rank_column (t : Arrow_table.t) (col_name : string) (rank_type : int) : int option array option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      Arrow_ffi.arrow_compute_rank handle.ptr col_name rank_type
  | _ -> None

(** Compute dense rank for a named numeric column.
    Shorthand for rank_column with rank_type=2. *)
let dense_rank_column (t : Arrow_table.t) (col_name : string) : int option array option =
  rank_column t col_name 2

(** Compute row_number for a named numeric column.
    Shorthand for rank_column with rank_type=0. *)
let row_number_column (t : Arrow_table.t) (col_name : string) : int option array option =
  rank_column t col_name 0

(** Compute min_rank for a named numeric column.
    Shorthand for rank_column with rank_type=1. *)
let min_rank_column (t : Arrow_table.t) (col_name : string) : int option array option =
  rank_column t col_name 1

(** Lag a numeric column by offset positions using Arrow native kernel.
    Returns Some(new_table) when native path succeeds, None otherwise. *)
let lag_column (t : Arrow_table.t) (col_name : string) (offset : int) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_lag_column handle.ptr col_name offset with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None

(** Lead a numeric column by offset positions using Arrow native kernel.
    Returns Some(new_table) when native path succeeds, None otherwise. *)
let lead_column (t : Arrow_table.t) (col_name : string) (offset : int) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_lead_column handle.ptr col_name offset with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None

(** Optimized group-by for high-cardinality keys.
    Uses pre-sized hash table and numeric fast path when >10k rows with
    all-numeric key columns. Falls back to standard group_by otherwise. *)
let group_by_optimized (t : Arrow_table.t) (keys : string list) : grouped_table =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
       (match Arrow_ffi.arrow_group_by_optimized handle.ptr keys with
        | Some gptr ->
            let gh = { ptr = gptr; freed = false } in
            register_group_finalizer gh;
            { base_table = t; group_keys = keys;
              native_group = Some gh; ocaml_groups = ref None }
        | None ->
            group_by t keys)
  | _ ->
      group_by t keys
