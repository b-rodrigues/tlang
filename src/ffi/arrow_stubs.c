#define CAML_NAME_SPACE
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
CAMLprim value caml_arrow_table_free(value v) { return Val_unit; }
CAMLprim value caml_arrow_table_num_rows(value v) { return Val_int(0); }
CAMLprim value caml_arrow_table_num_columns(value v) { return Val_int(0); }
CAMLprim value caml_arrow_table_get_column_by_name(value v1, value v2) { return Val_int(0); }
CAMLprim value caml_arrow_table_get_schema(value v) { return Val_int(0); }
CAMLprim value caml_arrow_table_get_column_data_by_name(value v1, value v2) { return Val_int(0); }
CAMLprim value caml_arrow_read_int64_column(value v) { return Val_int(0); }
CAMLprim value caml_arrow_read_float64_column(value v) { return Val_int(0); }
CAMLprim value caml_arrow_read_boolean_column(value v) { return Val_int(0); }
CAMLprim value caml_arrow_read_string_column(value v) { return Val_int(0); }
CAMLprim value caml_arrow_read_csv(value v) { return Val_int(0); }
CAMLprim value caml_arrow_table_project(value v1, value v2) { return Val_int(0); }
CAMLprim value caml_arrow_table_filter_mask(value v1, value v2) { return Val_int(0); }
CAMLprim value caml_arrow_table_sort(value v1, value v2, value v3) { return Val_int(0); }
CAMLprim value caml_arrow_compute_add_scalar(value v1, value v2, value v3) { return Val_int(0); }
CAMLprim value caml_arrow_compute_multiply_scalar(value v1, value v2, value v3) { return Val_int(0); }
CAMLprim value caml_arrow_compute_subtract_scalar(value v1, value v2, value v3) { return Val_int(0); }
CAMLprim value caml_arrow_compute_divide_scalar(value v1, value v2, value v3) { return Val_int(0); }
CAMLprim value caml_arrow_table_group_by(value v1, value v2) { return Val_int(0); }
CAMLprim value caml_arrow_grouped_table_free(value v) { return Val_unit; }
CAMLprim value caml_arrow_group_sum(value v1, value v2) { return Val_int(0); }
CAMLprim value caml_arrow_group_mean(value v1, value v2) { return Val_int(0); }
CAMLprim value caml_arrow_group_count(value v) { return Val_int(0); }
CAMLprim value caml_arrow_array_get_buffer_ptr(value v) { return Val_int(0); }
CAMLprim value caml_arrow_float64_array_to_bigarray(value v) { return Val_int(0); }
CAMLprim value caml_arrow_int64_array_to_bigarray(value v) { return Val_int(0); }
