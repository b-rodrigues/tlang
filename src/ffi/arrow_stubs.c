/* src/ffi/arrow_stubs.c */
/* C FFI stubs for Apache Arrow C GLib integration.                       */
/* These stubs bridge OCaml to the Arrow C GLib (GObject-based) library.  */
/*                                                                        */
/* DEPENDENCIES: arrow-glib (pkg-config: arrow-glib)                      */
/*   Install via: nix develop (flake.nix includes arrow-glib)             */

#include <arrow-glib/arrow-glib.h>
#include <parquet-glib/parquet-glib.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/bigarray.h>
#include <math.h>

/* ===================================================================== */
/* Memory Management                                                     */
/* ===================================================================== */

/* Free Arrow table when OCaml GC collects it */
CAMLprim value caml_arrow_table_free(value v_ptr) {
  CAMLparam1(v_ptr);
  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  if (table != NULL) {
    g_object_unref(table);
  }
  CAMLreturn(Val_unit);
}

/* ===================================================================== */
/* Table Queries                                                         */
/* ===================================================================== */

/* Get number of rows */
CAMLprim value caml_arrow_table_num_rows(value v_ptr) {
  CAMLparam1(v_ptr);
  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  gint64 nrows = garrow_table_get_n_rows(table);
  CAMLreturn(Val_int(nrows));
}

/* Get number of columns */
CAMLprim value caml_arrow_table_num_columns(value v_ptr) {
  CAMLparam1(v_ptr);
  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  guint ncols = garrow_table_get_n_columns(table);
  CAMLreturn(Val_int(ncols));
}

/* ===================================================================== */
/* Schema Extraction                                                     */
/* ===================================================================== */

/* Get schema as list of (name, type_tag) pairs.
   type_tag: 0=Int64, 1=Float64, 2=Boolean, 3=String,
             4=Dictionary, 5=List, 6=Null, 7=Date */
CAMLprim value caml_arrow_table_get_schema(value v_ptr) {
  CAMLparam1(v_ptr);
  CAMLlocal3(v_result, v_col, v_cons);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  GArrowSchema *schema = garrow_table_get_schema(table);
  guint ncols = garrow_schema_n_fields(schema);

  /* Build OCaml list of (name, type_tag) pairs — build in reverse then reverse */
  v_result = Val_emptylist;
  for (gint i = ncols - 1; i >= 0; i--) {
    GArrowField *field = garrow_schema_get_field(schema, i);
    const gchar *name = garrow_field_get_name(field);
    GArrowDataType *dtype = garrow_field_get_data_type(field);

    /* Map Arrow type to T arrow_type tag */
    int type_tag;
    if (GARROW_IS_INT8_DATA_TYPE(dtype) || GARROW_IS_INT16_DATA_TYPE(dtype) ||
        GARROW_IS_INT32_DATA_TYPE(dtype) || GARROW_IS_INT64_DATA_TYPE(dtype) ||
        GARROW_IS_UINT8_DATA_TYPE(dtype) || GARROW_IS_UINT16_DATA_TYPE(dtype) ||
        GARROW_IS_UINT32_DATA_TYPE(dtype) || GARROW_IS_UINT64_DATA_TYPE(dtype))
                                                  type_tag = 0; /* ArrowInt64 */
    else if (GARROW_IS_DOUBLE_DATA_TYPE(dtype))   type_tag = 1; /* ArrowFloat64 */
    else if (GARROW_IS_BOOLEAN_DATA_TYPE(dtype))  type_tag = 2; /* ArrowBoolean */
    else if (GARROW_IS_STRING_DATA_TYPE(dtype) ||
             GARROW_IS_LARGE_STRING_DATA_TYPE(dtype))
                                                  type_tag = 3; /* ArrowString */
    else if (GARROW_IS_DICTIONARY_DATA_TYPE(dtype))
                                                  type_tag = 4; /* ArrowDictionary */
    else if (GARROW_IS_LIST_DATA_TYPE(dtype))     type_tag = 5; /* ArrowList */
    else if (GARROW_IS_DATE32_DATA_TYPE(dtype) ||
             GARROW_IS_DATE64_DATA_TYPE(dtype))   type_tag = 7; /* ArrowDate */
    else                                          type_tag = 6; /* ArrowNull */

    /* Create tuple (name, type_tag) */
    v_col = caml_alloc(2, 0);
    Store_field(v_col, 0, caml_copy_string(name));
    Store_field(v_col, 1, Val_int(type_tag));

    /* Cons onto list */
    v_cons = caml_alloc(2, 0);
    Store_field(v_cons, 0, v_col);
    Store_field(v_cons, 1, v_result);
    v_result = v_cons;

    /* dtype and field are full transfers but unreffing here might be problematic if they are cached?
       Actually, documentation says they are full. Keeping unref for field but removing for dtype for now. */
    g_object_unref(field);
  }

  g_object_unref(schema);
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Column Data Extraction                                                */
/* ===================================================================== */

/* Get a column's combined array pointer by name.
   For multi-chunk columns, combines all chunks into a single contiguous
   array so that column reading functions receive complete data.
   Returns Some(nativeint) or None. */
CAMLprim value caml_arrow_table_get_column_data_by_name(value v_ptr, value v_col_name) {
  CAMLparam2(v_ptr, v_col_name);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *col_name = String_val(v_col_name);

  /* Use schema to find column index by name */
  GArrowSchema *schema = garrow_table_get_schema(table);
  gint idx = garrow_schema_get_field_index(schema, col_name);
  g_object_unref(schema);

  if (idx < 0) {
    CAMLreturn(Val_none);
  }

  GArrowChunkedArray *chunked = garrow_table_get_column_data(table, idx);
  if (chunked == NULL) {
    CAMLreturn(Val_none);
  }

  guint n_chunks = garrow_chunked_array_get_n_chunks(chunked);
  if (n_chunks == 0) {
    g_object_unref(chunked);
    CAMLreturn(Val_none);
  }

  GArrowArray *array = NULL;

  if (n_chunks == 1) {
    array = garrow_chunked_array_get_chunk(chunked, 0);
    /* garrow_chunked_array_get_chunk returns a new reference (transfer full)
       according to some versions, but let's check. If it was double-reffed,
       it would leak. If it was borrowed, we need this ref.
       Given the CRITICAL errors, we are unreffing too much somewhere. */
    if (array) g_object_ref(array);
  } else {
    GError *error = NULL;
    GArrowArray *combined = garrow_chunked_array_combine(chunked, &error);
    if (combined != NULL) {
      array = combined;
    } else {
      if (error) g_error_free(error);
      array = garrow_chunked_array_get_chunk(chunked, 0);
      if (array) g_object_ref(array);
    }
  }

  g_object_unref(chunked);

  if (array == NULL) {
    CAMLreturn(Val_none);
  }

  v_result = caml_alloc(1, 0); /* Some(...) */
  Store_field(v_result, 0, caml_copy_nativeint((intnat)array));

  /* Note: the returned GArrowArray* has one reference.
     Column reading functions (caml_arrow_read_*_column) are responsible
     for calling g_object_unref(array) after copying data.
     Zero-copy bigarray functions intentionally do NOT unref, keeping
     the array alive for the lifetime of the bigarray view. */
  CAMLreturn(v_result);
}

/* Read an Int64 column into an OCaml int option array.
   The caller-supplied GArrowArray* is unreffed after data is fully copied
   into the OCaml heap, preventing the reference leak from
   garrow_chunked_array_get_chunk(). */
CAMLprim value caml_arrow_read_int64_column(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal2(v_result, v_some);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  gint64 length = garrow_array_get_length(array);

  v_result = caml_alloc(length, 0);

  GArrowInt64Array *int64_array = GARROW_IS_INT64_ARRAY(array) ? GARROW_INT64_ARRAY(array) : NULL;
  GArrowInt32Array *int32_array = GARROW_IS_INT32_ARRAY(array) ? GARROW_INT32_ARRAY(array) : NULL;
  GArrowInt16Array *int16_array = GARROW_IS_INT16_ARRAY(array) ? GARROW_INT16_ARRAY(array) : NULL;
  GArrowInt8Array  *int8_array  = GARROW_IS_INT8_ARRAY(array)  ? GARROW_INT8_ARRAY(array)  : NULL;
  GArrowUInt64Array *uint64_array = GARROW_IS_UINT64_ARRAY(array) ? GARROW_UINT64_ARRAY(array) : NULL;
  GArrowUInt32Array *uint32_array = GARROW_IS_UINT32_ARRAY(array) ? GARROW_UINT32_ARRAY(array) : NULL;
  GArrowUInt16Array *uint16_array = GARROW_IS_UINT16_ARRAY(array) ? GARROW_UINT16_ARRAY(array) : NULL;
  GArrowUInt8Array  *uint8_array  = GARROW_IS_UINT8_ARRAY(array)  ? GARROW_UINT8_ARRAY(array)  : NULL;

  for (gint64 i = 0; i < length; i++) {
    if (garrow_array_is_null(array, i)) {
      Store_field(v_result, i, Val_none);
    } else {
      gint64 val = 0;
      if (int64_array)      val = garrow_int64_array_get_value(int64_array, i);
      else if (int32_array) val = garrow_int32_array_get_value(int32_array, i);
      else if (int16_array) val = garrow_int16_array_get_value(int16_array, i);
      else if (int8_array)  val = garrow_int8_array_get_value(int8_array, i);
      else if (uint64_array) {
        guint64 u = garrow_uint64_array_get_value(uint64_array, i);
        val = (u > (guint64)G_MAXINT64) ? G_MAXINT64 : (gint64)u;
      }
      else if (uint32_array) val = (gint64)garrow_uint32_array_get_value(uint32_array, i);
      else if (uint16_array) val = (gint64)garrow_uint16_array_get_value(uint16_array, i);
      else if (uint8_array)  val = (gint64)garrow_uint8_array_get_value(uint8_array, i);

      v_some = caml_alloc(1, 0); /* Some(...) */
      Store_field(v_some, 0, Val_long(val));
      Store_field(v_result, i, v_some);
    }
  }

  /* Release the reference obtained from garrow_chunked_array_get_chunk().
     The parent GArrowTable still holds its own reference chain
     (table → chunked_array → chunk), so the underlying data remains alive. */
  g_object_unref(array);
  CAMLreturn(v_result);
}

/* Read a Float64 (double) column into an OCaml float option array.
   Unrefs the GArrowArray after copying all data. */
CAMLprim value caml_arrow_read_float64_column(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal2(v_result, v_some);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  gint64 length = garrow_array_get_length(array);

  v_result = caml_alloc(length, 0);

  GArrowDoubleArray *dbl_array = GARROW_DOUBLE_ARRAY(array);
  for (gint64 i = 0; i < length; i++) {
    if (garrow_array_is_null(array, i)) {
      Store_field(v_result, i, Val_none);
    } else {
      gdouble val = garrow_double_array_get_value(dbl_array, i);
      v_some = caml_alloc(1, 0); /* Some(...) */
      Store_field(v_some, 0, caml_copy_double(val));
      Store_field(v_result, i, v_some);
    }
  }

  g_object_unref(array);
  CAMLreturn(v_result);
}

/* Read a Boolean column into an OCaml bool option array.
   Unrefs the GArrowArray after copying all data. */
CAMLprim value caml_arrow_read_boolean_column(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal2(v_result, v_some);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  gint64 length = garrow_array_get_length(array);

  v_result = caml_alloc(length, 0);

  GArrowBooleanArray *bool_array = GARROW_BOOLEAN_ARRAY(array);
  for (gint64 i = 0; i < length; i++) {
    if (garrow_array_is_null(array, i)) {
      Store_field(v_result, i, Val_none);
    } else {
      gboolean val = garrow_boolean_array_get_value(bool_array, i);
      v_some = caml_alloc(1, 0); /* Some(...) */
      Store_field(v_some, 0, Val_bool(val));
      Store_field(v_result, i, v_some);
    }
  }

  g_object_unref(array);
  CAMLreturn(v_result);
}

/* Read a String column into an OCaml string option array.
   Unrefs the GArrowArray after copying all data. */
CAMLprim value caml_arrow_read_string_column(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal2(v_result, v_some);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  gint64 length = garrow_array_get_length(array);

  v_result = caml_alloc(length, 0);

  GArrowStringArray *str_array = GARROW_IS_STRING_ARRAY(array) ? GARROW_STRING_ARRAY(array) : NULL;
  GArrowLargeStringArray *lstr_array = GARROW_IS_LARGE_STRING_ARRAY(array) ? GARROW_LARGE_STRING_ARRAY(array) : NULL;

  for (gint64 i = 0; i < length; i++) {
    if (garrow_array_is_null(array, i)) {
      Store_field(v_result, i, Val_none);
    } else {
      gchar *val = NULL;
      if (str_array) val = garrow_string_array_get_string(str_array, i);
      else if (lstr_array) val = garrow_large_string_array_get_string(lstr_array, i);

      if (val) {
        v_some = caml_alloc(1, 0); /* Some(...) */
        Store_field(v_some, 0, caml_copy_string(val));
        g_free(val);
        Store_field(v_result, i, v_some);
      } else {
        Store_field(v_result, i, Val_none);
      }
    }
  }

  g_object_unref(array);
  CAMLreturn(v_result);
}

/* Read a Date32 (or Date64) column into an OCaml int option array.
   Date32 stores days since epoch (1970-01-01).
   Date64 stores milliseconds since epoch, which we convert to days.
   Unrefs the GArrowArray after copying all data. */
CAMLprim value caml_arrow_read_date32_column(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal2(v_result, v_some);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  gint64 length = garrow_array_get_length(array);

  v_result = caml_alloc(length, 0);

  GArrowDate32Array *date32_array = GARROW_IS_DATE32_ARRAY(array) ? GARROW_DATE32_ARRAY(array) : NULL;
  GArrowDate64Array *date64_array = GARROW_IS_DATE64_ARRAY(array) ? GARROW_DATE64_ARRAY(array) : NULL;

  for (gint64 i = 0; i < length; i++) {
    if (garrow_array_is_null(array, i)) {
      Store_field(v_result, i, Val_none);
    } else {
      gint32 days = 0;
      if (date32_array) {
        days = garrow_date32_array_get_value(date32_array, i);
      } else if (date64_array) {
        gint64 millis = garrow_date64_array_get_value(date64_array, i);
        /* Date64 stores midnight-aligned milliseconds; floor to days.
           Arrow spec requires Date64 values to be multiples of 86400000,
           so truncation == floor for well-formed data. */
        days = (gint32)(millis / 86400000LL);
      }
      v_some = caml_alloc(1, 0); /* Some(...) */
      Store_field(v_some, 0, Val_long(days));
      Store_field(v_result, i, v_some);
    }
  }

  g_object_unref(array);
  CAMLreturn(v_result);
}

/* Read a Dictionary (factor) column into an OCaml tuple:
   (int option array * string list * bool)
   - indices: 0-based index into levels for each row (None for NA)
   - levels: list of unique level strings
   - ordered: read from GArrowDictionaryDataType's ordered property
   Unrefs the GArrowArray after copying all data. */
CAMLprim value caml_arrow_read_dictionary_column(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal5(v_result, v_indices, v_some, v_levels, v_cons);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);

  if (!GARROW_IS_DICTIONARY_ARRAY(array)) {
    /* Not a dictionary array — return empty result */
    v_indices = caml_alloc(0, 0);
    v_levels = Val_emptylist;
    v_result = caml_alloc(3, 0);
    Store_field(v_result, 0, v_indices);
    Store_field(v_result, 1, v_levels);
    Store_field(v_result, 2, Val_bool(0));
    g_object_unref(array);
    CAMLreturn(v_result);
  }

  GArrowDictionaryArray *dict_array = GARROW_DICTIONARY_ARRAY(array);
  gint64 length = garrow_array_get_length(array);

  /* Read ordered flag from the Arrow dictionary data type */
  GArrowDataType *arr_dtype = garrow_array_get_value_data_type(array);
  gboolean ordered = FALSE;
  if (GARROW_IS_DICTIONARY_DATA_TYPE(arr_dtype)) {
    ordered = garrow_dictionary_data_type_is_ordered(
      GARROW_DICTIONARY_DATA_TYPE(arr_dtype));
  }
  g_object_unref(arr_dtype);

  /* Extract dictionary (levels) — only string dictionaries are supported */
  GArrowArray *dictionary = garrow_dictionary_array_get_dictionary(dict_array);
  gint64 n_levels = garrow_array_get_length(dictionary);

  if (!GARROW_IS_STRING_ARRAY(dictionary) && !GARROW_IS_LARGE_STRING_ARRAY(dictionary)) {
    /* Non-string dictionary values are not supported for factor columns.
       Return empty result (NullColumn equivalent) rather than partial data. */
    v_indices = caml_alloc(0, 0);
    v_levels = Val_emptylist;
    v_result = caml_alloc(3, 0);
    Store_field(v_result, 0, v_indices);
    Store_field(v_result, 1, v_levels);
    Store_field(v_result, 2, Val_bool(0));
    g_object_unref(dictionary);
    g_object_unref(array);
    CAMLreturn(v_result);
  }

  /* Build OCaml string list for levels (in order) */
  v_levels = Val_emptylist;
  for (gint64 i = n_levels - 1; i >= 0; i--) {
    gchar *level_str = NULL;
    if (GARROW_IS_STRING_ARRAY(dictionary)) {
      level_str = garrow_string_array_get_string(GARROW_STRING_ARRAY(dictionary), i);
    } else {
      level_str = garrow_large_string_array_get_string(GARROW_LARGE_STRING_ARRAY(dictionary), i);
    }
    if (level_str) {
      v_cons = caml_alloc(2, 0);
      Store_field(v_cons, 0, caml_copy_string(level_str));
      Store_field(v_cons, 1, v_levels);
      v_levels = v_cons;
      g_free(level_str);
    }
  }

  /* Extract indices */
  GArrowArray *indices_arr = garrow_dictionary_array_get_indices(dict_array);
  v_indices = caml_alloc(length, 0);

  for (gint64 i = 0; i < length; i++) {
    if (garrow_array_is_null(array, i)) {
      Store_field(v_indices, i, Val_none);
    } else {
      gint64 idx = 0;
      if (GARROW_IS_INT8_ARRAY(indices_arr))
        idx = garrow_int8_array_get_value(GARROW_INT8_ARRAY(indices_arr), i);
      else if (GARROW_IS_INT16_ARRAY(indices_arr))
        idx = garrow_int16_array_get_value(GARROW_INT16_ARRAY(indices_arr), i);
      else if (GARROW_IS_INT32_ARRAY(indices_arr))
        idx = garrow_int32_array_get_value(GARROW_INT32_ARRAY(indices_arr), i);
      else if (GARROW_IS_INT64_ARRAY(indices_arr))
        idx = garrow_int64_array_get_value(GARROW_INT64_ARRAY(indices_arr), i);
      else if (GARROW_IS_UINT8_ARRAY(indices_arr))
        idx = (gint64)garrow_uint8_array_get_value(GARROW_UINT8_ARRAY(indices_arr), i);
      else if (GARROW_IS_UINT16_ARRAY(indices_arr))
        idx = (gint64)garrow_uint16_array_get_value(GARROW_UINT16_ARRAY(indices_arr), i);
      else if (GARROW_IS_UINT32_ARRAY(indices_arr))
        idx = (gint64)garrow_uint32_array_get_value(GARROW_UINT32_ARRAY(indices_arr), i);
      else if (GARROW_IS_UINT64_ARRAY(indices_arr))
        idx = (gint64)garrow_uint64_array_get_value(GARROW_UINT64_ARRAY(indices_arr), i);
      else {
        /* Unsupported index type — treat as null */
        Store_field(v_indices, i, Val_none);
        continue;
      }

      v_some = caml_alloc(1, 0); /* Some(...) */
      Store_field(v_some, 0, Val_long(idx));
      Store_field(v_indices, i, v_some);
    }
  }

  /* indices_arr and dictionary are borrowed components - don't unref them */
  /* Build result tuple: (indices, levels, ordered) */
  v_result = caml_alloc(3, 0);
  Store_field(v_result, 0, v_indices);
  Store_field(v_result, 1, v_levels);
  Store_field(v_result, 2, Val_bool(ordered));

  g_object_unref(array);
  CAMLreturn(v_result);
}

