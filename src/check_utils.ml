(* src/check_utils.ml *)
(* Shared logic for running T files in check mode.
   Used by both the CLI (repl.ml) and REPL-callable functions (t_check, t_diff, t_fix). *)

open Ast

(* --- Source location helpers --- *)

let source_location ?file pos : source_location =
  {
    file;
    line = pos.Lexing.pos_lnum;
    column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1);
  }

let make_located_error ?file code message pos =
  VError {
    code;
    message;
    context = [];
    location = Some (source_location ?file pos);
    na_count = 0;
  }

let interrupt_error () =
  VError {
    code = RuntimeError;
    message = "Interrupted.";
    context = [];
    location = None;
    na_count = 0;
  }

(* --- Parsing and evaluation --- *)

(** Generate a helpful message for common parse errors.
    Currently detects: trailing comma in pipeline blocks. *)
let parse_error_message lexbuf =
  let lexeme = try Lexing.lexeme lexbuf with _ -> "" in
  if lexeme = "," then begin
    let buf = Bytes.to_string lexbuf.Lexing.lex_buffer in
    let offset = Lexing.lexeme_start lexbuf in
    let before = String.sub buf 0 offset in
    let rec find_pipeline i =
      if i < 0 then false
      else if i + 8 <= String.length before && String.sub before i 8 = "pipeline" then true
      else find_pipeline (i - 1)
    in
    if find_pipeline (offset - 1) then
      "Unexpected ',' in pipeline block. Pipeline nodes are separated by newlines or semicolons, not commas."
    else
      "Parse Error"
  end else
    "Parse Error"

let parse_and_eval ?filename ?(failfast=false) mode env input =
  let lexbuf = Lexing.from_string input in
  (match filename with
   | Some file -> lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = file }
   | None -> ());
  try
    let program = Parser.program Lexer.token lexbuf in
    match Typecheck.validate_program ~mode program with
    | Error err -> (VError err, env)
    | Ok () -> Eval.eval_program ~resilient:(not failfast) program env
  with
  | Lexer.SyntaxError msg ->
      let pos = Lexing.lexeme_start_p lexbuf in
      (make_located_error ?file:filename SyntaxError ("Syntax Error: " ^ msg) pos, env)
  | Parser.Error ->
      let pos = Lexing.lexeme_start_p lexbuf in
      (make_located_error ?file:filename SyntaxError (parse_error_message lexbuf) pos, env)
  | Mixed_bracket_form ->
      let pos = Lexing.lexeme_start_p lexbuf in
      (make_located_error ?file:filename SyntaxError "Mixed bracket literal (found both single elements and key-value pairs)" pos, env)
  | Invalid_match_pattern msg ->
      let pos = Lexing.lexeme_start_p lexbuf in
      (make_located_error ?file:filename SyntaxError msg pos, env)
  | Invalid_type_declaration msg ->
      let pos = Lexing.lexeme_start_p lexbuf in
      (make_located_error ?file:filename SyntaxError msg pos, env)
  | Sys.Break ->
      (interrupt_error (), env)

let run_file ?content ?failfast mode filename env =
  try
    let input =
      match content with
      | Some c -> c
      | None ->
          let ch = open_in filename in
          let c = really_input_string ch (in_channel_length ch) in
          close_in ch;
          c
    in
    parse_and_eval ~filename ?failfast mode env input
  with
  | Sys_error msg ->
      (VError {
         code = FileError;
         message = "File Error: " ^ msg;
         context = [];
         location = None;
         na_count = 0;
       }, env)

(* --- Check mode --- *)

let extra_diagnostics_hook : (string -> Diagnostics.diagnostic list) ref = ref (fun _ -> [])

(** Annotation diagnostics shared by the CLI check and the test suite.
    Walks top-level statements left to right, tracking declared annotation
    contracts: a fresh annotated `=` records its contract, a fresh
    unannotated `=` drops any earlier contract (new binding, own rules),
    and `:=` is checked against the standing contract. Only top-level
    statements participate, so nested scopes can never produce a false
    warning. `rm(...)` drops contracts for its literal and bare-word
    targets. Inferred types come from per-statement recordings taken
    during analysis in visit order, so each line is judged on the type it
    actually had — later reassignments cannot shift blame to the wrong
    line. *)
let annotation_diagnostics program stmt_types filename =
  let declared : (string, Ast.typ) Hashtbl.t = Hashtbl.create 16 in
  let diags = ref [] in
  (* Single constructor for both diagnostic shapes below: [kind] selects
     the message ("expression infers to" for the binding line,
     "reassignment infers to" for `:=` lines). *)
  let mk_diag ~kind name annotation inferred loc =
    let expected = Ast.Utils.typ_to_string annotation in
    let actual = Ast.Utils.typ_to_string inferred in
    let line = match loc with
      | Some l -> Some l.Ast.line
      | None -> None
    in
    let col = match loc with
      | Some l -> Some l.Ast.column
      | None -> None
    in
    { Diagnostics.diag_id = Diagnostics.gen_id ();
      Diagnostics.diag_error_class = Diagnostics.Type_error;
      Diagnostics.diag_severity = Warning;
      Diagnostics.diag_phase = Schema;
      Diagnostics.diag_node_id = None;
      Diagnostics.diag_node_lang = None;
      Diagnostics.diag_file = Some filename;
      Diagnostics.diag_line = line;
      Diagnostics.diag_column = col;
      Diagnostics.diag_end_line = None;
      Diagnostics.diag_end_column = None;
      Diagnostics.diag_message = Printf.sprintf
        "Variable `%s` annotated as %s, but %s infers to %s."
        name expected kind actual;
      Diagnostics.diag_expected = Some expected;
      Diagnostics.diag_actual = Some actual;
      Diagnostics.diag_caused_by = [];
      Diagnostics.diag_suggested_fix = Diagnostics.no_fix;
    }
  in
  (* Type this statement actually had: recorded during analysis in visit
     order, before later reassignments overwrite the scope. Falls back to
     `TUnknown` (silent: unknown matches every annotation) when absent. *)
  let stmt_ty i =
    match Hashtbl.find_opt stmt_types i with
    | Some st -> Semantic_type.to_ast_typ st
    | _ -> Ast.TUnknown
  in
  List.iteri (fun i (stmt : Ast.stmt) ->
    match stmt.node with
    | Ast.Assignment { name; typ = Some annotation; _ } ->
        let inferred_ast = stmt_ty i in
        if not (Ast.types_compatible inferred_ast annotation) then
          diags := mk_diag ~kind:"expression" name annotation inferred_ast stmt.loc :: !diags;
        Hashtbl.replace declared name annotation
    | Ast.Assignment { name; typ = None; _ } ->
        Hashtbl.remove declared name
    | Ast.Reassignment { name; _ } ->
        (match Hashtbl.find_opt declared name with
         | Some annotation ->
             let inferred_ast = stmt_ty i in
             if not (Ast.types_compatible inferred_ast annotation) then
               diags := mk_diag ~kind:"reassignment" name annotation inferred_ast stmt.loc :: !diags
         | None -> ())
    | Expression e ->
        (match e.node with
         | Call { fn = { node = Var "rm"; _ }; args; _ } ->
             List.iter (fun (_, a) ->
               match a.node with
               | Value (VString s) | Var s -> Hashtbl.remove declared s
               | _ -> ()
             ) args
         | _ -> ())
    | _ -> ()
  ) program;
  List.rev !diags

