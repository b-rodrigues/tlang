open Ast

let registry = Hashtbl.create 16

let register name serializer =
  Hashtbl.replace registry name serializer

let lookup name =
  Hashtbl.find_opt registry name

let get_builtins () =
  Hashtbl.to_seq registry |> List.of_seq

let init_builtins () =
  let mk_ser format = {
    s_format = format;
    s_writer = VNull; (* To be replaced by actual built-ins later *)
    s_reader = VNull; 
    s_r_writer = None;
    s_r_reader = None;
    s_py_writer = None;
    s_py_reader = None;
  } in
  List.iter (fun name -> register name (mk_ser name))
    ["csv"; "arrow"; "json"; "pmml"; "tlang"; "bin"; "text"]