/* Read a List column into an OCaml array of (int * int) option.
   Each element is Some(offset, length) describing a slice of the child array,
   or None for null entries. The child array nativeint is returned separately
   so the OCaml side can read it with the appropriate typed reader.
   Returns: (nativeint option * (int * int) option array)
     - nativeint option: child GArrowArray pointer (Some) or None if empty
     - (int * int) option array: per-row (offset, length) or None for null */
CAMLprim value caml_arrow_read_list_column(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal5(v_result, v_slices, v_some, v_tuple, v_child_opt);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);

  if (!GARROW_IS_LIST_ARRAY(array)) {
    /* Not a list array — return (None, [||]) */
    v_slices = caml_alloc(0, 0);
    v_result = caml_alloc(2, 0);
    Store_field(v_result, 0, Val_none);
    Store_field(v_result, 1, v_slices);
    g_object_unref(array);
    CAMLreturn(v_result);
  }

  GArrowListArray *list_array = GARROW_LIST_ARRAY(array);
  gint64 length = garrow_array_get_length(array);

  /* Get the flattened child values array.
     garrow_list_array_get_values() returns a borrowed reference (transfer none),
     so we must take our own reference to keep it alive after unreffing the
     parent list array below. The OCaml side will release this reference via
     arrow_unref after reading all struct fields. */
  GArrowArray *values_array = garrow_list_array_get_values(list_array);
  g_object_ref(values_array);

  /* Wrap child array pointer as Some(nativeint) */
  v_child_opt = caml_alloc(1, 0); /* Some(...) */
  Store_field(v_child_opt, 0, caml_copy_nativeint((intnat)values_array));

  /* Build per-row slice descriptors */
  v_slices = caml_alloc(length, 0);
  for (gint64 i = 0; i < length; i++) {
    if (garrow_array_is_null(array, i)) {
      Store_field(v_slices, i, Val_none);
    } else {
      gint32 offset = garrow_list_array_get_value_offset(list_array, i);
      gint32 len = garrow_list_array_get_value_length(list_array, i);
      v_tuple = caml_alloc(2, 0);
      Store_field(v_tuple, 0, Val_int(offset));
      Store_field(v_tuple, 1, Val_int(len));
      v_some = caml_alloc(1, 0); /* Some(...) */
      Store_field(v_some, 0, v_tuple);
      Store_field(v_slices, i, v_some);
    }
  }

  v_result = caml_alloc(2, 0);
  Store_field(v_result, 0, v_child_opt);
  Store_field(v_result, 1, v_slices);

  g_object_unref(array);
  CAMLreturn(v_result);
}

/* Read the schema (field names + type tags) from a struct array.
   Returns OCaml list of (string * int) pairs.
   Does NOT take ownership of the input array — caller manages lifecycle. */
CAMLprim value caml_arrow_read_struct_fields(value v_ptr) {
  CAMLparam1(v_ptr);
  CAMLlocal3(v_result, v_tuple, v_cons);

  GArrowArray *arr = (GArrowArray *)Nativeint_val(v_ptr);

  if (!GARROW_IS_STRUCT_ARRAY(arr)) {
    CAMLreturn(Val_emptylist);
  }

  GArrowDataType *base_dtype = garrow_array_get_value_data_type(arr);
  if (!GARROW_IS_STRUCT_DATA_TYPE(base_dtype)) {
    g_object_unref(base_dtype);
    CAMLreturn(Val_emptylist);
  }
  GArrowStructDataType *sdtype = GARROW_STRUCT_DATA_TYPE(base_dtype);
  int n = garrow_struct_data_type_get_n_fields(sdtype);

  v_result = Val_emptylist;
  for (int i = n - 1; i >= 0; i--) {
    GArrowField *field = garrow_struct_data_type_get_field(sdtype, i);
    const gchar *fname = garrow_field_get_name(field);
    GArrowDataType *fdtype = garrow_field_get_data_type(field);

    int type_tag;
    if (GARROW_IS_INT8_DATA_TYPE(fdtype) || GARROW_IS_INT16_DATA_TYPE(fdtype) ||
        GARROW_IS_INT32_DATA_TYPE(fdtype) || GARROW_IS_INT64_DATA_TYPE(fdtype) ||
        GARROW_IS_UINT8_DATA_TYPE(fdtype) || GARROW_IS_UINT16_DATA_TYPE(fdtype) ||
        GARROW_IS_UINT32_DATA_TYPE(fdtype) || GARROW_IS_UINT64_DATA_TYPE(fdtype))
                                                   type_tag = 0;
    else if (GARROW_IS_DOUBLE_DATA_TYPE(fdtype))   type_tag = 1;
    else if (GARROW_IS_BOOLEAN_DATA_TYPE(fdtype))  type_tag = 2;
    else if (GARROW_IS_STRING_DATA_TYPE(fdtype) ||
             GARROW_IS_LARGE_STRING_DATA_TYPE(fdtype))
                                                   type_tag = 3;
    else if (GARROW_IS_DICTIONARY_DATA_TYPE(fdtype))
                                                   type_tag = 4;
    else if (GARROW_IS_LIST_DATA_TYPE(fdtype))     type_tag = 5;
    else if (GARROW_IS_DATE32_DATA_TYPE(fdtype) ||
             GARROW_IS_DATE64_DATA_TYPE(fdtype))   type_tag = 7;
    else                                           type_tag = 6;

    v_tuple = caml_alloc(2, 0);
    Store_field(v_tuple, 0, caml_copy_string(fname));
    Store_field(v_tuple, 1, Val_int(type_tag));

    v_cons = caml_alloc(2, 0);
    Store_field(v_cons, 0, v_tuple);
    Store_field(v_cons, 1, v_result);
    v_result = v_cons;
  }

  g_object_unref(base_dtype);
  CAMLreturn(v_result);
}

/* Extract a single field (by index) from a struct array.
   Returns Some(nativeint) with the field array pointer, or None.
   The returned array is a new GObject reference that the caller must unref
   (or pass to a column reader which unrefs). */
CAMLprim value caml_arrow_read_struct_field(value v_ptr, value v_idx) {
  CAMLparam2(v_ptr, v_idx);
  CAMLlocal1(v_result);

  GArrowArray *arr = (GArrowArray *)Nativeint_val(v_ptr);
  int idx = Int_val(v_idx);

  if (!GARROW_IS_STRUCT_ARRAY(arr)) {
    CAMLreturn(Val_none);
  }

  GArrowStructArray *sarr = GARROW_STRUCT_ARRAY(arr);
  GArrowArray *field_arr = garrow_struct_array_get_field(sarr, idx);
  if (field_arr == NULL) {
    CAMLreturn(Val_none);
  }

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)field_arr));
  CAMLreturn(v_result);
}

/* Generic GObject unref — used to free child array pointers after reading. */
CAMLprim value caml_arrow_unref(value v_ptr) {
  CAMLparam1(v_ptr);
  gpointer obj = (gpointer)Nativeint_val(v_ptr);
  if (obj) g_object_unref(obj);
  CAMLreturn(Val_unit);
}

/* ===================================================================== */
/* CSV Reading                                                           */
/* ===================================================================== */

