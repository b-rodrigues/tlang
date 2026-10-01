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

(** Reserved-name check: node names must not collide with builtin functions or
    runtime symbols.  Such a name can never be resolved as a cross-pipeline
    dependency at construction time (free-variable inference treats env-bound
    names as already known), so a colliding node is silently unreachable from
    other nodes' blocks.  The canonical list lives in reserved_names.ml and is
    audited against [Packages.init_env] by the test suite. *)
let check_reserved_node_names (p : pipeline_result) : validation_error list =
  List.filter_map (fun (name, _) ->
    if Reserved_names.is_reserved_node_name name then
      Some { ve_kind = "StructuralError";
             ve_message = Reserved_names.reserved_error_message name;
             ve_node = Some name }
    else None
  ) p.p_exprs

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
    | Value (VDict pairs) -> List.exists (fun (_, v) -> is_bin_value v) pairs
    | ListLit items -> List.exists (fun (_, e) -> is_bin_format e) items
    | DictLit items -> List.exists (fun (_, e) -> is_bin_format e) items
    | _ -> false
  and is_bin_value = function
    | VString s -> String.lowercase_ascii s = "bin"
    | VSymbol s ->
        let s = String.lowercase_ascii (if String.starts_with ~prefix:"^" s then String.sub s 1 (String.length s - 1) else s) in
        s = "bin"
    | VSerializer s -> s.s_format = "bin"
    | VDict pairs -> List.exists (fun (_, v) -> is_bin_value v) pairs
    | VList items -> List.exists (fun (_, v) -> is_bin_value v) items
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

(** Built-in serializer/deserializer formats. Mirrors
    [Serialization_registry.init_builtins] plus the [Builder_populate]
    strategy list: anything outside this set needs a strategy dict with
    inline snippets (see docs/serializers.md). Custom formats can never
    be bare names — there is no quoting escape. *)
let known_serializer_formats =
  [ "pmml"; "ipc"; "parquet"; "json"; "csv"; "default"; "onnx"; "bin"; "text"; "tlang";
    (* Legacy spellings that resolve today: "serialize" is the T-native
       default writer (see nix_emit_node ser_call fallback). *) "serialize" ]

(** Closed keys for a strategy dict. A dict in strategy position is a
    strategy by design (not by accident): exactly these keys, with
    `format` always present and snippet values as inline <{ ... }> code. *)
let strategy_dict_keys =
  [ "format"; "writer"; "reader";
    "r_writer"; "r_reader"; "py_writer"; "py_reader";
    "julia_writer"; "julia_reader" ]

let strategy_dict_help =
  "Define a strategy dict: [format: ^name, r_writer: <{ ... }>, r_reader: <{ ... }>, ...] (see docs/serializers.md)."

