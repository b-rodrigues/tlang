open Ast

let value_length (v : value) : int =
  match v with
  | VList items -> List.length items
  | VVector items -> Array.length items
  | _ -> 1

let slice_value (v : value) (index : int) : value =
  match v with
  | VList items ->
      (match List.nth_opt items index with
       | Some (_, v) -> v
       | None -> VNA NAGeneric)
  | VVector items ->
      if index >= 0 && index < Array.length items then
        Array.get items index
      else VNA NAGeneric
  | _ -> v

let value_to_literal (v : value) : string =
  match v with
  | VInt n -> string_of_int n
  | VFloat f ->
      let s = string_of_float f in
      if not (String.contains s '.') then s ^ ".0" else s
  | VBool true -> "true"
  | VBool false -> "false"
  | VString s -> "\"" ^ String.escaped s ^ "\""
  | VSymbol s -> s
  | VNA _ -> "NA"
  | other -> Utils.value_to_string other

let rec substitute_vars_in_expr
    (substs : (string * value) list)
    (index : int)
    (expr : Ast.expr)
    : Ast.expr =
  let subst = substitute_vars_in_expr substs index in
  match expr.node with
  | Var s ->
      (match List.find_opt (fun (name, _) -> name = s) substs with
       | Some (_, dep_value) ->
           let literal = slice_value dep_value index in
           Ast.mk_expr (Ast.Value literal)
       | None -> expr)
  | Call { fn; args } ->
      Ast.mk_expr (Ast.Call { fn = subst fn; args = List.map (fun (n, e) -> (n, subst e)) args })
  | BinOp { op; left; right } ->
      Ast.mk_expr (Ast.BinOp { op; left = subst left; right = subst right })
  | UnOp { op; operand } ->
      Ast.mk_expr (Ast.UnOp { op; operand = subst operand })
  | DotAccess { target; field } ->
      Ast.mk_expr (Ast.DotAccess { target = subst target; field })
  | IfElse { cond; then_; else_ } ->
      Ast.mk_expr (Ast.IfElse { cond = subst cond; then_ = subst then_; else_ = subst else_ })
  | Match { scrutinee; cases } ->
      Ast.mk_expr (Ast.Match { scrutinee = subst scrutinee; cases = List.map (fun (p, e) -> (p, subst e)) cases })
  | ListLit items ->
      Ast.mk_expr (Ast.ListLit (List.map (fun (n, e) -> (n, subst e)) items))
  | DictLit items ->
      Ast.mk_expr (Ast.DictLit (List.map (fun (k, e) -> (k, subst e)) items))
  | ListComp { expr; clauses } ->
      Ast.mk_expr (Ast.ListComp { expr = subst expr; clauses })
  | Lambda l ->
      Ast.mk_expr (Ast.Lambda { l with body = subst l.body })
  | BroadcastOp { op; left; right } ->
      Ast.mk_expr (Ast.BroadcastOp { op; left = subst left; right = subst right })
  | Unquote e -> Ast.mk_expr (Ast.Unquote (subst e))
  | UnquoteSplice e -> Ast.mk_expr (Ast.UnquoteSplice (subst e))
  | RawCode { raw_text; raw_identifiers } ->
      let new_text = List.fold_left (fun text (dep_name, dep_value) ->
        if List.mem dep_name raw_identifiers then
          let literal_str = value_to_literal (slice_value dep_value index) in
          Str.global_replace
            (Str.regexp ("\\b" ^ Str.quote dep_name ^ "\\b"))
            literal_str
            text
        else text
      ) raw_text substs in
      Ast.mk_expr (Ast.RawCode { raw_text = new_text; raw_identifiers })
  | _ -> expr

type branch_info = {
  branch_name : string;
  orig_name : string;
  branch_un : unbuilt_node;
}

let get_node_command (p : pipeline_result) (name : string) : Ast.expr option =
  match List.assoc_opt name p.p_nodes with
  | Some (VNode un) -> Some un.un_command
  | Some (VComputedNode _) -> List.assoc_opt name p.p_exprs
  | _ -> None