/* Read CSV file using Arrow CSV reader */
CAMLprim value caml_arrow_read_csv(value v_path) {
  CAMLparam1(v_path);
  CAMLlocal1(v_result);

  const char *path = String_val(v_path);
  GError *error = NULL;

  /* Open input file */
  GArrowMemoryMappedInputStream *input =
    garrow_memory_mapped_input_stream_new(path, &error);
  if (input == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  /* Create CSV read options with custom NULL values (NA, na, N/A, "") */
  GArrowCSVReadOptions *options = garrow_csv_read_options_new();
  if (options) {
    const gchar *null_values[] = {"NA", "na", "N/A", ""};
    garrow_csv_read_options_set_null_values(options, null_values, 4);
  }

  /* Create CSV reader */
  GArrowCSVReader *reader =
    garrow_csv_reader_new(GARROW_INPUT_STREAM(input), options, &error);
  if (options) g_object_unref(options);

  if (reader == NULL) {
    g_object_unref(input);
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  /* Read table */
  GArrowTable *table = garrow_csv_reader_read(reader, &error);
  g_object_unref(reader);
  g_object_unref(input);

  if (table == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  /* Wrap as Some(nativeint) */
  v_result = caml_alloc(1, 0);  /* Some(...) */
  Store_field(v_result, 0, caml_copy_nativeint((intnat)table));
  CAMLreturn(v_result);
}

/* Read Parquet file using parquet-glib Arrow reader */
CAMLprim value caml_arrow_read_parquet(value v_path) {
  CAMLparam1(v_path);
  CAMLlocal1(v_result);

  const char *path = String_val(v_path);
  GError *error = NULL;

  GParquetArrowFileReader *reader =
    gparquet_arrow_file_reader_new_path(path, &error);
  if (reader == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  GArrowTable *table = gparquet_arrow_file_reader_read_table(reader, &error);
  g_object_unref(reader);

  if (table == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  v_result = caml_alloc(1, 0);  /* Some(...) */
  Store_field(v_result, 0, caml_copy_nativeint((intnat)table));
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Column Projection (Select)                                            */
/* ===================================================================== */

/* Project columns by name — zero-copy operation */
CAMLprim value caml_arrow_table_project(value v_ptr, value v_names) {
  CAMLparam2(v_ptr, v_names);
  CAMLlocal2(v_result, v_head);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);

  /* Count column names */
  int n_names = 0;
  value iter = v_names;
  while (iter != Val_emptylist) {
    n_names++;
    iter = Field(iter, 1);
  }

  /* Build index array from column names */
  guint *indices = (guint *)malloc(sizeof(guint) * n_names);
  GArrowSchema *schema = garrow_table_get_schema(table);

  iter = v_names;
  for (int i = 0; i < n_names; i++) {
    v_head = Field(iter, 0);
    const char *name = String_val(v_head);
    int idx = garrow_schema_get_field_index(schema, name);
    if (idx < 0) {
      free(indices);
      g_object_unref(schema);
      CAMLreturn(Val_none);
    }
    indices[i] = (guint)idx;
    iter = Field(iter, 1);
  }

  g_object_unref(schema);

  /* Build new table with selected columns using Arrow APIs */
  GError *error = NULL;
  GList *fields_list = NULL;
  GArrowChunkedArray **columns_arr = (GArrowChunkedArray **)malloc(sizeof(GArrowChunkedArray *) * n_names);

  GArrowSchema *old_schema = garrow_table_get_schema(table);
  for (int i = 0; i < n_names; i++) {
    guint idx = indices[i];
    GArrowField *field = garrow_schema_get_field(old_schema, idx);
    fields_list = g_list_append(fields_list, g_object_ref(field));
    columns_arr[i] = garrow_table_get_column_data(table, idx);
    g_object_unref(field);
  }
  g_object_unref(old_schema);
  free(indices);

  GArrowSchema *new_schema = garrow_schema_new(fields_list);
  g_list_free_full(fields_list, g_object_unref);

  GArrowTable *result = garrow_table_new_chunked_arrays(new_schema, columns_arr, n_names, &error);

  for (int i = 0; i < n_names; i++) {
    if (columns_arr[i]) g_object_unref(columns_arr[i]);
  }
  free(columns_arr);
  g_object_unref(new_schema);

  if (result == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)result));
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Filter (Take with boolean mask)                                       */
/* ===================================================================== */

/* Filter rows using a boolean array */
CAMLprim value caml_arrow_table_filter_mask(value v_ptr, value v_mask) {
  CAMLparam2(v_ptr, v_mask);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  int n = Wosize_val(v_mask);

  /* Build boolean array from OCaml bool array */
  GArrowBooleanArrayBuilder *builder = garrow_boolean_array_builder_new();
  GError *error = NULL;

  for (int i = 0; i < n; i++) {
    gboolean mask_val = Bool_val(Field(v_mask, i));
    garrow_boolean_array_builder_append_value(builder, mask_val, &error);
    if (error) {
      g_object_unref(builder);
      g_error_free(error);
      CAMLreturn(Val_none);
    }
  }

  GArrowArray *mask_array = garrow_array_builder_finish(GARROW_ARRAY_BUILDER(builder), &error);
  g_object_unref(builder);

  if (mask_array == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  /* Apply filter - cast to GArrowBooleanArray as required by the API */
  GArrowTable *result = garrow_table_filter(table, GARROW_BOOLEAN_ARRAY(mask_array), NULL, &error);
  g_object_unref(mask_array);

  if (result == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)result));
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Sort                                                                  */
/* ===================================================================== */

/* Sort table by column name, ascending or descending.
   Returns Some(nativeint) or None on error. */
CAMLprim value caml_arrow_table_sort(value v_ptr, value v_col_name, value v_ascending) {
  CAMLparam3(v_ptr, v_col_name, v_ascending);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *col_name = String_val(v_col_name);
  gboolean ascending = Bool_val(v_ascending);

  GError *error = NULL;

  /* Create sort key with column name and order */
  GArrowSortOrder order = ascending
    ? GARROW_SORT_ORDER_ASCENDING
    : GARROW_SORT_ORDER_DESCENDING;
  GArrowSortKey *sort_key = garrow_sort_key_new(col_name, order, &error);
  if (sort_key == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  GArrowSortOptions *options = garrow_sort_options_new(NULL);
  garrow_sort_options_add_sort_key(options, sort_key);

  /* Get sort indices */
  GArrowUInt64Array *indices =
    garrow_table_sort_indices(table, options, &error);
  g_object_unref(sort_key);
  g_object_unref(options);

  if (indices == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  /* Take rows by sorted indices */
  GArrowTable *sorted = garrow_table_take(table,
    GARROW_ARRAY(indices), NULL, &error);
  g_object_unref(indices);

  if (sorted == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)sorted));
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Scalar Arithmetic Operations                                          */
/* ===================================================================== */

/* Helper: rebuild a GArrowTable replacing one column's ChunkedArray.
   Copies the schema and all columns, substituting the column at `idx`
   with `new_col`. The schema field at `idx` is updated to match the
   new column's data type (e.g., Int64 → Float64 after scalar op).
   Returns a new GArrowTable* or NULL on failure. */
static GArrowTable *
rebuild_table_with_column(GArrowTable *table, guint idx, GArrowChunkedArray *new_col)
{
  GError *error = NULL;
  GArrowSchema *old_schema = garrow_table_get_schema(table);
  guint ncols = garrow_schema_n_fields(old_schema);

  GList *fields_list = NULL;
  GArrowChunkedArray **columns_arr =
      (GArrowChunkedArray **)malloc(sizeof(GArrowChunkedArray *) * ncols);

  for (guint i = 0; i < ncols; i++) {
    if (i == idx) {
      /* Create a new field with the replacement column's data type */
      GArrowField *old_field = garrow_schema_get_field(old_schema, i);
      const gchar *name = garrow_field_get_name(old_field);
      GArrowDataType *new_dtype = garrow_chunked_array_get_value_data_type(new_col);
      GArrowField *new_field = garrow_field_new(name, new_dtype);
      fields_list = g_list_append(fields_list, new_field);
      columns_arr[i] = g_object_ref(new_col);
      g_object_unref(new_dtype);
      g_object_unref(old_field);
    } else {
      GArrowField *field = garrow_schema_get_field(old_schema, i);
      fields_list = g_list_append(fields_list, g_object_ref(field));
      columns_arr[i] = garrow_table_get_column_data(table, i);
      g_object_unref(field);
    }
  }

  GArrowSchema *new_schema = garrow_schema_new(fields_list);
  g_list_free_full(fields_list, g_object_unref);

  GArrowTable *result =
      garrow_table_new_chunked_arrays(new_schema, columns_arr, ncols, &error);

  for (guint i = 0; i < ncols; i++) {
    if (columns_arr[i]) g_object_unref(columns_arr[i]);
  }
  free(columns_arr);
  g_object_unref(new_schema);
  g_object_unref(old_schema);

  if (result == NULL && error) g_error_free(error);
  return result;
}

/* Helper: apply a scalar arithmetic operation element-by-element on a
   Float64 (double) column. Builds a new GArrowChunkedArray* with the
   results. op_code: 0=add, 1=multiply, 2=subtract, 3=divide.
   Returns NULL on failure or type mismatch. */
static GArrowChunkedArray *
apply_double_scalar_op(GArrowChunkedArray *chunked, double scalar_val, int op_code)
{
  GError *error = NULL;
  guint n_chunks = garrow_chunked_array_get_n_chunks(chunked);

  /* Process each chunk, collecting result arrays */
  GList *result_chunks = NULL;
  gboolean ok = TRUE;

  for (guint c = 0; c < n_chunks && ok; c++) {
    GArrowArray *chunk = garrow_chunked_array_get_chunk(chunked, c);
    gint64 length = garrow_array_get_length(chunk);

    /* Build a new double array with the operation applied */
    GArrowDoubleArrayBuilder *builder = garrow_double_array_builder_new();

    for (gint64 i = 0; i < length; i++) {
      if (garrow_array_is_null(chunk, i)) {
        garrow_array_builder_append_null(GARROW_ARRAY_BUILDER(builder), &error);
      } else {
        gdouble val;

        if (GARROW_IS_DOUBLE_ARRAY(chunk)) {
          val = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk), i);
        } else if (GARROW_IS_INT64_ARRAY(chunk)) {
          val = (gdouble)garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk), i);
        } else {
          ok = FALSE;
          break;
        }

        gdouble result;
        switch (op_code) {
          case 0: result = val + scalar_val; break;
          case 1: result = val * scalar_val; break;
          case 2: result = val - scalar_val; break;
          case 3: result = val / scalar_val; break;  /* IEEE 754: x/0 → ±Inf, 0/0 → NaN */
          default: result = val; break;
        }

        garrow_double_array_builder_append_value(builder, result, &error);
      }
      if (error) { ok = FALSE; break; }
    }

    if (ok) {
      GArrowArray *result_array =
          garrow_array_builder_finish(GARROW_ARRAY_BUILDER(builder), &error);
      if (result_array) {
        result_chunks = g_list_append(result_chunks, result_array);
      } else {
        ok = FALSE;
      }
    }
    g_object_unref(builder);
    g_object_unref(chunk);
  }

  if (!ok || result_chunks == NULL) {
    g_list_free_full(result_chunks, g_object_unref);
    if (error) g_error_free(error);
    return NULL;
  }

  /* Build ChunkedArray from result chunks.
     garrow_chunked_array_new takes (GList *chunks, GError **error). */
  GArrowChunkedArray *result =
      garrow_chunked_array_new(result_chunks, &error);

  g_list_free_full(result_chunks, g_object_unref);

  if (result == NULL && error) g_error_free(error);
  return result;
}

/* Generic scalar operation: table_ptr, column_name, scalar, op_code.
   op_code: 0=add, 1=multiply, 2=subtract, 3=divide.
   Returns Some(new_table_ptr) or None. */
static value arrow_scalar_op_impl(value v_ptr, value v_col_name, value v_scalar, int op_code) {
  CAMLparam3(v_ptr, v_col_name, v_scalar);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *col_name = String_val(v_col_name);
  double scalar_val = Double_val(v_scalar);

  GArrowSchema *schema = garrow_table_get_schema(table);
  gint idx = garrow_schema_get_field_index(schema, col_name);
  g_object_unref(schema);

  if (idx < 0) CAMLreturn(Val_none);

  GArrowChunkedArray *col = garrow_table_get_column_data(table, idx);
  if (col == NULL) CAMLreturn(Val_none);

  GArrowChunkedArray *result_col = apply_double_scalar_op(col, scalar_val, op_code);
  g_object_unref(col);

  if (result_col == NULL) CAMLreturn(Val_none);

  GArrowTable *new_table = rebuild_table_with_column(table, (guint)idx, result_col);
  g_object_unref(result_col);

  if (new_table == NULL) CAMLreturn(Val_none);

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)new_table));
  CAMLreturn(v_result);
}

/* Add a scalar to every element of a column.
   Args: table_ptr, column_name, scalar_value
   Returns: Some(new_table_ptr) or None */
CAMLprim value caml_arrow_compute_add_scalar(value v_ptr, value v_col_name, value v_scalar) {
  return arrow_scalar_op_impl(v_ptr, v_col_name, v_scalar, 0);
}

/* Multiply every element of a column by a scalar.
   Args: table_ptr, column_name, scalar_value
   Returns: Some(new_table_ptr) or None */
CAMLprim value caml_arrow_compute_multiply_scalar(value v_ptr, value v_col_name, value v_scalar) {
  return arrow_scalar_op_impl(v_ptr, v_col_name, v_scalar, 1);
}

/* Subtract a scalar from every element of a column.
   Args: table_ptr, column_name, scalar_value
   Returns: Some(new_table_ptr) or None */
CAMLprim value caml_arrow_compute_subtract_scalar(value v_ptr, value v_col_name, value v_scalar) {
  return arrow_scalar_op_impl(v_ptr, v_col_name, v_scalar, 2);
}

/* Divide every element of a column by a scalar.
   Args: table_ptr, column_name, scalar_value
   Returns: Some(new_table_ptr) or None */
CAMLprim value caml_arrow_compute_divide_scalar(value v_ptr, value v_col_name, value v_scalar) {
  return arrow_scalar_op_impl(v_ptr, v_col_name, v_scalar, 3);
}

/* ===================================================================== */
/* Column-to-Column Arithmetic (Vectorized Processing)                    */
/* ===================================================================== */

/* Helper: apply a binary arithmetic operation element-by-element between two
   numeric columns. Builds a new GArrowChunkedArray* with the results.
   op_code: 0=add, 1=multiply, 2=subtract, 3=divide.
   Returns NULL on failure or type mismatch. */
