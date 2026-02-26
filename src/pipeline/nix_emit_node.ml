(* src/pipeline/nix_emit_node.ml *)
open Nix_utils
open Nix_unparse

let emit_node (name, expr) deps import_lines runtime serializer deserializer functions includes noop =
  if noop then
    Printf.sprintf {|
  %s = pkgs.runCommand "%s" {} ''
    mkdir -p $out
    echo "Build skipped for %s" > $out/NOOPBUILD
  '';|} name name name
  else
  let is_pmml_ser = match serializer with Ast.Value (Ast.VString "pmml") -> true | _ -> false in
  let is_pmml_des = match deserializer with Ast.Value (Ast.VString "pmml") -> true | _ -> false in

  let ext, extra_input = match runtime with
    | "R" -> 
        let inputs = if is_pmml_ser || is_pmml_des then "r-env pkgs.jre" else "r-env" in
        "R", inputs
    | "Python" -> "py", "py-env"
    | _ -> "t", ""
  in

  let deps_inputs = String.concat " " (if extra_input = "" then deps else extra_input :: deps) in
  let deps_exports =
    deps
    |> List.map (fun d -> Printf.sprintf "      export T_NODE_%s=${%s}\n" d d)
    |> String.concat ""
  in
  let imports_echo =
    if runtime = "T" then
      import_lines
      |> List.map (fun line ->
        Printf.sprintf "      echo %s >> node_script.t" (shell_single_quote line))
      |> String.concat "\n"
    else ""
  in
  
  let ser_s = unparse_expr serializer in
  let des_s = unparse_expr deserializer in
  let eval_string_list lst =
    lst
    |> List.map (Eval.eval_expr (ref (Ast.Env.empty)))
    |> List.map (function Ast.VString s -> s | _ -> "")
    |> List.filter (fun s -> s <> "")
  in
  let funcs = eval_string_list functions in
  let _incs = eval_string_list includes in

  let src_block = "    src = sources;" in



  let source_files =
    if runtime = "R" then
      funcs |> List.map (fun f -> Printf.sprintf "      echo \"source('%s')\" >> node_script.R" f) |> String.concat "\n"
    else if runtime = "Python" then
      funcs |> List.map (fun f -> Printf.sprintf "      echo \"exec(open('%s').read())\" >> node_script.py" f) |> String.concat "\n"
    else
      funcs |> List.map (fun f -> Printf.sprintf "      echo %s >> node_script.t" (shell_single_quote (Printf.sprintf "import \"%s\"" f))) |> String.concat "\n"
  in
  
  let is_json_ser = match serializer with Ast.Value (Ast.VString "json") -> true | _ -> false in
  let is_json_des = match deserializer with Ast.Value (Ast.VString "json") -> true | _ -> false in
  let is_arrow_ser = match serializer with Ast.Value (Ast.VString "arrow") -> true | _ -> false in
  let is_arrow_des = match deserializer with Ast.Value (Ast.VString "arrow") -> true | _ -> false in
  let is_pmml_ser = match serializer with Ast.Value (Ast.VString "pmml") -> true | _ -> false in
  let is_pmml_des = match deserializer with Ast.Value (Ast.VString "pmml") -> true | _ -> false in

  let t_json_r_code = {|
t_write_json <- function(object, path) {
  jsonlite::write_json(object, path, auto_unbox = TRUE, null = "null")
}
t_read_json <- function(path) {
  jsonlite::read_json(path, simplifyVector = TRUE)
}
|} in

  let t_json_py_code = {|
import json
def t_write_json(obj, path):
    with open(path, "w") as f:
        json.dump(obj, f)
def t_read_json(path):
    with open(path) as f:
        return json.load(f)
|} in

  let t_arrow_r_code = {|
t_write_arrow <- function(object, path) {
  arrow::write_ipc_file(as.data.frame(object), path)
}
t_read_arrow <- function(path) {
  arrow::read_ipc_file(path)
}
|} in

  let t_arrow_py_code = {|
import pyarrow as pa
import pyarrow.ipc as ipc
import pandas as pd

def t_write_arrow(df, path):
    if isinstance(df, pd.DataFrame):
        table = pa.Table.from_pandas(df)
    else:
        table = df
    with pa.OSFile(path, 'wb') as f:
        with ipc.new_file(f, table.schema) as writer:
            writer.write_table(table)

def t_read_arrow(path):
    with pa.OSFile(path, 'rb') as f:
        return ipc.open_file(f).read_pandas()
|} in

  let t_pmml_r_code = {|
t_write_pmml <- function(object, path) {
  r2pmml::r2pmml(object, path)
}
t_read_pmml <- function(path) {
  # Load as XML/PMML object if needed, but T executes natively.
  # For R consumers, we might use the pmml package if available.
  if (requireNamespace("pmml", quietly = TRUE)) {
    return(pmml::read.pmml(path))
  }
  return(path)
}
|} in

  let t_pmml_py_code = {|
from pypmml import Model
def t_write_pmml(model, path):
    # Python export to PMML usually requires nyoka or sklearn2pmml.
    # If using nyoka:
    try:
        from nyoka import skl_to_pmml
        skl_to_pmml(model, None, None, path)
    except ImportError:
        # Fallback/placeholder for now as user stressed pypmml
        raise ImportError("PMML export in Python requires 'nyoka' package.")

def t_read_pmml(path):
    return Model.load(path)
|} in

  let json_injection =
    if is_json_ser || is_json_des then
      if runtime = "R" then
        Printf.sprintf "      cat << 'EOF' >> node_script.R\n%s\nEOF" t_json_r_code
      else if runtime = "Python" then
        Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" t_json_py_code
      else ""
    else ""
  in

  let arrow_injection =
    if is_arrow_ser || is_arrow_des then
      if runtime = "R" then
        Printf.sprintf "      cat << 'EOF' >> node_script.R\n%s\nEOF" t_arrow_r_code
      else if runtime = "Python" then
        Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" t_arrow_py_code
      else ""
    else ""
  in

  let pmml_injection =
    if is_pmml_ser || is_pmml_des then
      if runtime = "R" then
        Printf.sprintf "      cat << 'EOF' >> node_script.R\n%s\nEOF" t_pmml_r_code
      else if runtime = "Python" then
        Printf.sprintf "      cat << 'EOF' >> node_script.py\n%s\nEOF" t_pmml_py_code
      else ""
    else ""
  in

  (* Logic for deserializing dependencies *)
  let deps_script_lines =
    deps
    |> List.map (fun d ->
      let des_call =
        if des_s = "default" then
          (if runtime = "R" then "readRDS" else "deserialize")
        else if is_json_des then
          "t_read_json"
        else if is_arrow_des then
          "t_read_arrow"
        else if is_pmml_des then
          "t_read_pmml"
        else des_s
      in
      if runtime = "R" then
        Printf.sprintf "      echo \"%s <- %s(\\\"$T_NODE_%s/artifact\\\")\" >> node_script.%s" d des_call d ext
      else
        Printf.sprintf "      echo \"%s = %s(\\\"$T_NODE_%s/artifact\\\")\" >> node_script.%s" d des_call d ext)
    |> String.concat "\n"
  in

  let expr_s = unparse_expr expr in
  let ser_call =
    if ser_s = "default" then
      (if runtime = "R" then "saveRDS" else "serialize")
    else if is_json_ser then
      "t_write_json"
    else if is_arrow_ser then
      "t_write_arrow"
    else if is_pmml_ser then
      "t_write_pmml"
    else ser_s
  in

  let is_raw_code = match expr with RawCode _ -> true | _ -> false in

  (* Check if raw code string contains a Python assignment to node_name.
     Looks for `name = ` (assignment, not `==` comparison) at the start of a line. *)
  let raw_assigns_to name s =
    let prefix = name ^ " = " in
    let prefix_eq = name ^ " ==" in
    String.split_on_char '\n' s
    |> List.exists (fun line ->
      let l = String.trim line in
      String.length l >= String.length prefix &&
      String.sub l 0 (String.length prefix) = prefix &&
      not (String.length l >= String.length prefix_eq &&
           String.sub l 0 (String.length prefix_eq) = prefix_eq))
  in

  let assign_script_lines =
    if runtime = "R" then
      if is_raw_code then
        Printf.sprintf {|      echo "%s <- local({" >> node_script.R
      cat <<'EOF' >> node_script.R
%s
EOF
      echo "})" >> node_script.R
      echo "%s(%s, \"$out/artifact\")" >> node_script.R
      echo "writeLines(as.character(class(%s)[1]), \"$out/class\")" >> node_script.R|} name expr_s ser_call name name
      else
        Printf.sprintf {|      cat <<'EOF' >> node_script.R
%s <- %s
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.R
      echo "writeLines(as.character(class(%s)[1]), \"$out/class\")" >> node_script.R|} name expr_s ser_call name name
    else if runtime = "Python" then
      if is_raw_code then
        if raw_assigns_to name expr_s then
          (* Statement-style: raw code explicitly assigns to node name — use as-is *)
          Printf.sprintf {|      cat <<'EOF' >> node_script.py
%s
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.py
      echo "with open(\"$out/class\", \"w\") as f: f.write(type(%s).__name__)" >> node_script.py|} expr_s ser_call name name
        else
          (* Expression-style: wrap with assignment to node name *)
          Printf.sprintf {|      cat <<'EOF' >> node_script.py
%s = (%s)
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.py
      echo "with open(\"$out/class\", \"w\") as f: f.write(type(%s).__name__)" >> node_script.py|} name expr_s ser_call name name
      else
        Printf.sprintf {|      cat <<'EOF' >> node_script.py
%s = %s
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.py
      echo "with open(\"$out/class\", \"w\") as f: f.write(type(%s).__name__)" >> node_script.py|} name expr_s ser_call name name
    else
      if is_raw_code then
        Printf.sprintf {|      echo "      %s = {" >> node_script.t
      cat <<'EOF' >> node_script.t
%s
EOF
      echo "      }" >> node_script.t
      echo "      %s(%s, \"$out/artifact\")" >> node_script.t
      echo "      write_text(\"$out/class\", type(%s))" >> node_script.t|} name expr_s ser_call name name
      else
        Printf.sprintf {|      cat <<'EOF' >> node_script.t
      %s = %s
EOF
      echo "      %s(%s, \"$out/artifact\")" >> node_script.t
      echo "      write_text(\"$out/class\", type(%s))" >> node_script.t|} name expr_s ser_call name name
  in

  (* Runtime specific build command *)
  let run_cmd = match runtime with
    | "R" -> "Rscript node_script.R"
    | "Python" -> "python node_script.py"
    | _ -> "t run --unsafe node_script.t"
  in

  Printf.sprintf {|
  %s = stdenv.mkDerivation {
    name = "%s";
    buildInputs = [ tBin %s ];
%s
    buildCommand = ''
      cp -r $src/* . || true
      chmod -R u+w .
%s
      cat << EOF > node_script.%s
EOF
%s
%s
%s
%s
%s
%s
%s
      mkdir -p $out
      %s
    '';
  };
|} name name deps_inputs src_block deps_exports ext json_injection arrow_injection pmml_injection imports_echo source_files deps_script_lines assign_script_lines run_cmd