let expand_pipeline_internal (p : pipeline_result) (to_script : string option) : value =
  if not p.p_has_patterns then
    VPipeline p
  else
    let existing_names = List.map fst p.p_exprs in

    let branches_result : (branch_info list, value) Result.t = List.fold_left (fun acc (name, pattern) ->
      match acc with
      | Error _ -> acc
      | Ok _ ->
          let process_map dep_names =
            let resolve_dep_value dep_name =
              match List.assoc_opt dep_name p.p_exprs with
              | Some expr ->
                  (try
                     match Eval.eval_expr (ref Ast.Env.empty) expr with
                     | VError _ -> VNA NAGeneric
                     | v -> v
                   with _ -> VNA NAGeneric)
              | None -> VNA NAGeneric
            in
            let dep_values = List.map resolve_dep_value dep_names in
            let has_missing = List.exists (fun v -> match v with VNA _ -> true | _ -> false) dep_values in
            if has_missing then Error (Error.type_error (Printf.sprintf "expand_pipeline: dependency value not found for node '%s'." name))
            else
              let lengths = List.map value_length dep_values in
              let branch_count = match lengths with h :: _ -> h | [] -> 0 in
              let lengths_match = List.for_all (fun l -> l = branch_count) lengths in
              if not lengths_match then Error (Error.type_error (Printf.sprintf "expand_pipeline: dependencies for node '%s' have mismatched lengths." name))
              else if branch_count = 0 then Ok []
              else
                match get_node_command p name with
                | Some command_expr ->
                    let substs = List.combine dep_names dep_values in
                    Ok (List.init branch_count (fun i ->
                      let branch_name = name ^ "_branch_" ^ string_of_int (i + 1) in
                      let substituted_command = substitute_vars_in_expr substs i command_expr in
                      { branch_name; orig_name = name; branch_un = {
                        un_command = substituted_command;
                        un_script = None;
                        un_runtime = "T";
                        un_serializer = Ast.mk_expr (Ast.Var "default");
                        un_deserializer = Ast.mk_expr (Ast.Var "default");
                        un_env_vars = [];
                        un_args = [];
                        un_shell = None;
                        un_shell_args = [];
                        un_functions = [];
                        un_includes = [];
                        un_noop = false;
                        un_dependencies = None;
                        un_pattern = None;
                        un_iteration = "vector";
                      }}
                    ))
                | None -> Error (Error.type_error (Printf.sprintf "expand_pipeline: node '%s' not found in pipeline." name))
          in
          (match pattern with
           | PatternMap deps -> process_map deps
           | PatternCross _ ->
               Error (Error.type_error (Printf.sprintf "expand_pipeline: `cross_pattern` is not yet implemented for node '%s'. Only `map_pattern` is supported in this release." name))
           | PatternSlice _  | PatternHead _ | PatternTail _ | PatternSample _ ->
               Error (Error.type_error (Printf.sprintf "expand_pipeline: this pattern type is not yet implemented for node '%s'. Only `map_pattern` is supported in this release." name)))
    ) (Ok []) p.p_patterns in

    match branches_result with
    | Error err -> err
    | Ok branches ->
        let branch_names = List.map (fun b -> b.branch_name) branches in
        let collisions = List.filter (fun bn -> List.mem bn existing_names) branch_names in
        if collisions <> [] then
          Error.make_error NameError
            (Printf.sprintf "expand_pipeline: branch name collision — node(s) already exist: %s. Rename the conflicting nodes or remove them before expansion."
               (String.concat ", " collisions))
        else
          let patterned_names = List.map fst p.p_patterns in
          let is_removed n = List.mem n patterned_names in

          let branch_nodes = List.map (fun b -> (b.branch_name, VNode b.branch_un)) branches in
          let branch_exprs = List.map (fun b -> (b.branch_name, b.branch_un.un_command)) branches in

          let copy_entry name lst =
            match List.assoc_opt name lst with
            | Some v -> Some v
            | None -> None
          in
          let make_branch_entries lst =
            List.filter_map (fun b ->
              match copy_entry b.orig_name lst with
              | Some v -> Some (b.branch_name, v)
              | None -> None
            ) branches
          in

          let expanded = {
            p_nodes          = List.filter (fun (n, _) -> not (is_removed n)) p.p_nodes @ branch_nodes;
            p_exprs          = List.filter (fun (n, _) -> not (is_removed n)) p.p_exprs @ branch_exprs;
            p_deps           = List.filter (fun (n, _) -> not (is_removed n)) p.p_deps @ make_branch_entries p.p_deps;
            p_imports        = p.p_imports;
            p_runtimes       = List.filter (fun (n, _) -> not (is_removed n)) p.p_runtimes @ make_branch_entries p.p_runtimes;
            p_serializers    = List.filter (fun (n, _) -> not (is_removed n)) p.p_serializers @ make_branch_entries p.p_serializers;
            p_deserializers  = List.filter (fun (n, _) -> not (is_removed n)) p.p_deserializers @ make_branch_entries p.p_deserializers;
            p_env_vars       = List.filter (fun (n, _) -> not (is_removed n)) p.p_env_vars @ make_branch_entries p.p_env_vars;
            p_args           = List.filter (fun (n, _) -> not (is_removed n)) p.p_args @ make_branch_entries p.p_args;
            p_shells         = List.filter (fun (n, _) -> not (is_removed n)) p.p_shells @ make_branch_entries p.p_shells;
            p_shell_args     = List.filter (fun (n, _) -> not (is_removed n)) p.p_shell_args @ make_branch_entries p.p_shell_args;
            p_functions      = List.filter (fun (n, _) -> not (is_removed n)) p.p_functions @ make_branch_entries p.p_functions;
            p_includes       = List.filter (fun (n, _) -> not (is_removed n)) p.p_includes @ make_branch_entries p.p_includes;
            p_noops          = List.filter (fun (n, _) -> not (is_removed n)) p.p_noops @ make_branch_entries p.p_noops;
            p_scripts        = List.filter (fun (n, _) -> not (is_removed n)) p.p_scripts @ make_branch_entries p.p_scripts;
            p_explicit_deps  = List.filter (fun (n, _) -> not (is_removed n)) p.p_explicit_deps @ make_branch_entries p.p_explicit_deps;
            p_node_diagnostics = List.filter (fun (n, _) -> not (is_removed n)) p.p_node_diagnostics @
              List.map (fun b -> (b.branch_name, Utils.empty_node_diagnostics)) branches;
            p_has_patterns   = false;
            p_patterns       = [];
            p_iterations     = List.filter (fun (n, _) -> not (is_removed n)) p.p_iterations @
              List.map (fun b -> (b.branch_name, "vector")) branches;
          } in

          (match to_script with
           | None -> VPipeline expanded
           | Some path ->
               let pipeline_def = Ast.PipelineDef (
                 List.filter (fun (n, _) -> not (is_removed n)) p.p_exprs @ branch_exprs
               ) in
               let script_content = Nix_unparse.unparse_expr (Ast.mk_expr pipeline_def) in
               (try
                  let oc = open_out path in
                  output_string oc script_content;
                  close_out oc;
                  VPipeline expanded
                with e ->
                  Error.make_error RuntimeError
                    (Printf.sprintf "expand_pipeline: could not write script to %s: %s" path (Printexc.to_string e))))

