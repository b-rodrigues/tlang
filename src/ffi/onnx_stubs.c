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
#include <stdint.h>
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
    if (input_count == 0 || output_count == 0) {
        SET_ERROR("ONNX model must have at least one input and one output.");
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

    /* Extract input width for the FIRST input (heuristic for predict()) */
    CHECK_STATUS_GOTO(g_ort->SessionGetInputTypeInfo(session, 0, &input_type_info));
    CHECK_STATUS_GOTO(g_ort->CastTypeInfoToTensorInfo(input_type_info, &tensor_info));
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

CAMLprim value caml_onnx_session_run_multi(value v_session, value v_input_names, value v_input_tensors, value v_output_names) {
    CAMLparam4(v_session, v_input_names, v_input_tensors, v_output_names);
    CAMLlocal3(v_result, v_temp_out, v_row);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v_session);
    char err_buf[2048] = {0};
    
    size_t in_count = Wosize_val(v_input_names);
    if (in_count == 0) SET_ERROR("No inputs provided for ONNX prediction");
    if (in_count != Wosize_val(v_input_tensors)) SET_ERROR("Mismatch between input names and tensors count");
    size_t out_req_count = Wosize_val(v_output_names);
    if (out_req_count == 0) SET_ERROR("No output names requested for ONNX prediction");

    const char** in_names = calloc(in_count, sizeof(char*));
    const char** out_names = calloc(out_req_count, sizeof(char*));
    OrtValue** in_tensors = calloc(in_count, sizeof(OrtValue*));
    OrtValue** out_tensors = calloc(out_req_count, sizeof(OrtValue*));
    float** in_data_ptrs = calloc(in_count, sizeof(float*));
    OrtMemoryInfo* memory_info = NULL;

    CHECK_STATUS_GOTO(g_ort->CreateCpuMemoryInfo(OrtDeviceAllocator, OrtMemTypeDefault, &memory_info));

    size_t common_nrows = 0;
    for (size_t i = 0; i < in_count; i++) {
        in_names[i] = String_val(Field(v_input_names, i));
        value v_matrix = Field(v_input_tensors, i);
        size_t nrows = Wosize_val(v_matrix);
        if (i == 0) common_nrows = nrows;
        else if (nrows != common_nrows) SET_ERROR("All ONNX input matrices must have the same number of rows (batch size)");
        
        if (nrows == 0) SET_ERROR("Empty input matrix for ONNX prediction");
        size_t ncols = Wosize_val(Field(v_matrix, 0)) / Double_wosize;
        
        float* input_data = malloc(nrows * ncols * sizeof(float));
        if (input_data == NULL) SET_ERROR("Failed to allocate ONNX input tensor buffer.");
        in_data_ptrs[i] = input_data;

        for (size_t r = 0; r < nrows; r++) {
            value row = Field(v_matrix, r);
            if (Wosize_val(row) / Double_wosize != ncols) SET_ERROR("Inconsistent column width in input matrix");
            for (size_t c = 0; c < ncols; c++) {
                input_data[r * ncols + c] = (float)Double_field(row, c);
            }
        }
        int64_t shape[] = { (int64_t)nrows, (int64_t)ncols };
        CHECK_STATUS_GOTO(g_ort->CreateTensorWithDataAsOrtValue(memory_info, input_data, nrows * ncols * sizeof(float), shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &in_tensors[i]));
    }

    for (size_t i = 0; i < out_req_count; i++) {
        out_names[i] = String_val(Field(v_output_names, i));
    }

    CHECK_STATUS_GOTO(g_ort->Run(s->session, NULL, in_names, (const OrtValue* const*)in_tensors, in_count, out_names, out_req_count, out_tensors));

    v_result = caml_alloc(out_req_count, 0);

    for (size_t k = 0; k < out_req_count; k++) {
        OrtValue* output_tensor = out_tensors[k];
        OrtTensorTypeAndShapeInfo* shape_info = NULL;
        ONNXTensorElementDataType output_type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED;
        int64_t* dims = NULL;

        CHECK_STATUS_GOTO(g_ort->GetTensorTypeAndShape(output_tensor, &shape_info));
        CHECK_STATUS_GOTO(g_ort->GetTensorElementType(shape_info, &output_type));
        size_t dim_count;
        CHECK_STATUS_GOTO(g_ort->GetDimensionsCount(shape_info, &dim_count));
        
        dims = malloc(sizeof(int64_t) * dim_count);
        CHECK_STATUS_GOTO(g_ort->GetDimensions(shape_info, dims, dim_count));

        size_t total_elements = 1;
        for(size_t i=0; i<dim_count; i++) total_elements *= dims[i];

        size_t out_len = total_elements;
        v_temp_out = caml_alloc(out_len * Double_wosize, Double_array_tag);

        switch (output_type) {
            case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT: {
                float* data = NULL;
                CHECK_STATUS_GOTO(g_ort->GetTensorMutableData(output_tensor, (void**)&data));
                for(size_t i=0; i<out_len; i++) Store_double_field(v_temp_out, i, (double)data[i]);
                break;
            }
            case ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE: {
                double* data = NULL;
                CHECK_STATUS_GOTO(g_ort->GetTensorMutableData(output_tensor, (void**)&data));
                for(size_t i=0; i<out_len; i++) Store_double_field(v_temp_out, i, data[i]);
                break;
            }
            case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64: {
                int64_t* data = NULL;
                CHECK_STATUS_GOTO(g_ort->GetTensorMutableData(output_tensor, (void**)&data));
                for(size_t i=0; i<out_len; i++) Store_double_field(v_temp_out, i, (double)data[i]);
                break;
            }
            case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32: {
                int32_t* data = NULL;
                CHECK_STATUS_GOTO(g_ort->GetTensorMutableData(output_tensor, (void**)&data));
                for(size_t i=0; i<out_len; i++) Store_double_field(v_temp_out, i, (double)data[i]);
                break;
            }
            default: SET_ERROR("Unsupported ONNX output tensor element type.");
        }
        Store_field(v_result, k, v_temp_out);
        if (shape_info) g_ort->ReleaseTensorTypeAndShapeInfo(shape_info);
        free(dims);
    }

    /* Cleanup */
    for (size_t i = 0; i < in_count; i++) {
        if (in_tensors[i]) g_ort->ReleaseValue(in_tensors[i]);
        free(in_data_ptrs[i]);
    }
    for (size_t i = 0; i < out_req_count; i++) {
        if (out_tensors[i]) g_ort->ReleaseValue(out_tensors[i]);
    }
    free(in_names); free(out_names); free(in_tensors); free(out_tensors); free(in_data_ptrs);
    if (memory_info) g_ort->ReleaseMemoryInfo(memory_info);

    CAMLreturn(v_result);

cleanup:
    if (memory_info) g_ort->ReleaseMemoryInfo(memory_info);
    for (size_t i = 0; i < in_count; i++) {
        if (in_tensors[i]) g_ort->ReleaseValue(in_tensors[i]);
        if (in_data_ptrs[i]) free(in_data_ptrs[i]);
    }
    for (size_t i = 0; i < out_req_count; i++) {
        if (out_tensors[i]) g_ort->ReleaseValue(out_tensors[i]);
    }
    free(in_names); free(out_names); free(in_tensors); free(out_tensors); free(in_data_ptrs);
    caml_failwith(err_buf);
}