static GArrowChunkedArray *
apply_double_column_op(GArrowChunkedArray *chunked1, GArrowChunkedArray *chunked2,
                       gint64 nrows, int op_code)
{
  GError *error = NULL;

  /* Build a single result array from both input chunked arrays */
  GArrowDoubleArrayBuilder *builder = garrow_double_array_builder_new();
  gboolean ok = TRUE;

  /* Track position within each chunked array's chunks */
  guint c1 = 0, c2 = 0;
  gint64 off1 = 0, off2 = 0;
  guint nc1 = garrow_chunked_array_get_n_chunks(chunked1);
  guint nc2 = garrow_chunked_array_get_n_chunks(chunked2);
  GArrowArray *chunk1 = nc1 > 0 ? garrow_chunked_array_get_chunk(chunked1, 0) : NULL;
  GArrowArray *chunk2 = nc2 > 0 ? garrow_chunked_array_get_chunk(chunked2, 0) : NULL;
  gint64 len1 = chunk1 ? garrow_array_get_length(chunk1) : 0;
  gint64 len2 = chunk2 ? garrow_array_get_length(chunk2) : 0;

  for (gint64 i = 0; i < nrows && ok; i++) {
    /* Advance chunk pointers if needed */
    while (off1 >= len1 && c1 + 1 < nc1) {
      if (chunk1) g_object_unref(chunk1);
      c1++;
      off1 = 0;
      chunk1 = garrow_chunked_array_get_chunk(chunked1, c1);
      len1 = garrow_array_get_length(chunk1);
    }
    while (off2 >= len2 && c2 + 1 < nc2) {
      if (chunk2) g_object_unref(chunk2);
      c2++;
      off2 = 0;
      chunk2 = garrow_chunked_array_get_chunk(chunked2, c2);
      len2 = garrow_array_get_length(chunk2);
    }

    /* Bounds check: if either chunk is exhausted or missing, stop processing */
    if (!chunk1 || !chunk2 || off1 >= len1 || off2 >= len2) { ok = FALSE; break; }

    if (garrow_array_is_null(chunk1, off1) || garrow_array_is_null(chunk2, off2)) {
      garrow_array_builder_append_null(GARROW_ARRAY_BUILDER(builder), &error);
    } else {
      gdouble val1, val2;

      /* Read val1 */
      if (GARROW_IS_DOUBLE_ARRAY(chunk1)) {
        val1 = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk1), off1);
      } else if (GARROW_IS_INT64_ARRAY(chunk1)) {
        val1 = (gdouble)garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk1), off1);
      } else { ok = FALSE; break; }

      /* Read val2 */
      if (GARROW_IS_DOUBLE_ARRAY(chunk2)) {
        val2 = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk2), off2);
      } else if (GARROW_IS_INT64_ARRAY(chunk2)) {
        val2 = (gdouble)garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk2), off2);
      } else { ok = FALSE; break; }

      gdouble result;
      switch (op_code) {
        case 0: result = val1 + val2; break;
        case 1: result = val1 * val2; break;
        case 2: result = val1 - val2; break;
        case 3: result = val1 / val2; break;  /* IEEE 754: x/0 → ±Inf, 0/0 → NaN */
        default: result = val1; break;
      }

      garrow_double_array_builder_append_value(builder, result, &error);
    }
    if (error) { ok = FALSE; break; }
    off1++;
    off2++;
  }

  if (chunk1) g_object_unref(chunk1);
  if (chunk2) g_object_unref(chunk2);

  if (!ok) {
    g_object_unref(builder);
    if (error) g_error_free(error);
    return NULL;
  }

  GArrowArray *result_array =
      garrow_array_builder_finish(GARROW_ARRAY_BUILDER(builder), &error);
  g_object_unref(builder);

  if (result_array == NULL) {
    if (error) g_error_free(error);
    return NULL;
  }

  /* Wrap single array into a ChunkedArray */
  GList *chunks_list = g_list_append(NULL, result_array);
  GArrowChunkedArray *result = garrow_chunked_array_new(chunks_list, &error);
  g_list_free(chunks_list);
  g_object_unref(result_array);

  return result;
}

/* Implementation for column-to-column binary operations.
   Looks up two columns by name, applies the operation, and builds a new table
   with a result column appended (named after the first column).
   Args: table_ptr, col_name1, col_name2, result_col_name
   Returns: Some(new_table_ptr) or None */
static value arrow_column_op_impl(value v_ptr, value v_col1, value v_col2,
                                  value v_result_name, int op_code) {
  CAMLparam4(v_ptr, v_col1, v_col2, v_result_name);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *col1_name = String_val(v_col1);
  const char *col2_name = String_val(v_col2);
  const char *result_name = String_val(v_result_name);

  GArrowSchema *schema = garrow_table_get_schema(table);
  gint idx1 = garrow_schema_get_field_index(schema, col1_name);
  gint idx2 = garrow_schema_get_field_index(schema, col2_name);
  g_object_unref(schema);

  if (idx1 < 0 || idx2 < 0) CAMLreturn(Val_none);

  GArrowChunkedArray *ca1 = garrow_table_get_column_data(table, idx1);
  GArrowChunkedArray *ca2 = garrow_table_get_column_data(table, idx2);
  if (ca1 == NULL || ca2 == NULL) {
    if (ca1) g_object_unref(ca1);
    if (ca2) g_object_unref(ca2);
    CAMLreturn(Val_none);
  }

  gint64 nrows = garrow_table_get_n_rows(table);
  GArrowChunkedArray *result_col = apply_double_column_op(ca1, ca2, nrows, op_code);
  g_object_unref(ca1);
  g_object_unref(ca2);

  if (result_col == NULL) CAMLreturn(Val_none);

  /* Add the result column to the table */
  GError *error = NULL;
  GArrowDataType *dtype = garrow_chunked_array_get_value_data_type(result_col);
  GArrowField *field = garrow_field_new(result_name, dtype);
  g_object_unref(dtype);

  guint ncols = garrow_table_get_n_columns(table);
  GArrowTable *new_table =
      garrow_table_add_column(table, ncols, field, result_col, &error);
  g_object_unref(field);
  g_object_unref(result_col);

  if (new_table == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)new_table));
  CAMLreturn(v_result);
}

/* Add two columns element-wise: result[i] = col1[i] + col2[i]
   Args: table_ptr, col1_name, col2_name, result_col_name
   Returns: Some(new_table_ptr) or None */
CAMLprim value caml_arrow_compute_add_columns(value v_ptr, value v_col1,
                                               value v_col2, value v_result) {
  return arrow_column_op_impl(v_ptr, v_col1, v_col2, v_result, 0);
}

/* Multiply two columns element-wise: result[i] = col1[i] * col2[i] */
CAMLprim value caml_arrow_compute_multiply_columns(value v_ptr, value v_col1,
                                                    value v_col2, value v_result) {
  return arrow_column_op_impl(v_ptr, v_col1, v_col2, v_result, 1);
}

/* Subtract two columns element-wise: result[i] = col1[i] - col2[i] */
CAMLprim value caml_arrow_compute_subtract_columns(value v_ptr, value v_col1,
                                                    value v_col2, value v_result) {
  return arrow_column_op_impl(v_ptr, v_col1, v_col2, v_result, 2);
}

/* Divide two columns element-wise: result[i] = col1[i] / col2[i] */
CAMLprim value caml_arrow_compute_divide_columns(value v_ptr, value v_col1,
                                                  value v_col2, value v_result) {
  return arrow_column_op_impl(v_ptr, v_col1, v_col2, v_result, 3);
}

/* ===================================================================== */
/* Group-By & Aggregation (Phase 3)                                      */
/* ===================================================================== */

/* Grouped table structure — stores pre-computed group information.
   Used as an opaque handle passed between OCaml group_by and aggregate calls. */
typedef struct {
  GArrowTable *table;       /* Original table (ref counted) */
  int n_groups;             /* Number of unique groups */
  int n_keys;               /* Number of key columns */
  int **group_row_indices;  /* group_row_indices[g] = array of row indices for group g */
  int *group_sizes;         /* group_sizes[g] = number of rows in group g */
  gchar ***group_key_values; /* group_key_values[g][k] = string key value for group g, key k */
  gchar **key_names;        /* key_names[k] = name of key column k */
} GroupedTable;

/* Free a GroupedTable and all its resources */
static void grouped_table_free(GroupedTable *gt) {
  if (gt == NULL) return;
  for (int g = 0; g < gt->n_groups; g++) {
    free(gt->group_row_indices[g]);
    for (int k = 0; k < gt->n_keys; k++) {
      g_free(gt->group_key_values[g][k]);
    }
    free(gt->group_key_values[g]);
  }
  free(gt->group_row_indices);
  free(gt->group_sizes);
  free(gt->group_key_values);
  for (int k = 0; k < gt->n_keys; k++) {
    g_free(gt->key_names[k]);
  }
  free(gt->key_names);
  g_object_unref(gt->table);
  free(gt);
}

/* Helper: extract a single cell value as a newly-allocated string.
   Caller must g_free() the returned string. */
static gchar *
cell_value_as_string(GArrowTable *table, int col_idx, gint64 row_idx)
{
  GArrowChunkedArray *chunked = garrow_table_get_column_data(table, col_idx);
  if (chunked == NULL) return g_strdup("");

  /* Locate the chunk and offset within it */
  guint n_chunks = garrow_chunked_array_get_n_chunks(chunked);
  gint64 offset = row_idx;
  GArrowArray *chunk = NULL;
  for (guint c = 0; c < n_chunks; c++) {
    chunk = garrow_chunked_array_get_chunk(chunked, c);
    gint64 chunk_len = garrow_array_get_length(chunk);
    if (offset < chunk_len) break;
    offset -= chunk_len;
    g_object_unref(chunk);
    chunk = NULL;
  }
  g_object_unref(chunked);

  if (chunk == NULL) return g_strdup("");

  gchar *result;
  if (garrow_array_is_null(chunk, offset)) {
    result = g_strdup("NA");
  } else if (GARROW_IS_INT64_ARRAY(chunk)) {
    gint64 v = garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk), offset);
    result = g_strdup_printf("%" G_GINT64_FORMAT, v);
  } else if (GARROW_IS_DOUBLE_ARRAY(chunk)) {
    gdouble v = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk), offset);
    result = g_strdup_printf("%g", v);
  } else if (GARROW_IS_BOOLEAN_ARRAY(chunk)) {
    gboolean v = garrow_boolean_array_get_value(GARROW_BOOLEAN_ARRAY(chunk), offset);
    result = g_strdup(v ? "true" : "false");
  } else if (GARROW_IS_STRING_ARRAY(chunk)) {
    result = garrow_string_array_get_string(GARROW_STRING_ARRAY(chunk), offset);
  } else {
    result = g_strdup("");
  }
  g_object_unref(chunk);
  return result;
}

/* Context for sorting groups by key values */
typedef struct {
  GArrowTable *table;
  int n_keys;
  int *key_indices;
  int *key_types; /* 0=Int64, 1=Float64, 3=String, etc. (uses arrow_type_of_tag logic) */
  gchar ***group_key_values;
} GroupedTableSortContext;

/* Helper to compare group key values for sorting. Matches OCaml's group order. */
static int
compare_group_keys(gconstpointer a, gconstpointer b, gpointer user_data)
{
  GroupedTableSortContext *ctx = (GroupedTableSortContext *)user_data;
  int g1 = *(int *)a;
  int g2 = *(int *)b;

  for (int k = 0; k < ctx->n_keys; k++) {
    const char *s1 = ctx->group_key_values[g1][k];
    const char *s2 = ctx->group_key_values[g2][k];

    /* Handle NAs (stored as "NA" in key strings) */
    gboolean is_na1 = (strcmp(s1, "NA") == 0);
    gboolean is_na2 = (strcmp(s2, "NA") == 0);
    if (is_na1 && !is_na2) return 1;  /* NAs last */
    if (!is_na1 && is_na2) return -1;
    if (is_na1 && is_na2) continue;

    int type_tag = ctx->key_types[k];
    if (type_tag == 0) { /* Int64 */
      gint64 v1 = g_ascii_strtoll(s1, NULL, 10);
      gint64 v2 = g_ascii_strtoll(s2, NULL, 10);
      if (v1 < v2) return -1;
      if (v1 > v2) return 1;
    } else if (type_tag == 1) { /* Float64 */
      gdouble v1 = g_ascii_strtod(s1, NULL);
      gdouble v2 = g_ascii_strtod(s2, NULL);
      if (v1 < v2) return -1;
      if (v1 > v2) return 1;
    } else {
      /* Default string comparison */
      int res = strcmp(s1, s2);
      if (res != 0) return res;
    }
  }
  return 0;
}

/* Group-by: hash-based grouping of table rows by key columns.
   Args: table_ptr (nativeint), key_names (string list)
   Returns: Some(grouped_table_ptr) or None on failure. */
