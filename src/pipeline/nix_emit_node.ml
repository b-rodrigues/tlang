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
  let ext, extra_input = match runtime with
    | "R" -> "R", "r-env"
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
  
  (* Logic for deserializing dependencies *)
  let deps_script_lines =
    deps
    |> List.map (fun d ->
      let des_call = if des_s = "default" then (if runtime = "R" then "readRDS" else "deserialize") else des_s in
      if runtime = "R" then
        Printf.sprintf "      echo \"%s <- %s(\\\"$T_NODE_%s/artifact\\\")\" >> node_script.%s" d des_call d ext
      else
        Printf.sprintf "      echo \"%s = %s(\\\"$T_NODE_%s/artifact\\\")\" >> node_script.%s" d des_call d ext)
    |> String.concat "\n"
  in

  let expr_s = unparse_expr expr in
  let ser_call = if ser_s = "default" then (if runtime = "R" then "saveRDS" else "serialize") else ser_s in

  let assign_script_lines =
    if runtime = "R" then
      Printf.sprintf {|      cat <<'EOF' >> node_script.R
%s <- %s
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.R|} name expr_s ser_call name
    else if runtime = "Python" then
      Printf.sprintf {|      cat <<'EOF' >> node_script.py
%s = %s
EOF
      echo "%s(%s, \"$out/artifact\")" >> node_script.py|} name expr_s ser_call name
    else
      Printf.sprintf {|      cat <<'EOF' >> node_script.t
      %s = %s
EOF
      echo "      %s(%s, \"$out/artifact\")" >> node_script.t|} name expr_s ser_call name
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
%s      cat << EOF > node_script.%s
EOF
%s
%s
%s
%s
      mkdir -p $out
      %s
    '';
  };
|} name name deps_inputs src_block deps_exports ext imports_echo source_files deps_script_lines assign_script_lines run_cmd
