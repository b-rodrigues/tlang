open Ast
open Nix_utils

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
