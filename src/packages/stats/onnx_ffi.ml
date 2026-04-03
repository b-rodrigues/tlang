(* src/packages/stats/onnx_ffi.ml *)

type session

external session_create : string -> session = "caml_onnx_session_create"
external session_run_multi : session -> string array -> float array array array -> string array -> float array array = "caml_onnx_session_run_multi"
external session_input_width : session -> int = "caml_onnx_session_input_width"
external session_input_names : session -> string array = "caml_onnx_session_input_names"
external session_output_names : session -> string array = "caml_onnx_session_output_names"
external session_metadata : session -> (string * string) list = "caml_onnx_session_metadata"

(* Global registry for session handles, indexed by path *)
let registry = Hashtbl.create 8

let get_session path =
  match Hashtbl.find_opt registry path with
  | Some session -> session
  | None ->
      let session = session_create path in
      Hashtbl.add registry path session;
      session

let close_session path =
  Hashtbl.remove registry path

let clear_cache () =
  Hashtbl.clear registry
