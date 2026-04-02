(* src/packages/stats/onnx_ffi.ml *)

type session

external session_create : string -> session = "caml_onnx_session_create"
external session_run : session -> float array array -> float array = "caml_onnx_session_run"
external session_input_width : session -> int = "caml_onnx_session_input_width"

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
