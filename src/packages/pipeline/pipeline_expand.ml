(*
--# Expand pattern-based branching in a pipeline.
--#
--# Patterned nodes using `map_pattern(dep)` or `cross_pattern(...)` are
--# replaced with N branch copies, where N is the product of the dependency
--# lengths. Supports List, Vector, and DataFrame dependencies.
--#
--# `populate_pipeline(p)`, `build_pipeline(p)`, and pipeline composition
--# functions (`chain`, `parallel`, `union`, ...) now call this function
--# automatically when they detect unexpanded patterns.
--#
--# @param p :: Pipeline The pipeline to expand.
--# @param to_script :: String | NA = NA Optional file path to write the expanded pipeline script.
--# @return :: Pipeline The expanded pipeline with branches in place of patterned nodes.
--# @example
--#   p = pipeline { x = [1, 2, 3]; y = node(command = <{ x }>, pattern = map_pattern(x)) }
--#   expanded = expand_pipeline(p)
--#   pipeline_nodes(expanded)  -- ["x", "y_branch_1", "y_branch_2", "y_branch_3"]
--# @family pipeline
--# @export
*)

open Ast

let value_length (v : value) : int =
  match v with
  | VList items -> List.length items
  | VVector items -> Array.length items
  | VDataFrame df -> Arrow_table.num_rows df.arrow_table
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
  | VDataFrame df ->
      let n = Arrow_table.num_rows df.arrow_table in
      if index >= 0 && index < n then
        VDataFrame { df with arrow_table = Arrow_table.slice df.arrow_table index 1 }
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
      (* Runtime-agnostic: identifier substitution via raw_identifiers list and
         \bname\b word-boundary regex is safe across all runtimes (R, Python,
         Julia, sh, etc.) — only identifiers explicitly detected by the parser
         are replaced. *)
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
  branch_index : int;
  branch_un : unbuilt_node;
}

let get_node_command (p : pipeline_result) (name : string) : Ast.expr option =
  match List.assoc_opt name p.p_nodes with
  | Some (VNode un) -> Some un.un_command
  | Some (VComputedNode _) -> List.assoc_opt name p.p_exprs
  | _ -> None

let resolve_dep_value (p : pipeline_result) (env : value Env.t) (dep_name : string) : value =
  let try_eval () =
    match List.assoc_opt dep_name p.p_exprs with
    | Some expr ->
        (try
           match Eval.eval_expr (ref env) expr with
           | VError _ -> VNA NAGeneric
           | v -> v
         with _ -> VNA NAGeneric)
    | None -> VNA NAGeneric
  in
  match List.assoc_opt dep_name p.p_nodes with
  | Some (VComputedNode _) -> try_eval ()
  | Some (VNodeResult { v = VComputedNode _; _ }) -> try_eval ()
  | Some (VNodeResult { v; _ }) -> v
  | Some v -> v
  | None ->
      match Ast.get_in_memory_node_value ~p_exprs:p.p_exprs ~node_name:dep_name with
      | Some (VNodeResult { v; _ }) ->
          (match v with VComputedNode _ -> try_eval () | _ -> v)
      | Some v ->
          (match v with VComputedNode _ -> try_eval () | _ -> v)
      | None -> try_eval ()