CAMLprim value caml_arrow_table_group_by(value v_ptr, value v_key_names) {
  CAMLparam2(v_ptr, v_key_names);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  gint64 nrows = garrow_table_get_n_rows(table);
  GArrowSchema *schema = garrow_table_get_schema(table);

  /* Count and resolve key column names → indices */
  int n_keys = 0;
  value iter = v_key_names;
  while (iter != Val_emptylist) {
    n_keys++;
    iter = Field(iter, 1);
  }
  if (n_keys == 0) {
    g_object_unref(schema);
    CAMLreturn(Val_none);
  }

  int *key_indices = (int *)malloc(sizeof(int) * n_keys);
  int *key_types = (int *)malloc(sizeof(int) * n_keys);
  gchar **key_names = (gchar **)malloc(sizeof(gchar *) * n_keys);
  iter = v_key_names;
  for (int i = 0; i < n_keys; i++) {
    value head = Field(iter, 0);
    const char *name = String_val(head);
    key_names[i] = g_strdup(name);
    key_indices[i] = garrow_schema_get_field_index(schema, name);
    if (key_indices[i] < 0) {
      /* Key column not found — clean up and return None */
      for (int j = 0; j <= i; j++) g_free(key_names[j]);
      free(key_names);
      free(key_indices);
      free(key_types);
      g_object_unref(schema);
      CAMLreturn(Val_none);
    }

    /* Extract type tag for sorting */
    GArrowField *field = garrow_schema_get_field(schema, key_indices[i]);
    GArrowDataType *dtype = garrow_field_get_data_type(field);
    if (GARROW_IS_INT8_DATA_TYPE(dtype) || GARROW_IS_INT16_DATA_TYPE(dtype) ||
        GARROW_IS_INT32_DATA_TYPE(dtype) || GARROW_IS_INT64_DATA_TYPE(dtype) ||
        GARROW_IS_UINT8_DATA_TYPE(dtype) || GARROW_IS_UINT16_DATA_TYPE(dtype) ||
        GARROW_IS_UINT32_DATA_TYPE(dtype) || GARROW_IS_UINT64_DATA_TYPE(dtype))
                                                  key_types[i] = 0; /* ArrowInt64 */
    else if (GARROW_IS_DOUBLE_DATA_TYPE(dtype))   key_types[i] = 1; /* ArrowFloat64 */
    else if (GARROW_IS_BOOLEAN_DATA_TYPE(dtype))  key_types[i] = 2; /* ArrowBoolean */
    else if (GARROW_IS_STRING_DATA_TYPE(dtype) ||
             GARROW_IS_LARGE_STRING_DATA_TYPE(dtype))
                                                  key_types[i] = 3; /* ArrowString */
    else if (GARROW_IS_DATE32_DATA_TYPE(dtype) ||
             GARROW_IS_DATE64_DATA_TYPE(dtype))   key_types[i] = 7; /* ArrowDate */
    else                                          key_types[i] = 6; /* Other/Null */

    g_object_unref(field);
    /* dtype is transfer none, do not unref */
    iter = Field(iter, 1);
  }
  g_object_unref(schema);

  /* Build composite key string for each row and group using GHashTable */
  GHashTable *group_map = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
  /* Track insertion order */
  GPtrArray *group_order = g_ptr_array_new(); /* stores owned copies of key strings */
  /* Store row indices per group as GArray of ints */
  GPtrArray *group_rows = g_ptr_array_new();  /* GArray<int>* per group */
  /* Store per-group key values: GPtrArray of gchar** arrays */
  GPtrArray *group_key_vals = g_ptr_array_new();

  for (gint64 r = 0; r < nrows; r++) {
    /* Build composite key: "val1\x1Fval2\x1F..." using Unit Separator (U+001F)
       which cannot appear in typical string data. */
    GString *key_buf = g_string_new(NULL);
    gchar **row_keys = (gchar **)malloc(sizeof(gchar *) * n_keys);
    for (int k = 0; k < n_keys; k++) {
      if (k > 0) g_string_append_c(key_buf, '\x1F');
      gchar *cell = cell_value_as_string(table, key_indices[k], r);
      g_string_append(key_buf, cell);
      row_keys[k] = cell; /* ownership transferred to row_keys */
    }
    gchar *key_str = g_string_free(key_buf, FALSE);

    gpointer group_idx_ptr = g_hash_table_lookup(group_map, key_str);
    if (group_idx_ptr == NULL) {
      /* New group — lookup returns NULL only for non-existent keys
         since we store group_idx + 1 (always >= 1) */
      int group_idx = group_order->len;
      g_hash_table_insert(group_map, g_strdup(key_str), GINT_TO_POINTER(group_idx + 1)); /* +1 to distinguish from NULL */
      g_ptr_array_add(group_order, g_strdup(key_str));
      GArray *rows = g_array_new(FALSE, FALSE, sizeof(int));
      int ri = (int)r;
      g_array_append_val(rows, ri);
      g_ptr_array_add(group_rows, rows);
      /* Store key values for this group (take ownership of row_keys) */
      g_ptr_array_add(group_key_vals, row_keys);
    } else {
      /* Existing group */
      int group_idx = GPOINTER_TO_INT(group_idx_ptr) - 1;
      GArray *rows = (GArray *)g_ptr_array_index(group_rows, group_idx);
      int ri = (int)r;
      g_array_append_val(rows, ri);
      /* Free duplicate row_keys for existing group */
      for (int k = 0; k < n_keys; k++) g_free(row_keys[k]);
      free(row_keys);
    }
    g_free(key_str);
  }

  /* Build the GroupedTable result and sort it */
  int n_groups = group_order->len;

  /* Reorder groups based on key values to match OCaml's sorted order */
  int *group_permutation = (int *)malloc(sizeof(int) * n_groups);
  for (int i = 0; i < n_groups; i++) group_permutation[i] = i;

  GroupedTableSortContext sort_ctx = {
    .table = table,
    .n_keys = n_keys,
    .key_indices = key_indices,
    .key_types = key_types,
    .group_key_values = (gchar ***)group_key_vals->pdata
  };

  g_qsort_with_data(group_permutation, n_groups, sizeof(int),
                    compare_group_keys, &sort_ctx);

  GroupedTable *gt = (GroupedTable *)malloc(sizeof(GroupedTable));
  gt->table = g_object_ref(table);
  gt->n_groups = n_groups;
  gt->n_keys = n_keys;
  gt->key_names = key_names;
  gt->group_sizes = (int *)malloc(sizeof(int) * n_groups);
  gt->group_row_indices = (int **)malloc(sizeof(int *) * n_groups);
  gt->group_key_values = (gchar ***)malloc(sizeof(gchar **) * n_groups);

  for (int i = 0; i < n_groups; i++) {
    int g = group_permutation[i];
    GArray *rows = (GArray *)g_ptr_array_index(group_rows, g);
    gt->group_sizes[i] = rows->len;
    gt->group_row_indices[i] = (int *)malloc(sizeof(int) * rows->len);
    memcpy(gt->group_row_indices[i], rows->data, sizeof(int) * rows->len);
    /* GArray itself will be free'd later, but we need to manage row_keys ownership */

    /* Copy key values for this group */
    gt->group_key_values[i] = (gchar **)g_ptr_array_index(group_key_vals, g);
  }

  /* Cleanup unused group arrays and strings */
  for (int g = 0; g < n_groups; g++) {
    GArray *rows = (GArray *)g_ptr_array_index(group_rows, g);
    g_array_free(rows, TRUE);

    gchar *composite_key = (gchar *)g_ptr_array_index(group_order, g);
    g_free(composite_key);
  }

  free(group_permutation);
  free(key_types);
  free(key_indices);
  g_ptr_array_free(group_order, TRUE);
  g_ptr_array_free(group_rows, TRUE);
  g_ptr_array_free(group_key_vals, TRUE);
  g_hash_table_destroy(group_map);

  v_result = caml_alloc(1, 0); /* Some(...) */
  Store_field(v_result, 0, caml_copy_nativeint((intnat)gt));
  CAMLreturn(v_result);
}

/* Free a grouped table handle (called from OCaml GC finalizer) */
CAMLprim value caml_arrow_grouped_table_free(value v_ptr) {
  CAMLparam1(v_ptr);
  GroupedTable *gt = (GroupedTable *)Nativeint_val(v_ptr);
  grouped_table_free(gt);
  CAMLreturn(Val_unit);
}

/* Helper: get a numeric value from a column at a given row index.
   Returns the value as a double. Sets *is_null to TRUE if the value is null. */
static gdouble
get_numeric_value(GArrowTable *table, int col_idx, int row_idx, gboolean *is_null)
{
  *is_null = FALSE;
  GArrowChunkedArray *chunked = garrow_table_get_column_data(table, col_idx);
  if (chunked == NULL) { *is_null = TRUE; return 0.0; }

  gint64 offset = row_idx;
  GArrowArray *chunk = NULL;
  guint n_chunks = garrow_chunked_array_get_n_chunks(chunked);
  for (guint c = 0; c < n_chunks; c++) {
    chunk = garrow_chunked_array_get_chunk(chunked, c);
    gint64 chunk_len = garrow_array_get_length(chunk);
    if (offset < chunk_len) break;
    offset -= chunk_len;
    g_object_unref(chunk);
    chunk = NULL;
  }
  g_object_unref(chunked);

  if (chunk == NULL) { *is_null = TRUE; return 0.0; }

  if (garrow_array_is_null(chunk, offset)) {
    g_object_unref(chunk);
    *is_null = TRUE;
    return 0.0;
  }

  gdouble val = 0.0;
  if (GARROW_IS_INT64_ARRAY(chunk)) {
    val = (gdouble)garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk), offset);
  } else if (GARROW_IS_DOUBLE_ARRAY(chunk)) {
    val = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk), offset);
  } else {
    *is_null = TRUE;
  }
  g_object_unref(chunk);
  return val;
}

/* Helper: build a result table from grouped aggregation.
   Creates a table with key columns + one aggregated value column.
   key_values[g][k] are the key column values, agg_values[g] is the aggregated value.
   agg_col_name is the name of the aggregated column. */
static GArrowTable *
build_aggregation_result(GroupedTable *gt, const char *agg_col_name,
                         gdouble *agg_values, gboolean *agg_nulls)
{
  GError *error = NULL;
  int ncols = gt->n_keys + 1;
  GList *fields_list = NULL;
  GArrowChunkedArray **columns = (GArrowChunkedArray **)malloc(sizeof(GArrowChunkedArray *) * ncols);

  /* Determine key column types from original table schema */
  GArrowSchema *orig_schema = garrow_table_get_schema(gt->table);

  for (int k = 0; k < gt->n_keys; k++) {
    gint idx = garrow_schema_get_field_index(orig_schema, gt->key_names[k]);
    GArrowField *orig_field = garrow_schema_get_field(orig_schema, idx);
    GArrowDataType *dtype = garrow_field_get_data_type(orig_field);

    /* Build the key column array for this key */
    if (GARROW_IS_INT64_DATA_TYPE(dtype)) {
      GArrowInt64ArrayBuilder *builder = garrow_int64_array_builder_new();
      for (int g = 0; g < gt->n_groups; g++) {
        gint64 v = g_ascii_strtoll(gt->group_key_values[g][k], NULL, 10);
        garrow_int64_array_builder_append_value(builder, v, &error);
        if (error) { g_error_free(error); error = NULL; }
      }
      GArrowArray *arr = garrow_array_builder_finish(GARROW_ARRAY_BUILDER(builder), &error);
      GList *chunk_list = g_list_append(NULL, arr);
      columns[k] = garrow_chunked_array_new(chunk_list, &error);
      g_list_free_full(chunk_list, g_object_unref);
      g_object_unref(builder);
    } else if (GARROW_IS_DOUBLE_DATA_TYPE(dtype)) {
      GArrowDoubleArrayBuilder *builder = garrow_double_array_builder_new();
      for (int g = 0; g < gt->n_groups; g++) {
        gdouble v = g_ascii_strtod(gt->group_key_values[g][k], NULL);
        garrow_double_array_builder_append_value(builder, v, &error);
        if (error) { g_error_free(error); error = NULL; }
      }
      GArrowArray *arr = garrow_array_builder_finish(GARROW_ARRAY_BUILDER(builder), &error);
      GList *chunk_list = g_list_append(NULL, arr);
      columns[k] = garrow_chunked_array_new(chunk_list, &error);
      g_list_free_full(chunk_list, g_object_unref);
      g_object_unref(builder);
    } else {
      /* Default to string for key columns */
      GArrowStringArrayBuilder *builder = garrow_string_array_builder_new();
      for (int g = 0; g < gt->n_groups; g++) {
        garrow_string_array_builder_append_string(builder, gt->group_key_values[g][k], &error);
        if (error) { g_error_free(error); error = NULL; }
      }
      GArrowArray *arr = garrow_array_builder_finish(GARROW_ARRAY_BUILDER(builder), &error);
      GList *chunk_list = g_list_append(NULL, arr);
      columns[k] = garrow_chunked_array_new(chunk_list, &error);
      g_list_free_full(chunk_list, g_object_unref);
      g_object_unref(builder);
    }

    GArrowField *new_field = garrow_field_new(gt->key_names[k], dtype);
    fields_list = g_list_append(fields_list, new_field);
    g_object_unref(dtype);
    g_object_unref(orig_field);
  }
  g_object_unref(orig_schema);

  /* Build the aggregated value column (always Float64) */
  GArrowDoubleArrayBuilder *agg_builder = garrow_double_array_builder_new();
  for (int g = 0; g < gt->n_groups; g++) {
    if (agg_nulls[g]) {
      garrow_array_builder_append_null(GARROW_ARRAY_BUILDER(agg_builder), &error);
    } else {
      garrow_double_array_builder_append_value(agg_builder, agg_values[g], &error);
    }
    if (error) { g_error_free(error); error = NULL; }
  }
  GArrowArray *agg_arr = garrow_array_builder_finish(GARROW_ARRAY_BUILDER(agg_builder), &error);
  GList *agg_chunk_list = g_list_append(NULL, agg_arr);
  columns[gt->n_keys] = garrow_chunked_array_new(agg_chunk_list, &error);
  g_list_free_full(agg_chunk_list, g_object_unref);
  g_object_unref(agg_builder);

  GArrowDoubleDataType *double_type = garrow_double_data_type_new();
  GArrowField *agg_field = garrow_field_new(agg_col_name, GARROW_DATA_TYPE(double_type));
  fields_list = g_list_append(fields_list, agg_field);
  g_object_unref(double_type);

  /* Build result table */
  GArrowSchema *result_schema = garrow_schema_new(fields_list);
  GArrowTable *result = garrow_table_new_chunked_arrays(result_schema, columns, ncols, &error);

  g_list_free_full(fields_list, g_object_unref);
  for (int i = 0; i < ncols; i++) {
    if (columns[i]) g_object_unref(columns[i]);
  }
  free(columns);
  g_object_unref(result_schema);

  if (result == NULL && error) g_error_free(error);
  return result;
}

/* Sum aggregation per group.
   Args: grouped_table_ptr, column_name
   Returns: Some(result_table_ptr) or None */
CAMLprim value caml_arrow_group_sum(value v_grouped_ptr, value v_col_name) {
  CAMLparam2(v_grouped_ptr, v_col_name);
  CAMLlocal1(v_result);

  GroupedTable *gt = (GroupedTable *)Nativeint_val(v_grouped_ptr);
  const char *col_name = String_val(v_col_name);

  /* Find column index */
  GArrowSchema *schema = garrow_table_get_schema(gt->table);
  gint col_idx = garrow_schema_get_field_index(schema, col_name);
  g_object_unref(schema);

  if (col_idx < 0) CAMLreturn(Val_none);

  gdouble *sums = (gdouble *)calloc(gt->n_groups, sizeof(gdouble));
  gboolean *nulls = (gboolean *)calloc(gt->n_groups, sizeof(gboolean));

  for (int g = 0; g < gt->n_groups; g++) {
    gdouble sum = 0.0;
    gboolean all_null = TRUE;
    for (int r = 0; r < gt->group_sizes[g]; r++) {
      gboolean is_null;
      gdouble val = get_numeric_value(gt->table, col_idx, gt->group_row_indices[g][r], &is_null);
      if (!is_null) {
        sum += val;
        all_null = FALSE;
      }
    }
    sums[g] = sum;
    nulls[g] = all_null;
  }

  GArrowTable *result = build_aggregation_result(gt, col_name, sums, nulls);
  free(sums);
  free(nulls);

  if (result == NULL) CAMLreturn(Val_none);

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)result));
  CAMLreturn(v_result);
}

/* Mean aggregation per group.
   Args: grouped_table_ptr, column_name
   Returns: Some(result_table_ptr) or None */
