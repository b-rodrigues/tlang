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

let rec unparse_expr = function
  | Value (VString s) -> "\"" ^ String.escaped s ^ "\""
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

let emit_node (name, expr) deps =
  let deps_inputs = String.concat " " deps in
  let deps_exports =
    deps
    |> List.map (fun d -> Printf.sprintf "      export T_NODE_%s=${%s}\n" d d)
    |> String.concat ""
  in
  let deps_script_lines =
    deps
    |> List.map (fun d ->
      Printf.sprintf "      echo '%s = deserialize(\"'$T_NODE_%s'/artifact.tobj\")' >> node_script.t" d d)
    |> String.concat "\n"
  in
  let expr_s = unparse_expr expr in
  Printf.sprintf {|
  %s = stdenv.mkDerivation {
    name = "%s";
    buildInputs = [ t_lang_env %s ];
    buildCommand = ''
%s      cat << EOF > node_script.t
EOF
%s
      cat << 'EOF' >> node_script.t
      %s = %s
      serialize(%s, "$out/artifact.tobj")
EOF
      mkdir -p $out
      t run node_script.t
    '';
  };
|} name name deps_inputs deps_exports deps_script_lines name expr_s name

let emit_pipeline (p : Ast.pipeline_result) =
  let node_names = List.map fst p.p_exprs in
  let nodes =
    p.p_exprs
    |> List.map (fun (name, expr) ->
      let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
      emit_node (name, expr) deps)
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
  t_lang_env = pkgs.stdenv;
in
rec {
%s
  pipeline_output = stdenv.mkDerivation {
    name = "pipeline_output";
    buildInputs = [ %s ];
    buildCommand = ''
      mkdir -p $out
%s
    '';
  };
}
|} nodes (String.concat " " node_names) final_copy
