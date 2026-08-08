(* src/pipeline/pipeline_validation.ml *)
(* Shared structural validation for pipelines.  Single source of truth used by:
   - builder_populate.ml  (build path — missing-file and serializer checks)
   - eval.ml              (cross-runtime deserializer check)
   - pipeline_validate / pipeline_assert  (package functions — report all errors)
   - t check tier 1 (Diagnostics.of_pipeline_validation)

   A [validation_error] carries a kind ("StructuralError" | "FileError" |
   "TypeError"), a message, and the offending node name (when applicable).  The
   kind maps onto [Diagnostics.error_class] via [error_class_of_string], so
   each product can render the error however it prefers.  Every check returns
   [] when the pipeline is healthy for that axis, so the functions compose
   with @ and stay deterministic (file order, then pipeline declaration order). *)

open Ast

type validation_error = {
  ve_kind : string;          (* "StructuralError" | "FileError" | "TypeError" *)
  ve_message : string;
  ve_node : string option;
}

let known_runtimes = [ "T"; "R"; "Python"; "Julia"; "Quarto"; "sh"; "fetchurl" ]

(** Pure local evaluation of serializer/function expressions.  Avoids a
    dependency on Eval (which in turn calls the pipeline validator), and is
    behaviourally equivalent for the Value/Literal forms these checks consume:
    symbols are treated as bare file names (matching how the build path handles
    [^myfunc] references), while unknown forms yield [VNA NAGeneric].
    NOTE: [Var] nodes (bound-variable references like [functions = some_var])
    cannot be resolved here without an eval environment.  The build path
    resolves them against the real env; `t check` tier 1 has this known
    limitation. *)
let rec expr_to_value (e : expr) : value =
  match e.node with
  | Value v -> v
  | Var _ -> VSymbol (Nix_unparse.expr_to_string e)
  | ListLit items -> VList (List.map (fun (n, e') -> (n, expr_to_value e')) items)
  | DictLit items -> VDict (List.map (fun (n, e') -> (n, expr_to_value e')) items)
  | _ -> VNA NAGeneric

