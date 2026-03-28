open Ast

let registry = Hashtbl.create 16

let register name serializer =
  Hashtbl.replace registry name serializer

let lookup name =
  Hashtbl.find_opt registry name

let get_builtins () =
  Hashtbl.to_seq registry |> List.of_seq

let init_builtins () =
  let not_implemented_builtin name = 
    VBuiltin {
      b_name = Some ("^" ^ name ^ "_io");
      b_arity = 2;
      b_variadic = false;
      b_func = (fun _ _ -> 
        Error.make_error RuntimeError (Printf.sprintf "Serializer ^%s does not have a T-native implementation yet. Use it in a pipeline with R or Python runtimes." name)
      )
    }
  in
  let mk_ser format =
    let (r_w, r_r, py_w, py_r) = 
      match format with
      | "csv" ->   (Some "r_write_csv",    Some "r_read_csv",    Some "py_write_csv",    Some "py_read_csv")
      | "arrow" -> (Some "r_write_arrow",  Some "r_read_arrow",  Some "py_write_arrow",  Some "py_read_arrow")
      | "json" ->  (Some "r_write_json",   Some "r_read_json",   Some "py_write_json",   Some "py_read_json")
      | "pmml" ->  (Some "r_write_pmml",   Some "r_read_pmml",   Some "py_write_pmml",   Some "py_read_pmml")
      | "text" ->  (Some "writeLines",     Some "readLines",     Some "lambda obj, path: open(path, 'w').write(str(obj))", Some "lambda path: open(path).read()")
      | _ -> (None, None, None, None)
    in
    {
      s_format = format;
      s_writer = not_implemented_builtin format;
      s_reader = not_implemented_builtin format; 
      s_r_writer = r_w;
      s_r_reader = r_r;
      s_py_writer = py_w;
      s_py_reader = py_r;
    }
  in
  List.iter (fun name -> register name (mk_ser name))
    ["csv"; "arrow"; "json"; "pmml"; "tlang"; "bin"; "text"]