let resolve_map_deps
    ?(expanded_map : (string * string list) list = [])
    (p : pipeline_result) (env : value Env.t) (name : string) (dep_names : string list) :
    (value list * int, value) Result.t =
  let dep_values = List.map (fun dep_name ->
    match List.find_opt (fun (orig, _) -> orig = dep_name) expanded_map with
    | Some (_, branches) ->
        VVector (Array.of_list (List.map (fun b -> VSymbol b) branches))
    | None -> resolve_dep_value p env dep_name
  ) dep_names in
  let has_missing = List.exists (fun v -> match v with VNA _ -> true | _ -> false) dep_values in
  if has_missing then
    Error (Error.type_error (Printf.sprintf "expand_pipeline: dependency value not found for node '%s'." name))
  else
    let lengths = List.map value_length dep_values in
    let branch_count = match lengths with h :: _ -> h | [] -> 0 in
    let lengths_match = List.for_all (fun l -> l = branch_count) lengths in
    if not lengths_match then
      let details = String.concat ", " (List.map2 (fun d l -> d ^ "=" ^ string_of_int l) dep_names lengths) in
      Error (Error.type_error (Printf.sprintf "expand_pipeline: dependencies for node '%s' have mismatched lengths (%s)." name details))
    else if branch_count = 0 then
      Error (Error.type_error (Printf.sprintf "expand_pipeline: dependencies for node '%s' have zero length." name))
    else
      Ok (dep_values, branch_count)