let register env =
  let expand_fn named_args _env =
    let get_arg name pos default named_args =
      match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
      | Some v -> (true, v)
      | None ->
          let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
          if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
          else (false, default)
    in
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["p"; "to_script"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "expand_pipeline: unknown argument '%s'" k)
    | None when positional_count > 2 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `expand_pipeline` accepts at most 2 positional arguments but received %d." positional_count)
    | None ->
      let (_p_provided, p_val) = get_arg "p" 1 (VNA NAGeneric) named_args in
      (match p_val with
       | VPipeline p ->
           let (_ts_provided, to_script_val) = get_arg "to_script" 2 (VNA NAGeneric) named_args in
           (match to_script_val with
            | VString s -> expand_pipeline_internal p (Some s)
            | VSymbol s -> expand_pipeline_internal p (Some s)
            | VNA _ -> expand_pipeline_internal p None
            | other ->
                Error.type_error (Printf.sprintf "expand_pipeline: `to_script` expects a String path, got %s." (Utils.type_name other)))
       | other ->
           Error.type_error (Printf.sprintf "expand_pipeline: expected a Pipeline as first argument, got %s." (Utils.type_name other)))
  in
  Env.add "expand_pipeline" (make_builtin_named ~name:"expand_pipeline" ~variadic:true 1 expand_fn) env
