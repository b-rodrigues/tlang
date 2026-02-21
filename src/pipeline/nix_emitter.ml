open Ast

let op_to_string = function
  | Plus -> "+"
  | Minus -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Mod -> "%"
  | Eq -> "=="
  | NEq -> "!="
  | Gt -> ">"
  | Lt -> "<"
  | GtEq -> ">="
  | LtEq -> "<="
  | And -> "&&"
  | Or -> "||"
  | BitAnd -> "&"
  | BitOr -> "|"
  | In -> "in"
  | Pipe -> "|>"
  | MaybePipe -> "?|>"
  | Formula -> "~"

let shell_single_quote s =
  "'" ^ String.concat "'\"\\'\"'" (String.split_on_char '\'' s) ^ "'"

let rec unparse_expr = function
  | Value v -> Ast.Utils.value_to_string v
  | Var s -> s
  | ColumnRef c -> "$" ^ c
  | Call { fn; args } ->
      let fn_s = unparse_expr fn in
      let args_s =
        args
        |> List.map (fun (name, e) ->
          match name with
          | Some n -> n ^ " = " ^ unparse_expr e
          | None -> unparse_expr e)
        |> String.concat ", "
      in
      Printf.sprintf "%s(%s)" fn_s args_s
  | Lambda { params; body; _ } ->
      Printf.sprintf "\\(%s) %s" (String.concat ", " params) (unparse_expr body)
  | IfElse { cond; then_; else_ } ->
      Printf.sprintf "if (%s) %s else %s" (unparse_expr cond) (unparse_expr then_) (unparse_expr else_)
  | ListLit xs ->
      xs
      |> List.map (fun (name, e) ->
        match name with
        | Some n -> n ^ " = " ^ unparse_expr e
        | None -> unparse_expr e)
      |> String.concat ", "
      |> Printf.sprintf "[%s]"
  | DictLit xs ->
      xs
      |> List.map (fun (k, e) -> Printf.sprintf "`%s`: %s" k (unparse_expr e))
      |> String.concat ", "
      |> Printf.sprintf "{%s}"
  | BinOp { op; left; right } | BroadcastOp { op; left; right } ->
      Printf.sprintf "(%s %s %s)" (unparse_expr left) (op_to_string op) (unparse_expr right)
  | UnOp { op; operand } ->
      let tok = match op with Not -> "!" | Neg -> "-" in
      Printf.sprintf "%s%s" tok (unparse_expr operand)
  | DotAccess { target; field } ->
      Printf.sprintf "%s.%s" (unparse_expr target) field
  | PipelineDef _ | IntentDef _ | ListComp _ | Block _ ->
      "null"

let unparse_import_stmt = function
  | Ast.Import filename -> Printf.sprintf "import \"%s\"" filename
  | Ast.ImportPackage pkg -> Printf.sprintf "import %s" pkg
  | Ast.ImportFrom { package; names } ->
      let name_strs = List.map (fun (s : Ast.import_spec) ->
        match s.import_alias with
        | Some alias -> Printf.sprintf "%s=%s" alias s.import_name
        | None -> s.import_name
      ) names in
      Printf.sprintf "import %s[%s]" package (String.concat ", " name_strs)
  | _ -> ""

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
      let line = Printf.sprintf "%s = deserialize(\"$T_NODE_%s/artifact.tobj\")" d d in
      Printf.sprintf "      echo %s >> node_script.t" (shell_single_quote line))
    |> String.concat "\n"
  in
  let expr_s = unparse_expr expr in
  Printf.sprintf {|
  %s = stdenv.mkDerivation {
    name = "%s";
    buildInputs = t_lang_env ++ [ %s ];
    buildCommand = ''
%s      cat << EOF > node_script.t
EOF
%s
%s
      cat <<'EOF' >> node_script.t
      %s = %s
      serialize(%s, "$out/artifact.tobj")
EOF
      mkdir -p $out
      t run --unsafe node_script.t
    '';
  };
|} name name deps_inputs deps_exports imports_echo deps_script_lines name expr_s name

let emit_pipeline (p : Ast.pipeline_result) =
  let import_lines = List.filter_map (fun stmt ->
    let s = unparse_import_stmt stmt in
    if s = "" then None else Some s
  ) p.p_imports in
  let node_names = List.map fst p.p_exprs in
  let nodes =
    p.p_exprs
    |> List.map (fun (name, expr) ->
      let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
      emit_node (name, expr) deps import_lines)
    |> String.concat "\n"
  in
  let final_copy =
    node_names
    |> List.map (fun n -> Printf.sprintf "      cp -r ${%s} $out/%s" n n)
    |> String.concat "\n"
  in
  Printf.sprintf {|
{ pkgs ? import <nixpkgs> {} }:
let
  stdenv = pkgs.stdenv;
  # Use local env.nix if it exists, otherwise fallback to stdenv
  env = if builtins.pathExists ./env.nix then import ./env.nix { inherit pkgs; } else { buildInputs = []; };
  t_lang_env = env.buildInputs or [];
in
rec {
%s
  pipeline_output = stdenv.mkDerivation {
    name = "pipeline_output";
    buildInputs = t_lang_env ++ [ %s ];
    buildCommand = ''
      mkdir -p $out
%s
    '';
  };
}
|} nodes (String.concat " " node_names) final_copy