(** Match exhaustiveness diagnostics (family level, no new syntax).
    Warns only when the scrutinee is syntactically known to be an Error
    or NA value and the arms lack the matching family pattern plus any
    catch-all. Unknown scrutinees (variables, calls other than [error],
    literals of other types) stay silent, so no previously clean program
    gains a warning. Per-code or per-variant exhaustiveness needs pattern
    syntax that names codes, which does not exist yet (see item 2). *)
type scrutinee_family = ErrorFamily | NAFamily | UnknownFamily

type match_site = {
  ms_scrutinee : Ast.expr;
  ms_cases : (Ast.match_pattern * Ast.expr) list;
  ms_loc : Ast.source_location option;
}

let family_of_scrutinee (e : Ast.expr) : scrutinee_family =
  match e.Ast.node with
  | Ast.Value v ->
      (match v with
       | Ast.VNA _ -> NAFamily
       | Ast.VError _ -> ErrorFamily
       (* Wildcard covers all other value forms (scalars, lists, frames):
          none of them is an Error or NA value by construction. *)
       | _ -> UnknownFamily)
  | Ast.Call { fn = { Ast.node = Ast.Var "error"; _ }; _ } -> ErrorFamily
  (* Wildcard covers every other expression shape (variables, general
     calls, operators, blocks): the family is genuinely unknown there. *)
  | _ -> UnknownFamily

let match_has_catchall cases =
  List.exists (fun (p, _) ->
    match p with
    | Ast.PWildcard | Ast.PVar _ -> true
    | Ast.PNA | Ast.PList _ | Ast.PError _ | Ast.PUnion _ -> false
  ) cases

let match_has_error_arm cases =
  List.exists (fun (p, _) ->
    match p with
    | Ast.PError _ -> true
    | Ast.PWildcard | Ast.PVar _ | Ast.PNA | Ast.PList _ | Ast.PUnion _ -> false
  ) cases

let match_has_na_arm cases =
  List.exists (fun (p, _) ->
    match p with
    | Ast.PNA -> true
    | Ast.PWildcard | Ast.PVar _ | Ast.PList _ | Ast.PError _ | Ast.PUnion _ -> false
  ) cases

let rec sites_in_expr (e : Ast.expr) : match_site list =
  let self =
    match e.Ast.node with
    | Ast.Match { scrutinee; cases } ->
        [{ ms_scrutinee = scrutinee; ms_cases = cases; ms_loc = e.Ast.loc }]
    (* Wildcard covers non-Match nodes: they contribute no site themselves,
       only their children below (see Ast.children_of_expr) do. *)
    | _ -> []
  in
  self @ List.concat_map sites_in_expr (Ast.children_of_expr e)

and sites_in_stmt (s : Ast.stmt) : match_site list =
  List.concat_map sites_in_expr (Ast.children_of_stmt s)

let mk_match_diag message loc filename =
  let line = match loc with
    | Some (l : Ast.source_location) -> Some l.Ast.line
    | None -> None
  in
  let col = match loc with
    | Some (l : Ast.source_location) -> Some l.Ast.column
    | None -> None
  in
  { Diagnostics.diag_id = Diagnostics.gen_id ();
    Diagnostics.diag_error_class = Match_error;
    Diagnostics.diag_severity = Warning;
    Diagnostics.diag_phase = Schema;
    Diagnostics.diag_node_id = None;
    Diagnostics.diag_node_lang = None;
    Diagnostics.diag_file = Some filename;
    Diagnostics.diag_line = line;
    Diagnostics.diag_column = col;
    Diagnostics.diag_end_line = None;
    Diagnostics.diag_end_column = None;
    Diagnostics.diag_message = message;
    Diagnostics.diag_expected = None;
    Diagnostics.diag_actual = None;
    Diagnostics.diag_caused_by = [];
    Diagnostics.diag_suggested_fix = Diagnostics.no_fix;
  }

let match_exhaustiveness_diagnostics program filename =
  let mk_diag ~missing ~hint loc =
    mk_match_diag
      (Printf.sprintf "Match on %s value lacks %s arm and has no catch-all. Add %s."
         missing missing hint)
      loc filename
  in
  (* Local accumulation across the site walk; a ref keeps the traversal
     iterative like annotation_diagnostics above. *)
  let diags = ref [] in
  let sites = List.concat_map sites_in_stmt program in
  List.iter (fun site ->
    if match_has_catchall site.ms_cases then ()
    else
      match family_of_scrutinee site.ms_scrutinee with
      | UnknownFamily -> ()
      | ErrorFamily ->
          if match_has_error_arm site.ms_cases then ()
          else diags := mk_diag ~missing:"an Error"
            ~hint:"Error { msg } => ... or _ => ..." site.ms_loc :: !diags
      | NAFamily ->
          if match_has_na_arm site.ms_cases then ()
          else diags := mk_diag ~missing:"an NA"
            ~hint:"NA => ... or _ => ..." site.ms_loc :: !diags
  ) sites;
  List.rev !diags

(** Union case diagnostics (per-case level, warn-only).
    Two passes over the parsed program: first collect union definitions
    (`type` declarations), then check every `match` whose scrutinee is a
    direct constructor call (`Circle(...)`) of a known union, or a variable
    bound unambiguously to one (`s = Circle(...)` exactly once program-wide,
    never reassigned, never a lambda parameter). Anything else stays
    silent, so no previously clean program gains a warning.
    Three warnings, all on the `match` line:
    - missing cases with no catch-all (names every missing case);
    - arms naming unknown cases (likely typos; names the valid set);
    - bare variable arms named exactly like a case of the scrutinee's
      union (they bind everything; suggests `Case()` instead). *)
