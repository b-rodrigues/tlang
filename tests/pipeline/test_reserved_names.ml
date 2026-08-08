(* tests/pipeline/test_reserved_names.ml *)
open Ast

let is_identifier_name (name : string) : bool =
  let is_first c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
  in
  let is_rest c =
    is_first c || (c >= '0' && c <= '9')
  in
  String.length name > 0
  && is_first name.[0]
  && String.for_all is_rest name

(* Minimal pipeline_result carrying only the node-name list; every other
   axis is empty so only the reserved-name check can fire. *)
let minimal_pipeline exprs : pipeline_result =
  { p_nodes = [];
    p_exprs = exprs;
    p_deps = [];
    p_imports = [];
    p_runtimes = [];
    p_serializers = [];
    p_deserializers = [];
    p_env_vars = [];
    p_args = [];
    p_shells = [];
    p_shell_args = [];
    p_functions = [];
    p_includes = [];
    p_noops = [];
    p_scripts = [];
    p_explicit_deps = [];
    p_node_diagnostics = [];
    p_has_patterns = false;
    p_patterns = [];
    p_iterations = [];
    p_flakes = [];
    p_provenance = [];
  }

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test =
  Printf.printf "Reserved Node Names:\n";

  (* --- Structural: check_reserved_node_names / collect_errors flag a
         reserved node name (construction via `pipeline { ... }` rejects
         these names, so a hand-built pipeline_result is the only way to
         exercise this branch). *)
  let p_reserved = minimal_pipeline [("n", Ast.mk_expr (Value (VInt 0)))] in
  let direct = Pipeline_validation.check_reserved_node_names p_reserved in
  (match direct with
   | [err] when err.ve_kind = "StructuralError" && err.ve_node = Some "n" &&
                 Test_helpers.contains err.ve_message "`n` is a builtin function" ->
       incr pass_count;
       Printf.printf "  ✓ check_reserved_node_names flags builtin collision `n`\n"
   | _ ->
       incr fail_count;
       let msg = Printf.sprintf
           "  ✗ check_reserved_node_names failed to flag builtin collision `n`. Got: %d error(s)\n"
           (List.length direct) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (match Pipeline_validation.collect_errors p_reserved with
   | err :: _ when err.ve_kind = "StructuralError" && err.ve_node = Some "n" ->
       incr pass_count;
       Printf.printf "  ✓ reserved-name error is first in collect_errors\n"
   | _ ->
       incr fail_count;
       let msg = "  ✗ reserved-name error not surfaced (or not first) in collect_errors\n" in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  let p_ok = minimal_pipeline [("safe_name", Ast.mk_expr (Value (VInt 0)))] in
  if Pipeline_validation.check_reserved_node_names p_ok = [] then begin
    incr pass_count;
    Printf.printf "  ✓ non-reserved node names pass the check\n"
  end else begin
    incr fail_count;
    let msg = "  ✗ non-reserved node name was flagged by check_reserved_node_names\n" in
    failures := msg :: !failures;
    Printf.printf "%s" msg
  end;

  (* --- Audit: the static reserved list must match the live environment.
         This is what forces the list to be updated whenever a builtin or
         known symbol is added. *)
  let env = Packages.init_env () in
  let bindings = Env.bindings env in
  let env_names = List.map fst bindings in
  (* `__`-prefixed names (e.g. __tlang_internal_import_origins__) are internal
     markers, not user-facing builtins, and cannot sensibly collide with node
     names. *)
  let env_identifier_names =
    List.filter (fun n -> is_identifier_name n && not (String.starts_with ~prefix:"__" n)) env_names
  in
  let missing = List.filter (fun n -> not (Reserved_names.is_reserved_node_name n)) env_identifier_names in
  let reserved_names = List.map fst Reserved_names.reserved in
  let duplicates =
    List.sort_uniq String.compare reserved_names
    |> fun uniq -> List.filter (fun n -> List.length (List.filter (fun n' -> n' = n) reserved_names) > 1) uniq
  in
  let extra = List.filter (fun n -> not (List.mem n env_names)) reserved_names in
  let kind_mismatches =
    List.filter_map (fun (n, expected) ->
      match List.assoc_opt n bindings with
      | Some v ->
          let actual = match v with VSymbol _ -> Reserved_names.RuntimeSymbol | _ -> Reserved_names.BuiltinFunction in
          if actual = expected then None else Some (n, actual, expected)
      | None -> None
    ) Reserved_names.reserved
  in
  if missing = [] && extra = [] && kind_mismatches = [] && duplicates = [] then begin
    incr pass_count;
    Printf.printf "  ✓ reserved list matches Packages.init_env (%d names, kinds included)\n"
      (List.length reserved_names)
  end else begin
    incr fail_count;
    let lines =
      (if missing <> [] then
         [ Printf.sprintf "    not reserved but bound in env: %s" (String.concat ", " missing) ]
       else [])
      @ (if extra <> [] then
           [ Printf.sprintf "    in list but not bound in env: %s" (String.concat ", " extra) ]
         else [])
      @ (if duplicates <> [] then
           [ Printf.sprintf "    duplicated in reserved list: %s" (String.concat ", " duplicates) ]
         else [])
      @ List.map (fun (n, actual, expected) ->
           Printf.sprintf "    kind mismatch for `%s`: env says %s, list says %s"
             n
             (match actual with Reserved_names.BuiltinFunction -> "builtin" | Reserved_names.RuntimeSymbol -> "symbol")
             (match expected with Reserved_names.BuiltinFunction -> "builtin" | Reserved_names.RuntimeSymbol -> "symbol"))
           kind_mismatches
    in
    let msg = "  ✗ reserved-node list diverged from Packages.init_env:\n" ^ String.concat "\n" lines ^ "\n" in
    failures := msg :: !failures;
    Printf.printf "%s" msg
  end
