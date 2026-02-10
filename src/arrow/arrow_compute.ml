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
           let new_schema = List.filter (fun (n, _) -> List.mem n names) t.schema in
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
  let pairs = Arrow_ffi.arrow_table_get_schema ptr in
  List.map (fun (name, tag) -> (name, Arrow_table.arrow_type_of_tag tag)) pairs

(** Add a scalar to every element of a named column.
    Uses Arrow Compute 'add' kernel when native handle is present. *)
let add_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_add_scalar handle.ptr col_name scalar with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None

(** Multiply every element of a named column by a scalar.
    Uses Arrow Compute 'multiply' kernel when native handle is present. *)
let multiply_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_multiply_scalar handle.ptr col_name scalar with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None

(** Subtract a scalar from every element of a named column.
    Uses Arrow Compute 'subtract' kernel when native handle is present. *)
let subtract_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_subtract_scalar handle.ptr col_name scalar with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None

(** Divide every element of a named column by a scalar.
    Uses Arrow Compute 'divide' kernel when native handle is present. *)
let divide_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_divide_scalar handle.ptr col_name scalar with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None

(* ===================================================================== *)
(* Group-By & Aggregation (Phase 3)                                      *)
(* ===================================================================== *)

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
  ocaml_groups : (string * int list) list;
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
    Falls back to pure OCaml hash-based grouping otherwise.
    Always populates ocaml_groups for compatibility with summarize.ml. *)
let rec group_by (t : Arrow_table.t) (keys : string list) : grouped_table =
  (* Always compute OCaml groups for backward compatibility *)
  let ocaml_result = group_by_ocaml t keys in
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_table_group_by handle.ptr keys with
       | Some gptr ->
           let gh = { ptr = gptr; freed = false } in
           register_group_finalizer gh;
           { ocaml_result with native_group = Some gh }
       | None ->
           (* Native grouping failed — use pure OCaml result *)
           ocaml_result)
  | _ ->
      ocaml_result

(** Pure OCaml group-by implementation *)
and group_by_ocaml (t : Arrow_table.t) (keys : string list) : grouped_table =
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
  { base_table = t; group_keys = keys;
    native_group = None; ocaml_groups = sorted_groups }

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
  let n_groups = List.length grouped.ocaml_groups in
  let t = grouped.base_table in
  (* Build key columns *)
  let key_col_values = List.map (fun k ->
    match Arrow_table.get_column t k with
    | Some col -> Arrow_bridge.column_to_values col
    | None -> Array.make (Arrow_table.num_rows t) Ast.VNull
  ) grouped.group_keys in
  let key_result_cols = List.mapi (fun ki k ->
    let key_vals = List.nth key_col_values ki in
    let col = Array.init n_groups (fun g_idx ->
      let (_, indices) = List.nth grouped.ocaml_groups g_idx in
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
  let agg_col_name = if agg_name = "count" then "n" else col_name in
  let agg_col = Array.init n_groups (fun g_idx ->
    let (_, indices) = List.nth grouped.ocaml_groups g_idx in
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
        Ast.VFloat (float_of_int (List.length indices))
    | _ -> Ast.VNull
  ) in
  let all_columns = key_result_cols @ [(agg_col_name, agg_col)] in
  Arrow_bridge.table_from_value_columns all_columns n_groups

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