let match_union_diagnostics program filename =
  let unions =
    List.filter_map (fun (s : Ast.stmt) ->
      match s.Ast.node with
      | Ast.TypeDecl { tname; tdef = Ast.UnionDef { ud_cases } } ->
          Some (tname, List.map fst ud_cases)
      | _ -> None
    ) program
  in
  if unions = [] then [] else
  (* Names bound anywhere in the program: every assignment target, every
     reassignment target, every lambda parameter. A variable scrutinee
     resolves to a union only when bound exactly once (to a direct
     union-case call) with no other binding — blocks share scope and only
     lambdas shadow, so any second binding makes resolution unsafe. *)
  let assigned = ref [] and reassigned = ref [] and params = ref [] in
  let rec uses_in_expr e =
    (match e.Ast.node with
     | Ast.Lambda l -> params := l.Ast.params @ !params
     | _ -> ());
    List.iter uses_in_expr (Ast.children_of_expr e)
  and uses_in_stmt s =
    (match s.Ast.node with
     | Ast.Assignment { name; expr = e; _ } ->
         assigned := name :: !assigned; uses_in_expr e
     | Ast.Reassignment { name; expr = e; _ } ->
         reassigned := name :: !reassigned; uses_in_expr e
     | _ -> List.iter uses_in_expr (Ast.children_of_stmt s))
  in
  let () = List.iter uses_in_stmt program in
  (* Every binder name anywhere in the program, including nested
     statements (blocks, branches), lambda parameters, and match arm
     patterns: a variable scrutinee resolves only when its single
     top-level binding is the only binding of that name program-wide.
     A rebinding hidden in a branch (`if (c) { s := ... }`) or a
     shadowing arm pattern would otherwise resolve to the wrong union
     and warn falsely. Silence is always safe here. *)
  (* Every name a match pattern binds: bare variables, list tails,
     error payloads, and union case payloads at any depth. *)
  let rec pattern_binders p =
    match p with
    | Ast.PVar s -> [s]
    | Ast.PList (ps, rest) ->
        List.concat_map pattern_binders ps
        @ (match rest with Some s -> [s] | None -> [])
    | Ast.PError (Some s) -> [s]
    | Ast.PUnion { pu_args; _ } -> List.concat_map pattern_binders pu_args
    | Ast.PWildcard | Ast.PNA | Ast.PError None -> []
  in
  let rec deep_binders_stmt acc s =
    match s.Ast.node with
    | Ast.Expression e -> deep_binders_expr acc e
    | Ast.Assignment { name; expr = e; _ } -> deep_binders_expr (name :: acc) e
    | Ast.Reassignment { name; expr = e; _ } -> deep_binders_expr (name :: acc) e
    | _ -> acc
  and deep_binders_expr acc e =
    match e.Ast.node with
    | Ast.Lambda l ->
        deep_binders_expr (l.Ast.params @ acc) l.Ast.body
    | Ast.Block stmts ->
        (* Blocks share scope: nested binders count. (`children_of_expr`
           would drop the names and keep only right-hand sides.) *)
        List.fold_left deep_binders_stmt acc stmts
    | Ast.Match { scrutinee; cases } ->
        (* Arm patterns bind names too (`children_of_expr` keeps only
           the scrutinee and arm bodies): a pattern variable shadowing
           a top-level union variable vetoes the variable resolution. *)
        let acc = deep_binders_expr acc scrutinee in
        List.fold_left (fun acc (p, body) ->
          deep_binders_expr (pattern_binders p @ acc) body
        ) acc cases
    | _ ->
        List.fold_left deep_binders_expr acc (Ast.children_of_expr e)
  in
  let all_binders = List.fold_left deep_binders_stmt [] program in
  let assigned_once name =
    List.length (List.filter (( = ) name) !assigned) = 1
    && not (List.mem name !reassigned)
    && not (List.mem name !params)
    && List.length (List.filter (( = ) name) all_binders) = 1
  in
  let union_var_map =
    List.filter_map (fun (s : Ast.stmt) ->
      match s.Ast.node with
      | Ast.Assignment { name; expr = e; _ } ->
          (match e.Ast.node with
           | Ast.Call { fn = { Ast.node = Ast.Var fname; _ }; _ } ->
               (match List.find_opt (fun (_, cases) -> List.mem fname cases) unions with
                | Some u when assigned_once name -> Some (name, u)
                | _ -> None)
           | _ -> None)
      | _ -> None
    ) program
  in
  (* Local accumulation across the site walk, as above. *)
  let diags = ref [] in
  let sites = List.concat_map sites_in_stmt program in
  let scrutinee_union e =
    match e.Ast.node with
    | Ast.Call { fn = { Ast.node = Ast.Var fname; _ }; _ } ->
        List.find_opt (fun (_, cases) -> List.mem fname cases) unions
    | Ast.Var name ->
        List.assoc_opt name union_var_map
    | _ -> None
  in
  List.iter (fun site ->
    match scrutinee_union site.ms_scrutinee with
    | None -> ()
    | Some (tname, cases) ->
        let quote c = "`" ^ c ^ "`" in
        List.iter (fun (p, _) ->
          match p with
          | Ast.PUnion { pu_case; _ } when not (List.mem pu_case cases) ->
              diags := mk_match_diag
                (Printf.sprintf "Match on `%s` value tests unknown case %s. Valid cases: %s."
                   tname (quote pu_case) (String.concat ", " (List.map quote cases)))
                site.ms_loc filename :: !diags
          | Ast.PVar name when List.mem name cases ->
              diags := mk_match_diag
                (Printf.sprintf "Match arm `%s` binds every value; did you mean `%s()` to test the `%s` case?"
                   name name tname)
                site.ms_loc filename :: !diags
          | Ast.PWildcard | Ast.PVar _ | Ast.PNA | Ast.PList _ | Ast.PError _ | Ast.PUnion _ -> ()
        ) site.ms_cases;
        if not (match_has_catchall site.ms_cases) then begin
          let covered =
            List.filter_map (fun (p, _) ->
              match p with Ast.PUnion { pu_case; _ } -> Some pu_case | _ -> None
            ) site.ms_cases
          in
          let missing = List.filter (fun c -> not (List.mem c covered)) cases in
          (match missing with
           | [] -> ()
           | first :: _ ->
               diags := mk_match_diag
                 (Printf.sprintf "Match on `%s` value misses case(s) %s and has no catch-all. Add `%s()` => ... or _ => ...."
                    tname (String.concat ", " (List.map quote missing)) first)
                 site.ms_loc filename :: !diags)
        end
  ) sites;
  List.rev !diags

(** Generic body check (warn-only, flexible for future strictness).
    Warns when a generic lambda declares a type-variable return
    (`\(T)(x: T -> T)`) but its body cannot be that variable: the body
    infers to a concrete type and never mentions its parameters
    (e.g. `\(T)(x: T -> T) "oops"`). One nesting level is covered
    (`List[T]`/`Dict[String, T]` returns against fixed literals, see
    `syntactic_shape` below). Bodies that mention any parameter stay
    silent (they may be generic); unknown bodies stay silent (no
    false positives). Deeper shapes are skipped entirely. Severity is
    Warning today; set [generic_body_strict] for Error when a future
    strict mode needs it. *)
let generic_body_strict = ref false

type generic_site = {
  gs_params : string list;
  gs_return_var : string;
  gs_return_typ : Ast.typ;
  gs_body : Ast.expr;
  gs_loc : Ast.source_location option;
}

let rec generic_lambdas_in_expr (e : Ast.expr) : generic_site list =
  let self =
    match e.Ast.node with
    | Ast.Lambda l ->
        (match l.Ast.generic_params, l.Ast.return_type with
         | _ :: _, Some ret ->
             let var_of = function
               | Ast.TVar r -> Some r
               | Ast.TList (Some (Ast.TVar r)) -> Some r
               | Ast.TDict (_, Some (Ast.TVar r)) -> Some r
               | _ -> None
             in
             (match var_of ret with
              | Some r ->
                  [{ gs_params = l.Ast.params; gs_return_var = r;
                     gs_return_typ = ret;
                     gs_body = l.Ast.body; gs_loc = e.Ast.loc }]
              | None -> [])
         | _ -> [])
    | _ -> []
  in
  self @ List.concat_map generic_lambdas_in_expr (Ast.children_of_expr e)

