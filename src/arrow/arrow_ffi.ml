(* src/arrow/arrow_ffi.ml *)
(* FFI bindings to Apache Arrow C GLib library.                          *)
(* These bindings will be activated when arrow-glib is available.        *)
(* For now, all operations use the pure OCaml fallback in arrow_table.ml *)
(*                                                                       *)
(* When Arrow C GLib is installed:                                       *)
(*   1. Uncomment the external declarations below                        *)
(*   2. Update src/dune to add (foreign_stubs (language c)               *)
(*        (names arrow_stubs) (flags (:include arrow_cflags.sexp)))      *)
(*   3. Build with: dune build                                           *)

(* --- Future FFI External Declarations --- *)
(* These will be implemented in src/ffi/arrow_stubs.c *)

(* external arrow_table_free : nativeint -> unit
     = "caml_arrow_table_free" *)

(* external arrow_table_num_rows : nativeint -> int
     = "caml_arrow_table_num_rows" *)

(* external arrow_table_num_columns : nativeint -> int
     = "caml_arrow_table_num_columns" *)

(* external arrow_table_get_column_by_name : nativeint -> string -> nativeint option
     = "caml_arrow_table_get_column_by_name" *)

(* external arrow_read_csv : string -> nativeint option
     = "caml_arrow_read_csv" *)

(* external arrow_table_project : nativeint -> string list -> nativeint
     = "caml_arrow_table_project" *)

(* external arrow_table_filter : nativeint -> bool array -> nativeint
     = "caml_arrow_table_filter" *)

(* external arrow_table_sort : nativeint -> string -> bool -> nativeint
     = "caml_arrow_table_sort" *)

(** FFI availability flag — false until Arrow C GLib is linked *)
let arrow_available = false

(** When Arrow FFI becomes available, this will wrap a C pointer *)
type native_table = {
  ptr : nativeint;
  prevent_gc : bool;  (* prevent GC from collecting while in use *)
}

(** Placeholder: create a native table wrapper *)
let _wrap_native_ptr _ptr =
  failwith "Arrow C GLib FFI not yet available. Using pure OCaml fallback."