CAMLprim value caml_arrow_group_mean(value v_grouped_ptr, value v_col_name) {
  CAMLparam2(v_grouped_ptr, v_col_name);
  CAMLlocal1(v_result);

  GroupedTable *gt = (GroupedTable *)Nativeint_val(v_grouped_ptr);
  const char *col_name = String_val(v_col_name);

  GArrowSchema *schema = garrow_table_get_schema(gt->table);
  gint col_idx = garrow_schema_get_field_index(schema, col_name);
  g_object_unref(schema);

  if (col_idx < 0) CAMLreturn(Val_none);

  gdouble *means = (gdouble *)calloc(gt->n_groups, sizeof(gdouble));
  gboolean *nulls = (gboolean *)calloc(gt->n_groups, sizeof(gboolean));

  for (int g = 0; g < gt->n_groups; g++) {
    gdouble sum = 0.0;
    int count = 0;
    for (int r = 0; r < gt->group_sizes[g]; r++) {
      gboolean is_null;
      gdouble val = get_numeric_value(gt->table, col_idx, gt->group_row_indices[g][r], &is_null);
      if (!is_null) {
        sum += val;
        count++;
      }
    }
    if (count > 0) {
      means[g] = sum / (gdouble)count;
      nulls[g] = FALSE;
    } else {
      nulls[g] = TRUE;
    }
  }

  GArrowTable *result = build_aggregation_result(gt, col_name, means, nulls);
  free(means);
  free(nulls);

  if (result == NULL) CAMLreturn(Val_none);

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)result));
  CAMLreturn(v_result);
}

/* Count aggregation per group.
   Args: grouped_table_ptr
   Returns: Some(result_table_ptr) or None
   Result has key columns + "n" column with group counts. */
CAMLprim value caml_arrow_group_count(value v_grouped_ptr) {
  CAMLparam1(v_grouped_ptr);
  CAMLlocal1(v_result);

  GroupedTable *gt = (GroupedTable *)Nativeint_val(v_grouped_ptr);

  gdouble *counts = (gdouble *)malloc(sizeof(gdouble) * gt->n_groups);
  gboolean *nulls = (gboolean *)calloc(gt->n_groups, sizeof(gboolean));

  for (int g = 0; g < gt->n_groups; g++) {
    counts[g] = (gdouble)gt->group_sizes[g];
  }

  GArrowTable *result = build_aggregation_result(gt, "n", counts, nulls);
  free(counts);
  free(nulls);

  if (result == NULL) CAMLreturn(Val_none);

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)result));
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Zero-Copy Buffer Access (Phase 4)                                     */
/* ===================================================================== */

/* Get the raw data buffer pointer and size from an Arrow array.
   Args: array_ptr (nativeint — GArrowArray*)
   Returns: Some (pointer, length) or None if buffer is unavailable.
   The pointer is to the raw value data buffer of the array.
   SAFETY: The returned pointer is valid only as long as the parent
   GArrowArray (and its parent GArrowTable) is alive. The GArrowBuffer
   wrapper is unreffed here, but the data is owned by the array. */
CAMLprim value caml_arrow_array_get_buffer_ptr(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal2(v_result, v_tuple);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  /* Cast to GArrowPrimitiveArray to access the data buffer.
     Int64Array and DoubleArray both inherit from PrimitiveArray. */
  if (!GARROW_IS_PRIMITIVE_ARRAY(array)) {
    CAMLreturn(Val_none);
  }
  GArrowBuffer *buffer =
    garrow_primitive_array_get_data_buffer(GARROW_PRIMITIVE_ARRAY(array));

  if (buffer == NULL) {
    CAMLreturn(Val_none);
  }

  GBytes *bytes = garrow_buffer_get_data(buffer);
  gsize size = 0;
  const guint8 *data = (const guint8 *)g_bytes_get_data(bytes, &size);

  /* Return Some (pointer, length) */
  v_tuple = caml_alloc(2, 0);
  Store_field(v_tuple, 0, caml_copy_nativeint((intnat)data));
  Store_field(v_tuple, 1, Val_long(size));

  v_result = caml_alloc(1, 0); /* Some(...) */
  Store_field(v_result, 0, v_tuple);

  /* Safe to unref: the GArrowBuffer and GBytes are wrappers; the actual
     data is owned by the GArrowArray, which remains alive via the
     OCaml-side GC finalizer on the parent table. */
  g_bytes_unref(bytes);
  g_object_unref(buffer);
  CAMLreturn(v_result);
}

/* Create a zero-copy Float64 Bigarray from an Arrow array.
   Args: array_ptr (nativeint — GArrowArray*)
   Returns: Some (float, float64_elt, c_layout) Array1.t or None.
   Handles buffer access internally — no raw pointers are exposed.
   The Bigarray does NOT own the memory (CAML_BA_EXTERNAL).
   Caller must keep the parent GArrowTable alive. */
CAMLprim value caml_arrow_float64_array_to_bigarray(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal1(v_result);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  /* Cast to GArrowPrimitiveArray to access the data buffer.
     DoubleArray inherits from PrimitiveArray. */
  if (!GARROW_IS_PRIMITIVE_ARRAY(array)) {
    CAMLreturn(Val_none);
  }
  GArrowBuffer *buffer =
    garrow_primitive_array_get_data_buffer(GARROW_PRIMITIVE_ARRAY(array));

  if (buffer == NULL) {
    CAMLreturn(Val_none);
  }

  GBytes *bytes = garrow_buffer_get_data(buffer);
  gsize size = 0;
  const guint8 *data = (const guint8 *)g_bytes_get_data(bytes, &size);
  intnat n_elements = (intnat)(size / sizeof(double));
  intnat dims[1] = { n_elements };

  value ba = caml_ba_alloc(
    CAML_BA_FLOAT64 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL,
    1, (void *)data, dims);

  /* Safe to unref the wrappers; data owned by the array */
  g_bytes_unref(bytes);
  g_object_unref(buffer);

  v_result = caml_alloc(1, 0); /* Some(...) */
  Store_field(v_result, 0, ba);
  CAMLreturn(v_result);
}

/* Create a zero-copy Int64 Bigarray from an Arrow array.
   Args: array_ptr (nativeint — GArrowArray*)
   Returns: Some (int64, int64_elt, c_layout) Array1.t or None.
   Handles buffer access internally — no raw pointers are exposed.
   The Bigarray does NOT own the memory (CAML_BA_EXTERNAL).
   Caller must keep the parent GArrowTable alive. */
CAMLprim value caml_arrow_int64_array_to_bigarray(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal1(v_result);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  /* Cast to GArrowPrimitiveArray to access the data buffer.
     Int64Array inherits from PrimitiveArray. */
  if (!GARROW_IS_PRIMITIVE_ARRAY(array)) {
    CAMLreturn(Val_none);
  }
  GArrowBuffer *buffer =
    garrow_primitive_array_get_data_buffer(GARROW_PRIMITIVE_ARRAY(array));

  if (buffer == NULL) {
    CAMLreturn(Val_none);
  }

  GBytes *bytes = garrow_buffer_get_data(buffer);
  gsize size = 0;
  const guint8 *data = (const guint8 *)g_bytes_get_data(bytes, &size);
  intnat n_elements = (intnat)(size / sizeof(gint64));
  intnat dims[1] = { n_elements };

  value ba = caml_ba_alloc(
    CAML_BA_INT64 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL,
    1, (void *)data, dims);

  /* Safe to unref the wrappers; data owned by the array */
  g_bytes_unref(bytes);
  g_object_unref(buffer);

  v_result = caml_alloc(1, 0); /* Some(...) */
  Store_field(v_result, 0, ba);
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Unary Math Operations (Phase 5 — Week 1)                              */
/* ===================================================================== */

/* Helper: apply a unary math operation element-by-element on a numeric column.
   op_code: 0=sqrt, 1=abs, 2=log, 3=exp.
   Returns a new GArrowChunkedArray* with the results, or NULL on failure. */
static GArrowChunkedArray *
apply_unary_math_op(GArrowChunkedArray *chunked, int op_code)
{
  GError *error = NULL;
  guint n_chunks = garrow_chunked_array_get_n_chunks(chunked);

  GList *result_chunks = NULL;
  gboolean ok = TRUE;

  for (guint c = 0; c < n_chunks && ok; c++) {
    GArrowArray *chunk = garrow_chunked_array_get_chunk(chunked, c);
    gint64 length = garrow_array_get_length(chunk);

    GArrowDoubleArrayBuilder *builder = garrow_double_array_builder_new();

    for (gint64 i = 0; i < length; i++) {
      if (garrow_array_is_null(chunk, i)) {
        garrow_array_builder_append_null(GARROW_ARRAY_BUILDER(builder), &error);
      } else {
        gdouble val;
        if (GARROW_IS_DOUBLE_ARRAY(chunk)) {
          val = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk), i);
        } else if (GARROW_IS_INT64_ARRAY(chunk)) {
          val = (gdouble)garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk), i);
        } else {
          ok = FALSE;
          break;
        }

        gdouble result;
        switch (op_code) {
          case 0: result = sqrt(val); break;
          case 1: result = fabs(val); break;
          case 2: result = log(val); break;
          case 3: result = exp(val); break;
          default: result = val; break;
        }

        garrow_double_array_builder_append_value(builder, result, &error);
      }
      if (error) { ok = FALSE; break; }
    }

    if (ok) {
      GArrowArray *result_array =
          garrow_array_builder_finish(GARROW_ARRAY_BUILDER(builder), &error);
      if (result_array) {
        result_chunks = g_list_append(result_chunks, result_array);
      } else {
        ok = FALSE;
      }
    }
    g_object_unref(builder);
    g_object_unref(chunk);
  }

  if (!ok || result_chunks == NULL) {
    g_list_free_full(result_chunks, g_object_unref);
    if (error) g_error_free(error);
    return NULL;
  }

  GArrowChunkedArray *result =
      garrow_chunked_array_new(result_chunks, &error);
  g_list_free_full(result_chunks, g_object_unref);

  if (result == NULL && error) g_error_free(error);
  return result;
}

/* Generic unary math operation: table_ptr, column_name, op_code.
   Returns Some(new_table_ptr) or None. */
static value arrow_unary_math_impl(value v_ptr, value v_col_name, int op_code) {
  CAMLparam2(v_ptr, v_col_name);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *col_name = String_val(v_col_name);

  GArrowSchema *schema = garrow_table_get_schema(table);
  gint idx = garrow_schema_get_field_index(schema, col_name);
  g_object_unref(schema);

  if (idx < 0) CAMLreturn(Val_none);

  GArrowChunkedArray *col = garrow_table_get_column_data(table, idx);
  if (col == NULL) CAMLreturn(Val_none);

  GArrowChunkedArray *result_col = apply_unary_math_op(col, op_code);
  g_object_unref(col);

  if (result_col == NULL) CAMLreturn(Val_none);

  GArrowTable *new_table = rebuild_table_with_column(table, (guint)idx, result_col);
  g_object_unref(result_col);

  if (new_table == NULL) CAMLreturn(Val_none);

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)new_table));
  CAMLreturn(v_result);
}

/* sqrt: Apply sqrt to every element of a named column */
CAMLprim value caml_arrow_compute_sqrt_column(value v_ptr, value v_col_name) {
  return arrow_unary_math_impl(v_ptr, v_col_name, 0);
}

/* abs: Apply fabs to every element of a named column */
CAMLprim value caml_arrow_compute_abs_column(value v_ptr, value v_col_name) {
  return arrow_unary_math_impl(v_ptr, v_col_name, 1);
}

/* log: Apply natural log to every element of a named column */
CAMLprim value caml_arrow_compute_log_column(value v_ptr, value v_col_name) {
  return arrow_unary_math_impl(v_ptr, v_col_name, 2);
}

/* exp: Apply exp to every element of a named column */
CAMLprim value caml_arrow_compute_exp_column(value v_ptr, value v_col_name) {
  return arrow_unary_math_impl(v_ptr, v_col_name, 3);
}

/* pow: Raise every element of a named column to a scalar power.
   Args: table_ptr, column_name, exponent
   Returns: Some(new_table_ptr) or None */
CAMLprim value caml_arrow_compute_pow_column(value v_ptr, value v_col_name, value v_exp) {
  CAMLparam3(v_ptr, v_col_name, v_exp);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *col_name = String_val(v_col_name);
  double exponent = Double_val(v_exp);

  GArrowSchema *schema = garrow_table_get_schema(table);
  gint idx = garrow_schema_get_field_index(schema, col_name);
  g_object_unref(schema);

  if (idx < 0) CAMLreturn(Val_none);

  GArrowChunkedArray *col = garrow_table_get_column_data(table, idx);
  if (col == NULL) CAMLreturn(Val_none);

  /* Apply pow element-by-element */
  GError *error = NULL;
  guint n_chunks = garrow_chunked_array_get_n_chunks(col);
  GList *result_chunks = NULL;
  gboolean ok = TRUE;

  for (guint c = 0; c < n_chunks && ok; c++) {
    GArrowArray *chunk = garrow_chunked_array_get_chunk(col, c);
    gint64 length = garrow_array_get_length(chunk);
    GArrowDoubleArrayBuilder *builder = garrow_double_array_builder_new();

    for (gint64 i = 0; i < length; i++) {
      if (garrow_array_is_null(chunk, i)) {
        garrow_array_builder_append_null(GARROW_ARRAY_BUILDER(builder), &error);
      } else {
        gdouble val;
        if (GARROW_IS_DOUBLE_ARRAY(chunk)) {
          val = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk), i);
        } else if (GARROW_IS_INT64_ARRAY(chunk)) {
          val = (gdouble)garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk), i);
        } else { ok = FALSE; break; }

        garrow_double_array_builder_append_value(builder, pow(val, exponent), &error);
      }
      if (error) { ok = FALSE; break; }
    }

    if (ok) {
      GArrowArray *arr = garrow_array_builder_finish(GARROW_ARRAY_BUILDER(builder), &error);
      if (arr) result_chunks = g_list_append(result_chunks, arr);
      else ok = FALSE;
    }
    g_object_unref(builder);
    g_object_unref(chunk);
  }

  g_object_unref(col);

  if (!ok || result_chunks == NULL) {
    g_list_free_full(result_chunks, g_object_unref);
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  GArrowChunkedArray *result_col = garrow_chunked_array_new(result_chunks, &error);
  g_list_free_full(result_chunks, g_object_unref);

  if (result_col == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  GArrowTable *new_table = rebuild_table_with_column(table, (guint)idx, result_col);
  g_object_unref(result_col);

  if (new_table == NULL) CAMLreturn(Val_none);

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_nativeint((intnat)new_table));
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Column-Level Aggregations (Phase 5 — Week 1)                          */
/* ===================================================================== */

/* Helper: extract numeric value from a chunked array at a row index.
   Used for aggregation operations. Returns the value and sets *is_null. */
static gdouble get_chunked_numeric_value(GArrowChunkedArray *chunked,
                                          gint64 row_idx, gboolean *is_null) {
  guint n_chunks = garrow_chunked_array_get_n_chunks(chunked);
  gint64 offset = row_idx;
  for (guint c = 0; c < n_chunks; c++) {
    GArrowArray *chunk = garrow_chunked_array_get_chunk(chunked, c);
    gint64 chunk_len = garrow_array_get_length(chunk);
    if (offset < chunk_len) {
      if (garrow_array_is_null(chunk, offset)) {
        *is_null = TRUE;
        g_object_unref(chunk);
        return 0.0;
      }
      gdouble val = 0.0;
      if (GARROW_IS_DOUBLE_ARRAY(chunk)) {
        val = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk), offset);
      } else if (GARROW_IS_INT64_ARRAY(chunk)) {
        val = (gdouble)garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk), offset);
      } else {
        *is_null = TRUE;
        g_object_unref(chunk);
        return 0.0;
      }
      *is_null = FALSE;
      g_object_unref(chunk);
      return val;
    }
    offset -= chunk_len;
    g_object_unref(chunk);
  }
  *is_null = TRUE;
  return 0.0;
}