and generic_lambdas_in_stmt (s : Ast.stmt) : generic_site list =
  List.concat_map generic_lambdas_in_expr (Ast.children_of_stmt s)

let rec expr_mentions_any (params : string list) (e : Ast.expr) : bool =
  match e.Ast.node with
  | Ast.Var name -> List.mem name params
  (* Inner bindings shadow outer params; a textual mention still
     counts as use (silent direction), so no false warning. *)
  | _ -> List.exists (expr_mentions_any params) (Ast.children_of_expr e)

and generic_stmt_mentions_any params (s : Ast.stmt) : bool =
  List.exists (expr_mentions_any params) (Ast.children_of_stmt s)

let generic_body_diagnostics program filename =
  (* Syntactic body type only (no Analyzer: Check_utils stays leaf so the
     library keeps its Analyzer -> Packages -> Check_utils order with no
     cycle). Certain-only: direct scalar literals warn; everything else
     stays silent for future passes. *)
  let rec syntactic_body_type (e : Ast.expr) : Semantic_type.t option =
    match e.Ast.node with
    | Ast.Value v ->
        (match v with
         | Ast.VInt _ -> Some Semantic_type.TInt
         | Ast.VFloat _ -> Some Semantic_type.TFloat
         | Ast.VBool _ -> Some Semantic_type.TBool
         | Ast.VString _ -> Some Semantic_type.TString
         | _ -> None)
    | Ast.Block stmts ->
        (match stmts with
         | [{ Ast.node = Ast.Expression inner; _ }] -> syntactic_body_type inner
         | _ -> None)
    | _ -> None
  in
  let diags = ref [] in
  let sites =
    List.concat_map generic_lambdas_in_stmt program
  in
  (* One-level container shapes over scalar literals: `[1, 2]` is
     `List[Int]`, `[a: 1]` is `Dict[String, Int]`. Anything deeper or
     non-literal is opaque (silent); a future pass can go deeper. *)
  let rec syntactic_shape (e : Ast.expr) : Ast.typ option =
    let scalar = function
      | Ast.VInt _ -> Some Ast.TInt
      | Ast.VFloat _ -> Some Ast.TFloat
      | Ast.VBool _ -> Some Ast.TBool
      | Ast.VString _ -> Some Ast.TString
      | _ -> None
    in
    let fold_elems ts =
      match List.sort_uniq compare ts with
      | [] -> None
      | [t] -> Some t
      | ts -> Some (Ast.TUnion ts)
    in
    match e.Ast.node with
    | Ast.Value v -> scalar v
    | Ast.ListLit items ->
        let elems = List.map (fun (_, x) ->
          match x.Ast.node with Ast.Value v -> scalar v | _ -> None) items in
        if List.exists Option.is_none elems then None
        else Some (Ast.TList (fold_elems (List.filter_map Fun.id elems)))
    | Ast.DictLit pairs ->
        let vals = List.map (fun (_, x) ->
          match x.Ast.node with Ast.Value v -> scalar v | _ -> None) pairs in
        if List.exists Option.is_none vals then None
        else Some (Ast.TDict (Some Ast.TString, fold_elems (List.filter_map Fun.id vals)))
    | Ast.Block stmts ->
        (match stmts with
         | [{ Ast.node = Ast.Expression inner; _ }] -> syntactic_shape inner
         | _ -> None)
    | _ -> None
  in
  let warn_site site expected actual =
    let sev = if !generic_body_strict then Diagnostics.Error else Diagnostics.Warning in
    let line = match site.gs_loc with
      | Some (l : Ast.source_location) -> Some l.Ast.line
      | None -> None
    in
    let col = match site.gs_loc with
      | Some (l : Ast.source_location) -> Some l.Ast.column
      | None -> None
    in
    diags := { Diagnostics.diag_id = Diagnostics.gen_id ();
      Diagnostics.diag_error_class = Diagnostics.Type_error;
      Diagnostics.diag_severity = sev;
      Diagnostics.diag_phase = Diagnostics.Schema;
      Diagnostics.diag_node_id = None;
      Diagnostics.diag_node_lang = None;
      Diagnostics.diag_file = Some filename;
      Diagnostics.diag_line = line;
      Diagnostics.diag_column = col;
      Diagnostics.diag_end_line = None;
      Diagnostics.diag_end_column = None;
      Diagnostics.diag_message = Printf.sprintf
        "Generic function declares return `%s` but its body infers to `%s` without using its parameters."
        expected actual;
      Diagnostics.diag_expected = Some expected;
      Diagnostics.diag_actual = Some actual;
      Diagnostics.diag_caused_by = [];
      Diagnostics.diag_suggested_fix = Diagnostics.no_fix;
    } :: !diags
  in
  List.iter (fun site ->
    if expr_mentions_any site.gs_params site.gs_body then ()
    else
      match site.gs_return_typ with
      | Ast.TVar _ ->
          (match syntactic_body_type site.gs_body with
           | None -> ()
           | Some concrete ->
               warn_site site site.gs_return_var (Semantic_type.to_string concrete))
      | Ast.TList (Some (Ast.TVar _)) | Ast.TDict (_, Some (Ast.TVar _)) ->
          (match syntactic_shape site.gs_body with
           | None -> ()
           | Some shape ->
               warn_site site
                 (Ast.Utils.typ_to_string site.gs_return_typ)
                 (Ast.Utils.typ_to_string shape))
      | _ -> ()
  ) sites;
  List.rev !diags

(** Registry shape for builtin call checks: runtime arity plus the
    documented parameter list (name and declared type string, when
    present). Built by [builtin_sigs_of_env] below, so the CLI hook and
    tests share one construction and cannot drift. This module stays a
    leaf: callers pass the environment in (`Analyzer -> Packages ->
    Check_utils` must not cycle). *)
type builtin_sig = {
  bs_arity : int;
  bs_variadic : bool;
  bs_params : (string * string option) list;
}

(** Derive call-check signatures for every builtin in an environment.
    Runtime arity comes from the builtin value; parameter names and
    declared types come from the documentation registry (empty when
    undocumented, which stays silent downstream). *)
let builtin_sigs_of_env env =
  let acc = ref [] in
  Ast.Env.iter (fun name v ->
    match v with
    | Ast.VBuiltin { Ast.b_name = Some n; Ast.b_arity; Ast.b_variadic; _ } when n = name ->
        let params =
          match Tdoc_registry.lookup n with
          | Some e ->
              List.map (fun (p : Tdoc_types.param_doc) ->
                (p.Tdoc_types.name, p.Tdoc_types.type_info)
              ) e.Tdoc_types.params
          | None -> []
        in
        acc := (n, { bs_arity = b_arity;
                     bs_variadic = b_variadic;
                     bs_params = params }) :: !acc
    | _ -> ()) env;
  !acc