(** Missing-file check: functions/includes/scripts referenced by the pipeline
    that do not exist on the file system.  One aggregated error, mirroring the
    build path's message. *)
let check_missing_files (p : pipeline_result) : validation_error list =
  let eval_string_list lst =
    lst
    |> List.map expr_to_value
    |> List.filter_map (function
         | VString s when s <> "" -> Some s
         | VSymbol s -> Some s
         | _ -> None)
  in
  let files =
    (List.concat_map snd p.p_functions @ List.concat_map snd p.p_includes)
    |> eval_string_list
    |> fun files -> files @ List.filter_map (fun (_, s) -> s) p.p_scripts
  in
  let missing = List.filter (fun f -> not (Sys.file_exists f)) files in
  match missing with
  | [] -> []
  | _ ->
      [{ ve_kind = "FileError";
         ve_message =
           Printf.sprintf "The following required files are missing from the file system: %s"
             (String.concat ", " missing);
         ve_node = None }]

(** Invalid-runtime check: every node runtime must be a known runtime. *)
let check_invalid_runtimes (p : pipeline_result) : validation_error list =
  List.filter_map (fun (name, runtime) ->
    if not (List.mem runtime known_runtimes) then
      Some { ve_kind = "TypeError";
             ve_message =
               Printf.sprintf "Node `%s` uses unknown runtime `%s`. Valid runtimes are: %s."
                 name runtime (String.concat ", " known_runtimes);
             ve_node = Some name }
    else None
  ) p.p_runtimes

(** Missing-dependency check: every entry in the resolved dep map must
    reference an actual node in the pipeline. *)
let check_missing_deps (p : pipeline_result) : validation_error list =
  let all_names = List.map fst p.p_exprs in
  List.concat_map (fun (name, deps) ->
    List.filter_map (fun dep ->
      if not (List.mem dep all_names) then
        Some { ve_kind = "StructuralError";
               ve_message =
                 Printf.sprintf "Node `%s` depends on `%s` which does not exist in the pipeline."
                   name dep;
               ve_node = Some name }
      else None
    ) deps
  ) p.p_deps

(** Cycle detection via DFS with three-color marking (white/gray/black).
    Returns the list of node names where a back-edge was detected (i.e. nodes
    that participate in a cycle and were re-entered during traversal).
    This is the canonical source of truth — both [pipeline_cycles] and the
    validation error path delegate to it. *)
let detect_cycles (p_deps : (string * string list) list) : string list =
  let all_names = List.map fst p_deps in
  let color = Hashtbl.create 16 in
  List.iter (fun n -> Hashtbl.add color n 0) all_names;
  let cycle_nodes = ref [] in
  let rec visit name =
    let c = match Hashtbl.find_opt color name with Some x -> x | None -> 0 in
    if c = 1 then begin
      if not (List.mem name !cycle_nodes) then
        cycle_nodes := name :: !cycle_nodes
    end else if c = 0 then begin
      Hashtbl.replace color name 1;
      let deps = match List.assoc_opt name p_deps with Some d -> d | None -> [] in
      List.iter visit deps;
      Hashtbl.replace color name 2
    end
  in
  List.iter visit all_names;
  !cycle_nodes

(** Cycle-detection check returning structured validation errors. *)
let check_cycles (p : pipeline_result) : validation_error list =
  match detect_cycles p.p_deps with
  | [] -> []
  | nodes ->
      [{ ve_kind = "StructuralError";
         ve_message =
           Printf.sprintf "Pipeline has dependency cycle(s) involving: %s."
             (String.concat ", " nodes);
         ve_node = None }]

(** Cross-runtime check: R/Python/Julia consumers of a dependency in a
    different runtime must declare an explicit deserializer.  Quarto, sh, and
    T consumers may consume any runtime's output. *)
let check_cross_runtime
    ~(deps : (string * string list) list)
    ~(runtimes : (string * string) list)
    ~(deserializers : (string * expr) list) : validation_error list =
  let has_default_deserializer name =
    match List.assoc_opt name deserializers with
    | Some e -> (match e.node with Var "default" -> true | _ -> false)
    | None -> true
  in
  List.filter_map (fun (name, my_deps) ->
    let my_runtime = match List.assoc_opt name runtimes with Some r -> r | None -> "T" in
    match List.find_opt (fun dname ->
      match List.assoc_opt dname runtimes with
      | Some dep_runtime ->
          dep_runtime <> my_runtime
          && my_runtime <> "Quarto"
          && my_runtime <> "sh"
          && my_runtime <> "T"
          && has_default_deserializer name
      | None -> false
    ) my_deps with
    | Some offender ->
        let offender_runtime =
          match List.assoc_opt offender runtimes with Some r -> r | None -> "Unknown"
        in
        Some { ve_kind = "StructuralError";
               ve_message =
                 Printf.sprintf "Node `%s` (%s) depends on `%s` (%s) but has no explicit deserializer."
                   name my_runtime offender offender_runtime;
               ve_node = Some name }
    | None -> None
  ) deps

(** Multiple dependencies with a single non-default deserializer strategy.
    `text` is exempt: it is the implicit default for shell/`capture = "stdout"`
    nodes, which read dependency artifacts as raw bytes and are format-agnostic. *)
let check_multi_dep_strategies (p : pipeline_result) : validation_error list =
  let is_dict_or_list = function
    | DictLit _ | ListLit _ | Value (VDict _) | Value (VList _) -> true
    | _ -> false
  in
  List.filter_map (fun (name, _) ->
    let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
    let des = match List.assoc_opt name p.p_deserializers with
      | Some e -> e | None -> mk_expr (Var "default")
    in
    if List.length deps >= 2 && not (is_dict_or_list des.node) then
      let strategy = Nix_unparse.expr_to_string des in
      if strategy <> "default" && strategy <> "text" then
        (match deps with
         | d1 :: d2 :: _ ->
             Some { ve_kind = "StructuralError";
                    ve_message =
                      Printf.sprintf
                        "Node `%s` has multiple dependencies but uses a single deserializer strategy (\"%s\").\nThis strategy is applied to ALL dependencies, which may cause parse errors if they use different formats (e.g. Arrow vs PMML).\nPlease use a dictionary to specify the deserializer for each dependency, e.g.:\n  deserializer = [ %s: \"...\", %s: \"...\" ]"
                        name strategy d1 d2;
                    ve_node = Some name }
         | _ -> None)
      else None
    else None
  ) p.p_exprs

(** Serializer/deserializer format coherence across dependency edges.
    `text` is treated as a format-agnostic wildcard on either side: it is the
    implicit default for shell/`capture = "stdout"` nodes, which emit and
    consume raw bytes (e.g. a shell node reading `$T_INPUT_<dep>`, or a node
    reading a shell node's raw stdout as `csv`). *)
let check_serializer_coherence (p : pipeline_result) : validation_error list =
  let get_ser name =
    match List.assoc_opt name p.p_serializers with
    | Some e -> expr_to_value e
    | None -> VNA NAGeneric
  in
  let get_des name =
    match List.assoc_opt name p.p_deserializers with
    | Some e -> expr_to_value e
    | None -> VNA NAGeneric
  in
  let extract_format = function
    | VSerializer s -> Some s.s_format
    | VString s | VSymbol s ->
        Some (let s = if String.starts_with ~prefix:"^" s then String.sub s 1 (String.length s - 1) else s in String.lowercase_ascii s)
    | VDict pairs ->
        (match List.assoc_opt "format" pairs with
         | Some (VString s) | Some (VSymbol s) -> Some (String.lowercase_ascii s)
         | Some (VSerializer s) -> Some s.s_format
         | _ -> None)
    | _ -> None
  in
  List.concat_map (fun (name, _) ->
    let deps = match List.assoc_opt name p.p_deps with Some d -> d | None -> [] in
    let node_des_val = get_des name in
    List.filter_map (fun dep_name ->
      let producer_ser_val = get_ser dep_name in
      let producer_fmt = extract_format producer_ser_val in
      let consumer_fmt =
        match node_des_val with
        | VDict pairs ->
            (match List.assoc_opt dep_name pairs with
             | Some v -> extract_format v
             | None -> extract_format node_des_val)
        | _ -> extract_format node_des_val
      in
      match producer_fmt, consumer_fmt with
      | Some pf, Some cf when pf <> cf && pf <> "default" && cf <> "default" && pf <> "text" && cf <> "text" ->
          Some { ve_kind = "StructuralError";
                 ve_message =
                   Printf.sprintf "Serializer coherence error: Node `%s` expects format `%s` for dependency `%s`, but `%s` produces format `%s`."
                     name cf dep_name dep_name pf;
                 ve_node = Some name }
      | _ -> None
    ) deps
  ) p.p_exprs

(** The ^bin serializer is only valid for fetchurl nodes. *)
let check_bin_only_for_fetchurl (p : pipeline_result) : validation_error list =
  let rec is_bin_format expr =
    match expr.node with
    | Value (VString s) -> String.lowercase_ascii s = "bin"
    | Value (VSymbol s) ->
        let s = String.lowercase_ascii (if String.starts_with ~prefix:"^" s then String.sub s 1 (String.length s - 1) else s) in
        s = "bin"
    | Value (VSerializer s) -> s.s_format = "bin"
    | ListLit items -> List.exists (fun (_, e) -> is_bin_format e) items
    | DictLit items -> List.exists (fun (_, e) -> is_bin_format e) items
    | _ -> false
  in
  List.filter_map (fun (name, _) ->
    let ser = match List.assoc_opt name p.p_serializers with
      | Some s -> s | None -> mk_expr (Var "default")
    in
    let runtime = match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T" in
    if is_bin_format ser && runtime <> "fetchurl" then
      Some { ve_kind = "StructuralError";
             ve_message =
               Printf.sprintf "The ^bin serializer is only supported for fetchurl nodes. Node `%s` uses runtime `%s`. Either set runtime = fetchurl or choose a different serializer."
                 name runtime;
             ve_node = Some name }
    else None
  ) p.p_exprs

(** Serializer-related errors (multi-dep strategies, coherence, ^bin). *)
let serializer_errors (p : pipeline_result) : validation_error list =
  check_multi_dep_strategies p
  @ check_serializer_coherence p
  @ check_bin_only_for_fetchurl p

(** All structural errors in deterministic order: missing files, invalid
    runtimes, missing deps, cycles, cross-runtime deserializer, then the
    serializer checks. *)
let collect_errors ?(serializer_checks = true) (p : pipeline_result) : validation_error list =
  check_missing_files p
  @ check_invalid_runtimes p
  @ check_missing_deps p
  @ check_cycles p
  @ check_cross_runtime ~deps:p.p_deps ~runtimes:p.p_runtimes
      ~deserializers:p.p_deserializers
  @ (if serializer_checks then serializer_errors p else [])

let first_error ?(serializer_checks = true) (p : pipeline_result) : validation_error option =
  match collect_errors ~serializer_checks p with
  | err :: _ -> Some err
  | [] -> None
