/* src/ffi/onnx_stubs.c */
#include <onnxruntime_c_api.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const OrtApi* g_ort = NULL;
OrtEnv* g_env = NULL;

static void copy_status_message(OrtStatus* status, char* err_buf, size_t err_buf_size) {
    if (status == NULL) {
        snprintf(err_buf, err_buf_size, "%s", "ONNX Runtime error");
        return;
    }
    const char* msg = g_ort->GetErrorMessage(status);
    snprintf(err_buf, err_buf_size, "%s", msg != NULL ? msg : "ONNX Runtime error");
    g_ort->ReleaseStatus(status);
}

#define CHECK_STATUS_GOTO(expr) do { \
    OrtStatus* _status = (expr); \
    if (_status != NULL) { \
        copy_status_message(_status, err_buf, sizeof(err_buf)); \
        goto cleanup; \
    } \
} while (0)

#define SET_ERROR(msg) do { \
    snprintf(err_buf, sizeof(err_buf), "%s", (msg)); \
    goto cleanup; \
} while (0)

static void init_ort() {
    char err_buf[2048] = {0};
    if (g_ort == NULL) {
        g_ort = OrtGetApiBase()->GetApi(ORT_API_VERSION);
        if (g_ort == NULL) caml_failwith("Failed to get ONNX Runtime API");
        CHECK_STATUS_GOTO(g_ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "tlang", &g_env));
    }
    return;

cleanup:
    caml_failwith(err_buf);
}

typedef struct {
    OrtSession* session;
    size_t input_count;
    size_t output_count;
    int64_t input_width;
    char** input_names;
    char** output_names;
} tlang_onnx_session;

static void finalize_onnx_session(value v) {
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v);
    if (s->session) {
        g_ort->ReleaseSession(s->session);
        s->session = NULL;
    }
    for (size_t i = 0; i < s->input_count; i++) free(s->input_names[i]);
    for (size_t i = 0; i < s->output_count; i++) free(s->output_names[i]);
    if (s->input_names) free(s->input_names);
    if (s->output_names) free(s->output_names);
}

static struct custom_operations onnx_session_ops = {
    "org.tstats.onnx_session",
    finalize_onnx_session,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default
};

CAMLprim value caml_onnx_session_create(value v_path) {
    CAMLparam1(v_path);
    CAMLlocal1(v);
    init_ort();
    const char* path = String_val(v_path);
    OrtSessionOptions* session_options = NULL;
    OrtSession* session = NULL;
    OrtAllocator* allocator = NULL;
    OrtTypeInfo* input_type_info = NULL;
    const OrtTensorTypeAndShapeInfo* tensor_info = NULL;
    char** input_names = NULL;
    char** output_names = NULL;
    int64_t* input_dims = NULL;
    size_t input_count = 0;
    size_t output_count = 0;
    int64_t input_width = 0;
    char err_buf[2048] = {0};

    CHECK_STATUS_GOTO(g_ort->CreateSessionOptions(&session_options));
    CHECK_STATUS_GOTO(g_ort->CreateSession(g_env, path, session_options, &session));
    CHECK_STATUS_GOTO(g_ort->SessionGetInputCount(session, &input_count));
    CHECK_STATUS_GOTO(g_ort->SessionGetOutputCount(session, &output_count));
    if (input_count != 1 || output_count != 1) {
        SET_ERROR("Function `predict` currently supports ONNX models with exactly one input and one output.");
    }

    input_names = calloc(input_count, sizeof(char*));
    output_names = calloc(output_count, sizeof(char*));
    if (input_names == NULL || output_names == NULL) {
        SET_ERROR("Failed to allocate ONNX input/output name buffers.");
    }

    CHECK_STATUS_GOTO(g_ort->GetAllocatorWithDefaultOptions(&allocator));

    for (size_t i = 0; i < input_count; i++) {
        char* name = NULL;
        CHECK_STATUS_GOTO(g_ort->SessionGetInputName(session, i, allocator, &name));
        input_names[i] = strdup(name);
        allocator->Free(allocator, name);
        if (input_names[i] == NULL) {
            SET_ERROR("Failed to copy ONNX input name.");
        }
    }

    for (size_t i = 0; i < output_count; i++) {
        char* name = NULL;
        CHECK_STATUS_GOTO(g_ort->SessionGetOutputName(session, i, allocator, &name));
        output_names[i] = strdup(name);
        allocator->Free(allocator, name);
        if (output_names[i] == NULL) {
            SET_ERROR("Failed to copy ONNX output name.");
        }
    }

    CHECK_STATUS_GOTO(g_ort->SessionGetInputTypeInfo(session, 0, &input_type_info));
    tensor_info = g_ort->CastTypeInfoToTensorInfo(input_type_info);
    if (tensor_info != NULL) {
        size_t dim_count = 0;
        CHECK_STATUS_GOTO(g_ort->GetDimensionsCount(tensor_info, &dim_count));
        if (dim_count > 0) {
            input_dims = malloc(sizeof(int64_t) * dim_count);
            if (input_dims == NULL) {
                SET_ERROR("Failed to allocate ONNX input shape buffer.");
            }
            CHECK_STATUS_GOTO(g_ort->GetDimensions(tensor_info, input_dims, dim_count));
            if (input_dims[dim_count - 1] > 0) {
                input_width = input_dims[dim_count - 1];
            }
        }
    }

    v = caml_alloc_custom(&onnx_session_ops, sizeof(tlang_onnx_session), 0, 1);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v);
    s->session = session;
    s->input_count = input_count;
    s->output_count = output_count;
    s->input_width = input_width;
    s->input_names = input_names;
    s->output_names = output_names;
    if (input_type_info) g_ort->ReleaseTypeInfo(input_type_info);
    if (session_options) g_ort->ReleaseSessionOptions(session_options);
    free(input_dims);
    CAMLreturn(v);