(** Every name with a local binding program-wide: assignments,
    reassignments, lambda parameters, match pattern binders, and import
    aliases (`import m [nick = name]`, `import "f.t" [nick = name]`).
    Calling such a name may hit the local, not the builtin, so call
    checks stay silent for it. Shared by the arity and argument-type
    checks below. A bare `import package` is deliberately excluded: it
    re-exposes the same builtins, so builtin signatures still apply.
    Selective package imports without an alias (`import m [name]`) are
    likewise excluded — they bind the package member under its own
    name, and for the standard packages that is the builtin itself.
    Only an alias can introduce a genuinely new local binding there.
    File imports always bind (user code may shadow anything). *)
let locally_bound_names program =
  let bound = Hashtbl.create 32 in
  let bind name = Hashtbl.replace bound name true in
  let bind_import_spec bind_plain (import_item : import_spec) =
    match import_item.import_alias with
    | Some nick -> bind nick
    | None -> if bind_plain then bind import_item.import_name else ()
  in
  let rec bind_pattern = function
    | PVar s -> bind s
    | PList (ps, rest) ->
        List.iter bind_pattern ps;
        (match rest with Some s -> bind s | None -> ())
    | PError (Some s) -> bind s
    | PUnion { pu_args; _ } -> List.iter bind_pattern pu_args
    | PWildcard | PNA | PError None -> ()
  in
  let rec collect_expr e =
    (match e.node with
     | Lambda l -> List.iter bind l.params
     | Match { cases; _ } -> List.iter (fun (p, _) -> bind_pattern p) cases
     | _ -> ());
    List.iter collect_expr (children_of_expr e)
  and collect_stmt s =
    (match s.node with
     | Assignment { name; _ } | Reassignment { name; _ } -> bind name
     | ImportFrom { names; _ } ->
         List.iter (bind_import_spec false) names
     | ImportFileFrom { names; _ } ->
         List.iter (bind_import_spec true) names
     | _ -> ());
    List.iter collect_expr (children_of_stmt s)
  in
  List.iter collect_stmt program;
  bound

(** Call sites with pipe context: a call directly right of `|>`/`?|>`
    sees the piped value as an implicit first argument, so the site
    keeps the left-hand expression. A bare `x |> f` is a site with no
    written arguments. Shared by the arity and argument-type checks. *)
let collect_call_sites program =
  let sites = ref [] in
  let rec walk_expr piped_left e =
    match e.node with
    | Call { fn = { node = Var name; _ }; args; _ } ->
        List.iter (fun (_, a) -> walk_expr None a) args;
        sites := (name, args, piped_left, e.loc) :: !sites
    | Call { fn; args; _ } ->
        walk_expr None fn;
        List.iter (fun (_, a) -> walk_expr None a) args
    | BinOp { op = (Pipe | MaybePipe); left; right; _ } ->
        walk_expr None left;
        (match right.node with
         | Call _ -> walk_expr (Some left) right
         | Var name ->
             sites := (name, [], Some left, right.loc) :: !sites
         | _ -> walk_expr None right)
    | _ ->
        List.iter (walk_expr None) (children_of_expr e)
  in
  List.iter (fun s -> List.iter (walk_expr None) (children_of_stmt s)) program;
  List.rev !sites

(** Shared constructor for call-check diagnostics (all Warning,
    Schema phase). *)
let mk_call_diag ~error_class ~message ~expected ~actual loc filename =
  let line = match loc with
    | Some (l : source_location) -> Some l.line
    | None -> None
  in
  let col = match loc with
    | Some (l : source_location) -> Some l.column
    | None -> None
  in
  { Diagnostics.diag_id = Diagnostics.gen_id ();
    Diagnostics.diag_error_class = error_class;
    Diagnostics.diag_severity = Diagnostics.Warning;
    Diagnostics.diag_phase = Diagnostics.Schema;
    Diagnostics.diag_node_id = None;
    Diagnostics.diag_node_lang = None;
    Diagnostics.diag_file = Some filename;
    Diagnostics.diag_line = line;
    Diagnostics.diag_column = col;
    Diagnostics.diag_end_line = None;
    Diagnostics.diag_end_column = None;
    Diagnostics.diag_message = message;
    Diagnostics.diag_expected = Some expected;
    Diagnostics.diag_actual = Some actual;
    Diagnostics.diag_caused_by = [];
    Diagnostics.diag_suggested_fix = Diagnostics.no_fix;
  }

(** Call arity diagnostics (warn-only).
    Mirrors the runtime arity rule in `Eval.eval_call` exactly: a
    non-variadic builtin takes exactly `b_arity` arguments, counting
    positional and named args together (a piped value counts one).
    Everything else stays silent: variadic builtins, unknown names,
    and names bound anywhere in the program (a local binding shadows
    the builtin). This catches mistakes the evaluator never reaches —
    calls inside lambdas, node blocks, and match arms — at check time.
    Severity is Warning. The builtin table is a parameter so this
    module stays a leaf (`Analyzer -> Packages -> Check_utils` must
    not cycle). *)
let call_arity_diagnostics ~builtins program filename =
  let bound = locally_bound_names program in
  let diags = ref [] in
  List.iter (fun (name, args, piped_left, loc) ->
    let received = List.length args + (match piped_left with Some _ -> 1 | None -> 0) in
    if Hashtbl.mem bound name then ()
    else match List.assoc_opt name builtins with
    | Some entry when not entry.bs_variadic && received <> entry.bs_arity ->
        diags := mk_call_diag
          ~error_class:Diagnostics.Arity_error
          ~message:(Printf.sprintf
            "Function `%s` expects %d argument(s) but received %d. The call fails at runtime."
            name entry.bs_arity received)
          ~expected:(string_of_int entry.bs_arity)
          ~actual:(string_of_int received)
          loc filename :: !diags
    | _ -> ()
  ) (collect_call_sites program);
  List.rev !diags

(** Call argument-type diagnostics (warn-only).
    Compares each argument's inferred type against the documented
    parameter type and warns on definite mismatches only. Positionals
    map to documented parameters in order (a piped value is the first
    positional); named arguments map by parameter name. A position
    stays silent whenever doubt exists: no documented type, `Any` or
    `Unknown` anywhere on either side, a parameter from the
    argument-shape vocabulary with no value inhabitants (`Column`,
    `Selection`, `KeywordArgs`, `Expressions`, `Strategy`), an
    undocumented extra position, or an unknown named argument. Sites
    whose count already fails the arity rule are skipped (the arity
    warning covers them). Severity is Warning. Inference arrives as a
    parameter so this module stays a leaf (see the arity check). *)
