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
#include <caml/bigarray.h>

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

  /* Use schema to find column index by name, then get column data */
  GArrowSchema *schema = garrow_table_get_schema(table);
  gint idx = garrow_schema_get_field_index(schema, name);
  g_object_unref(schema);

  if (idx < 0) {
    CAMLreturn(Val_none);
  }

  GArrowChunkedArray *column = garrow_table_get_column_data(table, idx);
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
      g_object_unref(schema);
      CAMLreturn(Val_none);
    }
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

  /* Build the GroupedTable result */
  int n_groups = group_order->len;
  GroupedTable *gt = (GroupedTable *)malloc(sizeof(GroupedTable));
  gt->table = g_object_ref(table);
  gt->n_groups = n_groups;
  gt->n_keys = n_keys;
  gt->key_names = key_names;
  gt->group_sizes = (int *)malloc(sizeof(int) * n_groups);
  gt->group_row_indices = (int **)malloc(sizeof(int *) * n_groups);
  gt->group_key_values = (gchar ***)malloc(sizeof(gchar **) * n_groups);

  for (int g = 0; g < n_groups; g++) {
    GArray *rows = (GArray *)g_ptr_array_index(group_rows, g);
    gt->group_sizes[g] = rows->len;
    gt->group_row_indices[g] = (int *)malloc(sizeof(int) * rows->len);
    memcpy(gt->group_row_indices[g], rows->data, sizeof(int) * rows->len);
    g_array_free(rows, TRUE);

    /* Use pre-stored key values (no delimiter parsing needed) */
    gt->group_key_values[g] = (gchar **)g_ptr_array_index(group_key_vals, g);

    gchar *composite_key = (gchar *)g_ptr_array_index(group_order, g);
    g_free(composite_key);
  }

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
  GArrowBuffer *buffer = garrow_array_get_value_data_buffer(array);

  if (buffer == NULL) {
    CAMLreturn(Val_none);
  }

  gsize size = garrow_buffer_get_size(buffer);
  const guint8 *data = garrow_buffer_get_data(buffer, &size);

  /* Return Some (pointer, length) */
  v_tuple = caml_alloc(2, 0);
  Store_field(v_tuple, 0, caml_copy_nativeint((intnat)data));
  Store_field(v_tuple, 1, Val_long(size));

  v_result = caml_alloc(1, 0); /* Some(...) */
  Store_field(v_result, 0, v_tuple);

  /* Safe to unref: the GArrowBuffer is a wrapper; the actual data is
     owned by the GArrowArray, which remains alive via the OCaml-side
     GC finalizer on the parent table. */
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
  GArrowBuffer *buffer = garrow_array_get_value_data_buffer(array);

  if (buffer == NULL) {
    CAMLreturn(Val_none);
  }

  gsize size = garrow_buffer_get_size(buffer);
  const guint8 *data = garrow_buffer_get_data(buffer, &size);
  intnat n_elements = (intnat)(size / sizeof(double));
  intnat dims[1] = { n_elements };

  value ba = caml_ba_alloc(
    CAML_BA_FLOAT64 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL,
    1, (void *)data, dims);

  /* Safe to unref the wrapper; data owned by the array */
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
  GArrowBuffer *buffer = garrow_array_get_value_data_buffer(array);

  if (buffer == NULL) {
    CAMLreturn(Val_none);
  }

  gsize size = garrow_buffer_get_size(buffer);
  const guint8 *data = garrow_buffer_get_data(buffer, &size);
  intnat n_elements = (intnat)(size / sizeof(gint64));
  intnat dims[1] = { n_elements };

  value ba = caml_ba_alloc(
    CAML_BA_INT64 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL,
    1, (void *)data, dims);

  /* Safe to unref the wrapper; data owned by the array */
  g_object_unref(buffer);

  v_result = caml_alloc(1, 0); /* Some(...) */
  Store_field(v_result, 0, ba);
  CAMLreturn(v_result);
}
