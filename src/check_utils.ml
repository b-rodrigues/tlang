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

let run_file ?failfast mode filename env =
  try
    let ch = open_in filename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    parse_and_eval ~filename ?failfast mode env content
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

(** Call arity diagnostics (warn-only).
    Mirrors the runtime arity rule in `Eval.eval_call` exactly: a
    non-variadic builtin takes exactly `b_arity` arguments, counting
    positional and named args together. A call on the right of `|>`
    or `?|>` gets the piped value as an implicit first argument, so
    one is added there (a bare `x |> f` counts one). Everything else
    stays silent: variadic builtins, unknown names, and names bound
    anywhere in the program (a local binding shadows the builtin).
    This catches mistakes the evaluator never reaches — calls inside
    lambdas, node blocks, and match arms — at check time. Severity is
    Warning. The builtin table is a parameter so this module stays a
    leaf (`Analyzer -> Packages -> Check_utils` must not cycle). *)
let call_arity_diagnostics ~builtins program filename =
  (* Every name with a local binding program-wide: assignments,
     reassignments, lambda parameters, and match pattern binders.
     Calling such a name may hit the local, not the builtin. *)
  let bound = Hashtbl.create 32 in
  let bind name = Hashtbl.replace bound name true in
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
     | _ -> ());
    List.iter collect_expr (children_of_stmt s)
  in
  List.iter collect_stmt program;
  (* Call sites with pipe context: a call directly right of `|>`/`?|>`
     sees one implicit extra argument. *)
  let sites = ref [] in
  let rec walk_expr piped e =
    match e.node with
    | Call { fn = { node = Var name; _ }; args; _ } ->
        List.iter (fun (_, a) -> walk_expr false a) args;
        sites := (name, List.length args + (if piped then 1 else 0), e.loc) :: !sites
    | Call { fn; args; _ } ->
        walk_expr false fn;
        List.iter (fun (_, a) -> walk_expr false a) args
    | BinOp { op = (Pipe | MaybePipe); left; right; _ } ->
        walk_expr false left;
        (match right.node with
         | Call _ -> walk_expr true right
         | Var name ->
             sites := (name, 1, right.loc) :: !sites
         | _ -> walk_expr false right)
    | _ ->
        List.iter (walk_expr false) (children_of_expr e)
  in
  List.iter (fun s -> List.iter (walk_expr false) (children_of_stmt s)) program;
  let diags = ref [] in
  List.iter (fun (name, received, loc) ->
    if Hashtbl.mem bound name then ()
    else match List.assoc_opt name builtins with
    | Some (expected, false) when received <> expected ->
        let line = match loc with
          | Some (l : source_location) -> Some l.line
          | None -> None
        in
        let col = match loc with
          | Some (l : source_location) -> Some l.column
          | None -> None
        in
        diags := { Diagnostics.diag_id = Diagnostics.gen_id ();
          Diagnostics.diag_error_class = Diagnostics.Arity_error;
          Diagnostics.diag_severity = Diagnostics.Warning;
          Diagnostics.diag_phase = Diagnostics.Schema;
          Diagnostics.diag_node_id = None;
          Diagnostics.diag_node_lang = None;
          Diagnostics.diag_file = Some filename;
          Diagnostics.diag_line = line;
          Diagnostics.diag_column = col;
          Diagnostics.diag_end_line = None;
          Diagnostics.diag_end_column = None;
          Diagnostics.diag_message = Printf.sprintf
            "Function `%s` expects %d argument(s) but received %d. The call fails at runtime."
            name expected received;
          Diagnostics.diag_expected = Some (string_of_int expected);
          Diagnostics.diag_actual = Some (string_of_int received);
          Diagnostics.diag_caused_by = [];
          Diagnostics.diag_suggested_fix = Diagnostics.no_fix;
        } :: !diags
    | _ -> ()
  ) (List.rev !sites);
  List.rev !diags

let run_check ?(schema=false) ?(env_check=false) ?(offline=false) mode filename env =
  let run () =
    Ast.check_mode := true;
    Fun.protect ~finally:(fun () -> Ast.check_mode := false)
      (fun () -> run_file ~failfast:true mode filename env)
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
      let unordered = extra_diags @ error_diags @ pipeline_diags in
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
           (Diagnostics.diagnostic_message d))
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
