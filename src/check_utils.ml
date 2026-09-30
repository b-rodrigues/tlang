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
     `Any` (silent) when absent. *)
  let stmt_ty i =
    match Hashtbl.find_opt stmt_types i with
    | Some st -> Semantic_type.to_ast_typ st
    | _ -> Ast.TCustom "Any"
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
       only their children below do. *)
    | _ -> []
  in
  self @ sites_in_children e

and sites_in_children (e : Ast.expr) : match_site list =
  match e.Ast.node with
  | Ast.Value _ | Ast.Var _ | Ast.ColumnRef _ | Ast.RawCode _ | Ast.ShellExpr _ -> []
  | Ast.Call { fn; args } ->
      sites_in_expr fn @ List.concat_map (fun (_, a) -> sites_in_expr a) args
  | Ast.ListLit items -> List.concat_map (fun (_, x) -> sites_in_expr x) items
  | Ast.DictLit pairs -> List.concat_map (fun (_, v) -> sites_in_expr v) pairs
  | Ast.BinOp { left; right; _ } | Ast.BroadcastOp { left; right; _ } ->
      sites_in_expr left @ sites_in_expr right
  | Ast.UnOp { operand; _ } -> sites_in_expr operand
  | Ast.DotAccess { target; _ } -> sites_in_expr target
  | Ast.IfElse { cond; then_; else_ } ->
      sites_in_expr cond @ sites_in_expr then_ @ sites_in_expr else_
  | Ast.Match { scrutinee; cases } ->
      sites_in_expr scrutinee
      @ List.concat_map (fun (_, body) -> sites_in_expr body) cases
  | Ast.Lambda l -> sites_in_expr l.Ast.body
  | Ast.Block stmts -> List.concat_map sites_in_stmt stmts
  | Ast.PipelineDef nodes | Ast.PipelineOfDef nodes | Ast.IntentDef nodes ->
      List.concat_map (fun (_, x) -> sites_in_expr x) nodes
  | Ast.Unquote x | Ast.UnquoteSplice x -> sites_in_expr x

and sites_in_stmt (s : Ast.stmt) : match_site list =
  match s.Ast.node with
  | Ast.Expression e -> sites_in_expr e
  | Ast.Assignment { expr = e; _ } -> sites_in_expr e
  | Ast.Reassignment { expr = e; _ } -> sites_in_expr e
  (* Type declarations hold static annotations only; no match sites. *)
  | Ast.TypeDecl _ -> []
  | Ast.Import _ | Ast.ImportPackage _ | Ast.ImportFrom _ | Ast.ImportFileFrom _ -> []

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
    direct constructor call (`Circle(...)`) of a known union. Anything
    else stays silent, so no previously clean program gains a warning.
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
  (* Local accumulation across the site walk, as above. *)
  let diags = ref [] in
  let sites = List.concat_map sites_in_stmt program in
  let scrutinee_union e =
    match e.Ast.node with
    | Ast.Call { fn = { Ast.node = Ast.Var fname; _ }; _ } ->
        List.find_opt (fun (_, cases) -> List.mem fname cases) unions
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
      extra_diags @ error_diags @ pipeline_diags
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
