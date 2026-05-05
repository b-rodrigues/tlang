open Ast
open Nix_utils

let dedent s =
  let lines = String.split_on_char '\n' s in
  (* Remove leading/trailing empty lines *)
  let rec remove_leading = function
    | l :: ls when String.trim l = "" -> remove_leading ls
    | ls -> ls
  in
  let lines = remove_leading (List.rev (remove_leading (List.rev lines))) in
  match lines with
  | [] -> ""
  | _ ->
    let min_indent =
      List.fold_left (fun min_acc l ->
        if String.trim l = "" then min_acc
        else
          let indent = ref 0 in
          while !indent < String.length l && l.[!indent] = ' ' do
            incr indent
          done;
          min min_acc !indent
      ) max_int lines
    in
    List.map (fun l ->
      if String.length l >= min_indent then
        String.sub l min_indent (String.length l - min_indent)
      else ""
    ) lines
    |> String.concat "\n"

(** Extract a plain string from an expression if it wraps VString/VSymbol,
    otherwise fall back to the general unparser. Used for serializer/deserializer fields.  *)
let rec expr_to_string expr =
  let strip_hat s = if String.starts_with ~prefix:"^" s then String.sub s 1 (String.length s - 1) else s in
  match expr.node with
  | Ast.Value (Ast.VString s) | Ast.Value (Ast.VSymbol s) -> strip_hat s
  | Ast.Value (Ast.VSerializer s) -> s.s_format
  | _ -> unparse_expr expr

and unparse_expr expr =
  match expr.node with
  | Value (VComputedNode cn) ->
      Printf.sprintf "computed_node(name=\"%s\", runtime=\"%s\", path=\"%s\")"
        (Serialization.json_escape cn.cn_name)
        (Serialization.json_escape cn.cn_runtime)
        (Serialization.json_escape cn.cn_path)
  | Value (VNode un) ->
      Printf.sprintf "node(runtime=\"%s\")" (Serialization.json_escape un.un_runtime)
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
  | Lambda { params; autoquote_params; body; _ } ->
      Printf.sprintf "\\(%s) %s"
        (String.concat ", " (Ast.Utils.display_params params autoquote_params))
        (unparse_expr body)
  | IfElse { cond; then_; else_ } ->
      Printf.sprintf "if (%s) %s else %s" (unparse_expr cond) (unparse_expr then_) (unparse_expr else_)
  | Match { scrutinee; cases } ->
      let rec unparse_pattern = function
        | PWildcard -> "_"
        | PVar name -> name
        | PNA -> "NA"
        | PError None -> "Error"
        | PError (Some field) -> Printf.sprintf "Error { %s }" field
        | PList (patterns, rest) ->
            let items =
              List.map unparse_pattern patterns
              @
              match rest with
              | Some name -> [".." ^ name]
              | None -> []
            in
            Printf.sprintf "[%s]" (String.concat ", " items)
      in
      let cases_s =
        cases
        |> List.map (fun (pattern, body) ->
          Printf.sprintf "%s => %s" (unparse_pattern pattern) (unparse_expr body))
        |> String.concat ", "
      in
      Printf.sprintf "match(%s) { %s }" (unparse_expr scrutinee) cases_s
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
      |> List.map (fun (k, e) -> Printf.sprintf "%s: %s" k (unparse_expr e))
      |> String.concat ", "
      |> Printf.sprintf "[%s]"
  | BinOp { op; left; right } | BroadcastOp { op; left; right } ->
      Printf.sprintf "(%s %s %s)" (unparse_expr left) (op_to_string op) (unparse_expr right)
  | UnOp { op; operand } ->
      let tok = match op with Not -> "!" | Neg -> "-" in
      Printf.sprintf "%s%s" tok (unparse_expr operand)
  | DotAccess { target; field } ->
      Printf.sprintf "%s.%s" (unparse_expr target) field
  | RawCode { raw_text; _ } -> dedent raw_text
  | Unquote e -> "!!" ^ unparse_expr e
  | UnquoteSplice e -> "!!!" ^ unparse_expr e
  | ShellExpr cmd -> "?<{ " ^ cmd ^ " }>"
  | PipelineDef nodes ->
      "pipeline { " ^ String.concat "; " (List.map (fun (n, e) -> n ^ " = " ^ unparse_expr e) nodes) ^ " }"
  | Block stmts -> "{ " ^ (List.map unparse_stmt stmts |> String.concat "; ") ^ " }"
  | ListComp _ -> "[...]"
  | IntentDef _ -> "intent { ... }"

and unparse_stmt stmt =
  match stmt.node with
  | Expression e -> unparse_expr e
  | Assignment { name; expr; _ } -> name ^ " = " ^ unparse_expr expr
  | Reassignment { name; expr } -> name ^ " := " ^ unparse_expr expr
  | Import filename -> Printf.sprintf "import \"%s\"" filename
  | ImportPackage pkg -> Printf.sprintf "import %s" pkg
  | ImportFrom { package; names } -> 
      let name_strs = List.map (fun (s : Ast.import_spec) ->
        match s.import_alias with
        | Some alias -> Printf.sprintf "%s=%s" alias s.import_name
        | None -> s.import_name
      ) names in
      Printf.sprintf "import %s[%s]" package (String.concat ", " name_strs)
  | ImportFileFrom { filename; names } -> 
      let name_strs = List.map (fun (s : Ast.import_spec) ->
        match s.import_alias with
        | Some alias -> Printf.sprintf "%s=%s" alias s.import_name
        | None -> s.import_name
      ) names in
      Printf.sprintf "import \"%s\"[%s]" filename (String.concat ", " name_strs)

let unparse_import_stmt = unparse_stmt
