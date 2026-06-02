open Ast

(** Merge: lst1 entries first, then lst2 entries whose keys are new to lst1. *)
let merge_new lst1 lst2 =
  let keys1 = List.map fst lst1 in
  lst1 @ List.filter (fun (k, _) -> not (List.mem k keys1)) lst2

let find_terminal_nodes (nodes : (string * 'a) list) (deps : (string * string list) list) : string list =
  let all_deps = List.concat_map snd deps in
  List.filter (fun name -> not (List.mem name all_deps)) (List.map fst nodes)

let find_root_nodes (nodes : (string * 'a) list) (deps : (string * string list) list) : string list =
  let local_names = List.map fst nodes in
  List.filter (fun name ->
    let node_deps = match List.assoc_opt name deps with Some d -> d | None -> [] in
    not (List.exists (fun d -> List.mem d local_names) node_deps)
  ) local_names

let rec bound_vars = function
  | PWildcard | PNA -> []
  | PVar name -> [name]
  | PError None -> []
  | PError (Some name) -> [name]
  | PList (patterns, rest) ->
      let names = List.concat_map bound_vars patterns in
      match rest with
      | Some name -> name :: names
      | None -> names

let rec rewrite_expr sub_name local_names (expr : Ast.expr) : Ast.expr =
  let loc = expr.loc in
  let node =
    match expr.node with
    | Var name when List.mem name local_names ->
        DotAccess { target = Ast.mk_expr ?loc (Var sub_name); field = name }
    | Var _ as v -> v
    | Value _ as v -> v
    | ColumnRef _ as c -> c
    | RawCode _ as r -> r
    | ShellExpr _ as s -> s
    | ListLit items ->
        ListLit (List.map (fun (name, e) -> (name, rewrite_expr sub_name local_names e)) items)
    | DictLit pairs ->
        DictLit (List.map (fun (name, e) -> (name, rewrite_expr sub_name local_names e)) pairs)
    | BinOp { op; left; right } ->
        BinOp { op; left = rewrite_expr sub_name local_names left; right = rewrite_expr sub_name local_names right }
    | BroadcastOp { op; left; right } ->
        BroadcastOp { op; left = rewrite_expr sub_name local_names left; right = rewrite_expr sub_name local_names right }
    | UnOp { op; operand } ->
        UnOp { op; operand = rewrite_expr sub_name local_names operand }
    | DotAccess { target; field } ->
        DotAccess { target = rewrite_expr sub_name local_names target; field }
    | Call { fn; args } ->
        Call { fn = rewrite_expr sub_name local_names fn;
               args = List.map (fun (name, e) -> (name, rewrite_expr sub_name local_names e)) args }
    | Lambda l ->
        let local_names_filtered = List.filter (fun n -> not (List.mem n l.params)) local_names in
        Lambda { l with body = rewrite_expr sub_name local_names_filtered l.body }
    | IfElse { cond; then_; else_ } ->
        IfElse { cond = rewrite_expr sub_name local_names cond;
                 then_ = rewrite_expr sub_name local_names then_;
                 else_ = rewrite_expr sub_name local_names else_ }
    | Match { scrutinee; cases } ->
        Match { scrutinee = rewrite_expr sub_name local_names scrutinee;
                cases = List.map (fun (pat, body) ->
                  let bound = bound_vars pat in
                  let local_names_filtered = List.filter (fun n -> not (List.mem n bound)) local_names in
                  (pat, rewrite_expr sub_name local_names_filtered body)
                ) cases }
    | Block stmts ->
        Block (List.map (rewrite_stmt sub_name local_names) stmts)
    | PipelineDef nodes ->
        PipelineDef (List.map (fun (name, e) -> (name, rewrite_expr sub_name local_names e)) nodes)
    | PipelineOfDef nodes ->
        PipelineOfDef (List.map (fun (name, e) -> (name, rewrite_expr sub_name local_names e)) nodes)
    | IntentDef pairs ->
        IntentDef (List.map (fun (name, e) -> (name, rewrite_expr sub_name local_names e)) pairs)
    | Unquote e ->
        Unquote (rewrite_expr sub_name local_names e)
    | UnquoteSplice e ->
        UnquoteSplice (rewrite_expr sub_name local_names e)
    | ListComp { expr; clauses } ->
        let rec filter_clauses local_acc = function
          | [] -> (local_acc, [])
          | CFor { var; iter } :: rest ->
              let next_local = List.filter (fun n -> n <> var) local_acc in
              let (final_local, rest_clauses) = filter_clauses next_local rest in
              (final_local, CFor { var; iter = rewrite_expr sub_name local_acc iter } :: rest_clauses)
          | CFilter filter_expr :: rest ->
              let (final_local, rest_clauses) = filter_clauses local_acc rest in
              (final_local, CFilter (rewrite_expr sub_name local_acc filter_expr) :: rest_clauses)
        in
        let (filtered_local, rewritten_clauses) = filter_clauses local_names clauses in
        ListComp { expr = rewrite_expr sub_name filtered_local expr; clauses = rewritten_clauses }
  in
  Ast.mk_expr ?loc node

and rewrite_stmt sub_name local_names (stmt : Ast.stmt) : Ast.stmt =
  let loc = stmt.loc in
  let node =
    match stmt.node with
    | Expression e -> Expression (rewrite_expr sub_name local_names e)
    | Assignment { name; typ; expr } ->
        Assignment { name; typ; expr = rewrite_expr sub_name local_names expr }
    | Reassignment { name; expr } ->
        Reassignment { name; expr = rewrite_expr sub_name local_names expr }
    | Import _ | ImportPackage _ | ImportFrom _ | ImportFileFrom _ as imp -> imp
  in
  Ast.mk_stmt ?loc node

let namespace_value sub_name local_names (v : value) : value =
  match v with
  | VComputedNode cn ->
      let cn_name = sub_name ^ "." ^ cn.cn_name in
      let cn_dependencies = List.map (fun dep ->
        if List.mem dep local_names then sub_name ^ "." ^ dep else dep
      ) cn.cn_dependencies in
      VComputedNode { cn with cn_name; cn_dependencies }
  | _ -> v

let namespace_diagnostics sub_name local_names nd =
  let nd_upstream_errors = List.map (fun name ->
    if List.mem name local_names then sub_name ^ "." ^ name else name
  ) nd.nd_upstream_errors in
  { nd with nd_upstream_errors }

let rec find_dot_access_targets (expr : Ast.expr) : string list =
  match expr.node with
  | Var _ | Value _ | ColumnRef _ | RawCode _ | ShellExpr _ -> []
  | ListLit items -> List.concat_map (fun (_, e) -> find_dot_access_targets e) items
  | DictLit pairs -> List.concat_map (fun (_, e) -> find_dot_access_targets e) pairs
  | BinOp { left; right; _ } | BroadcastOp { left; right; _ } ->
      find_dot_access_targets left @ find_dot_access_targets right
  | UnOp { operand; _ } -> find_dot_access_targets operand
  | DotAccess { target; _ } ->
      (match target.node with
       | Var name -> [name]
       | _ -> find_dot_access_targets target)
  | Call { fn; args } ->
      find_dot_access_targets fn @ List.concat_map (fun (_, e) -> find_dot_access_targets e) args
  | Lambda l -> find_dot_access_targets l.body
  | IfElse { cond; then_; else_ } ->
      find_dot_access_targets cond @ find_dot_access_targets then_ @ find_dot_access_targets else_
  | Match { scrutinee; cases } ->
      find_dot_access_targets scrutinee @ List.concat_map (fun (_, body) -> find_dot_access_targets body) cases
  | Block stmts -> List.concat_map find_dot_access_targets_stmt stmts
  | PipelineDef nodes | PipelineOfDef nodes | IntentDef nodes ->
      List.concat_map (fun (_, e) -> find_dot_access_targets e) nodes
  | Unquote e | UnquoteSplice e -> find_dot_access_targets e
  | ListComp { expr; clauses } ->
      find_dot_access_targets expr @ List.concat_map (function
        | CFor { iter; _ } -> find_dot_access_targets iter
        | CFilter f -> find_dot_access_targets f
      ) clauses

and find_dot_access_targets_stmt (stmt : Ast.stmt) : string list =
  match stmt.node with
  | Expression e -> find_dot_access_targets e
  | Assignment { expr; _ } -> find_dot_access_targets expr
  | Reassignment { expr; _ } -> find_dot_access_targets expr
  | Import _ | ImportPackage _ | ImportFrom _ | ImportFileFrom _ -> []

let rec flatten_meta (v : value) : pipeline_result =
  match v with
  | VPipeline p -> p
  | VMetaPipeline mp ->
      let flattened_subs = List.map (fun (name, sub_val) ->
        (name, flatten_meta sub_val)
      ) mp.mp_pipelines in
      let namespaced_subs = List.map (fun (sub_name, flat_sub) ->
        let local_names = List.map fst flat_sub.p_exprs in
        let ns n = sub_name ^ "." ^ n in
        (sub_name, flat_sub, local_names, ns)
      ) flattened_subs in
      let final_deps = ref [] in
      List.iter (fun (sub_name, flat_sub, local_names, ns) ->
        let sub_deps = List.map (fun (n, deps) ->
          (ns n, List.map (fun d -> if List.mem d local_names then ns d else d) deps)
        ) flat_sub.p_deps in
        let dep_sub_names = match List.assoc_opt sub_name mp.mp_deps with Some d -> d | None -> [] in
        let sub_names = List.map fst mp.mp_pipelines in
        let inferred_deps =
          List.concat_map (fun (_, e) -> find_dot_access_targets e) flat_sub.p_exprs
          |> List.filter (fun target -> List.mem target sub_names && target <> sub_name)
        in
        let all_dep_sub_names = List.sort_uniq compare (dep_sub_names @ inferred_deps) in
        let sub_roots = find_root_nodes flat_sub.p_exprs flat_sub.p_deps in
        let updated_sub_deps = List.map (fun (n, deps) ->
          let orig_n = String.sub n (String.length sub_name + 1) (String.length n - String.length sub_name - 1) in
          if List.mem orig_n sub_roots then
            let additional_deps = List.concat_map (fun dep_sub_name ->
              match List.assoc_opt dep_sub_name flattened_subs with
              | None -> []
              | Some dep_flat ->
                  let dep_terminals = find_terminal_nodes dep_flat.p_exprs dep_flat.p_deps in
                  List.map (fun term -> dep_sub_name ^ "." ^ term) dep_terminals
            ) all_dep_sub_names in
            let clean_deps = List.filter (fun d -> not (List.mem d sub_names)) deps in
            (n, clean_deps @ additional_deps)
          else
            (n, deps)
        ) sub_deps in
        final_deps := !final_deps @ updated_sub_deps
      ) namespaced_subs;
      let merge_fields select_field combine_field =
        List.fold_left (fun acc (_, flat_sub, local_names, ns) ->
          let field_val = select_field flat_sub local_names ns in
          combine_field acc field_val
        ) [] namespaced_subs
      in
      let p_nodes = merge_fields (fun flat local ns ->
        let sub_name = String.sub (ns "") 0 (String.length (ns "") - 1) in
        List.map (fun (n, v) -> (ns n, namespace_value sub_name local v)) flat.p_nodes
      ) (@) in
      let p_exprs = merge_fields (fun flat local ns ->
        let sub_name = String.sub (ns "") 0 (String.length (ns "") - 1) in
        List.map (fun (n, e) -> (ns n, rewrite_expr sub_name local e)) flat.p_exprs
      ) (@) in
      let p_imports = merge_fields (fun flat _ _ -> flat.p_imports) (@) in
      let p_imports = List.sort_uniq compare p_imports in
      let p_runtimes = merge_fields (fun flat _ ns -> List.map (fun (n, r) -> (ns n, r)) flat.p_runtimes) (@) in
      let p_serializers = merge_fields (fun flat local ns ->
        let sub_name = String.sub (ns "") 0 (String.length (ns "") - 1) in
        List.map (fun (n, s) -> (ns n, rewrite_expr sub_name local s)) flat.p_serializers
      ) (@) in
      let p_deserializers = merge_fields (fun flat local ns ->
        let sub_name = String.sub (ns "") 0 (String.length (ns "") - 1) in
        List.map (fun (n, s) -> (ns n, rewrite_expr sub_name local s)) flat.p_deserializers
      ) (@) in
      let p_env_vars = merge_fields (fun flat _ ns -> List.map (fun (n, ev) -> (ns n, ev)) flat.p_env_vars) (@) in
      let p_args = merge_fields (fun flat _ ns -> List.map (fun (n, a) -> (ns n, a)) flat.p_args) (@) in
      let p_shells = merge_fields (fun flat _ ns -> List.map (fun (n, s) -> (ns n, s)) flat.p_shells) (@) in
      let p_shell_args = merge_fields (fun flat local ns ->
        let sub_name = String.sub (ns "") 0 (String.length (ns "") - 1) in
        List.map (fun (n, sa) -> (ns n, List.map (rewrite_expr sub_name local) sa)) flat.p_shell_args
      ) (@) in
      let p_functions = merge_fields (fun flat local ns ->
        let sub_name = String.sub (ns "") 0 (String.length (ns "") - 1) in
        List.map (fun (n, f) -> (ns n, List.map (rewrite_expr sub_name local) f)) flat.p_functions
      ) (@) in
      let p_includes = merge_fields (fun flat local ns ->
        let sub_name = String.sub (ns "") 0 (String.length (ns "") - 1) in
        List.map (fun (n, i) -> (ns n, List.map (rewrite_expr sub_name local) i)) flat.p_includes
      ) (@) in
      let p_noops = merge_fields (fun flat _ ns -> List.map (fun (n, no) -> (ns n, no)) flat.p_noops) (@) in
      let p_scripts = merge_fields (fun flat _ ns -> List.map (fun (n, sc) -> (ns n, sc)) flat.p_scripts) (@) in
      let p_explicit_deps = merge_fields (fun flat _ ns ->
        List.map (fun (n, ed) -> (ns n, Option.map (List.map ns) ed)) flat.p_explicit_deps
      ) (@) in
      let p_node_diagnostics = merge_fields (fun flat local ns ->
        List.map (fun (n, nd) -> (ns n, namespace_diagnostics (String.sub (ns "") 0 (String.length (ns "") - 1)) local nd)) flat.p_node_diagnostics
      ) (@) in
      {
        p_nodes;
        p_exprs;
        p_deps = !final_deps;
        p_imports;
        p_runtimes;
        p_serializers;
        p_deserializers;
        p_env_vars;
        p_args;
        p_shells;
        p_shell_args;
        p_functions;
        p_includes;
        p_noops;
        p_scripts;
        p_explicit_deps;
        p_node_diagnostics;
      }
  | _ -> failwith "meta_flatten: expected a MetaPipeline or Pipeline value"

let register ~(rerun_pipeline : ?strict:bool -> ?verbose:bool -> value Env.t -> pipeline_result -> value) env =

(*
--# Chain Two Pipelines
--#
--# Connects two pipelines by merging them. The second pipeline can reference
--# node names from the first pipeline as dependencies — these are automatically
--# satisfied. Errors if there are name collisions (other than the intentional
--# inter-pipeline wiring) or if no shared names exist between the two pipelines.
--#
--# @name chain
--# @param p1 :: Pipeline The upstream pipeline (provides outputs).
--# @param p2 :: Pipeline The downstream pipeline (consumes inputs).
--# @return :: Pipeline A merged pipeline with p2's nodes wired to p1's outputs.
--# @example
--#   p_etl |> chain(p_model)
--# @family pipeline
--# @seealso parallel, union
--# @export
*)
  let env = Env.add "chain"
    (make_builtin ~name:"chain" 2 (fun args env ->
      match args with
      | [VPipeline p1; VPipeline p2] ->
          let names1 = List.map fst p1.p_exprs in
          let names2 = List.map fst p2.p_exprs in
          (* Check for name collisions (same node in both) *)
          let collisions = List.filter (fun n -> List.mem n names2) names1 in
          if collisions <> [] then
            Error.make_error ValueError
              (Printf.sprintf
                 "Function `chain`: name collision(s) detected: %s. Use `rename_node` to resolve."
                 (String.concat ", " collisions))
          else begin
            (* Find shared references: node names from p1 that appear as deps in p2 *)
            let p2_all_deps = List.concat_map snd p2.p_deps in
            let shared = List.filter (fun n -> List.mem n p2_all_deps) names1 in
            if shared = [] then
              Error.make_error ValueError
                "Function `chain`: no shared dependency names found between the two pipelines."
            else
              rerun_pipeline ?strict:None env {
                p_nodes        = merge_new p1.p_nodes p2.p_nodes;
                p_exprs        = merge_new p1.p_exprs p2.p_exprs;
                p_deps         = merge_new p1.p_deps p2.p_deps;
                p_imports      = p1.p_imports @ p2.p_imports;
                p_runtimes     = merge_new p1.p_runtimes p2.p_runtimes;
                p_serializers  = merge_new p1.p_serializers p2.p_serializers;
                p_deserializers = merge_new p1.p_deserializers p2.p_deserializers;
                p_env_vars     = merge_new p1.p_env_vars p2.p_env_vars;
                p_args         = merge_new p1.p_args p2.p_args;
                p_shells       = merge_new p1.p_shells p2.p_shells;
                p_shell_args   = merge_new p1.p_shell_args p2.p_shell_args;
                p_functions    = merge_new p1.p_functions p2.p_functions;
                p_includes     = merge_new p1.p_includes p2.p_includes;
                p_noops        = merge_new p1.p_noops p2.p_noops;
                p_scripts      = merge_new p1.p_scripts p2.p_scripts;
                p_explicit_deps = merge_new p1.p_explicit_deps p2.p_explicit_deps;
                p_node_diagnostics = merge_new p1.p_node_diagnostics p2.p_node_diagnostics;
              }
          end
      | [_; _] -> Error.type_error "Function `chain` expects two Pipeline arguments."
      | _ -> Error.arity_error_named "chain" 2 (List.length args)
    ))
    env
  in

(*
--# Combine Pipelines in Parallel
--#
--# Combines two pipelines that are intended to run independently. Errors
--# immediately if any node name exists in both pipelines. Outputs are not
--# automatically wired.
--#
--# @name parallel
--# @param p1 :: Pipeline The first pipeline.
--# @param p2 :: Pipeline The second pipeline.
--# @return :: Pipeline A merged pipeline with all nodes from both.
--# @example
--#   parallel(p_r_model, p_py_model)
--# @family pipeline
--# @seealso chain, union
--# @export
*)
  let env = Env.add "parallel"
    (make_builtin ~name:"parallel" 2 (fun args env ->
      match args with
      | [VPipeline p1; VPipeline p2] ->
          let names1 = List.map fst p1.p_exprs in
          let names2 = List.map fst p2.p_exprs in
          let collisions = List.filter (fun n -> List.mem n names2) names1 in
          if collisions <> [] then
            Error.make_error ValueError
              (Printf.sprintf
                 "Function `parallel`: name collision(s) detected: %s. Use `rename_node` to resolve."
                 (String.concat ", " collisions))
          else
            rerun_pipeline ?strict:None env {
              p_nodes        = merge_new p1.p_nodes p2.p_nodes;
              p_exprs        = merge_new p1.p_exprs p2.p_exprs;
              p_deps         = merge_new p1.p_deps p2.p_deps;
              p_imports      = p1.p_imports @ p2.p_imports;
              p_runtimes     = merge_new p1.p_runtimes p2.p_runtimes;
              p_serializers  = merge_new p1.p_serializers p2.p_serializers;
              p_deserializers = merge_new p1.p_deserializers p2.p_deserializers;
              p_env_vars     = merge_new p1.p_env_vars p2.p_env_vars;
              p_args         = merge_new p1.p_args p2.p_args;
              p_shells       = merge_new p1.p_shells p2.p_shells;
              p_shell_args   = merge_new p1.p_shell_args p2.p_shell_args;
              p_functions    = merge_new p1.p_functions p2.p_functions;
              p_includes     = merge_new p1.p_includes p2.p_includes;
              p_noops        = merge_new p1.p_noops p2.p_noops;
              p_scripts      = merge_new p1.p_scripts p2.p_scripts;
              p_explicit_deps = merge_new p1.p_explicit_deps p2.p_explicit_deps;
              p_node_diagnostics = merge_new p1.p_node_diagnostics p2.p_node_diagnostics;
            }
      | [_; _] -> Error.type_error "Function `parallel` expects two Pipeline arguments."
      | _ -> Error.arity_error_named "parallel" 2 (List.length args)
    ))
    env
  in

  let env = Env.add "meta_flatten"
    (make_builtin ~name:"meta_flatten" 1 (fun args env ->
      match args with
      | [v] ->
          (try
             let flat_p = flatten_meta v in
             rerun_pipeline ?strict:None env flat_p
           with
           | Failure msg -> Error.make_error ValueError msg
           | _ -> Error.make_error TypeError "meta_flatten expects a MetaPipeline or Pipeline value")
      | _ -> Error.arity_error_named "meta_flatten" 1 (List.length args)
    ))
    env
  in

  env