/* Generic column aggregation: table_ptr, column_name.
   agg_code: 0=sum, 1=mean, 2=min, 3=max.
   Returns Some(float) or None.
   Iterates chunks sequentially for O(n) instead of O(n*c) access. */
static value arrow_column_agg_impl(value v_ptr, value v_col_name, int agg_code) {
  CAMLparam2(v_ptr, v_col_name);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *col_name = String_val(v_col_name);

  GArrowSchema *schema = garrow_table_get_schema(table);
  gint idx = garrow_schema_get_field_index(schema, col_name);
  g_object_unref(schema);

  if (idx < 0) CAMLreturn(Val_none);

  GArrowChunkedArray *col = garrow_table_get_column_data(table, idx);
  if (col == NULL) CAMLreturn(Val_none);

  gdouble result = 0.0;
  int count = 0;
  gboolean initialized = FALSE;

  /* Iterate chunks sequentially — O(n) total instead of O(n*c) */
  guint n_chunks = garrow_chunked_array_get_n_chunks(col);
  for (guint c = 0; c < n_chunks; c++) {
    GArrowArray *chunk = garrow_chunked_array_get_chunk(col, c);
    gint64 chunk_len = garrow_array_get_length(chunk);

    /* Verify chunk type is numeric before iterating */
    gboolean is_double = GARROW_IS_DOUBLE_ARRAY(chunk);
    gboolean is_int64 = GARROW_IS_INT64_ARRAY(chunk);
    if (!is_double && !is_int64) {
      g_object_unref(chunk);
      continue; /* Skip non-numeric chunks */
    }

    for (gint64 i = 0; i < chunk_len; i++) {
      if (garrow_array_is_null(chunk, i)) continue;

      gdouble val;
      if (is_double) {
        val = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk), i);
      } else {
        val = (gdouble)garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk), i);
      }

      switch (agg_code) {
        case 0: /* sum */
          result += val;
          break;
        case 1: /* mean */
          result += val;
          count++;
          break;
        case 2: /* min */
          if (!initialized || val < result) result = val;
          break;
        case 3: /* max */
          if (!initialized || val > result) result = val;
          break;
      }
      initialized = TRUE;
    }
    g_object_unref(chunk);
  }
  g_object_unref(col);

  if (!initialized) CAMLreturn(Val_none);
  if (agg_code == 1 && count > 0) result = result / (gdouble)count;
  if (agg_code == 1 && count == 0) CAMLreturn(Val_none);

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, caml_copy_double(result));
  CAMLreturn(v_result);
}

CAMLprim value caml_arrow_compute_sum_column(value v_ptr, value v_col_name) {
  return arrow_column_agg_impl(v_ptr, v_col_name, 0);
}

CAMLprim value caml_arrow_compute_mean_column(value v_ptr, value v_col_name) {
  return arrow_column_agg_impl(v_ptr, v_col_name, 1);
}

CAMLprim value caml_arrow_compute_min_column(value v_ptr, value v_col_name) {
  return arrow_column_agg_impl(v_ptr, v_col_name, 2);
}

CAMLprim value caml_arrow_compute_max_column(value v_ptr, value v_col_name) {
  return arrow_column_agg_impl(v_ptr, v_col_name, 3);
}

/* ===================================================================== */
/* Comparison Operations (Phase 5 — Week 1)                              */
/* ===================================================================== */

/* Compare each element of a named numeric column to a scalar.
   op_code: 0=eq, 1=lt, 2=gt, 3=le, 4=ge.
   Returns Some(bool_array) or None. */