let call_type_diagnostics ~sigs ~infer program filename =
  let rec has_unknown = function
    | Semantic_type.TUnknown -> true
    | Semantic_type.TList u | Semantic_type.TVector u -> has_unknown u
    | Semantic_type.TDict (k, v) -> has_unknown k || has_unknown v
    | Semantic_type.TUnion ts -> List.exists has_unknown ts
    | Semantic_type.TFunction (args, ret) ->
        List.exists (fun (_, u) -> has_unknown u) args || has_unknown ret
    | _ -> false
  in
  (* Argument-shape words name call positions, not values: no runtime
     value ever infers to them, so any concrete comparison would warn
     falsely. `Strategy` owns custom formats with pipeline context. *)
  let shape_word = function
    | "Column" | "Selection" | "KeywordArgs" | "Expressions" | "Strategy" -> true
    | _ -> false
  in
  let bound = locally_bound_names program in
  (* NSE verbs wrap `$col`-mentioning expressions in row lambdas before
     evaluation, so an inferred per-row type (e.g. `Bool` for `$mpg > 20`
     in `filter`) never meets the documented parameter type. Any
     argument mentioning a column reference stays silent. *)
  let rec uses_columnref e =
    (match e.node with ColumnRef _ -> true | _ -> false)
    || List.exists uses_columnref (children_of_expr e)
  in
  let diags = ref [] in
  List.iter (fun (name, args, piped_left, loc) ->
    if Hashtbl.mem bound name then ()
    else match List.assoc_opt name sigs with
    | None -> ()
    | Some entry ->
        let received = List.length args + (match piped_left with Some _ -> 1 | None -> 0) in
        if not entry.bs_variadic && received <> entry.bs_arity then ()
        else begin
          let params = List.filter (fun (n, _) -> n <> "...") entry.bs_params in
          let positionals =
            (match piped_left with Some l -> [(None, l)] | None -> [])
            @ List.filter (fun (n, _) -> n = None) args
          in
          let named = List.filter_map (fun (n, e) ->
            match n with Some s -> Some (s, e) | None -> None) args in
          (* Positionals fill the parameters not already claimed by
             name, in order. Runtime arg matching differs per builtin
             (plain builtins bind values in written order with names
             stripped; named-aware ones like `ifelse` match positionals
             in order and named arguments by name, erroring on
             double-binds), so mapping a positional onto a name-claimed
             parameter can only warn falsely — e.g. `f(a = 1, "x")`
             binds `a = 1` either way. Claimed slots are therefore
             removed before assigning positionals; named arguments
             always check against their named parameter. Note this is
             more lenient than runtime for plain builtins (where
             `f(opt = "x", 1)` would misbind `"x"` to the first
             parameter): that only ever misses warnings, never adds
             false ones. *)
          let claimed = List.map fst named in
          let params_open =
            List.filter (fun (n, _) -> not (List.mem n claimed)) params
          in
          let check_one pname ptype_opt arg =
            match ptype_opt with
            | None -> ()
            | Some s ->
                let param = Semantic_type.from_string s in
                if param = Semantic_type.TAny || has_unknown param then ()
                else
                  let expected = Semantic_type.to_ast_typ param in
                  let skip_expected = match expected with
                    | TCustom w -> shape_word w
                    | _ -> false
                  in
                  (* The expected text quotes the documented signature
                     verbatim (`List[Float] | Vector[Float]`), since the
                     AST rendering collapses `Vector` into `List`. *)
                  if skip_expected || uses_columnref arg then ()
                  else begin
                    let actual =
                      try Semantic_type.to_ast_typ (infer arg)
                      with _ -> TUnknown
                    in
                    if not (types_compatible actual expected) then
                      diags := mk_call_diag
                        ~error_class:Diagnostics.Type_error
                        ~message:(Printf.sprintf
                          "Function `%s` expects argument `%s` to be %s, but it infers to %s."
                          name pname s (Utils.typ_to_string actual))
                        ~expected:s
                        ~actual:(Utils.typ_to_string actual)
                        loc filename :: !diags
                  end
          in
          List.iteri (fun i (_, e) ->
            match List.nth_opt params_open i with
            | Some (pname, ptype) -> check_one pname ptype e
            | None -> ()
          ) positionals;
          List.iter (fun (n, e) ->
            match List.find_opt (fun (p, _) -> p = n) params with
            | Some (_, ptype) -> check_one n ptype e
            | None -> ()
          ) named
        end
  ) (collect_call_sites program);
  List.rev !diags

(** Declared node names for one pipeline: [pni_names] mirrors the
    existence checks in runtime reads (`p.field` dot access,
    `pipeline_node`, two-argument `get` consult `p_exprs` first, then
    cached `p_nodes`; run_check unions both, covering branch expansion
    and lens writes); [pni_patterns] covers lazy `orig_branch_N`
    expansion. *)
type pipeline_node_index = {
  pni_names : string list;
  pni_patterns : string list;
}

(** Dangling pipeline-node read diagnostics (warn-only).
    Warns when `p.field`, `pipeline_node(p, name)`, or two-argument
    `get(p, name)` names a node that the pipeline does not declare.
    This catches typos the evaluator never reaches — reads inside
    lambdas, node blocks, and match arms — at check time. A pipeline
    variable resolves only when it has exactly one top-level
    assignment, no top-level reassignment, and no other binding: any
    nested assignment or reassignment rebinds locally and shadows the
    outer name, as does any shadowing binder anywhere (lambda
    parameters, match binders, type names, import aliases/names);
    anything else stays silent. Unknown pipelines (imports,
    parameters, meta-pipelines), non-literal node names, three-argument
    `get` (which returns its default), `orig_branch_N` names whose
    origin is declared, and `prefix` reads of dotted node names all
    stay silent, mirroring runtime resolution. Near-miss names carry a
    `Suggest_identifier` fix, which `t fix` never auto-applies (manual
    rename). Severity is Warning. *)
