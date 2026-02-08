/* src/ffi/arrow_stubs.c */
/* C FFI stubs for Apache Arrow C GLib integration.                       */
/* These stubs bridge OCaml to the Arrow C GLib (GObject-based) library.  */
/*                                                                        */
/* COMPILATION: Not compiled in the current build. When arrow-glib is     */
/* available, add to src/dune:                                            */
/*   (foreign_stubs (language c) (names arrow_stubs)                      */
/*     (flags (:include arrow_cflags.sexp)))                              */
/*                                                                        */
/* DEPENDENCIES: arrow-glib (pkg-config: arrow-glib)                      */
/*   Install via: nix develop (flake.nix includes arrow-glib)             */

#ifdef ARROW_GLIB_AVAILABLE

#include <arrow-glib/arrow-glib.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>

/* --- Memory Management --- */

/* Free Arrow table when OCaml GC collects it */
CAMLprim value caml_arrow_table_free(value v_ptr) {
  CAMLparam1(v_ptr);
  GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
  if (table != NULL) {
    g_object_unref(table);
  }
  CAMLreturn(Val_unit);
}

/* --- Table Queries --- */

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

/* --- CSV Reading --- */

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
    /* Return None for error */
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

/* --- Column Projection (Select) --- */

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

/* --- Filter (Take with boolean mask) --- */

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
    gboolean val = Bool_val(Field(v_mask, i));
    garrow_boolean_array_builder_append_value(builder, val, &error);
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

#endif /* ARROW_GLIB_AVAILABLE */
