open Ast

(*
--# Mutate Pipeline Node Metadata
--#
--# Modifies metadata fields on pipeline nodes. Supports a `where` named
--# argument to scope changes to a subset of nodes. Without `where`, all
--# nodes are affected.
--#
--# Mutable metadata fields: `noop` (Bool), `serializer` (String),
--# `deserializer` (String), `runtime` (String), `deps` (List[String]),
--# `functions` (List[String]), `include` (List[String]),
--# `env_vars` (Dict), `args` (Dict), `shell` (String), `shell_args` (List[String]),
--# `flake` (String).
--#
--# The `where` clause uses NSE (`$field`) just like `filter_node`.
--#
--# @name mutate_node
--# @param p :: Pipeline The pipeline to modify.
--# @param ... :: KeywordArgs Metadata assignments as `$field = value` pairs.
--# @param where :: Function (Optional) Predicate scoping which nodes are updated.
--# @return :: Pipeline A new pipeline with updated node metadata.
--# @example
--#   p |> mutate_node($noop = true)
--#   p |> mutate_node($serializer = "pmml", where = $runtime == "R")
--# @family pipeline
--# @seealso filter_node, rename_node
--# @export
*)
let register ~eval_call env =
  Env.add "mutate_node"
    (make_builtin_named ~name:"mutate_node" ~variadic:true 1 (fun named_args env ->
      match named_args with
      | [] -> Error.arity_error_named "mutate_node" 1 0
      | (_, VPipeline p) :: rest ->
          (* Separate the optional `where` predicate from field assignments.
             Named args arrive as (string option * value) pairs. *)
          let where_pred_opt = List.assoc_opt (Some "where") rest in
          let mutations = List.filter (fun (name, _) -> name <> Some "where") rest in
          let depths = Pipeline_to_frame.compute_depths p.p_deps in
          (* Determine whether a node matches the optional where predicate *)
          let matches name =
            match where_pred_opt with
            | None -> true
            | Some pred ->
                let row_dict = VDict (Pipeline_to_frame.node_metadata_dict name p depths) in
                (match eval_call env pred [(None, Ast.mk_expr (Value row_dict))] with
                 | VBool b -> b
                 | _ -> false)
          in
          (* Apply all mutations to the appropriate pipeline fields.
             Collect the first type error if any mutation argument has the wrong type. *)
          let first_error = ref None in
          let check name type_name expected_type =
            Printf.sprintf "Function `mutate_node`: `%s` must be a %s, got %s."
              name expected_type (Utils.type_name type_name)
          in
          let new_runtimes =
            match List.assoc_opt (Some "runtime") mutations with
            | None -> p.p_runtimes
            | Some (VString v) ->
                List.map (fun (n, old) -> if matches n then (n, v) else (n, old)) p.p_runtimes
            | Some v ->
                first_error := Some (Error.type_error (check "runtime" v "String"));
                p.p_runtimes
          in
          let new_noops =
            match List.assoc_opt (Some "noop") mutations with
            | None -> p.p_noops
            | Some (VBool v) ->
                List.map (fun (n, old) -> if matches n then (n, v) else (n, old)) p.p_noops
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "noop" v "Bool"));
                p.p_noops
          in
          let new_serializers =
            match List.assoc_opt (Some "serializer") mutations with
            | None -> p.p_serializers
            | Some (VString v) ->
                List.map (fun (n, old) ->
                  if matches n then (n, Ast.mk_expr (Ast.Value (Ast.VString v))) else (n, old)
                ) p.p_serializers
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "serializer" v "String"));
                p.p_serializers
          in
          let new_deserializers =
            match List.assoc_opt (Some "deserializer") mutations with
            | None -> p.p_deserializers
            | Some (VString v) ->
                List.map (fun (n, old) ->
                  if matches n then (n, Ast.mk_expr (Ast.Value (Ast.VString v))) else (n, old)
                ) p.p_deserializers
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "deserializer" v "String"));
                p.p_deserializers
          in
          let new_explicit_deps, new_p_deps =
            match List.assoc_opt (Some "deps") mutations with
            | None -> p.p_explicit_deps, p.p_deps
            | Some (VList items) ->
                let invalid_dep =
                  List.find_map (fun (_, v) ->
                    match v with
                    | VString _ | VSymbol _ -> None
                    | bad -> Some bad
                  ) items
                in
                (match invalid_dep with
                | Some bad ->
                    if !first_error = None then
                      first_error := Some (Error.type_error (check "deps" bad "String or Symbol"));
                    p.p_explicit_deps, p.p_deps
                | None ->
                    let deps =
                      List.filter_map (fun (_, v) ->
                        match v with
                        | VString s | VSymbol s -> Some s
                        | _ -> None
                      ) items
                    in
                    let new_explicit = List.map (fun (n, old) -> if matches n then (n, Some deps) else (n, old)) p.p_explicit_deps in
                    let new_pdeps = List.map (fun (n, old) -> if matches n then (n, deps) else (n, old)) p.p_deps in
                    new_explicit, new_pdeps)
            | Some (VNA _) ->
                (* Clearing explicit deps would leave p_explicit_deps and p_deps inconsistent.
                   Dependency edges cannot be safely re-derived here because that requires the
                   original eval environment and raw code text. Reject the operation so callers
                   don't get a silently stale dependency graph. *)
                if !first_error = None then
                  first_error := Some (Error.type_error "Function `mutate_node` cannot clear `deps` with NA because dependency edges cannot be re-derived here; rerun the pipeline to rebuild deps.");
                p.p_explicit_deps, p.p_deps
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "deps" v "List of Strings or Symbols"));
                 p.p_explicit_deps, p.p_deps
          in

          (* --- functions (List[String] — replace) --- *)
          let new_functions =
            match List.assoc_opt (Some "functions") mutations with
            | None -> p.p_functions
            | Some (VList _ | VString _ | VSymbol _ | VNA _ as v) ->
                let funcs = options_value_to_expr_list v in
                List.map (fun (n, old) -> if matches n then (n, funcs) else (n, old)) p.p_functions
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "functions" v "List of Strings or Symbols"));
                p.p_functions
          in

          (* --- include (List[String] — replace) --- *)
          let new_includes =
            match List.assoc_opt (Some "include") mutations with
            | None -> p.p_includes
            | Some (VList _ | VString _ | VSymbol _ | VNA _ as v) ->
                let incs = options_value_to_expr_list v in
                List.map (fun (n, old) -> if matches n then (n, incs) else (n, old)) p.p_includes
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "include" v "List of Strings or Symbols"));
                p.p_includes
          in

          (* --- env_vars (Dict — replace) --- *)
          let new_env_vars =
            match List.assoc_opt (Some "env_vars") mutations with
            | None -> p.p_env_vars
            | Some (VDict pairs) ->
                List.map (fun (n, old) -> if matches n then (n, pairs) else (n, old)) p.p_env_vars
            | Some (VNA _) ->
                List.map (fun (n, old) -> if matches n then (n, []) else (n, old)) p.p_env_vars
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "env_vars" v "Dict"));
                p.p_env_vars
          in

          (* --- args (Dict — replace) --- *)
          let new_args =
            match List.assoc_opt (Some "args") mutations with
            | None -> p.p_args
            | Some (VDict pairs) ->
                List.map (fun (n, old) -> if matches n then (n, pairs) else (n, old)) p.p_args
            | Some (VNA _) ->
                List.map (fun (n, old) -> if matches n then (n, []) else (n, old)) p.p_args
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "args" v "Dict"));
                p.p_args
          in

          (* --- shell (String — replace) --- *)
          let new_shells =
            match List.assoc_opt (Some "shell") mutations with
            | None -> p.p_shells
            | Some (VString s) ->
                List.map (fun (n, old) -> if matches n then (n, Some s) else (n, old)) p.p_shells
            | Some (VSymbol s) ->
                List.map (fun (n, old) -> if matches n then (n, Some s) else (n, old)) p.p_shells
            | Some (VNA _) ->
                List.map (fun (n, old) -> if matches n then (n, None) else (n, old)) p.p_shells
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "shell" v "String"));
                p.p_shells
          in

          (* --- shell_args (List[String] — replace) --- *)
          let new_shell_args =
            match List.assoc_opt (Some "shell_args") mutations with
            | None -> p.p_shell_args
            | Some (VList _ | VString _ | VSymbol _ | VNA _ as v) ->
                let args = options_value_to_expr_list v in
                List.map (fun (n, old) -> if matches n then (n, args) else (n, old)) p.p_shell_args
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "shell_args" v "List of Strings or Symbols"));
                p.p_shell_args
          in

          (* --- flake (String — replace) --- *)
          let new_flakes =
            match List.assoc_opt (Some "flake") mutations with
            | None -> p.p_flakes
            | Some (VString s) ->
                List.map (fun (n, old) -> if matches n then (n, Some s) else (n, old)) p.p_flakes
            | Some (VSymbol s) ->
                List.map (fun (n, old) -> if matches n then (n, Some s) else (n, old)) p.p_flakes
            | Some (VNA _) ->
                List.map (fun (n, old) -> if matches n then (n, None) else (n, old)) p.p_flakes
            | Some v ->
                if !first_error = None then
                  first_error := Some (Error.type_error (check "flake" v "String"));
                p.p_flakes
          in

          (match !first_error with
          | Some e -> e
          | None ->
              let mut_ser = List.mem_assoc (Some "serializer") mutations in
              let mut_deser = List.mem_assoc (Some "deserializer") mutations in
              let mut_noop = List.mem_assoc (Some "noop") mutations in
              let mut_deps = List.mem_assoc (Some "deps") mutations in
              let mut_funcs = List.mem_assoc (Some "functions") mutations in
              let mut_incs = List.mem_assoc (Some "include") mutations in
              let mut_env = List.mem_assoc (Some "env_vars") mutations in
              let mut_args = List.mem_assoc (Some "args") mutations in
              let mut_shell = List.mem_assoc (Some "shell") mutations in
              let mut_shell_args = List.mem_assoc (Some "shell_args") mutations in
              let mut_flake = List.mem_assoc (Some "flake") mutations in
              let new_provenance =
                List.map (fun (n, prov) ->
                  if not (matches n) then (n, prov)
                  else
                    let explicit_deps =
                      if mut_deps then
                        (match List.assoc_opt n new_p_deps with
                         | Some ds -> List.map (fun d -> (d, Ast.Source_node)) ds
                         | None -> prov.Ast.prov_explicit_deps)
                      else prov.Ast.prov_explicit_deps
                    in
                    let funcs =
                      if mut_funcs then
                        (match List.assoc_opt n new_functions with
                         | Some fs -> List.map (fun f -> (f, Ast.Source_node)) fs
                         | None -> prov.Ast.prov_functions)
                      else prov.Ast.prov_functions
                    in
                    let incs =
                      if mut_incs then
                        (match List.assoc_opt n new_includes with
                         | Some fs -> List.map (fun f -> (f, Ast.Source_node)) fs
                         | None -> prov.Ast.prov_includes)
                      else prov.Ast.prov_includes
                    in
                    let env_vars =
                      if mut_env then
                        (match List.assoc_opt n new_env_vars with
                         | Some vs -> List.map (fun (k, _) -> (k, Ast.Source_node)) vs
                         | None -> prov.Ast.prov_env_vars)
                      else prov.Ast.prov_env_vars
                    in
                    let args =
                      if mut_args then
                        (match List.assoc_opt n new_args with
                         | Some vs -> List.map (fun (k, _) -> (k, Ast.Source_node)) vs
                         | None -> prov.Ast.prov_args)
                      else prov.Ast.prov_args
                    in
                    let shell_args =
                      if mut_shell_args then
                        (match List.assoc_opt n new_shell_args with
                         | Some sa -> List.map (fun s -> (s, Ast.Source_node)) sa
                         | None -> prov.Ast.prov_shell_args)
                      else prov.Ast.prov_shell_args
                    in
                    (n, {
                          Ast.prov_functions = funcs;
                          Ast.prov_includes = incs;
                          Ast.prov_env_vars = env_vars;
                          Ast.prov_args = args;
                          Ast.prov_shell_args = shell_args;
                          Ast.prov_explicit_deps = explicit_deps;
                          Ast.prov_serializer = (if mut_ser then Some Ast.Source_node else prov.Ast.prov_serializer);
                          Ast.prov_deserializer = (if mut_deser then Some Ast.Source_node else prov.Ast.prov_deserializer);
                          Ast.prov_shell = (if mut_shell then Some Ast.Source_node else prov.Ast.prov_shell);
                          Ast.prov_flake = (if mut_flake then Some Ast.Source_node else prov.Ast.prov_flake);
                          Ast.prov_noop = (if mut_noop then Some Ast.Source_node else prov.Ast.prov_noop) })
                ) p.p_provenance
              in
              VPipeline {
                p with
                p_runtimes     = new_runtimes;
                p_noops        = new_noops;
                p_serializers  = new_serializers;
                p_deserializers = new_deserializers;
                p_explicit_deps = new_explicit_deps;
                p_deps         = new_p_deps;
                p_functions    = new_functions;
                p_includes     = new_includes;
                p_env_vars     = new_env_vars;
                p_args         = new_args;
                p_shells       = new_shells;
                p_shell_args   = new_shell_args;
                p_flakes       = new_flakes;
                p_provenance   = new_provenance;
              })
      | (_, _) :: _ -> Error.type_error "Function `mutate_node` expects a Pipeline as first argument."
    ))
    env