(** Unknown-format check: every serializer/deserializer strategy must be a
    known built-in format or a well-formed strategy dict (closed keys,
    `format` present, custom formats carrying an inline snippet for the
    node's runtime and role). Catches renames without aliases
    (notably `^arrow`, renamed to `^ipc` in 0.55.0) and typos at validation
    time instead of build time, where they die with
    `could not find function "<format>"`. *)
let check_known_formats (p : pipeline_result) : validation_error list =
  let runtime_of name =
    match List.assoc_opt name p.p_runtimes with Some r -> r | None -> "T"
  in
  let snippet_key_for runtime role =
    match runtime, role with
    | "R", "serializer" -> Some "r_writer"
    | "R", _ -> Some "r_reader"
    | "Python", "serializer" -> Some "py_writer"
    | "Python", _ -> Some "py_reader"
    | "Julia", "serializer" -> Some "julia_writer"
    | "Julia", _ -> Some "julia_reader"
    | _ -> None
  in
  let strip_hat s =
    if String.length s > 0 && s.[0] = '^' then String.sub s 1 (String.length s - 1) else s
  in
  (* A dict is a strategy dict by design when it carries any strategy
     key (`format` or a snippet key). Anything else is a dependency map
     ([dep: strategy]) and recurses per value. In particular a dict with
     snippet keys but no `format` is a malformed strategy, not a map. *)
  let is_strategy_dict pairs =
    List.exists (fun k -> List.mem k strategy_dict_keys) (List.map fst pairs)
  in
  let bare_message role s name =
    Printf.sprintf "Unknown %s `%s` on node `%s`: bare names are not strategies. Define a strategy dict [format: ^name, ...snippets] (see docs/serializers.md)." role s name
  in
  let text_error role runtime fmt name =
    if fmt = "text" && not (List.mem runtime ["T"; "sh"; "fetchurl"]) then
      [(Some "text", Printf.sprintf "Format `^text` on node `%s` (%s) is only supported for T and sh nodes (raw bytes). R, Python, and Julia nodes cannot use it." name role)]
    else []
  in
  let is_hat s = String.length s > 0 && s.[0] = '^' in
  (* Caret-prefixed unknowns used strategy syntax with an unknown format
     (typo or removed name): keep the "format" wording plus the hint.
     Truly bare names never were strategies: teach the dict form.
     `^text` is real but runtime-bound (raw bytes for T and sh only):
     reject it on runtimes whose tables carry no text reader/writer so it
     fails here with an ordinary error instead of an emitter
     `Invalid_argument`. *)
  let unknown_symbol role runtime s name =
    let fmt = String.lowercase_ascii (strip_hat s) in
    if List.mem fmt known_serializer_formats then
      if fmt = "text" && not (List.mem runtime ["T"; "sh"; "fetchurl"]) then
        [(Some fmt, Printf.sprintf "Format `^text` on node `%s` (%s) is only supported for T and sh nodes (raw bytes). R, Python, and Julia nodes cannot use it." name role)]
      else []
    else if is_hat s then
      [(Some fmt, Printf.sprintf "Unknown %s format `%s` on node `%s`." role s name)]
    else [(Some fmt, bare_message role s name)]
  in
  (* Closed-shape check shared by literal and evaluated strategy dicts.
     [fmt_of] classifies the `format` field and [code_of] any other field:
     [`Ok] carries the canonical value, [`Blind] marks indirection the
     checker cannot see through (Var/VError — skipped, surfaced
     elsewhere), [`Bad] marks malformed input. Returns complete messages
     (no format hint attached). *)
  let check_dict_shape ~role ~name ~runtime keys find fmt_of code_of =
    let errs = ref [] in
    let add m = errs := m :: !errs in
    List.iter (fun k ->
      if not (List.mem k strategy_dict_keys) then
        add (Printf.sprintf "Unknown key `%s` in %s strategy dict on node `%s`. Valid keys: %s."
          k role name (String.concat ", " strategy_dict_keys))
    ) keys;
    (match find "format" with
     | None ->
         add (Printf.sprintf "Strategy dict on node `%s` (%s) is missing the `format` key. %s"
           name role strategy_dict_help)
     | Some fv ->
         (match fmt_of fv with
          | `Ok fmt when List.mem fmt known_serializer_formats -> ()
          | `Ok fmt ->
              (match runtime with
               | "T" ->
                   add (Printf.sprintf "Custom format `^%s` on node `%s` (%s) needs R, Python, or Julia snippets, but node runtime is T. T nodes support built-in formats only."
                     fmt name role)
               | "R" | "Python" | "Julia" ->
                   (match snippet_key_for runtime role with
                    | Some key ->
                        (match find key with
                         | None ->
                             add (Printf.sprintf "Custom format `^%s` on node `%s` (%s) is missing `%s`. Provide it as an inline <{ ... }> block."
                               fmt name role key)
                         | Some _ -> ())
                    | None -> ())
               | "Quarto" -> ()
               | rt ->
                   add (Printf.sprintf "Custom format `^%s` on node `%s` (%s) is not supported for runtime `%s`. Use a built-in format."
                     fmt name role rt))
          | `Bad ->
              add (Printf.sprintf "Strategy dict `format` on node `%s` (%s) must be a ^-prefixed symbol (e.g. ^yaml). %s"
                name role strategy_dict_help)
          | `Blind -> ()));
    List.iter (fun k ->
      if k <> "format" then
        match find k with
        | Some sv -> (match code_of sv with
            | `Bad ->
                add (Printf.sprintf "Key `%s` in %s strategy dict on node `%s` must be an inline <{ ... }> code block."
                  k role name)
            | _ -> ())
        | None -> ()
    ) keys;
    !errs
  in
  let expr_fmt_of e =
    match e.node with
    | Value (VSymbol s) | Value (VString s) ->
        let f = String.lowercase_ascii (strip_hat s) in
        if f = "" then `Bad else `Ok f
    | Value (VSerializer s) -> `Ok s.s_format
    | Var _ -> `Blind
    | Value (VError _) -> `Blind
    | _ -> `Bad
  and expr_code_of e =
    match e.node with
    | RawCode _ -> `Ok
    | Var _ -> `Blind
    | Value (VError _) -> `Blind
    | _ -> `Bad
  and value_fmt_of v =
    match v with
    | VSymbol s | VString s ->
        let f = String.lowercase_ascii (strip_hat s) in
        if f = "" then `Bad else `Ok f
    | VSerializer s -> `Ok s.s_format
    | VError _ -> `Blind
    | _ -> `Bad
  and value_code_of = function
    | VRawCode _ -> `Ok
    | VError _ -> `Blind
    | _ -> `Bad
  in
  let dict_expr_errors ~role ~name pairs =
    List.map (fun m -> (None, m))
      (check_dict_shape ~role ~name ~runtime:(runtime_of name)
         (List.map fst pairs) (fun k -> List.assoc_opt k pairs)
         expr_fmt_of expr_code_of)
  in
  let dict_value_errors ~role ~name pairs =
    List.map (fun m -> (None, m))
      (check_dict_shape ~role ~name ~runtime:(runtime_of name)
         (List.map fst pairs) (fun k -> List.assoc_opt k pairs)
         value_fmt_of value_code_of)
  in
  let rec unknown_in role name expr =
    match expr.node with
    | Value (VSerializer s) ->
        if List.mem s.s_format known_serializer_formats then
          text_error role (runtime_of name) s.s_format name
        else [(Some s.s_format, Printf.sprintf "Unknown %s format `%s` on node `%s`." role s.s_format name)]
    | Value (VString s) | Value (VSymbol s) -> unknown_symbol role (runtime_of name) s name
    | Value (VDict pairs) ->
        if is_strategy_dict pairs then dict_value_errors ~role ~name pairs
        else List.concat_map (fun (_, v) -> unknown_value role name v) pairs
    | Value (VError _) -> []
    | Var v ->
        (* Closed strategies: a bare variable in strategy position can only
           be an indirection that validation cannot see through statically.
           Closed members (`default`, `^csv`, …) pass through for the
           default sentinels and literal-equivalent indirections;
           anything else fails naming the strategy-dict form — the same
           contract node() construction enforces after evaluation. *)
        unknown_symbol role (runtime_of name) v name
    | ListLit items -> List.concat_map (fun (_, e) -> unknown_in role name e) items
    | DictLit items ->
        if is_strategy_dict items then dict_expr_errors ~role ~name items
        else
          List.concat_map (fun (k, e) ->
            if k = "format" then [] else unknown_in role name e) items
    | _ -> []
  and unknown_value role name v =
    match v with
    | VSerializer s ->
        if List.mem s.s_format known_serializer_formats then
          text_error role (runtime_of name) s.s_format name
        else [(Some s.s_format, Printf.sprintf "Unknown %s format `%s` on node `%s`." role s.s_format name)]
    | VString s | VSymbol s -> unknown_symbol role (runtime_of name) s name
    | VDict pairs ->
        if is_strategy_dict pairs then dict_value_errors ~role ~name pairs
        else List.concat_map (fun (_, v) -> unknown_value role name v) pairs
    | VList items -> List.concat_map (fun (_, v) -> unknown_value role name v) items
    | VError _ -> []
    | _ -> []
  in
  let hint fmt =
    if fmt = "arrow" then " Did you mean ^ipc? (^arrow was renamed to ^ipc in 0.55.0 with no alias.)"
    else " Valid built-in formats: ^bin, ^csv, ^default, ^ipc, ^json, ^onnx, ^parquet, ^pmml, ^text, ^tlang."
  in
  List.concat_map (fun (name, _) ->
    let ser = match List.assoc_opt name p.p_serializers with
      | Some s -> s | None -> mk_expr (Var "default")
    in
    let des = match List.assoc_opt name p.p_deserializers with
      | Some e -> e | None -> mk_expr (Var "default")
    in
    List.map (fun (fmt_opt, m) ->
      let suffix = match fmt_opt with None -> "" | Some fmt -> hint fmt in
      { ve_kind = "TypeError";
        ve_message = m ^ suffix;
        ve_node = Some name })
      (unknown_in "serializer" name ser
       @ unknown_in "deserializer" name des)
  ) p.p_exprs

(** Quarto nodes render documents: strategies are undefined for them.
    Any explicit non-default serializer/deserializer is a TypeError
    instead of a silently ignored argument. Unset positions (absent or
    `default`) stay silent. *)
let check_quarto_strategies (p : pipeline_result) : validation_error list =
  let explicit_non_default = function
    | None -> false
    | Some e -> not (Ast.Utils.is_default_serializer_expr ~runtime:"Quarto" e)
  in
  List.filter_map (fun (name, _) ->
    match List.assoc_opt name p.p_runtimes with
    | Some "Quarto" ->
        let ser_set = explicit_non_default (List.assoc_opt name p.p_serializers) in
        let des_set = explicit_non_default (List.assoc_opt name p.p_deserializers) in
        (match ser_set, des_set with
         | false, false -> None
         | true, _ ->
             Some { ve_kind = "TypeError";
                    ve_message = Printf.sprintf "serializer for quarto undefined: node `%s` sets a serializer, but Quarto nodes render documents and take no serializer. Remove the `serializer` argument." name;
                    ve_node = Some name }
         | _, true ->
             Some { ve_kind = "TypeError";
                    ve_message = Printf.sprintf "deserializer for quarto undefined: node `%s` sets a deserializer, but Quarto nodes render documents and take no deserializer. Remove the `deserializer` argument." name;
                    ve_node = Some name })
    | _ -> None
  ) p.p_exprs

(** Serializer-related errors (multi-dep strategies, coherence, ^bin). *)
let serializer_errors (p : pipeline_result) : validation_error list =
  check_multi_dep_strategies p
  @ check_serializer_coherence p
  @ check_bin_only_for_fetchurl p
  @ check_known_formats p
  @ check_quarto_strategies p

(** All structural errors in deterministic order: missing files, invalid
    runtimes, missing deps, cycles, cross-runtime deserializer, then the
    serializer checks. *)
let collect_errors ?(serializer_checks = true) (p : pipeline_result) : validation_error list =
  check_reserved_node_names p
  @ check_missing_files p
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
