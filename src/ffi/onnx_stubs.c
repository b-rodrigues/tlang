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

#define CHECK_STATUS(status) \
  if (status != NULL) { \
    const char* msg = g_ort->GetErrorMessage(status); \
    g_ort->ReleaseStatus(status); \
    caml_failwith(msg); \
  }

static void init_ort() {
    if (g_ort == NULL) {
        g_ort = OrtGetApiBase()->GetApi(ORT_API_VERSION);
        if (g_ort == NULL) caml_failwith("Failed to get ONNX Runtime API");
        CHECK_STATUS(g_ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "tlang", &g_env));
    }
}

typedef struct {
    OrtSession* session;
    size_t input_count;
    size_t output_count;
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
    init_ort();
    const char* path = String_val(v_path);
    OrtSessionOptions* session_options;
    CHECK_STATUS(g_ort->CreateSessionOptions(&session_options));
    OrtSession* session;
    CHECK_STATUS(g_ort->CreateSession(g_env, path, session_options, &session));
    g_ort->ReleaseSessionOptions(session_options);

    size_t input_count, output_count;
    CHECK_STATUS(g_ort->SessionGetInputCount(session, &input_count));
    CHECK_STATUS(g_ort->SessionGetOutputCount(session, &output_count));

    char** input_names = malloc(sizeof(char*) * input_count);
    char** output_names = malloc(sizeof(char*) * output_count);

    OrtAllocator* allocator;
    CHECK_STATUS(g_ort->GetAllocatorWithDefaultOptions(&allocator));

    for (size_t i = 0; i < input_count; i++) {
        char* name;
        CHECK_STATUS(g_ort->SessionGetInputName(session, i, allocator, &name));
        input_names[i] = strdup(name);
        allocator->Free(allocator, name);
    }

    for (size_t i = 0; i < output_count; i++) {
        char* name;
        CHECK_STATUS(g_ort->SessionGetOutputName(session, i, allocator, &name));
        output_names[i] = strdup(name);
        allocator->Free(allocator, name);
    }

    value v = caml_alloc_custom(&onnx_session_ops, sizeof(tlang_onnx_session), 0, 1);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v);
    s->session = session;
    s->input_count = input_count;
    s->output_count = output_count;
    s->input_names = input_names;
    s->output_names = output_names;
    CAMLreturn(v);
}

CAMLprim value caml_onnx_session_run(value v_session, value v_inputs) {
    CAMLparam2(v_session, v_inputs);
    CAMLlocal1(v_result);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v_session);
    size_t nrows = Wosize_val(v_inputs);
    if (nrows == 0) caml_failwith("Empty input for ONNX prediction");
    size_t ncols = Wosize_val(Field(v_inputs, 0)) / Double_wosize;

    float* input_data = malloc(nrows * ncols * sizeof(float));
    for (size_t i = 0; i < nrows; i++) {
        value row = Field(v_inputs, i);
        for (size_t j = 0; j < ncols; j++) {
            input_data[i * ncols + j] = (float)Double_field(row, j);
        }
    }

    OrtMemoryInfo* memory_info;
    CHECK_STATUS(g_ort->CreateCpuMemoryInfo(OrtDeviceAllocator, OrtMemTypeDefault, &memory_info));
    int64_t input_shape[] = { (int64_t)nrows, (int64_t)ncols };
    OrtValue* input_tensor = NULL;
    CHECK_STATUS(g_ort->CreateTensorWithDataAsOrtValue(memory_info, input_data, nrows * ncols * sizeof(float), input_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor));
    g_ort->ReleaseMemoryInfo(memory_info);

    const char* input_names[] = { s->input_names[0] };
    const char* output_names[] = { s->output_names[0] };
    OrtValue* output_tensor = NULL;
    CHECK_STATUS(g_ort->Run(s->session, NULL, input_names, (const OrtValue* const*)&input_tensor, 1, output_names, 1, &output_tensor));
    
    g_ort->ReleaseValue(input_tensor);
    free(input_data);

    float* output_data;
    CHECK_STATUS(g_ort->GetTensorMutableData(output_tensor, (void**)&output_data));
    OrtTensorTypeAndShapeInfo* shape_info;
    CHECK_STATUS(g_ort->GetTensorTypeAndShape(output_tensor, &shape_info));
    size_t dim_count;
    CHECK_STATUS(g_ort->GetDimensionsCount(shape_info, &dim_count));
    int64_t* dims = malloc(sizeof(int64_t) * dim_count);
    CHECK_STATUS(g_ort->GetDimensions(shape_info, dims, dim_count));
    g_ort->ReleaseTensorTypeAndShapeInfo(shape_info);

    size_t total_out = 1;
    for (size_t i = 0; i < dim_count; i++) total_out *= dims[i];
    v_result = caml_alloc(total_out * Double_wosize, Double_array_tag);
    for (size_t i = 0; i < total_out; i++) {
        Store_double_field(v_result, i, (double)output_data[i]);
    }

    g_ort->ReleaseValue(output_tensor);
    free(dims);
    CAMLreturn(v_result);
}