let dangling_node_read_diagnostics ~pipelines program filename =
  let assign_count = Hashtbl.create 8 in
  let reassigned = Hashtbl.create 8 in
  let shadowed = Hashtbl.create 8 in
  let mark tbl name = Hashtbl.replace tbl name true in
  let rec mark_pattern = function
    | PVar s -> mark shadowed s
    | PList (ps, rest) ->
        List.iter mark_pattern ps;
        (match rest with Some s -> mark shadowed s | None -> ())
    | PError (Some s) -> mark shadowed s
    | PUnion { pu_args; _ } -> List.iter mark_pattern pu_args
    | PWildcard | PNA | PError None -> ()
  in
  (* Binding names at every level. A nested assignment rebinds
     locally and shadows the outer name for that block (reads after
     it never touch the pipeline), so nested bindings silence the
     variable outright instead of counting toward the single
     top-level assignment. Binder audit: Lambda params, match
     patterns, assignments, reassignments, type names, and import
     aliases/names cover every T binder (no loops or comprehensions
     exist; type names cannot shadow per the eval guard, but are
     marked anyway). Erring silent is the safe direction throughout. *)
  let rec scan_stmt ~toplevel (s : stmt) =
    (match s.node with
    | Assignment { name; _ } ->
        if toplevel then
          let n = 1 + Option.value ~default:0 (Hashtbl.find_opt assign_count name) in
          Hashtbl.replace assign_count name n
        else mark shadowed name
    | Reassignment { name; _ } ->
        if toplevel then mark reassigned name
        else mark shadowed name
    | TypeDecl { tname; _ } -> mark shadowed tname
    | ImportFrom { names; _ } ->
        (* Only aliases shadow: a bare `import pkg [name]` re-exposes
           the package member under its own name, which for standard
           packages is the builtin itself. *)
        List.iter (fun (im : import_spec) ->
          match im.import_alias with
          | Some nick -> mark shadowed nick
          | None -> ()
        ) names
    | ImportFileFrom { names; _ } ->
        (* File imports bind user code, which may shadow anything, so
           both plain names and aliases count (unlike package imports
           above, where only aliases can introduce new bindings). *)
        List.iter (fun (im : import_spec) ->
          mark shadowed im.import_name;
          (match im.import_alias with Some nick -> mark shadowed nick | None -> ())
        ) names
    | _ -> ());
    List.iter scan_expr (children_of_stmt s)
  and scan_expr e =
    (* The Block arm is exclusive: children_of_expr on a Block yields
       exactly the statements' child expressions (ast.ml), so the
       generic recursion below would walk each nested block twice per
       level (2^depth). scan_stmt covers names and recurses into child
       expressions. *)
    match e.node with
    | Block blk -> List.iter (scan_stmt ~toplevel:false) blk
    | Lambda l ->
        List.iter (mark shadowed) l.params;
        List.iter scan_expr (children_of_expr e)
    | Match { cases; _ } ->
        List.iter (fun (p, _) -> mark_pattern p) cases;
        List.iter scan_expr (children_of_expr e)
    | _ -> List.iter scan_expr (children_of_expr e)
  in
  let rec all_exprs e =
    e :: List.concat_map all_exprs (children_of_expr e)
  in
  let exprs =
    List.concat_map (fun s -> List.concat_map all_exprs (children_of_stmt s)) program
  in
  List.iter (scan_stmt ~toplevel:true) program;
  let shadowed_fn name =
    Hashtbl.mem shadowed name
    || Hashtbl.mem assign_count name
    || Hashtbl.mem reassigned name
  in
  let resolvable pname =
    match List.assoc_opt pname pipelines with
    | None -> None
    | Some info ->
        if Hashtbl.find_opt assign_count pname = Some 1
           && not (Hashtbl.mem reassigned pname)
           && not (Hashtbl.mem shadowed pname)
        then Some info
        else None
  in
  (* A literal node selector: strings as written, symbols and `$name`
     column references stripped to the bare node name. Anything else
     (variables, calls) is dynamic and stays silent. *)
  let literal_node_name e =
    match e.node with
    | Value (VString s) -> Some s
    | Value (VSymbol s) -> Some (Utils.strip_dollar s)
    | ColumnRef s -> Some s
    | _ -> None
  in
  (* Mirror Eval.try_lazy_expand_branch name parsing: the last
     `_branch_N` suffix (positive N) resolves when its origin is a
     declared node or pattern. *)
  let branch_resolves names pats field =
    let marker = "_branch_" in
    let mlen = String.length marker in
    let flen = String.length field in
    let rec find pos =
      if pos < 0 then false
      else if pos + mlen <= flen && String.sub field pos mlen = marker then
        let orig = String.sub field 0 pos in
        let suffix = String.sub field (pos + mlen) (flen - pos - mlen) in
        (match int_of_string_opt suffix with
         | Some n when n > 0 ->
             List.mem orig names || List.mem orig pats
         | _ -> find (pos - 1))
      else find (pos - 1)
    in
    find (flen - mlen)
  in
  (* Mirror Eval.has_node_prefix: `p.prefix` reads on to dotted names. *)
  let prefix_resolves names field =
    let pfx = field ^ "." in
    List.exists (fun n ->
      String.length n > String.length pfx
      && String.starts_with ~prefix:pfx n
    ) names
  in
  let diags = ref [] in
  let check_site pname info node loc =
    if List.mem node info.pni_names
       || branch_resolves info.pni_names info.pni_patterns node
       || prefix_resolves info.pni_names node then ()
    else begin
      let names = info.pni_names in
      let loc_line = match loc with Some (l : source_location) -> l.line | None -> 1 in
      let fix =
        match Ast.suggest_names_with_scores node names with
        | [] -> Diagnostics.no_fix
        | (best, dist) :: rest ->
            let is_unique =
              match rest with
              | [] -> true
              | (_, runner_dist) :: _ -> runner_dist > dist
            in
            Diagnostics.make_suggest_identifier_fix
              ~name:node ~suggestion:best ~edit_distance:dist ~is_unique
              ~file:filename ~line:loc_line ()
      in
      let valid =
        if List.length names <= 10 && names <> [] then
          " Valid nodes: " ^ String.concat ", " names ^ "."
        else ""
      in
      diags := {
        Diagnostics.diag_id = Diagnostics.gen_id ();
        Diagnostics.diag_error_class = Diagnostics.Key_error;
        Diagnostics.diag_severity = Diagnostics.Warning;
        (* Wire, not Schema: this is name resolution on the DAG
           (cf. NameError mapping), and tier-1 structural checks
           ("no dangling node refs") live at this tier. *)
        Diagnostics.diag_phase = Diagnostics.Wire;
        Diagnostics.diag_node_id = None;
        Diagnostics.diag_node_lang = None;
        Diagnostics.diag_file = Some filename;
        Diagnostics.diag_line = (match loc with Some (l : source_location) -> Some l.line | None -> None);
        Diagnostics.diag_column = (match loc with Some (l : source_location) -> Some l.column | None -> None);
        Diagnostics.diag_end_line = None;
        Diagnostics.diag_end_column = None;
        Diagnostics.diag_message = Printf.sprintf
          "Node `%s` not found in pipeline `%s`.%s" node pname valid;
        Diagnostics.diag_expected = None;
        Diagnostics.diag_actual = None;
        Diagnostics.diag_caused_by = [];
        Diagnostics.diag_suggested_fix = fix;
      } :: !diags
    end
  in
  let check_call_args fn_name args loc =
    if shadowed_fn fn_name then ()
    else match args with
    | [(_, { node = Var pname; _ }); (_, namex)] ->
        (match resolvable pname with
         | Some info ->
             (match literal_node_name namex with
              | Some n -> check_site pname info n loc
              | None -> ())
         | None -> ())
    | _ -> ()
  in
  List.iter (fun e ->
    match e.node with
    | DotAccess { target = { node = Var pname; _ }; field } ->
        (match resolvable pname with
         | Some info -> check_site pname info field e.loc
         | None -> ())
    | Call { fn = { node = Var "pipeline_node"; _ }; args; _ } ->
        check_call_args "pipeline_node" args e.loc
    | Call { fn = { node = Var "get"; _ }; args; _ } ->
        check_call_args "get" args e.loc
    | _ -> ()
  ) exprs;
  List.rev !diags

