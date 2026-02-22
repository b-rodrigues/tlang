(* src/pipeline/nix_emit_node.ml *)
open Nix_utils
open Nix_unparse

let emit_node (name, expr) deps import_lines =
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
  let deps_script_lines =
    deps
    |> List.map (fun d ->
      Printf.sprintf "      echo \"%s = deserialize(\\\"$T_NODE_%s/artifact.tobj\\\")\" >> node_script.t" d d)
    |> String.concat "\n"
  in
  let expr_s = unparse_expr expr in
  Printf.sprintf {|
  %s = stdenv.mkDerivation {
    name = "%s";
    buildInputs = t_lang_env ++ [ %s ];
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
      echo "      serialize(%s, \"$out/artifact.tobj\")" >> node_script.t
      mkdir -p $out
      t run --unsafe node_script.t
    '';
  };
|} name name deps_inputs deps_exports imports_echo deps_script_lines name expr_s name