CAMLprim value caml_arrow_compute_compare_scalar(value v_ptr, value v_col_name,
                                                  value v_scalar, value v_op_code) {
  CAMLparam4(v_ptr, v_col_name, v_scalar, v_op_code);
  CAMLlocal2(v_result, v_arr);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *col_name = String_val(v_col_name);
  double scalar_val = Double_val(v_scalar);
  int op_code = Int_val(v_op_code);

  GArrowSchema *schema = garrow_table_get_schema(table);
  gint idx = garrow_schema_get_field_index(schema, col_name);
  g_object_unref(schema);

  if (idx < 0) CAMLreturn(Val_none);

  GArrowChunkedArray *col = garrow_table_get_column_data(table, idx);
  if (col == NULL) CAMLreturn(Val_none);

  gint64 nrows = garrow_chunked_array_get_n_rows(col);
  v_arr = caml_alloc(nrows, 0);

  gint64 arr_idx = 0;
  guint n_chunks = garrow_chunked_array_get_n_chunks(col);
  for (guint c = 0; c < n_chunks; c++) {
    GArrowArray *chunk = garrow_chunked_array_get_chunk(col, c);
    gint64 chunk_len = garrow_array_get_length(chunk);

    for (gint64 i = 0; i < chunk_len; i++) {
      gboolean cmp_result = FALSE;
      if (!garrow_array_is_null(chunk, i)) {
        gdouble val = 0.0;
        if (GARROW_IS_DOUBLE_ARRAY(chunk)) {
          val = garrow_double_array_get_value(GARROW_DOUBLE_ARRAY(chunk), i);
        } else if (GARROW_IS_INT64_ARRAY(chunk)) {
          val = (gdouble)garrow_int64_array_get_value(GARROW_INT64_ARRAY(chunk), i);
        }
        switch (op_code) {
          case 0: cmp_result = (val == scalar_val); break;
          case 1: cmp_result = (val < scalar_val); break;
          case 2: cmp_result = (val > scalar_val); break;
          case 3: cmp_result = (val <= scalar_val); break;
          case 4: cmp_result = (val >= scalar_val); break;
          default: cmp_result = FALSE; break;
        }
      }
      Store_field(v_arr, arr_idx, Val_bool(cmp_result));
      arr_idx++;
    }
    g_object_unref(chunk);
  }

  g_object_unref(col);

  v_result = caml_alloc(1, 0);
  Store_field(v_result, 0, v_arr);
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* IPC Read/Write                                                       */
/* ===================================================================== */

/* Read Arrow table from IPC file */
CAMLprim value caml_arrow_read_ipc(value v_path) {
  CAMLparam1(v_path);
  CAMLlocal1(v_result);

  const char *path = String_val(v_path);
  GError *error = NULL;

  GArrowMemoryMappedInputStream *input =
    garrow_memory_mapped_input_stream_new(path, &error);
  if (input == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  /* Feather V2 IS Arrow IPC File format */
  GArrowFeatherFileReader *reader =
    garrow_feather_file_reader_new(GARROW_SEEKABLE_INPUT_STREAM(input), &error);
  if (reader == NULL) {
    g_object_unref(input);
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  GArrowTable *table = garrow_feather_file_reader_read(reader, &error);
  g_object_unref(reader);
  g_object_unref(input);

  if (table == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_none);
  }

  /* Wrap as Some(nativeint) */
  v_result = caml_alloc(1, 0);  /* Some(...) */
  Store_field(v_result, 0, caml_copy_nativeint((intnat)table));
  CAMLreturn(v_result);
}

/* Write Arrow table to IPC file */
CAMLprim value caml_arrow_write_ipc(value v_ptr, value v_path) {
  CAMLparam2(v_ptr, v_path);
  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *path = String_val(v_path);
  GError *error = NULL;

  GArrowFileOutputStream *output =
    garrow_file_output_stream_new(path, FALSE, &error);
  if (output == NULL) {
    if (error) g_error_free(error);
    CAMLreturn(Val_bool(FALSE));
  }

  GArrowSchema *schema = garrow_table_get_schema(table);
  GArrowRecordBatchFileWriter *writer =
    garrow_record_batch_file_writer_new(GARROW_OUTPUT_STREAM(output), schema, &error);
  g_object_unref(schema);

  if (writer == NULL) {
    g_object_unref(output);
    if (error) g_error_free(error);
    CAMLreturn(Val_bool(FALSE));
  }

  gboolean ok = garrow_record_batch_writer_write_table(GARROW_RECORD_BATCH_WRITER(writer), table, &error);
  garrow_record_batch_writer_close(GARROW_RECORD_BATCH_WRITER(writer), NULL);
  g_object_unref(writer);
  g_object_unref(output);

  if (!ok && error) g_error_free(error);
  CAMLreturn(Val_bool(ok));
}
/* Create a native Arrow table from a list of (name, type_tag, array) tuples.
   type_tag: 0=Int64, 1=Float64, 2=Boolean, 3=String, 7=Date.
   array is an OCaml option array (None = null, Some x = value). */
CAMLprim value caml_arrow_table_new(value v_cols) {
  CAMLparam1(v_cols);
  CAMLlocal4(v_iter, v_col, v_arr, v_res);
  GError *error = NULL;

  GList *fields = NULL;
  GList *columns = NULL;
  
  v_iter = v_cols;
  while (v_iter != Val_emptylist) {
    v_col = Field(v_iter, 0);
    const char *name = String_val(Field(v_col, 0));
    int type_tag = Int_val(Field(v_col, 1));
    v_arr = Field(v_col, 2);
    int n_rows = Wosize_val(v_arr);
    
    GArrowDataType *dtype = NULL;
    GArrowArrayBuilder *builder = NULL;

    switch (type_tag) {
      case 0: // Int64
        dtype = (GArrowDataType *)garrow_int64_data_type_new();
        builder = (GArrowArrayBuilder *)garrow_int64_array_builder_new();
        for (int i = 0; i < n_rows; i++) {
          value v_opt = Field(v_arr, i);
          if (Is_block(v_opt)) { // Some(x)
            garrow_int64_array_builder_append_value(GARROW_INT64_ARRAY_BUILDER(builder), Long_val(Field(v_opt, 0)), &error);
          } else {
            garrow_array_builder_append_null(builder, &error);
          }
          if (error) break;
        }
        break;
      case 1: // Float64
        dtype = (GArrowDataType *)garrow_double_data_type_new();
        builder = (GArrowArrayBuilder *)garrow_double_array_builder_new();
        for (int i = 0; i < n_rows; i++) {
          value v_opt = Field(v_arr, i);
          if (Is_block(v_opt)) {
            garrow_double_array_builder_append_value(GARROW_DOUBLE_ARRAY_BUILDER(builder), Double_val(Field(v_opt, 0)), &error);
          } else {
            garrow_array_builder_append_null(builder, &error);
          }
          if (error) break;
        }
        break;
      case 2: // Boolean
        dtype = (GArrowDataType *)garrow_boolean_data_type_new();
        builder = (GArrowArrayBuilder *)garrow_boolean_array_builder_new();
        for (int i = 0; i < n_rows; i++) {
          value v_opt = Field(v_arr, i);
          if (Is_block(v_opt)) {
            garrow_boolean_array_builder_append_value(GARROW_BOOLEAN_ARRAY_BUILDER(builder), Bool_val(Field(v_opt, 0)), &error);
          } else {
            garrow_array_builder_append_null(builder, &error);
          }
          if (error) break;
        }
        break;
      case 3: // String
        dtype = (GArrowDataType *)garrow_string_data_type_new();
        builder = (GArrowArrayBuilder *)garrow_string_array_builder_new();
        for (int i = 0; i < n_rows; i++) {
          value v_opt = Field(v_arr, i);
          if (Is_block(v_opt)) {
            garrow_string_array_builder_append_string(GARROW_STRING_ARRAY_BUILDER(builder), String_val(Field(v_opt, 0)), &error);
          } else {
            garrow_array_builder_append_null(builder, &error);
          }
          if (error) break;
        }
        break;
      case 4: { // Dictionary (Factor)
        /* v_arr is a tuple: (int option array, string list, bool)
           Field 0 = indices (int option array)
           Field 1 = levels (string list)
           Field 2 = ordered (bool — encoded in Arrow DictionaryDataType) */
        value v_dict_indices = Field(v_arr, 0);
        value v_dict_levels = Field(v_arr, 1);
        gboolean dict_ordered = Bool_val(Field(v_arr, 2));
        int n_indices = Wosize_val(v_dict_indices);

        /* Build the dictionary (levels) as a GArrowStringArray */
        GArrowStringArrayBuilder *dict_builder = garrow_string_array_builder_new();
        value v_level_iter = v_dict_levels;
        while (v_level_iter != Val_emptylist) {
          value v_head = Field(v_level_iter, 0);
          garrow_string_array_builder_append_string(dict_builder, String_val(v_head), &error);
          if (error) break;
          v_level_iter = Field(v_level_iter, 1);
        }
        if (error) {
          g_object_unref(dict_builder);
          break;
        }
        GArrowArray *dict_arr = garrow_array_builder_finish(GARROW_ARRAY_BUILDER(dict_builder), &error);
        g_object_unref(dict_builder);
        if (error || dict_arr == NULL) {
          if (dict_arr) g_object_unref(dict_arr);
          break;
        }

        /* Build the indices as a GArrowInt32Array */
        GArrowInt32ArrayBuilder *idx_builder = garrow_int32_array_builder_new();
        for (int i = 0; i < n_indices; i++) {
          value v_opt = Field(v_dict_indices, i);
          if (Is_block(v_opt)) { /* Some(idx) */
            garrow_int32_array_builder_append_value(idx_builder, (gint32)Long_val(Field(v_opt, 0)), &error);
          } else {
            garrow_array_builder_append_null(GARROW_ARRAY_BUILDER(idx_builder), &error);
          }
          if (error) break;
        }
        if (error) {
          g_object_unref(idx_builder);
          g_object_unref(dict_arr);
          break;
        }
        GArrowArray *idx_arr = garrow_array_builder_finish(GARROW_ARRAY_BUILDER(idx_builder), &error);
        g_object_unref(idx_builder);
        if (error || idx_arr == NULL) {
          if (idx_arr) g_object_unref(idx_arr);
          g_object_unref(dict_arr);
          break;
        }

        /* Create Dictionary data type and array — pass ordered flag from OCaml */
        GArrowDataType *idx_dtype = (GArrowDataType *)garrow_int32_data_type_new();
        GArrowDataType *val_dtype = (GArrowDataType *)garrow_string_data_type_new();
        dtype = (GArrowDataType *)garrow_dictionary_data_type_new(idx_dtype, val_dtype, dict_ordered);
        g_object_unref(idx_dtype);
        g_object_unref(val_dtype);

        GArrowDictionaryArray *dict_array_obj = garrow_dictionary_array_new(
          dtype, idx_arr, dict_arr, &error);
        g_object_unref(idx_arr);
        g_object_unref(dict_arr);

        if (error || dict_array_obj == NULL) {
          if (dict_array_obj) g_object_unref(dict_array_obj);
          break;
        }

        /* Wrap in chunked array and add to field/column lists directly */
        GList *chunks = g_list_append(NULL, dict_array_obj);
        GArrowChunkedArray *chunked = garrow_chunked_array_new(chunks, &error);
        g_list_free(chunks);
        g_object_unref(dict_array_obj);

        if (error || chunked == NULL) {
          if (chunked) g_object_unref(chunked);
          break;
        }

        GArrowField *field = garrow_field_new(name, dtype);
        fields = g_list_append(fields, field);
        columns = g_list_append(columns, chunked);
        g_object_unref(dtype);
        dtype = NULL;
        n_rows = 0;
        break;
      }
      case 5: { // List of Structs (ListColumn — nested DataFrames)
        /* v_arr is a tuple:
           Field 0 = offsets (int array, length = n_list_rows+1)
           Field 1 = present (bool array, length = n_list_rows, true=valid)
           Field 2 = sub_columns ((string * int * data) list — same format as top-level cols) */
        value v_offsets = Field(v_arr, 0);
        value v_present = Field(v_arr, 1);
        value v_sub_cols_list = Field(v_arr, 2);

        int n_offsets = Wosize_val(v_offsets);
        int n_list_rows = Wosize_val(v_present);
        int n_total_vals = 0;
        if (n_offsets > 0) {
          n_total_vals = Int_val(Field(v_offsets, n_offsets - 1));
        }

        /* Count sub-columns */
        int n_sub_cols = 0;
        { value v_cnt = v_sub_cols_list;
          while (v_cnt != Val_emptylist) { n_sub_cols++; v_cnt = Field(v_cnt, 1); }
        }

        if (n_sub_cols == 0) break; /* empty struct — skip */

        GArrowField **sub_fields = g_new0(GArrowField *, n_sub_cols);
        GArrowArray **sub_arrays = g_new0(GArrowArray *, n_sub_cols);
        int sub_ok = 1;
        int si = 0;

        value v_sc = v_sub_cols_list;
        while (v_sc != Val_emptylist && sub_ok) {
          value v_sub = Field(v_sc, 0);
          const char *sub_name = String_val(Field(v_sub, 0));
          int sub_tag = Int_val(Field(v_sub, 1));
          value v_sub_data = Field(v_sub, 2);

          GArrowDataType *sub_dtype = NULL;
          GArrowArrayBuilder *sub_builder = NULL;

          switch (sub_tag) {
            case 0: { /* Int64 */
              sub_dtype = (GArrowDataType *)garrow_int64_data_type_new();
              sub_builder = (GArrowArrayBuilder *)garrow_int64_array_builder_new();
              for (int j = 0; j < n_total_vals; j++) {
                value v_opt = Field(v_sub_data, j);
                if (Is_block(v_opt))
                  garrow_int64_array_builder_append_value(GARROW_INT64_ARRAY_BUILDER(sub_builder), Long_val(Field(v_opt, 0)), &error);
                else
                  garrow_array_builder_append_null(sub_builder, &error);
                if (error) { sub_ok = 0; break; }
              }
              break;
            }
            case 1: { /* Float64 */
              sub_dtype = (GArrowDataType *)garrow_double_data_type_new();
              sub_builder = (GArrowArrayBuilder *)garrow_double_array_builder_new();
              for (int j = 0; j < n_total_vals; j++) {
                value v_opt = Field(v_sub_data, j);
                if (Is_block(v_opt))
                  garrow_double_array_builder_append_value(GARROW_DOUBLE_ARRAY_BUILDER(sub_builder), Double_val(Field(v_opt, 0)), &error);
                else
                  garrow_array_builder_append_null(sub_builder, &error);
                if (error) { sub_ok = 0; break; }
              }
              break;
            }
            case 2: { /* Boolean */
              sub_dtype = (GArrowDataType *)garrow_boolean_data_type_new();
              sub_builder = (GArrowArrayBuilder *)garrow_boolean_array_builder_new();
              for (int j = 0; j < n_total_vals; j++) {
                value v_opt = Field(v_sub_data, j);
                if (Is_block(v_opt))
                  garrow_boolean_array_builder_append_value(GARROW_BOOLEAN_ARRAY_BUILDER(sub_builder), Bool_val(Field(v_opt, 0)), &error);
                else
                  garrow_array_builder_append_null(sub_builder, &error);
                if (error) { sub_ok = 0; break; }
              }
              break;
            }
            case 3: { /* String */
              sub_dtype = (GArrowDataType *)garrow_string_data_type_new();
              sub_builder = (GArrowArrayBuilder *)garrow_string_array_builder_new();
              for (int j = 0; j < n_total_vals; j++) {
                value v_opt = Field(v_sub_data, j);
                if (Is_block(v_opt))
                  garrow_string_array_builder_append_string(GARROW_STRING_ARRAY_BUILDER(sub_builder), String_val(Field(v_opt, 0)), &error);
                else
                  garrow_array_builder_append_null(sub_builder, &error);
                if (error) { sub_ok = 0; break; }
              }
              break;
            }
            case 7: { /* Date32 */
              sub_dtype = (GArrowDataType *)garrow_date32_data_type_new();
              sub_builder = (GArrowArrayBuilder *)garrow_date32_array_builder_new();
              for (int j = 0; j < n_total_vals; j++) {
                value v_opt = Field(v_sub_data, j);
                if (Is_block(v_opt))
                  garrow_date32_array_builder_append_value(GARROW_DATE32_ARRAY_BUILDER(sub_builder), (gint32)Long_val(Field(v_opt, 0)), &error);
                else
                  garrow_array_builder_append_null(sub_builder, &error);
                if (error) { sub_ok = 0; break; }
              }
              break;
            }
            default:
              sub_ok = 0;
              break;
          }

          if (sub_ok && sub_builder) {
            GArrowArray *sub_array = garrow_array_builder_finish(sub_builder, &error);
            g_object_unref(sub_builder);
            if (error || sub_array == NULL) {
              if (sub_array) g_object_unref(sub_array);
              if (sub_dtype) g_object_unref(sub_dtype);
              sub_ok = 0;
            } else {
              sub_fields[si] = garrow_field_new(sub_name, sub_dtype);
              sub_arrays[si] = sub_array;
              g_object_unref(sub_dtype);
              si++;
            }
          } else {
            if (sub_builder) g_object_unref(sub_builder);
            if (sub_dtype) g_object_unref(sub_dtype);
          }

          v_sc = Field(v_sc, 1);
        }

        if (!sub_ok || si == 0) {
          for (int k = 0; k < si; k++) {
            g_object_unref(sub_fields[k]);
            g_object_unref(sub_arrays[k]);
          }
          g_free(sub_fields);
          g_free(sub_arrays);
          break;
        }

        /* Build struct data type from sub-fields */
        GList *field_list = NULL;
        for (int k = 0; k < si; k++)
          field_list = g_list_append(field_list, sub_fields[k]);
        GArrowStructDataType *struct_dtype_obj =
          garrow_struct_data_type_new(field_list);

        /* Build struct array from sub-arrays */
        GList *array_list = NULL;
        for (int k = 0; k < si; k++)
          array_list = g_list_append(array_list, sub_arrays[k]);
        GArrowStructArray *struct_arr_obj = garrow_struct_array_new(
          GARROW_DATA_TYPE(struct_dtype_obj), n_total_vals,
          array_list, NULL, 0);

        g_list_free(field_list);
        g_list_free(array_list);
        for (int k = 0; k < si; k++) {
          g_object_unref(sub_fields[k]);
          g_object_unref(sub_arrays[k]);
        }
        g_free(sub_fields);
        g_free(sub_arrays);

        if (struct_arr_obj == NULL) {
          g_object_unref(struct_dtype_obj);
          break;
        }

        /* Build offsets buffer (int32) */
        gint32 *offsets_raw = g_new(gint32, n_offsets);
        for (int k = 0; k < n_offsets; k++) {
          offsets_raw[k] = (gint32)Int_val(Field(v_offsets, k));
        }
        GBytes *offsets_bytes = g_bytes_new(offsets_raw, n_offsets * sizeof(gint32));
        GArrowBuffer *offsets_buf = garrow_buffer_new_bytes(offsets_bytes);
        g_bytes_unref(offsets_bytes);
        g_free(offsets_raw);

        /* Build null bitmap */
        int n_nulls = 0;
        int bitmap_bytes = (n_list_rows + 7) / 8;
        guint8 *bitmap_raw = g_new0(guint8, bitmap_bytes > 0 ? bitmap_bytes : 1);
        for (int k = 0; k < n_list_rows; k++) {
          if (Bool_val(Field(v_present, k)))
            bitmap_raw[k / 8] |= (guint8)(1 << (k % 8));
          else
            n_nulls++;
        }
        GArrowBuffer *null_bmp = NULL;
        if (n_nulls > 0) {
          GBytes *null_bytes = g_bytes_new(bitmap_raw, bitmap_bytes);
          null_bmp = garrow_buffer_new_bytes(null_bytes);
          g_bytes_unref(null_bytes);
        }
        g_free(bitmap_raw);

        /* Create list data type */
        GArrowField *item_field = garrow_field_new(
          "item", GARROW_DATA_TYPE(struct_dtype_obj));
        GArrowListDataType *list_dtype_obj =
          garrow_list_data_type_new(item_field);
        g_object_unref(item_field);

        /* Create list array */
        GArrowListArray *list_arr_obj = garrow_list_array_new(
          GARROW_DATA_TYPE(list_dtype_obj),
          n_list_rows, offsets_buf,
          GARROW_ARRAY(struct_arr_obj),
          null_bmp, n_nulls);
 
        /* Lifecycle management: some versions of arrow-glib seem to have issues
           if we unref these immediately. We accept a small leak for stability. */
        /* g_object_unref(offsets_buf); */
        /* if (null_bmp) g_object_unref(null_bmp); */
        /* g_object_unref(struct_arr_obj); */
        g_object_unref(struct_dtype_obj);

        if (list_arr_obj == NULL) {
          g_object_unref(list_dtype_obj);
          break;
        }

        /* Wrap in chunked array */
        GList *lchunks = g_list_append(NULL, list_arr_obj);
        GArrowChunkedArray *lchunked = garrow_chunked_array_new(lchunks, &error);
        g_list_free(lchunks);
        g_object_unref(list_arr_obj);

        if (error || lchunked == NULL) {
          if (lchunked) g_object_unref(lchunked);
          g_object_unref(list_dtype_obj);
          break;
        }

        GArrowField *list_field_obj = garrow_field_new(
          name, GARROW_DATA_TYPE(list_dtype_obj));
        fields = g_list_append(fields, list_field_obj);
        columns = g_list_append(columns, lchunked);
        g_object_unref(list_dtype_obj);
        dtype = NULL;
        builder = NULL;
        n_rows = 0;
        break;
      }
      case 7: // Date32 (days since epoch)
        dtype = (GArrowDataType *)garrow_date32_data_type_new();
        builder = (GArrowArrayBuilder *)garrow_date32_array_builder_new();
        for (int i = 0; i < n_rows; i++) {
          value v_opt = Field(v_arr, i);
          if (Is_block(v_opt)) { // Some(days)
            garrow_date32_array_builder_append_value(GARROW_DATE32_ARRAY_BUILDER(builder), (gint32)Long_val(Field(v_opt, 0)), &error);
          } else {
            garrow_array_builder_append_null(builder, &error);
          }
          if (error) break;
        }
        break;
      default:
        break;
    }

    if (error) {
      if (builder) g_object_unref(builder);
      if (dtype) g_object_unref(dtype);
      break;
    }

    if (builder) {
      GArrowArray *array = garrow_array_builder_finish(builder, &error);
      if (error) {
         g_object_unref(builder);
         if (dtype) g_object_unref(dtype);
         break;
      }
      GList *chunks = g_list_append(NULL, array);
      GArrowChunkedArray *chunked = garrow_chunked_array_new(chunks, &error);
      g_list_free(chunks);
      g_object_unref(builder);
      g_object_unref(array);

      if (error) {
         if (dtype) g_object_unref(dtype);
         break;
      }

      GArrowField *field = garrow_field_new(name, dtype);
      fields = g_list_append(fields, field);
      columns = g_list_append(columns, chunked);
      if (dtype) g_object_unref(dtype);
      dtype = NULL;
    }

    v_iter = Field(v_iter, 1);
  }

  GArrowTable *table = NULL;
  if (fields && columns) {
    GArrowSchema *schema = garrow_schema_new(fields);
    guint n = g_list_length(columns);
    GArrowChunkedArray **cols_arr = g_new(GArrowChunkedArray *, n);
    GList *iter = columns;
    for (guint i = 0; i < n; i++) {
        cols_arr[i] = (GArrowChunkedArray *)iter->data;
        iter = iter->next;
    }
    table = garrow_table_new_chunked_arrays(schema, cols_arr, n, &error);
    g_free(cols_arr);
    g_object_unref(schema);
  }

  if (fields) g_list_free_full(fields, g_object_unref);
  if (columns) g_list_free_full(columns, g_object_unref);

  if (table == NULL) {
    if (error) {
      // printf("[DEBUG C] table creation error: %s\n", error->message);
      g_error_free(error);
    }
    CAMLreturn(Val_none);
  }

  v_res = caml_alloc(1, 0);
  Store_field(v_res, 0, caml_copy_nativeint((intnat)table));
  CAMLreturn(v_res);
}