(** Parse program text for static checks. Returns None when the text
    cannot be parsed; those failures are already reported through the
    evaluation path, so the AST walk stays silent. The catch-all is
    deliberate: the lexer/parser exception surface is open-ended
    (including resource exhaustion on hostile input), and silence on
    doubt fits this check's design. *)
let parse_program_string content filename =
  try
    let lexbuf = Lexing.from_string content in
    lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
    Some (Parser.program Lexer.token lexbuf)
  with
  | Sys.Break -> raise Sys.Break
  | _ -> None

let run_check ?(schema=false) ?(env_check=false) ?(offline=false) mode filename env =
  (* Read once: evaluation and the dangling-read walk share the text. *)
  let content =
    try
      let ch = open_in filename in
      Fun.protect ~finally:(fun () -> close_in_noerr ch)
        (fun () -> Some (really_input_string ch (in_channel_length ch)))
    with Sys_error _ -> None
  in
  let run () =
    Ast.check_mode := true;
    Fun.protect ~finally:(fun () -> Ast.check_mode := false)
      (fun () -> run_file ?content ~failfast:true mode filename env)
  in
  let (result, new_env) = run () in
  let check_result =
    let pipelines : (string * pipeline_result) list = match result with
      | VPipeline p -> [("pipeline", p)]
      | VError _ -> []
      | _ ->
          let bindings = Env.bindings new_env in
          List.filter_map (fun (name, v) ->
            match v with
            | VPipeline p -> Some (name, p)
            | _ -> None
          ) bindings
    in
    let existing_node_names =
      List.concat_map (fun (_name, p) ->
        List.map fst p.Ast.p_exprs
      ) pipelines
    in
    let diag_list : Diagnostics.diagnostic list =
      let error_diags = match result with
        | VError err -> [Diagnostics.of_verror ~file:filename ~existing_node_names err]
        | _ -> []
      in
      let pipeline_diags = List.concat_map (fun (_name, p) ->
        let wire_diags =
          Diagnostics.of_pipeline_result ~file:filename p
          @ Diagnostics.of_pipeline_validation ~file:filename p
        in
        let schema_diags =
          if schema then Schema_check.check_pipeline_schemas ~file:filename p
          else []
        in
        let env_diags =
          if env_check then Env_check.check_env ~offline ~file:filename p
          else []
        in
        wire_diags @ schema_diags @ env_diags
      ) pipelines in
      let extra_diags = !extra_diagnostics_hook filename in
      (* Dangling node reads use evaluated pipeline values (accurate
         for derived pipelines) but only when the file evaluates
         cleanly: with failfast on, a top-level dangling read already
         surfaces as the runtime error, so warning again would double
         report. Clean files still gain warnings for reads hidden in
         unexecuted code (lambdas, node blocks, match arms). *)
      let dangling_diags =
        match result with
        | VError _ -> []
        | _ ->
            let node_maps =
              List.filter_map (fun (name, v) ->
                match v with
                | VPipeline p ->
                    (* Runtime reads consult cached results first, so
                       materialized node names count alongside declared
                       ones (covers branch expansion and lens writes). *)
                    let expr_names = List.map fst p.p_exprs in
                    let extra = List.filter (fun n -> not (List.mem n expr_names))
                      (List.map fst p.p_nodes) in
                    Some (name, { pni_names = expr_names @ extra;
                                  pni_patterns = List.map fst p.p_patterns })
                | _ -> None
              ) (Env.bindings new_env)
            in
            if node_maps = [] then []
            else match content with
              | None -> []
              | Some text ->
                  (match parse_program_string text filename with
                   | None -> []
                   | Some program ->
                       dangling_node_read_diagnostics ~pipelines:node_maps program filename)
      in
      let unordered = extra_diags @ error_diags @ pipeline_diags @ dangling_diags in
      (* Diagnostics read better in source order than grouped by category:
         stable sort by location, keeping category order within one spot.
         Location-less diagnostics sort last. Applies to text and JSON. *)
      let loc_key d =
        ((match d.Diagnostics.diag_line with Some l -> l | None -> max_int),
         (match d.Diagnostics.diag_column with Some c -> c | None -> max_int))
      in
      List.stable_sort (fun a b -> compare (loc_key a) (loc_key b)) unordered
    in
    let check_phase = Diagnostics.worst_phase diag_list in
    let tier = Diagnostics.worst_tier diag_list in
    Diagnostics.make_result ~tier ~phase:check_phase diag_list
  in
  check_result

(* --- Formatting --- *)

let format_check_result ?(json=false) check_result =
  if json then
    Yojson.Safe.pretty_to_string (Diagnostics.check_result_to_yojson check_result)
  else begin
    let buf = Buffer.create 256 in
    let cr_diags = Diagnostics.check_result_entries check_result in
    List.iter (fun d ->
      (* Human-readable location prefix (file:line:column) so users and
         agents can jump straight to the fault. Parts without a location
         keep the legacy format; JSON output is unchanged. *)
      let loc = match d.Diagnostics.diag_file with
        | None -> ""
        | Some f ->
            (match d.Diagnostics.diag_line with
             | None -> f ^ ": "
             | Some l ->
                 (match d.Diagnostics.diag_column with
                  | None -> Printf.sprintf "%s:%d: " f l
                  | Some c -> Printf.sprintf "%s:%d:%d: " f l c))
      in
      Buffer.add_string buf
        (Printf.sprintf "%s%s [%s] %s\n"
           loc
           (Diagnostics.severity_to_string (Diagnostics.diagnostic_severity d))
           (Diagnostics.error_class_to_string (Diagnostics.diagnostic_error_class d))
           (Diagnostics.diagnostic_message d));
      (* Actionable details: expected vs actual, cause chain, and the
         suggested fix summary. JSON already carries these fields; text
         now shows them too so humans and LLMs can act without --json. *)
      (match d.Diagnostics.diag_expected, d.Diagnostics.diag_actual with
       | Some e, Some a ->
           Buffer.add_string buf (Printf.sprintf "    expected: %s | actual: %s\n" e a)
       | Some e, None ->
           Buffer.add_string buf (Printf.sprintf "    expected: %s\n" e)
       | None, Some a ->
           Buffer.add_string buf (Printf.sprintf "    actual: %s\n" a)
       | None, None -> ());
      (match d.Diagnostics.diag_caused_by with
       | [] -> ()
       | causes ->
           Buffer.add_string buf (Printf.sprintf "    caused by: %s\n" (String.concat ", " causes)));
      (match Diagnostics.suggested_fix_summary d.Diagnostics.diag_suggested_fix with
       | None -> ()
       | Some s -> Buffer.add_string buf (Printf.sprintf "    %s\n" s))
    ) cr_diags;
    if cr_diags <> [] then Buffer.add_char buf '\n';
    Buffer.contents buf
  end

(** Extract pipeline(s) from a file run in check mode *)
let extract_pipelines mode filename env =
  let (result, new_env) =
    Ast.check_mode := true;
    Fun.protect ~finally:(fun () -> Ast.check_mode := false)
      (fun () -> run_file ~failfast:true mode filename env)
  in
  match result with
  | VPipeline p -> Ok [("pipeline", p)]
  | VError err -> Error err
  | _ ->
      let bindings = Env.bindings new_env in
      let pipelines = List.filter_map (fun (name, v) ->
        match v with VPipeline p -> Some (name, p) | _ -> None
      ) bindings in
      if pipelines = [] then
        Error { code = FileError;
                message = Printf.sprintf "No pipeline found in %s." filename;
                context = []; location = None; na_count = 0 }
      else Ok pipelines
