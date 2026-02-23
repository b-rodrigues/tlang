(* src/pipeline/nix_emit_node.ml *)
open Nix_utils
open Nix_unparse

let emit_node (name, expr) deps import_lines runtime serializer deserializer =
  let deps_inputs = String.concat " " deps in
  let deps_exports =
    deps
    |> List.map (fun d -> Printf.sprintf "      export T_NODE_%s=${%s}\n" d d)
    |> String.concat ""
  in
  let imports_echo =
    import_lines
    |> List.map (fun line ->
      Printf.sprintf "      echo %s >> node_script.t" (shell_single_quote line))
    |> String.concat "\n"
  in
  
  let ser_s = unparse_expr serializer in
  let des_s = unparse_expr deserializer in
  
  (* Logic for deserializing dependencies *)
  let deps_script_lines =
    deps
    |> List.map (fun d ->
      let des_call = if des_s = "default" then "deserialize" else des_s in
      (* Using the node-specific deserializer for all inputs (V1 limitation) *)
      Printf.sprintf "      echo \"%s = %s(\\\"$T_NODE_%s/artifact.tobj\\\")\" >> node_script.t" d des_call d)
    |> String.concat "\n"
  in

  let expr_s = unparse_expr expr in
  let ser_call = if ser_s = "default" then "serialize" else ser_s in

  (* Runtime specific build command *)
  let run_cmd = match runtime with
    | "T" -> "t run --unsafe node_script.t"
    | "R" -> "Rscript node_script.R" (* Placeholder *)
    | "Python" -> "python node_script.py" (* Placeholder *)
    | _ -> "t run --unsafe node_script.t"
  in

  Printf.sprintf {|
  %s = stdenv.mkDerivation {
    name = "%s";
    buildInputs = [ tBin %s ];
    src = sources;
    buildCommand = ''
      cp -r $src/* . || true
      chmod -R u+w .
%s      cat << EOF > node_script.t
EOF
%s
%s
      cat <<'EOF' >> node_script.t
      %s = %s
EOF
      echo "      %s(%s, \"$out/artifact.tobj\")" >> node_script.t
      mkdir -p $out
      %s
    '';
  };
|} name name deps_inputs deps_exports imports_echo deps_script_lines name expr_s ser_call name run_cmd