CAMLprim value caml_onnx_session_input_width(value v_session) {
    CAMLparam1(v_session);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v_session);
    CAMLreturn(Val_int(s->input_width > 0 ? s->input_width : 0));
}

CAMLprim value caml_onnx_session_input_names(value v_session) {
    CAMLparam1(v_session);
    CAMLlocal1(v_names);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v_session);
    v_names = caml_alloc(s->input_count, 0);
    for (size_t i = 0; i < s->input_count; i++) {
        Store_field(v_names, i, caml_copy_string(s->input_names[i]));
    }
    CAMLreturn(v_names);
}

CAMLprim value caml_onnx_session_output_names(value v_session) {
    CAMLparam1(v_session);
    CAMLlocal1(v_names);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v_session);
    v_names = caml_alloc(s->output_count, 0);
    for (size_t i = 0; i < s->output_count; i++) {
        Store_field(v_names, i, caml_copy_string(s->output_names[i]));
    }
    CAMLreturn(v_names);
}

CAMLprim value caml_onnx_session_metadata(value v_session) {
    CAMLparam1(v_session);
    CAMLlocal3(v_res, v_pair, v_cons);
    tlang_onnx_session* s = (tlang_onnx_session*)Data_custom_val(v_session);
    OrtModelMetadata* metadata = NULL;
    OrtAllocator* allocator = NULL;
    char** keys = NULL;
    int64_t num_keys = 0;
    char err_buf[2048] = {0};

    if (g_ort->SessionGetModelMetadata(s->session, &metadata) != 0) {
         CAMLreturn(Val_int(0));
    }
    
    CHECK_STATUS_GOTO(g_ort->GetAllocatorWithDefaultOptions(&allocator));
    CHECK_STATUS_GOTO(g_ort->ModelMetadataGetCustomMetadataMapKeys(metadata, allocator, &keys, &num_keys));

    v_res = Val_int(0); /* Empty list */

    for (int64_t i = num_keys - 1; i >= 0; i--) {
        char* val_str = NULL;
        if (g_ort->ModelMetadataLookupCustomMetadataMap(metadata, allocator, keys[i], &val_str) == 0) {
            v_pair = caml_alloc(2, 0);
            Store_field(v_pair, 0, caml_copy_string(keys[i]));
            Store_field(v_pair, 1, caml_copy_string(val_str != NULL ? val_str : ""));
            
            v_cons = caml_alloc(2, 0);
            Store_field(v_cons, 0, v_pair);
            Store_field(v_cons, 1, v_res);
            v_res = v_cons;
            if (val_str) allocator->Free(allocator, val_str);
        }
        allocator->Free(allocator, keys[i]);
    }
    if (keys) free(keys);

    char *producer = NULL, *description = NULL;
    g_ort->ModelMetadataGetProducerName(metadata, allocator, &producer);
    if (producer) {
        v_pair = caml_alloc(2, 0);
        Store_field(v_pair, 0, caml_copy_string("producer"));
        Store_field(v_pair, 1, caml_copy_string(producer));
        v_cons = caml_alloc(2, 0);
        Store_field(v_cons, 0, v_pair);
        Store_field(v_cons, 1, v_res);
        v_res = v_cons;
        allocator->Free(allocator, producer);
    }
    g_ort->ModelMetadataGetDescription(metadata, allocator, &description);
    if (description) {
        v_pair = caml_alloc(2, 0);
        Store_field(v_pair, 0, caml_copy_string("description"));
        Store_field(v_pair, 1, caml_copy_string(description));
        v_cons = caml_alloc(2, 0);
        Store_field(v_cons, 0, v_pair);
        Store_field(v_cons, 1, v_res);
        v_res = v_cons;
        allocator->Free(allocator, description);
    }

    g_ort->ReleaseModelMetadata(metadata);
    CAMLreturn(v_res);

cleanup:
    if (metadata) g_ort->ReleaseModelMetadata(metadata);
    if (keys) free(keys);
    caml_failwith(err_buf);
}