cleanup:
    if (input_type_info) g_ort->ReleaseTypeInfo(input_type_info);
    if (session_options) g_ort->ReleaseSessionOptions(session_options);
    if (session) g_ort->ReleaseSession(session);
    if (input_names) {
        for (size_t i = 0; i < input_count; i++) free(input_names[i]);
        free(input_names);
    }
    if (output_names) {
        for (size_t i = 0; i < output_count; i++) free(output_names[i]);
        free(output_names);
    }
    free(input_dims);
    caml_failwith(err_buf);
}

CAMLprim value caml_onnx_session_run(value v_session, value v_inputs) {
    CAMLparam2(v_session, v_inputs);
    CAMLlocal1(v_result);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v_session);
    char err_buf[2048] = {0};
    float* input_data = NULL;
    OrtMemoryInfo* memory_info = NULL;
    OrtValue* input_tensor = NULL;
    OrtValue* output_tensor = NULL;
    OrtTensorTypeAndShapeInfo* shape_info = NULL;
    int64_t* dims = NULL;
    size_t nrows = Wosize_val(v_inputs);
    if (s->input_count != 1 || s->output_count != 1) {
        SET_ERROR("Function `predict` currently supports ONNX models with exactly one input and one output.");
    }
    if (nrows == 0) SET_ERROR("Empty input for ONNX prediction");
    size_t ncols = Wosize_val(Field(v_inputs, 0)) / Double_wosize;

    input_data = malloc(nrows * ncols * sizeof(float));
    if (input_data == NULL) {
        SET_ERROR("Failed to allocate ONNX input tensor buffer.");
    }
    for (size_t i = 0; i < nrows; i++) {
        value row = Field(v_inputs, i);
        size_t row_cols = Wosize_val(row) / Double_wosize;
        /* Defensive runtime check: malformed or inconsistent matrix input should
           fail safely here instead of being forwarded to ONNX Runtime. */
        if (row_cols != ncols) {
            snprintf(
                err_buf,
                sizeof(err_buf),
                "ONNX prediction input rows must all have the same width: expected %zu but received %zu.",
                ncols,
                row_cols
            );
            goto cleanup;
        }
        for (size_t j = 0; j < ncols; j++) {
            input_data[i * ncols + j] = (float)Double_field(row, j);
        }
    }

    CHECK_STATUS_GOTO(g_ort->CreateCpuMemoryInfo(OrtDeviceAllocator, OrtMemTypeDefault, &memory_info));
    int64_t input_shape[] = { (int64_t)nrows, (int64_t)ncols };
    CHECK_STATUS_GOTO(g_ort->CreateTensorWithDataAsOrtValue(memory_info, input_data, nrows * ncols * sizeof(float), input_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor));

    const char* input_names[] = { s->input_names[0] };
    const char* output_names[] = { s->output_names[0] };
    CHECK_STATUS_GOTO(g_ort->Run(s->session, NULL, input_names, (const OrtValue* const*)&input_tensor, 1, output_names, 1, &output_tensor));

    float* output_data;
    CHECK_STATUS_GOTO(g_ort->GetTensorMutableData(output_tensor, (void**)&output_data));
    CHECK_STATUS_GOTO(g_ort->GetTensorTypeAndShape(output_tensor, &shape_info));
    size_t dim_count;
    CHECK_STATUS_GOTO(g_ort->GetDimensionsCount(shape_info, &dim_count));
    if (dim_count == 0) {
        SET_ERROR("ONNX output tensor has no dimensions.");
    }
    dims = malloc(sizeof(int64_t) * dim_count);
    if (dims == NULL) {
        SET_ERROR("Failed to allocate ONNX output shape buffer.");
    }
    CHECK_STATUS_GOTO(g_ort->GetDimensions(shape_info, dims, dim_count));

    size_t total_out = 1;
    for (size_t i = 0; i < dim_count; i++) total_out *= dims[i];
    v_result = caml_alloc(total_out * Double_wosize, Double_array_tag);
    for (size_t i = 0; i < total_out; i++) {
        Store_double_field(v_result, i, (double)output_data[i]);
    }

    if (shape_info) g_ort->ReleaseTensorTypeAndShapeInfo(shape_info);
    if (output_tensor) g_ort->ReleaseValue(output_tensor);
    if (input_tensor) g_ort->ReleaseValue(input_tensor);
    if (memory_info) g_ort->ReleaseMemoryInfo(memory_info);
    free(input_data);
    free(dims);
    CAMLreturn(v_result);

cleanup:
    if (shape_info) g_ort->ReleaseTensorTypeAndShapeInfo(shape_info);
    if (output_tensor) g_ort->ReleaseValue(output_tensor);
    if (input_tensor) g_ort->ReleaseValue(input_tensor);
    if (memory_info) g_ort->ReleaseMemoryInfo(memory_info);
    free(input_data);
    free(dims);
    caml_failwith(err_buf);
}

CAMLprim value caml_onnx_session_input_width(value v_session) {
    CAMLparam1(v_session);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v_session);
    CAMLreturn(Val_int(s->input_width > 0 ? s->input_width : 0));
}