let make_branch (name : string) (orig_name : string) (i : int) (command_expr : Ast.expr) : branch_info =
  let branch_name = name ^ "_branch_" ^ string_of_int (i + 1) in
  { branch_name; orig_name; branch_index = i; branch_un = {
    un_command = command_expr;
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

let process_map
    ?(expanded_map : (string * string list) list = [])
    (p : pipeline_result) (env : value Env.t) (name : string) (dep_names : string list)
    : (branch_info list, value) Result.t =
  match resolve_map_deps ~expanded_map p env name dep_names with
  | Error _ as e -> e
  | Ok (dep_values, branch_count) ->
      match get_node_command p name with
      | Some command_expr ->
          let substs = List.combine dep_names dep_values in
          Ok (List.init branch_count (fun i ->
            let substituted_command = substitute_vars_in_expr substs i command_expr in
            make_branch name name i substituted_command
          ))
      | None -> Error (Error.type_error (Printf.sprintf "expand_pipeline: node '%s' not found in pipeline." name))

let compute_cross_element_indices (sub_lengths : int list) (_total_branches : int) (branch_idx : int) : int list =
  let rec go idx remaining_lengths acc =
    match remaining_lengths with
    | [] -> List.rev acc
    | len :: rest ->
        let stride = List.fold_left ( * ) 1 rest in
        let elem = (idx / stride) mod len in
        go idx rest (elem :: acc)
  in
  go branch_idx sub_lengths []

let process_cross
    ?(expanded_map : (string * string list) list = [])
    (p : pipeline_result) (env : value Env.t) (name : string) (sub_patterns : pattern_expr list)
    : (branch_info list, value) Result.t =
  let resolved_subs_result =
    List.fold_left (fun acc sub ->
      match acc with
      | Error _ -> acc
      | Ok subs ->
          (match sub with
           | PatternMap dep_names ->
               (match resolve_map_deps ~expanded_map p env name dep_names with
                | Ok (dep_values, branch_count) -> Ok (subs @ [(dep_names, dep_values, branch_count)])
                | Error _ as e -> e)
           | PatternCross _ ->
               Error (Error.type_error
                 (Printf.sprintf "expand_pipeline: nested cross_pattern is not supported for node '%s'." name))
           | PatternSlice _ | PatternHead _ | PatternTail _ | PatternSample _ ->
               Error (Error.type_error
                 (Printf.sprintf "expand_pipeline: only map_pattern is supported inside cross_pattern for node '%s'." name)))
    ) (Ok []) sub_patterns
  in
  match resolved_subs_result with
  | Error _ as e -> e
  | Ok resolved_subs ->
      let sub_lengths = List.map (fun (_, _, bc) -> bc) resolved_subs in
      let total_branches = List.fold_left ( * ) 1 sub_lengths in
      match get_node_command p name with
      | None -> Error (Error.type_error (Printf.sprintf "expand_pipeline: node '%s' not found in pipeline." name))
      | Some command_expr ->
          Ok (List.init total_branches (fun i ->
            let indices = compute_cross_element_indices sub_lengths total_branches i in
            let substs = List.concat (List.map2 (fun (dep_names, dep_values, _) elem_idx ->
              List.map2 (fun dep_name dep_value ->
                (dep_name, slice_value dep_value elem_idx)
              ) dep_names dep_values
            ) resolved_subs indices) in
            let substituted_command = substitute_vars_in_expr substs 0 command_expr in
            make_branch name name i substituted_command
          ))

let expand_pipeline_internal (p : pipeline_result) (env : value Env.t) (to_script : string option) : value =
  if not p.p_has_patterns then
    VPipeline p
  else
    let existing_names = List.map fst p.p_exprs in
    let patterned_node_names = List.map fst p.p_patterns in

    (* Build dependency graph among patterned nodes for topological sort *)
    let pattern_dep_names (name : string) : string list =
      match List.assoc_opt name p.p_patterns with
      | Some (PatternMap deps) ->
          List.filter (fun d -> List.mem d patterned_node_names) deps
      | Some (PatternCross subs) ->
          let all_deps = List.concat_map (function
            | PatternMap deps -> deps
            | _ -> []
          ) subs in
          List.filter (fun d -> List.mem d patterned_node_names) all_deps
      | _ -> []
    in

    (* Kahn's algorithm for topological sort — deps before dependents *)
    let sorted_patterns =
      let in_degree : (string, int) Hashtbl.t = Hashtbl.create 16 in
      let dependents : (string, string list) Hashtbl.t = Hashtbl.create 16 in
      List.iter (fun (name, _) ->
        Hashtbl.replace in_degree name 0;
        Hashtbl.replace dependents name []
      ) p.p_patterns;
      List.iter (fun (name, _) ->
        let deps = pattern_dep_names name in
        Hashtbl.replace in_degree name (List.length deps);
        List.iter (fun dep ->
          Hashtbl.replace dependents dep (name :: Hashtbl.find dependents dep)
        ) deps
      ) p.p_patterns;
      let queue = Queue.create () in
      Hashtbl.iter (fun name deg ->
        if deg = 0 then Queue.push name queue
      ) in_degree;
      let result = ref [] in
      while Queue.length queue > 0 do
        let name = Queue.pop queue in
        result := name :: !result;
        List.iter (fun dependent ->
          let new_deg = Hashtbl.find in_degree dependent - 1 in
          Hashtbl.replace in_degree dependent new_deg;
          if new_deg = 0 then Queue.push dependent queue
        ) (Hashtbl.find dependents name)
      done;
      if List.length !result <> List.length p.p_patterns then
        Error (Error.make_error StructuralError
          "expand_pipeline: circular dependency detected among patterned nodes.")
      else
        let sorted_names = List.rev !result in
        Ok (List.filter_map (fun name ->
          List.find_opt (fun (n, _) -> n = name) p.p_patterns
        ) sorted_names)
    in

    match sorted_patterns with
    | Error err -> err
    | Ok sorted_patterns ->

    let all_branches = ref [] in
    let expanded_map = ref [] in

    let result = List.fold_left (fun acc (name, pattern) ->
      match acc with
      | Error _ -> acc
      | Ok () ->
          let branch_result = match pattern with
            | PatternMap deps ->
                process_map ~expanded_map:!expanded_map p env name deps
            | PatternCross subs ->
                process_cross ~expanded_map:!expanded_map p env name subs
            | PatternSlice _ | PatternHead _ | PatternTail _ | PatternSample _ ->
                Error (Error.type_error
                  (Printf.sprintf "expand_pipeline: this pattern type is not yet implemented for node '%s'. Only `map_pattern` and `cross_pattern` are supported in this release." name))
          in
          match branch_result with
          | Error e -> Error e
          | Ok new_branches ->
              all_branches := !all_branches @ new_branches;
              let branch_names = List.map (fun b -> b.branch_name) new_branches in
              expanded_map := (name, branch_names) :: !expanded_map;
              Ok ()
    ) (Ok ()) sorted_patterns in

    match result with
    | Error err -> err
    | Ok () ->
        let branches = !all_branches in
        let branch_names = List.map (fun b -> b.branch_name) branches in
        let collisions = List.filter (fun bn -> List.mem bn existing_names) branch_names in
        if collisions <> [] then
          Error.make_error NameError
            (Printf.sprintf "expand_pipeline: branch name collision — node(s) already exist: %s. Rename the conflicting nodes or remove them before expansion."
               (String.concat ", " collisions))
        else
          let is_removed n = List.mem n patterned_node_names in

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
          let make_branch_deps entries =
            List.filter_map (fun b ->
              match List.assoc_opt b.orig_name entries with
              | Some deps ->
                  let updated = List.map (fun dep ->
                    match List.find_opt (fun (orig, _) -> orig = dep) !expanded_map with
                    | Some (_, branch_names) -> List.nth branch_names b.branch_index
                    | None -> dep
                  ) deps in
                  Some (b.branch_name, updated)
              | None -> None
            ) branches
          in
          let make_branch_explicit_deps entries =
            List.filter_map (fun b ->
              match List.assoc_opt b.orig_name entries with
              | Some deps_opt ->
                  let updated = Option.map (fun deps ->
                    List.map (fun dep ->
                      match List.find_opt (fun (orig, _) -> orig = dep) !expanded_map with
                      | Some (_, branch_names) -> List.nth branch_names b.branch_index
                      | None -> dep
                    ) deps
                  ) deps_opt in
                  Some (b.branch_name, updated)
              | None -> None
            ) branches
          in

          let expanded = {
            p_nodes          = List.filter (fun (n, _) -> not (is_removed n)) p.p_nodes @ branch_nodes;
            p_exprs          = List.filter (fun (n, _) -> not (is_removed n)) p.p_exprs @ branch_exprs;
            p_deps           = List.filter (fun (n, _) -> not (is_removed n)) p.p_deps @ make_branch_deps p.p_deps;
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
            p_explicit_deps  = List.filter (fun (n, _) -> not (is_removed n)) p.p_explicit_deps @ make_branch_explicit_deps p.p_explicit_deps;
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

let expand_pipeline_for_build (p : pipeline_result) (env : value Env.t) : (pipeline_result, value) Result.t =
  if not p.p_has_patterns then Ok p
  else
    match expand_pipeline_internal p env None with
    | VPipeline p' -> Ok p'
    | VError _ as err -> Error err
    | other -> Error (Error.type_error
      (Printf.sprintf "expand_pipeline: internal error — expected VPipeline, got %s" (Utils.value_to_string other)))

(* Wire up auto-expansion callbacks for composition and set-op modules *)
let () =
  Pipeline_composition.expand_for_build := expand_pipeline_for_build;
  Pipeline_set_ops.expand_for_build := expand_pipeline_for_build

let register env =
  let expand_fn named_args env =
    let get_arg = Pipeline_args.get_arg in
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
      let p_val = match p_val with
        | VMetaPipeline _ -> Pipeline_composition.flatten_meta p_val
        | _ -> p_val
      in
      (match p_val with
       | VPipeline p ->
           let (_ts_provided, to_script_val) = get_arg "to_script" 2 (VNA NAGeneric) named_args in
           (match to_script_val with
            | VString s -> expand_pipeline_internal p env (Some s)
            | VSymbol s -> expand_pipeline_internal p env (Some s)
            | VNA _ -> expand_pipeline_internal p env None
            | other ->
                Error.type_error (Printf.sprintf "expand_pipeline: `to_script` expects a String path, got %s." (Utils.type_name other)))
       | other ->
           Error.type_error (Printf.sprintf "expand_pipeline: expected a Pipeline as first argument, got %s." (Utils.type_name other)))
  in
  Env.add "expand_pipeline" (make_builtin_named ~name:"expand_pipeline" ~variadic:true 1 expand_fn) env
