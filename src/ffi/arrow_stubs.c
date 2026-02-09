/* src/ffi/arrow_stubs.c */
/* C FFI stubs for Apache Arrow C GLib integration.                       */
/* These stubs bridge OCaml to the Arrow C GLib (GObject-based) library.  */
/*                                                                        */
/* DEPENDENCIES: arrow-glib (pkg-config: arrow-glib)                      */
/*   Install via: nix develop (flake.nix includes arrow-glib)             */

#include <arrow-glib/arrow-glib.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>

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

/* Get column by name — returns option (Some nativeint | None) */
CAMLprim value caml_arrow_table_get_column_by_name(value v_ptr, value v_name) {
  CAMLparam2(v_ptr, v_name);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *name = String_val(v_name);

  GArrowChunkedArray *column = garrow_table_get_column_by_name(table, name);
  if (column == NULL) {
    CAMLreturn(Val_none);
  }

  /* Wrap as Some(nativeint) */
  v_result = caml_alloc(1, 0);  /* Some(...) */
  Store_field(v_result, 0, caml_copy_nativeint((intnat)column));
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Schema Extraction                                                     */
/* ===================================================================== */

/* Get schema as list of (name, type_tag) pairs.
   type_tag: 0=Int64, 1=Float64, 2=Boolean, 3=String, 4=Null */
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
    if (GARROW_IS_INT64_DATA_TYPE(dtype))        type_tag = 0; /* ArrowInt64 */
    else if (GARROW_IS_DOUBLE_DATA_TYPE(dtype))   type_tag = 1; /* ArrowFloat64 */
    else if (GARROW_IS_BOOLEAN_DATA_TYPE(dtype))  type_tag = 2; /* ArrowBoolean */
    else if (GARROW_IS_STRING_DATA_TYPE(dtype) ||
             GARROW_IS_LARGE_STRING_DATA_TYPE(dtype))
                                                  type_tag = 3; /* ArrowString */
    else                                          type_tag = 4; /* ArrowNull */

    /* Create tuple (name, type_tag) */
    v_col = caml_alloc(2, 0);
    Store_field(v_col, 0, caml_copy_string(name));
    Store_field(v_col, 1, Val_int(type_tag));

    /* Cons onto list */
    v_cons = caml_alloc(2, 0);
    Store_field(v_cons, 0, v_col);
    Store_field(v_cons, 1, v_result);
    v_result = v_cons;

    g_object_unref(field);
  }

  g_object_unref(schema);
  CAMLreturn(v_result);
}

/* ===================================================================== */
/* Column Data Extraction                                                */
/* ===================================================================== */

/* Get a column's first chunk array pointer by name.
   Returns Some(nativeint) or None. */
CAMLprim value caml_arrow_table_get_column_data(value v_ptr, value v_col_name) {
  CAMLparam2(v_ptr, v_col_name);
  CAMLlocal1(v_result);

  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  const char *col_name = String_val(v_col_name);

  GArrowChunkedArray *chunked = garrow_table_get_column_by_name(table, col_name);
  if (chunked == NULL) {
    CAMLreturn(Val_none);
  }

  /* For simplicity, assume single chunk. Multi-chunk support can be added later. */
  GArrowArray *array = garrow_chunked_array_get_chunk(chunked, 0);

  v_result = caml_alloc(1, 0); /* Some(...) */
  Store_field(v_result, 0, caml_copy_nativeint((intnat)array));

  g_object_unref(chunked);
  CAMLreturn(v_result);
}

/* Read an Int64 column into an OCaml int option array */
CAMLprim value caml_arrow_read_int64_column(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal2(v_result, v_some);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  gint64 length = garrow_array_get_length(array);

  v_result = caml_alloc(length, 0);

  GArrowInt64Array *int_array = GARROW_INT64_ARRAY(array);
  for (gint64 i = 0; i < length; i++) {
    if (garrow_array_is_null(array, i)) {
      Store_field(v_result, i, Val_none);
    } else {
      gint64 val = garrow_int64_array_get_value(int_array, i);
      v_some = caml_alloc(1, 0); /* Some(...) */
      Store_field(v_some, 0, Val_long(val));
      Store_field(v_result, i, v_some);
    }
  }

  CAMLreturn(v_result);
}

/* Read a Float64 (double) column into an OCaml float option array */
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

  CAMLreturn(v_result);
}

/* Read a Boolean column into an OCaml bool option array */
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

  CAMLreturn(v_result);
}

/* Read a String column into an OCaml string option array */
CAMLprim value caml_arrow_read_string_column(value v_array_ptr) {
  CAMLparam1(v_array_ptr);
  CAMLlocal2(v_result, v_some);

  GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
  gint64 length = garrow_array_get_length(array);

  v_result = caml_alloc(length, 0);

  GArrowStringArray *str_array = GARROW_STRING_ARRAY(array);
  for (gint64 i = 0; i < length; i++) {
    if (garrow_array_is_null(array, i)) {
      Store_field(v_result, i, Val_none);
    } else {
      gchar *val = garrow_string_array_get_string(str_array, i);
      v_some = caml_alloc(1, 0); /* Some(...) */
      Store_field(v_some, 0, caml_copy_string(val));
      g_free(val);
      Store_field(v_result, i, v_some);
    }
  }

  CAMLreturn(v_result);
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

  /* Create CSV read options */
  GArrowCSVReadOptions *options = garrow_csv_read_options_new();

  /* Create CSV reader */
  GArrowCSVReader *reader =
    garrow_csv_reader_new(GARROW_INPUT_STREAM(input), options, &error);
  g_object_unref(options);

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
      caml_failwith("Column not found");
    }
    indices[i] = (guint)idx;
    iter = Field(iter, 1);
  }

  g_object_unref(schema);

  /* Select columns */
  GError *error = NULL;
  GArrowTable *result = garrow_table_select_columns(table, indices, n_names, &error);
  free(indices);

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

  /* Apply filter */
  GArrowTable *result = garrow_table_filter(table, mask_array, NULL, &error);
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
