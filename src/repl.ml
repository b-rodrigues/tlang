(* src/repl.ml *)
(* CLI and interactive REPL for the T language — 0.51.1 *)

let version = Version.version
let codename = Version.codename

(* --- Readline / History --- *)

let history_file =
  try Filename.concat (Sys.getenv "HOME") ".t_history"
  with Not_found -> ".t_history"

let max_history_length = 1000

let () =
  ignore (LNoise.history_set ~max_length:max_history_length);
  ignore (LNoise.history_load ~filename:history_file)

(* --- Parsing and Evaluation --- *)
(* Delegated to Check_utils (library module) so both the CLI and
   REPL-callable functions share the same implementation. *)

let make_located_error = Check_utils.make_located_error
let interrupt_error = Check_utils.interrupt_error
let parse_and_eval = Check_utils.parse_and_eval
let run_file = Check_utils.run_file

(* --- Pipeline Detection --- *)

(** Recursively check if an expression contains a call to build_pipeline *)
let rec expr_has_build_pipeline = function
  | { Ast.node = Ast.Call { fn = { Ast.node = Ast.Var "build_pipeline"; _ }; _ }; _ } -> true
  | { Ast.node = Ast.Call { fn = { Ast.node = Ast.Var "populate_pipeline"; _ }; _ }; _ } -> true
  | { Ast.node = Ast.Call { fn; args; _ }; _ } ->
      expr_has_build_pipeline fn ||
      List.exists (fun (_, e) -> expr_has_build_pipeline e) args
  | { Ast.node = Ast.BinOp { left; right; _ } | Ast.BroadcastOp { left; right; _ }; _ } ->
      expr_has_build_pipeline left || expr_has_build_pipeline right
  | { Ast.node = Ast.IfElse { cond; then_; else_ }; _ } ->
      expr_has_build_pipeline cond ||
      expr_has_build_pipeline then_ ||
      expr_has_build_pipeline else_
  | { Ast.node = Ast.Match { scrutinee; cases }; _ } ->
      expr_has_build_pipeline scrutinee ||
      List.exists (fun (_, body) -> expr_has_build_pipeline body) cases
  | { Ast.node = Ast.Lambda { body; _ }; _ } -> expr_has_build_pipeline body
  | { Ast.node = Ast.ListLit items; _ } -> List.exists (fun (_, e) -> expr_has_build_pipeline e) items
  | { Ast.node = Ast.DictLit pairs; _ } -> List.exists (fun (_, e) -> expr_has_build_pipeline e) pairs
  | { Ast.node = Ast.UnOp { operand; _ }; _ } -> expr_has_build_pipeline operand
  | { Ast.node = Ast.DotAccess { target; _ }; _ } -> expr_has_build_pipeline target
  | { Ast.node = Ast.Block stmts; _ } -> List.exists stmt_has_build_pipeline stmts
  | { Ast.node = Ast.PipelineDef _; _ }
  | { Ast.node = Ast.PipelineOfDef _; _ } -> true
  | { Ast.node = Ast.IntentDef pairs; _ } -> List.exists (fun (_, e) -> expr_has_build_pipeline e) pairs
  | _ -> false

and stmt_has_build_pipeline = function
  | { Ast.node = Ast.Expression e; _ } -> expr_has_build_pipeline e
  | { Ast.node = Ast.Assignment { expr; _ }; _ } -> expr_has_build_pipeline expr
  | { Ast.node = Ast.Reassignment { expr; _ }; _ } -> expr_has_build_pipeline expr
  | { Ast.node = Ast.Import _ | Ast.ImportPackage _ | Ast.ImportFrom _ | Ast.ImportFileFrom _; _ } -> false

let program_has_build_pipeline (program : Ast.program) =
  List.exists stmt_has_build_pipeline program

(* --- Multi-line Input Detection --- *)

(** Count unmatched opening brackets/parens/braces in a string *)
let count_open_delimiters s =
  let depth = ref 0 in
  let in_string = ref false in
  let string_char = ref '"' in
  let len = String.length s in
  let i = ref 0 in
  while !i < len do
    let c = s.[!i] in
    if !in_string then begin
      if c = '\\' && !i + 1 < len then
        i := !i + 1  (* Skip escaped character *)
      else if c = !string_char then
        in_string := false
    end else begin
      match c with
      | '"' | '\'' -> in_string := true; string_char := c
      | '(' | '[' | '{' -> incr depth
      | ')' | ']' | '}' -> decr depth
      | _ -> ()
    end;
    i := !i + 1
  done;
  !depth

(** Check if input appears to be an incomplete expression *)
let is_incomplete input =
  let trimmed = String.trim input in
  if trimmed = "" then false
  else
    (* Unclosed delimiters *)
    let open_count = count_open_delimiters trimmed in
    if open_count > 0 then true
    (* Trailing pipe operator: |> or ?|> *)
    else
      let len = String.length trimmed in
      (len >= 3 && String.sub trimmed (len - 3) 3 = "?|>") ||
      (len >= 2 && String.sub trimmed (len - 2) 2 = "|>")

(* --- Pretty-Printing for REPL --- *)

let color_reset = "\027[0m"
let color_bold = "\027[1m"
let color_red = "\027[31m"
let color_blue = "\027[34m"
let color_gray = "\027[90m"

(** Format a value as a string for REPL display *)
let repl_format_value v =
  let buf = Buffer.create 256 in
  let bprintf fmt = Printf.ksprintf (Buffer.add_string buf) fmt in
  let maybe_package_info v =
    match v with
    | Ast.VDict pairs ->
        let lookup key = List.assoc_opt key pairs in
        (match lookup "name", lookup "description", lookup "functions" with
        | Some (Ast.VString name), Some (Ast.VString description), Some (Ast.VList fns) ->
            let fn_names = List.filter_map (function (_, Ast.VString s) -> Some s | _ -> None) fns in
            if List.length fn_names = List.length fns then Some (name, description, fn_names)
            else None
        | _ -> None)
    | _ -> None
  in
  (match v with
  | Ast.(VNA NAGeneric) -> ()
  | Ast.VError { context; _ } ->
      bprintf "%s%s%s\n" color_red (Ast.Utils.value_to_string v) color_reset;
      if context <> [] then begin
        bprintf "%sContext:%s\n" color_gray color_reset;
        List.iter (fun (k, v) -> bprintf "  %s: %s\n" k (Ast.Utils.value_to_string v)) context
      end
  | Ast.VDataFrame _ | Ast.VPipeline _ ->
      bprintf "%s\n" (Pretty_print.pretty_print_value v)
  | other ->
      (match maybe_package_info other with
      | Some (name, description, functions) ->
          bprintf "\n  %s%s%s\n\n  %s\n\n  %sFunctions (%d):%s\n"
            color_bold name color_reset description color_blue (List.length functions) color_reset;
          List.iter (fun fn_name -> bprintf "    - %s\n" fn_name) functions
      | None -> bprintf "%s\n" (Pretty_print.pretty_print_value other)));
  Buffer.contents buf

(** Pretty-print a value for REPL display *)
let repl_display_value v =
  Printf.printf "%s" (repl_format_value v);
  flush stdout;
  flush stderr

(* --- Magic Commands and Help --- *)

let magic_command_help = [
  ("time",    "<expr>", "Time an expression");
  ("ls",      "",       "List directory contents");
  ("pwd",     "",       "Print working directory");
  ("cd",      "<dir>",  "Change directory");
  ("env",     "",       "List environment variables");
  ("history", "",       "Show command history");
  ("objects", "",       "List user-defined objects");
  ("magic",   "",       "List available magic commands");
  ("reset",   "",       "Reset environment to base (remove all user objects)");
  ("save",    "<file>", "Save session transcript to file");
  ("save",    "verbose <file>", "Save session transcript with verbose output");
]

let known_magic_commands = List.map (fun (n, _, _) -> n) magic_command_help

let string_of_magic_commands () =
  let buf = Buffer.create 512 in
  let max_w = List.fold_left (fun m (n, a, _) ->
    let len = 1 + String.length n + if a = "" then 0 else 1 + String.length a in
    max m len
  ) 0 magic_command_help
  in
  List.iter (fun (name, args, desc) ->
    let cmd = "%" ^ name ^ if args = "" then "" else " " ^ args in
    Buffer.add_string buf (Printf.sprintf "  %-*s  %s\n" max_w cmd desc)
  ) magic_command_help;
  Buffer.contents buf

let print_magic_commands () =
  Printf.printf "%s" (string_of_magic_commands ())

let levenshtein_distance s t =
  let m = String.length s and n = String.length t in
  if m = 0 then n
  else if n = 0 then m
  else begin
    let dp = Array.make_matrix (m + 1) (n + 1) 0 in
    for i = 0 to m do dp.(i).(0) <- i done;
    for j = 0 to n do dp.(0).(j) <- j done;
    for i = 1 to m do
      for j = 1 to n do
        let cost = if s.[i-1] = t.[j-1] then 0 else 1 in
        dp.(i).(j) <- min (dp.(i-1).(j) + 1) (min (dp.(i).(j-1) + 1) (dp.(i-1).(j-1) + cost))
      done
    done;
    dp.(m).(n)
  end

let rec value_summary v =
  match v with
  | Ast.VInt n -> string_of_int n
  | Ast.VFloat f -> string_of_float f
  | Ast.VBool b -> string_of_bool b
  | Ast.VString s -> "\"" ^ Ast.Utils.escape_string_utf8 s ^ "\""
  | Ast.VSymbol s -> s
  | Ast.VNA na_t ->
      let tag = Ast.Utils.na_type_to_string na_t in
      if tag = "" then "NA" else "NA(" ^ tag ^ ")"
  | Ast.VDate days ->
      let tm = Unix.gmtime (float_of_int days *. 86400.) in
      Printf.sprintf "Date(%04d-%02d-%02d)" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
  | Ast.VDatetime _ -> Ast.Utils.value_to_string v
  | Ast.VDataFrame { arrow_table; group_keys } ->
      let base = Printf.sprintf "%d rows x %d cols"
        (Arrow_table.num_rows arrow_table) (Arrow_table.num_columns arrow_table)
      in
      if group_keys = [] then base
      else Printf.sprintf "%s [grouped by: %s]" base (String.concat ", " group_keys)
  | Ast.VPipeline { p_nodes; _ } ->
      let n = List.length p_nodes in
      Printf.sprintf "%d node%s" n (if n = 1 then "" else "s")
  | Ast.VMetaPipeline { mp_pipelines; _ } ->
      let n = List.length mp_pipelines in
      Printf.sprintf "%d sub-pipeline%s" n (if n = 1 then "" else "s")
  | Ast.VList items ->
      let n = List.length items in
      Printf.sprintf "[%d item%s]" n (if n = 1 then "" else "s")
  | Ast.VVector arr ->
      Printf.sprintf "Vector[%d elements]" (Array.length arr)
  | Ast.VNDArray { shape; _ } ->
      let dims = Array.to_list shape |> List.map string_of_int |> String.concat " x " in
      Printf.sprintf "NDArray(%s)" dims
  | Ast.VDict pairs ->
      let lookup k = List.assoc_opt k pairs in
      (match lookup "model_type", lookup "r_squared", lookup "nobs" with
       | Some (Ast.VString mt), Some (Ast.VFloat r2), Some (Ast.VInt n) ->
           Printf.sprintf "%s (r²=%.2f, n=%d)" mt r2 n
       | Some (Ast.VString mt), Some (Ast.VFloat r2), _ ->
           Printf.sprintf "%s (r²=%.2f)" mt r2
       | Some (Ast.VString mt), _, Some (Ast.VInt n) ->
           Printf.sprintf "%s (n=%d)" mt n
       | Some (Ast.VString mt), _, _ -> mt
       | Some (Ast.VSymbol s), _, _ -> s
       | _ -> Printf.sprintf "{%d keys}" (List.length pairs))
  | Ast.VLambda { params; autoquote_params; _ } ->
      "\\(" ^ String.concat ", " (Ast.Utils.display_params params autoquote_params) ^ ") -> ..."
  | Ast.VBuiltin { b_name; _ } ->
      (match b_name with Some name -> name | None -> "<builtin>")
  | Ast.VError { code; message; _ } ->
      let trunc =
        if String.length message > 60 then
          String.sub message 0 60 ^ "..."
        else
          message
      in
      Printf.sprintf "%s: %s" (Ast.Utils.error_code_to_string code) trunc
  | Ast.VFactor (idx, levels, ordered) ->
      let level = match List.nth_opt levels idx with Some s -> s | None -> "NA" in
      if ordered then Printf.sprintf "ordered Factor(%s)" level
      else Printf.sprintf "Factor(%s)" level
  | Ast.VPeriod p ->
      Printf.sprintf "Period(%dy %dm)" p.p_years p.p_months
  | Ast.VDuration sec -> Printf.sprintf "Duration(%g)" sec
  | Ast.VInterval _ -> Ast.Utils.value_to_string v
  | Ast.VLens _ -> Ast.Utils.value_to_string v
  | Ast.VIntent { intent_fields } ->
      Printf.sprintf "Intent{%s}" (String.concat ", " (List.map fst intent_fields))
  | Ast.VFormula { response; predictors; _ } ->
      Printf.sprintf "%s ~ %s" (String.concat " + " response) (String.concat " + " predictors)
  | Ast.VExpr e -> "Expression(" ^ Ast.Utils.unparse_expr e ^ ")"
  | Ast.VQuo { q_expr; _ } -> "Quosure(" ^ Ast.Utils.unparse_expr q_expr ^ ")"
  | Ast.VComputedNode cn -> Printf.sprintf "computed_node<%s>" cn.cn_runtime
  | Ast.VSerializer s -> Printf.sprintf "serializer<^%s>" s.s_format
  | Ast.VNode un -> Printf.sprintf "node<%s>" un.un_runtime
  | Ast.VNullNode -> "<null>"
  | Ast.VPattern _ -> "Pattern"
  | Ast.VBuildLog bl -> Printf.sprintf "BuildLog(%d nodes)" (List.length bl.bl_nodes)
  | Ast.VShellResult { sr_stdout; _ } -> "\"" ^ String.escaped sr_stdout ^ "\""
  | Ast.VRawCode s -> "<{ " ^ s ^ " }>"
  | Ast.VUnquote v -> "!!" ^ value_summary v
  | Ast.VUnquoteSplice v -> "!!!" ^ value_summary v
  | Ast.VDynamicArg (n, v) -> n ^ " := " ^ value_summary v
  | Ast.VEnv _ -> "<environment>"
  | Ast.VNodeResult { v; _ } -> value_summary v
  | Ast.VExpect Ast.Expect_pass -> "PASS"
  | Ast.VExpect (Ast.Expect_stop msg) -> Printf.sprintf "STOP(%s)" msg
  | Ast.VExpect (Ast.Expect_hold msg) -> Printf.sprintf "HOLD(%s)" msg

(* --- Session Transcript and Base Env --- *)

type session_entry =
  | EvalEntry of string * Ast.value
  | MagicEntry of string * string

let session_transcript : session_entry list ref = ref []
let base_env_ref = ref Ast.Env.empty

let save_session env fname_parts ~verbose =
  let fname = String.trim (String.concat " " fname_parts) in
  if fname = "" then
    (env, Some "Error: Please specify a filename (e.g., %save session.t)\n", true)
  else
    let entries = List.rev !session_transcript in
    try
      let oc = open_out fname in
      Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
        List.iter (fun entry ->
          match entry with
          | EvalEntry (cmd, v) ->
              Printf.fprintf oc "# %s\n" cmd;
              let output = if verbose then Pretty_print.pretty_print_value v else value_summary v in
              String.split_on_char '\n' output
              |> List.iter (fun line -> if line <> "" then Printf.fprintf oc "# %s\n" line);
              Printf.fprintf oc "\n"
          | MagicEntry (cmd, output) ->
              Printf.fprintf oc "# %s\n" cmd;
              String.split_on_char '\n' (String.trim output)
              |> List.iter (fun line -> if line <> "" then Printf.fprintf oc "# %s\n" line);
              Printf.fprintf oc "\n"
        ) entries
      );
      let out = Printf.sprintf "Session saved to %s\n" fname in
      (env, Some out, true)
    with Sys_error msg ->
      (env, Some ("Error saving session: " ^ msg ^ "\n"), true)

let handle_magic line env mode base_keys =
  let parts = String.split_on_char ' ' (String.sub line 1 (String.length line - 1)) |> List.filter (fun s -> s <> "") in
  match parts with
  | "time" :: expr_parts ->
      let expr_str = String.concat " " expr_parts in
      let start_time = Unix.gettimeofday () in
      let (result, new_env) = parse_and_eval ?failfast:None mode env expr_str in
      let end_time = Unix.gettimeofday () in
      let result_str = repl_format_value result in
      let out = result_str ^ Printf.sprintf "%sExecution time: %.4f seconds%s\n" color_gray (end_time -. start_time) color_reset in
      (new_env, Some out, true)
  | ["ls"] ->
      let files = Sys.readdir "." |> Array.to_list in
      let out = String.concat "  " files ^ "\n" in
      (env, Some out, true)
  | ["pwd"] ->
      let out = Sys.getcwd () ^ "\n" in
      (env, Some out, true)
  | ["cd"; dir] ->
      let expanded_dir =
        if dir = "~" then
          try Sys.getenv "HOME" with Not_found -> dir
        else if String.length dir >= 2 && String.sub dir 0 2 = "~/" then
          try (Sys.getenv "HOME") ^ String.sub dir 1 (String.length dir - 1)
          with Not_found -> dir
        else
          dir
      in
      (try Sys.chdir expanded_dir; (env, None, true)
       with Sys_error msg -> (env, Some ("Error: " ^ msg ^ "\n"), true))
  | ["env"] ->
      let out = String.concat "\n" (Array.to_list (Unix.environment ())) ^ "\n" in
      (env, Some out, true)
  | ["history"] ->
      let items =
        try
          let ch = open_in history_file in
          let lines =
            try
              let rec loop acc =
                try loop (input_line ch :: acc)
                with End_of_file -> List.rev acc
              in
              loop []
            with e ->
              close_in_noerr ch;
              raise e
          in
          close_in ch;
          Array.of_list lines
        with _ -> [||]
      in
      let total = Array.length items in
      let start = max 0 (total - 50) in
      let out =
        if total = 0 then Printf.sprintf "%s(no history)%s\n" color_gray color_reset
        else begin
          let buf = Buffer.create 512 in
          for i = start to total - 1 do
            Buffer.add_string buf (Printf.sprintf "%5d  %s\n" (i + 1) items.(i))
          done;
          Buffer.contents buf
        end
      in
      (env, Some out, true)
  | ["objects"] | ["who"] ->
      let items = Ast.Env.fold (fun k v acc ->
        if not (Hashtbl.mem base_keys k) then (k, v) :: acc else acc
      ) env [] |> List.sort (fun (a,_) (b,_) -> String.compare a b) in
      let name_w = List.fold_left (fun m (n,_) -> max m (String.length n)) 4 items in
      let type_w = List.fold_left (fun m (_,v) -> max m (String.length (Ast.Utils.type_name v))) 4 items in
      let buf = Buffer.create 512 in
      Buffer.add_string buf (Printf.sprintf "%sUser-defined objects (%d):%s\n" color_blue (List.length items) color_reset);
      List.iter (fun (n, v) ->
        Buffer.add_string buf (Printf.sprintf "  %-*s  %-*s  %s\n" name_w n type_w (Ast.Utils.type_name v) (value_summary v))
      ) items;
      Buffer.add_string buf "\n";
      (env, Some (Buffer.contents buf), true)
  | ["magic"] ->
      let out = Printf.sprintf "%sAvailable magic commands:%s\n%s\n" color_blue color_reset (string_of_magic_commands ()) in
      (env, Some out, true)
  | ["reset"] ->
      session_transcript := [];
      let out = Printf.sprintf "%sEnvironment reset to base.%s\n" color_blue color_reset in
      (!base_env_ref, Some out, true)
  | "save" :: "verbose" :: fname_parts ->
      save_session env fname_parts ~verbose:true
  | "save" :: fname_parts ->
      save_session env fname_parts ~verbose:false
  | _ ->
      let cmd = match parts with [] -> "" | hd :: _ -> hd in
      let suggestion =
        if cmd = "" then None
        else
          let dists = List.map (fun k -> (k, levenshtein_distance cmd k)) known_magic_commands in
          let (best, min_d) = List.fold_left (fun (bk, bd) (k, d) ->
            if d < bd then (k, d) else (bk, bd)
          ) ("", max_int) dists
          in
          if min_d <= max 1 (String.length cmd / 2) then Some best else None
      in
      let out = match suggestion with
       | Some s -> Printf.sprintf "Unknown magic command: %s\nDid you mean: %%%s?\n" line s
       | None -> Printf.sprintf "Unknown magic command: %s\n" line
      in
      (env, Some out, true)

(* --- CLI Commands --- *)

let print_help () =
  Printf.printf "T language — version %s\n\n" version;
  Printf.printf "Usage: t <command> [arguments]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  repl              Start the interactive REPL (default)\n";
  Printf.printf "  run [--json] <file.t>      Execute a T source file\n";
  Printf.printf "  run [--json] --expr <expr> Execute a T expression directly\n";
  Printf.printf "  check [--json] [--schema] [--env] <file.t>  Validate pipeline structure (no Nix builds)\n";
  Printf.printf "  diff [--json] [--log-a <n>] [--log-b <n>] <file.t>  Compare two builds (output diff)\n";
  Printf.printf "  debug <node>      Start a subshell to debug a pipeline node\n";
  Printf.printf "  --mode <m>        Type-check mode: repl or strict\n";
  Printf.printf "  --failfast        Stop execution on first error\n";
  Printf.printf "  explain <expr>    Explain a value or expression\n";
  Printf.printf "  init --package <n>  Create a new T package\n";
  Printf.printf "  init --project <n>  Create a new T project\n";
  Printf.printf "  export_artifacts <file.t> <archive>  Export a pipeline cache archive\n";
  Printf.printf "  import_artifacts <file.t> <archive>  Import a pipeline cache archive\n";
  Printf.printf "  test              Run tests in the current directory\n";
  Printf.printf "  update            Update dependencies and nixpkgs date from tproject.toml\n";
  Printf.printf "  upgrade           Upgrade T version and nixpkgs date to today's date\n";
  Printf.printf "  add <runtime> <pkg>  Add a package to tproject.toml (R, Python, or Julia)\n";
  Printf.printf "  doctor            Check package health\n";
  Printf.printf "  docs              Open documentation\n";
  Printf.printf "  --help, -h        Show this help message\n";
  Printf.printf "  --version, -v     Show version\n";
  Printf.printf "\nREPL Power Features:\n";
  print_magic_commands ()

let print_version () =
  Printf.printf "T language version %s\n" version

let exit_with_error message =
  Printf.eprintf "Error: %s\n" message;
  exit 1

let ensure_file_path filename =
  match Cli_args.validate_path ~kind:Cli_args.File filename with
  | Ok () -> ()
  | Error msg -> exit_with_error msg

let parse_program_from_file filename =
  try
    let ch = open_in filename in
    let content =
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    let lexbuf = Lexing.from_string content in
    lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
    try
      Ok (Parser.program Lexer.token lexbuf)
    with
    | Lexer.SyntaxError msg ->
        let pos = Lexing.lexeme_start_p lexbuf in
        Error (make_located_error ~file:filename Ast.SyntaxError ("Syntax Error: " ^ msg) pos)
    | Parser.Error ->
        let pos = Lexing.lexeme_start_p lexbuf in
        Error (make_located_error ~file:filename Ast.SyntaxError (Check_utils.parse_error_message lexbuf) pos)
    | Ast.Mixed_bracket_form ->
        let pos = Lexing.lexeme_start_p lexbuf in
        Error (make_located_error ~file:filename Ast.SyntaxError "Mixed bracket literal (found both single elements and key-value pairs)" pos)
    | Ast.Invalid_match_pattern msg ->
        let pos = Lexing.lexeme_start_p lexbuf in
        Error (make_located_error ~file:filename Ast.SyntaxError msg pos)
    | Sys.Break ->
        Error (interrupt_error ())
  with
  | Sys_error msg ->
      Error (Ast.VError {
        code = Ast.FileError;
        message = "File Error: " ^ msg;
        context = [];
        location = None;
        na_count = 0;
      })

let resolve_pipeline_from_program_result filename (program : Ast.program) result env =
  let result = !Ast.meta_pipeline_flatten_resolver result in
  match result with
  | Ast.VPipeline p -> Ok p
  | _ ->
      let pipeline_bindings =
        Pipeline_script.top_level_assigned_names program
        |> List.filter_map (fun name ->
          match Ast.Env.find_opt name env with
          | Some v ->
              (match !Ast.meta_pipeline_flatten_resolver v with
               | Ast.VPipeline p -> Some (name, p)
               | _ -> None)
          | None -> None)
      in
      match List.assoc_opt "p" pipeline_bindings, pipeline_bindings with
      | Some p, _ -> Ok p
      | None, [(_, p)] -> Ok p
      | None, [] ->
          Error
            (Printf.sprintf
               "No pipeline value was found in `%s`. Return a Pipeline value or bind it to `p` before calling this command."
               filename)
      | None, bindings ->
          Error
            (Printf.sprintf
               "Multiple pipeline bindings were found in `%s` (%s). Bind the desired pipeline to `p` before calling this command."
               filename (String.concat ", " (List.map fst bindings)))

let cmd_artifact_transfer action filename archive_path env =
  Packages.ensure_docs_loaded ();
  ensure_file_path filename;
  match parse_program_from_file filename with
  | Error err ->
      Printf.eprintf "%s" (Pretty_print.pretty_print_value err);
      exit 1
  | Ok program ->
      let (result, new_env) = run_file Typecheck.Strict filename env in
      match result with
      | Ast.VError _ ->
          Printf.eprintf "%s" (Pretty_print.pretty_print_value result);
          exit 1
      | _ ->
          (match resolve_pipeline_from_program_result filename program result new_env with
           | Error msg -> exit_with_error msg
           | Ok pipeline ->
               let transfer_result =
                 match action with
                 | `Export -> Builder_artifacts.export_artifacts (VPipeline pipeline) archive_path
                 | `Import -> Builder_artifacts.import_artifacts (VPipeline pipeline) archive_path
               in
               match transfer_result with
               | Ok message -> Printf.printf "%s\n" message
               | Error err ->
                   Printf.eprintf "%s\n"
                     (Pretty_print.pretty_print_value
                        (Ast.VError {
                          code = err.code;
                          message = err.message;
                          context = [];
                          location = None;
                          na_count = 0;
                        }));
                   exit 1)

let flush_warnings_to_out () =
  match Sys.getenv_opt "out" with
  | Some out_path ->
      let wrote = ref false in
      let write_warnings warnings =
        let warning_values = List.map (fun w -> (None, Ast.Utils.node_warning_to_value w)) warnings in
        let json = Serialization.value_to_yojson (Ast.VList warning_values) in
        let warnings_path = Filename.concat out_path "warnings" in
        (try
           let ch = open_out warnings_path in
           output_string ch (Yojson.Safe.to_string ~std:true json);
           close_out ch
         with _ -> ())
      in
      (* Try pipeline diagnostics first (last evaluated node) *)
      (match !Eval.last_evaluated_node_name with
       | Some node_name ->
           (match List.find_opt (fun (n, _) -> n = node_name) !Eval.last_node_diagnostics with
            | Some (_, diag) when diag.Ast.nd_warnings <> [] ->
                write_warnings diag.Ast.nd_warnings; wrote := true
            | _ -> ())
       | None -> ());
      (* Fall back to global warnings (emitted outside pipeline eval) *)
      if not !wrote then begin
        let global = List.rev !Eval.global_warnings in
        if global <> [] then begin
          write_warnings global;
          Eval.global_warnings := []
        end
      end
  | None -> ()

let cmd_run ?(unsafe=false) ?failfast ?(json=false) mode filename env =
  Packages.ensure_docs_loaded ();
  ensure_file_path filename;
  if json then Ast.ndjson_mode := true;
  if not unsafe then begin
    try
      let ch = open_in filename in
      let content = really_input_string ch (in_channel_length ch) in
      close_in ch;
      let lexbuf = Lexing.from_string content in
      (try
        let program = Parser.program Lexer.token lexbuf in
        if not (program_has_build_pipeline program) then begin
          Printf.eprintf "Error: non-interactive execution requires a pipeline.\n";
          Printf.eprintf "Use --unsafe to override.\n";
          exit 1
        end
      with _ -> ())
    with _ -> ()
  end;
  let (result, _env) =
    Fun.protect ~finally:(fun () -> if json then Ast.ndjson_mode := false)
      (fun () -> run_file ?failfast mode filename env)
  in
  flush_warnings_to_out ();
  match result with
  | Ast.VError _ ->
      if json then
        exit 1
      else begin
        Printf.eprintf "%s" (Pretty_print.pretty_print_value result);
        exit 1
      end
  | Ast.(VNA NAGeneric) -> ()
  | v ->
      if not json then print_string (Pretty_print.pretty_print_value v)

let cmd_run_expr ?failfast ?(json=false) mode expr env =
  Packages.ensure_docs_loaded ();
  if json then Ast.ndjson_mode := true;
  let (result, _) =
    Fun.protect ~finally:(fun () -> if json then Ast.ndjson_mode := false)
      (fun () -> parse_and_eval ?failfast mode env expr)
  in
  flush_warnings_to_out ();
  match result with
  | Ast.VError _ ->
      if json then
        exit 1
      else begin
        Printf.eprintf "%s" (Pretty_print.pretty_print_value result); exit 1
      end
  | Ast.(VNA NAGeneric) -> ()
  | v ->
      if not json then print_string (Pretty_print.pretty_print_value v)

let check_type_annotations filename =
  try
    let ch = open_in filename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    let lexbuf = Lexing.from_string content in
    lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
    let program = Parser.program Lexer.token lexbuf in
    let scope = Symbol_table.create_scope () in
    Symbol_table.register_keywords scope;
    let _ = Analyzer.analyze program scope in
    let diags = ref [] in
    List.iter (fun (stmt : Ast.stmt) ->
      match stmt.node with
      | Ast.Assignment { name; typ = Some annotation; _ } ->
          let inferred_ast = match Symbol_table.lookup scope name with
            | Some { Symbol_table.typ = Some st; _ } -> Semantic_type.to_ast_typ st
            | _ -> Ast.TCustom "Any"
          in
          if not (Ast.types_compatible inferred_ast annotation) then begin
            let expected = Ast.Utils.typ_to_string annotation in
            let actual = Ast.Utils.typ_to_string inferred_ast in
            let line = match stmt.loc with
              | Some l -> Some l.Ast.line
              | None -> None
            in
            let col = match stmt.loc with
              | Some l -> Some l.Ast.column
              | None -> None
            in
            diags := {
              Diagnostics.diag_id = Diagnostics.gen_id ();
              diag_error_class = Diagnostics.Type_error;
              diag_severity = Warning;
              diag_phase = Schema;
              diag_node_id = None;
              diag_node_lang = None;
              diag_file = Some filename;
              diag_line = line;
              diag_column = col;
              diag_end_line = None;
              diag_end_column = None;
              diag_message = Printf.sprintf
                "Variable `%s` annotated as %s, but expression infers to %s."
                name expected actual;
              diag_expected = Some expected;
              diag_actual = Some actual;
              diag_caused_by = [];
              diag_suggested_fix = Diagnostics.no_fix;
            } :: !diags
          end
      | _ -> ()
    ) program;
    List.rev !diags
  with
  | Lexer.SyntaxError _ ->
    (* Parse/syntax errors are already reported by check_utils normal flow. *)
    []
  | Parser.Error | Ast.Mixed_bracket_form ->
    []
  | exn ->
    Printf.eprintf "Warning: type annotation check unexpected exception: %s\n" (Printexc.to_string exn);
    []

let run_check ?(schema=false) ?(env_check=false) ?(offline=false) mode filename env =
  Packages.ensure_docs_loaded ();
  ensure_file_path filename;
  Check_utils.run_check ~schema ~env_check ~offline mode filename env

let print_check_result ?(json=false) check_result =
  let output = Check_utils.format_check_result ~json check_result in
  if json then
    print_string output
  else
    Printf.eprintf "%s" output

let cmd_check ?(json=false) ?(schema=false) ?(env_check=false) ?(offline=false) mode filename env =
  let check_result = run_check ~schema ~env_check ~offline mode filename env in
  print_check_result ~json check_result;
  exit (Diagnostics.exit_code_of_diagnostics (Diagnostics.check_result_entries check_result))

let cmd_check_watch ?(json=false) ?(schema=false) ?(env_check=false) ?(offline=false) mode filename env =
  let get_mtime path =
    try (Unix.stat path).Unix.st_mtime with Unix.Unix_error _ -> 0.0
  in
  let poll_interval = 0.5 in
  let last_mtime = ref (get_mtime filename) in
  let last_exit_code = ref 0 in
  Printf.eprintf "Watching %s for changes (Ctrl+C to stop)...\n%!" filename;
  (* Initial run *)
  let check_result = run_check ~schema ~env_check ~offline mode filename env in
  print_check_result ~json check_result;
  last_exit_code := Diagnostics.exit_code_of_diagnostics (Diagnostics.check_result_entries check_result);
  let forever = ref true in
  Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ -> forever := false));
  while !forever do
    Unix.sleepf poll_interval;
    let current_mtime = get_mtime filename in
    if current_mtime > !last_mtime then begin
      last_mtime := current_mtime;
      Printf.eprintf "\n--- file changed, re-checking ---\n%!";
      let check_result = run_check ~schema ~env_check ~offline mode filename env in
      print_check_result ~json check_result;
      last_exit_code := Diagnostics.exit_code_of_diagnostics (Diagnostics.check_result_entries check_result)
    end
  done;
  Printf.eprintf "\nStopped watching.\n%!";
  exit !last_exit_code

let cmd_diff ?(json=false) ?(log_a=2) ?(log_b=1) filename env =
  Packages.ensure_docs_loaded ();
  ensure_file_path filename;
  let (result, new_env) =
    Ast.check_mode := true;
    Fun.protect ~finally:(fun () -> Ast.check_mode := false)
      (fun () -> run_file ~failfast:true Typecheck.Strict filename env)
  in
  let pipelines =
    match result with
    | Ast.VPipeline p -> [("pipeline", p)]
    | Ast.VError _ -> []
    | _ ->
        let bindings = Ast.Env.bindings new_env in
        List.filter_map (fun (name, v) ->
          match v with
          | Ast.VPipeline p -> Some (name, p)
          | _ -> None
        ) bindings
  in
  match pipelines with
  | [] ->
      Printf.eprintf "No pipeline found in %s.\n" filename;
      exit 1
  | (_, p) :: _ ->
      let is_default = (log_a = 2 && log_b = 1) in
      if is_default then
        match Builder_diff.find_two_matching_logs p with
        | None ->
            Printf.eprintf "Need at least 2 matching build logs to diff.\n";
            Printf.eprintf "Run build_pipeline(p) at least twice first.\n";
            exit 1
        | Some (path_a, path_b) ->
            (match Builder_diff.compute_diff path_a path_b with
             | Error msg ->
                 Printf.eprintf "Error computing diff: %s\n" msg;
                 exit 1
             | Ok diff_result ->
                 if json then
                   print_string (Yojson.Safe.pretty_to_string (Builder_diff.diff_result_to_yojson diff_result))
                 else
                   Builder_diff.print_diff_result diff_result;
                 exit 0)
      else
        let logs = Builder.get_logs () in
        let try_log log_file =
          let full_path = Filename.concat Builder.pipeline_dir log_file in
          match Builder.read_log full_path with
          | Ok entries when Builder_read_node.pipeline_matches_logged_entries p entries -> Some full_path
          | _ -> None
        in
        let matching = List.filter_map try_log logs in
        let n_matching = List.length matching in
        if n_matching < 2 then begin
          Printf.eprintf "Need at least 2 matching build logs to diff. Found %d.\n" n_matching;
          Printf.eprintf "Run build_pipeline(p) at least twice first.\n";
          exit 1
        end else if log_a < 1 || log_b < 1 then begin
          Printf.eprintf "Invalid rank: --log-a and --log-b must be >= 1 (got --log-a %d --log-b %d).\n" log_a log_b;
          exit 1
        end else if log_a > n_matching || log_b > n_matching then begin
          Printf.eprintf "Requested rank exceeds available builds: --log-a %d --log-b %d but only %d matching builds found.\n" log_a log_b n_matching;
          exit 1
        end else begin
          let path_a = List.nth matching (log_a - 1) in
          let path_b = List.nth matching (log_b - 1) in
          match Builder_diff.compute_diff path_a path_b with
          | Error msg ->
              Printf.eprintf "Error computing diff: %s\n" msg;
              exit 1
          | Ok diff_result ->
              if json then
                print_string (Yojson.Safe.pretty_to_string (Builder_diff.diff_result_to_yojson diff_result))
              else
                Builder_diff.print_diff_result diff_result;
              exit 0
        end

let cmd_debug ?(unsafe=false) ?failfast mode filename node_name env =
  let _ = unsafe in
  Packages.ensure_docs_loaded ();
  ensure_file_path filename;
  let (result, new_env) = run_file ?failfast mode filename env in
  match result with
  | Ast.VError _ ->
      Printf.eprintf "%s" (Pretty_print.pretty_print_value result); exit 1
  | _ ->
      let find_node_by_name node_name env =
        let bindings = Ast.Env.bindings env in
        let rec search_pipelines = function
          | [] -> None
          | (_, Ast.VPipeline p) :: rest ->
              (match List.find_opt (fun (name, _) -> name = node_name) p.p_nodes with
               | Some (_, node_val) ->
                   (match node_val with
                    | Ast.VComputedNode cn -> Some cn
                    | _ -> search_pipelines rest)
               | None -> search_pipelines rest)
          | _ :: rest -> search_pipelines rest
        in
        match Ast.Env.find_opt node_name env with
        | Some (Ast.VComputedNode cn) -> Some cn
        | _ -> search_pipelines bindings
      in
      (match find_node_by_name node_name new_env with
       | Some cn ->
           let debug_func =
             match Ast.Env.find_opt "debug_node" new_env with
             | Some (Ast.VBuiltin b) -> b.b_func
             | _ -> exit_with_error "Function `debug_node` not found in pipeline package."
           in
           let named_args = [(Some "node", Ast.VComputedNode cn)] in
           let env_ref = ref new_env in
           let _ = debug_func named_args env_ref in
           ()
       | None ->
           exit_with_error (Printf.sprintf "Could not find node `%s` in the pipeline defined in '%s'." node_name filename))

let cmd_init_package args =
  match Scaffold.parse_init_flags args with
  | Error _ when args = [] ->
      let opts = Scaffold.interactive_init "" in
      (match Scaffold.scaffold_package opts with
      | Ok () -> Printf.printf "Package initialized successfully.\n"
      | Error e -> Printf.eprintf "Error: %s\n" e; exit 1)
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
  | Ok opts ->
      let opts = if opts.interactive then Scaffold.interactive_init opts.target_name else opts in
      match Scaffold.scaffold_package opts with
      | Ok () -> Printf.printf "Package initialized successfully.\n"
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let cmd_init_project args =
  match Scaffold.parse_init_flags args with
  | Error _ when args = [] ->
      let opts = Scaffold.interactive_init ~placeholder:"my_project" "" in
      (match Scaffold.scaffold_project opts with
      | Ok () -> Printf.printf "Project initialized successfully.\n"
      | Error e -> Printf.eprintf "Error: %s\n" e; exit 1)
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
  | Ok opts ->
      let opts = if opts.interactive then Scaffold.interactive_init ~placeholder:"my_project" opts.target_name else opts in
      match Scaffold.scaffold_project opts with
      | Ok () -> Printf.printf "Project initialized successfully.\n"
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let cmd_explain ?failfast mode rest env =
  Packages.ensure_docs_loaded ();
  let json = List.mem "--json" rest in
  let has_node = List.mem "--node" rest in
  let rec get_node_arg = function
    | [] -> None
    | "--node" :: v :: _ -> Some v
    | _ :: xs -> get_node_arg xs
  in
  let node_arg_opt = get_node_arg rest in
  if has_node && node_arg_opt = None then begin
    Printf.eprintf "Usage: t explain --node <pipeline_var>.<node_name> [pipeline.t]\n";
    exit 1
  end;
  match node_arg_opt with
  | Some node_arg ->
      let pipeline_var, node_name =
        match String.split_on_char '.' node_arg with
        | [v; n] when v <> "" && n <> "" -> (v, n)
        | _ -> Printf.eprintf "Error: Invalid --node format. Expected <pipeline_var>.<node_name>.\n"; exit 1
      in
      let remaining = List.filter (fun s -> s <> "--json" && s <> "--node" && s <> node_arg) rest in
      let filename =
        match remaining with
        | [] -> "src/pipeline.t"
        | [f] -> f
        | _ -> Printf.eprintf "Usage: t explain --node <pipeline_var>.<node_name> [pipeline.t]\n"; exit 1
      in
      if not (Sys.file_exists filename) then begin
        Printf.eprintf "Error: File '%s' not found.\n" filename;
        exit 1
      end;
      let old_check_mode = !Ast.check_mode in
      Ast.check_mode := true;
      (try
         let (_, env_val) = Check_utils.run_file ?failfast mode filename env in
         Ast.check_mode := old_check_mode;
         let pipeline_opt =
           match Ast.Env.find_opt pipeline_var env_val with
           | Some (Ast.VPipeline p) -> Some p
           | _ -> None
         in
         match pipeline_opt with
         | None ->
             Printf.eprintf "Error: Pipeline variable '%s' not found or is not a Pipeline.\n" pipeline_var;
             exit 1
         | Some p ->
             let diagnostics_map = Builder_read_node.merge_pipeline_node_diagnostics_with_latest_log p in
             match List.assoc_opt node_name diagnostics_map with
             | None ->
                 Printf.eprintf "Error: Node '%s' not found in the pipeline.\n" node_name;
                 exit 1
             | Some d ->
                 if json then begin
                   let fields = ref [
                     ("pipeline", `String pipeline_var);
                     ("node", `String node_name);
                   ] in
                   (match d.nd_error with
                    | Some err ->
                        fields := !fields @ [
                          ("status", `String "failed");
                          ("error_code", `String err.ne_kind);
                          ("message", `String err.ne_message);
                        ];
                        if err.ne_fn <> "" then
                          fields := !fields @ [("function", `String err.ne_fn)]
                    | None ->
                        fields := !fields @ [("status", `String "success")]);
                   let warnings_json =
                     List.map (fun w ->
                       `Assoc [
                         ("code", `String w.Ast.nw_kind);
                         ("message", `String w.Ast.nw_message);
                       ]
                     ) d.nd_warnings
                   in
                   fields := !fields @ [("warnings", `List warnings_json)];
                   let json_obj = `Assoc !fields in
                   print_endline (Yojson.Safe.pretty_to_string json_obj)
                 end else begin
                   let has_output = ref false in
                   (match d.nd_error with
                    | Some err ->
                        has_output := true;
                        Printf.printf "Node '%s' failed:\n" node_name;
                        Printf.printf "  Error Code: %s\n" err.ne_kind;
                        Printf.printf "  Message: %s\n" err.ne_message;
                        if err.ne_fn <> "" then Printf.printf "  Function: %s\n" err.ne_fn
                    | None -> ());
                   if d.nd_warnings <> [] then begin
                     has_output := true;
                     Printf.printf "Node '%s' has warning(s):\n" node_name;
                     List.iter (fun w ->
                       Printf.printf "  - [%s] %s\n" w.Ast.nw_kind w.Ast.nw_message
                     ) d.nd_warnings
                   end;
                   if not !has_output then
                     Printf.printf "Node '%s' compiled/built successfully with no errors or warnings.\n" node_name
                 end
       with e ->
         Ast.check_mode := old_check_mode;
         Printf.eprintf "Error loading '%s': %s\n" filename (Printexc.to_string e);
         exit 1)
  | None ->
      let expr_str = String.concat " " (List.filter (fun s -> s <> "--json") rest) in
      if expr_str = "" then (Printf.eprintf "Usage: t explain <expr> | t explain --node <pipeline_var>.<node_name> [pipeline.t]\n"; exit 1)
      else begin
        let (result, env') = parse_and_eval ?failfast mode env expr_str in
        let explain_expr = "explain(__explain_target__)" in
        let env'' = Ast.Env.add "__explain_target__" result env' in
        let (explain_result, _) = parse_and_eval ?failfast mode env'' explain_expr in
        print_string (Pretty_print.pretty_print_value explain_result)
      end

let cmd_test args =
  let cwd = Sys.getcwd () in
  let opts =
    match Cli_args.parse_test_args ~cwd args with
    | Ok opts -> opts
    | Error msg -> exit_with_error msg
  in
  (match Cli_args.validate_path ~kind:Cli_args.Directory opts.target_dir with
   | Ok () -> ()
   | Error msg -> exit_with_error msg);
  if opts.coverage then begin
    print_endline "Cleaning old coverage data...";
    let target_q = Filename.quote opts.target_dir in
    let cwd_q = Filename.quote cwd in
    let cmd =
      if opts.target_dir <> cwd then
        Printf.sprintf "find %s %s -name '*.coverage' -delete 2>/dev/null" target_q cwd_q
      else
        Printf.sprintf "find %s -name '*.coverage' -delete 2>/dev/null" target_q
    in
    let _ = Sys.command cmd in
    ()
  end;
  if opts.list_only then begin
    let test_dir = Filename.concat opts.target_dir "tests" in
    if not (Sys.file_exists test_dir && Sys.is_directory test_dir) then
      print_endline "No tests/ directory found."
    else begin
      let ignore_patterns = Test_discovery.read_tignore test_dir in
      let files = Test_discovery.discover_tests ~ignore_patterns test_dir in
      let files =
        if opts.only_patterns <> [] then
          List.filter (fun f -> Test_discovery.matches_any_pattern opts.target_dir f opts.only_patterns) files
        else files
      in
      let files =
        if opts.not_patterns <> [] then
          List.filter (fun f -> not (Test_discovery.matches_any_pattern opts.target_dir f opts.not_patterns)) files
        else files
      in
      List.iter (fun f ->
        print_endline (Test_discovery.relative_path opts.target_dir f)
      ) files
    end
  end else begin
    let quiet = opts.format <> Human in
    let suite_result =
      Test_discovery.run_suite ~verbose:opts.verbose ~quiet
        ~only:opts.only_patterns ~not_:opts.not_patterns
        ~failfast:opts.failfast ~timeout:opts.timeout
        opts.target_dir
    in
    (match opts.format with
     | Human -> ()
     | Json ->
         let json = Test_discovery.suite_result_to_yojson suite_result in
         print_endline (Yojson.Safe.pretty_to_string json)
     | Junit ->
         let xml = Test_discovery.suite_result_to_xml suite_result in
         print_endline xml);
    if opts.coverage then begin
      let find_coverage_files dir =
        if Sys.file_exists dir && Sys.is_directory dir then
          Array.to_list (Sys.readdir dir)
          |> List.filter (fun f -> Filename.check_suffix f ".coverage")
        else []
      in
      let coverage_files =
        find_coverage_files opts.target_dir @
        (if opts.target_dir <> cwd then find_coverage_files cwd else [])
      in
      if coverage_files = [] then
        print_endline "\nNo coverage data found. Build with `nix build .#t-coverage` first,\nor run `dune build --instrument-with bisect_ppx` for a local build."
      else begin
        print_endline "\nCoverage summary:";
        let cmd = "bisect-ppx-report summary 2>&1" in
        let ic = Unix.open_process_in cmd in
        let buf = Buffer.create 256 in
        (try
           while true do
             Buffer.add_char buf (input_char ic)
           done
         with End_of_file -> ());
        let _ = Unix.close_process_in ic in
        print_string (Buffer.contents buf)
      end
    end;
    if suite_result.failed > 0 then exit 1
  end

let cmd_doctor () = Package_doctor.run_doctor ()

let cmd_publish () =
  let dir = Sys.getcwd () in
  let tag_and_push v =
    match Release_manager.validate_tests_pass () with
    | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
    | Ok () ->
        match Release_manager.create_git_tag v with
        | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
        | Ok tag ->
            match Release_manager.push_git_tag tag with
            | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
            | Ok () -> Printf.printf "Successfully published %s\n" tag
  in
  match Release_manager.get_package_version dir with
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
  | Ok v ->
      Printf.printf "Publishing v%s...\n" v;
      match Release_manager.validate_version_format v with
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
      | Ok () ->
          match Release_manager.validate_clean_git () with
          | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
          | Ok () ->
              match Release_manager.validate_git_remote () with
              | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
              | Ok () ->
                  (match Release_manager.validate_changelog dir v with
                   | Error msg -> Printf.eprintf "Warning: %s\n" msg
                   | Ok () -> ());
                  tag_and_push v

let cmd_docs () = Documentation_manager.open_docs (Sys.getcwd ())

let rec mkdir_p path =
  if not (Sys.file_exists path) then begin
    let parent = Filename.dirname path in
    if parent <> path && parent <> "." && parent <> "/" then mkdir_p parent;
    (try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
  end

let recursive_files dir =
  let rec walk acc d =
    let entries = try Sys.readdir d with _ -> [||] in
    Array.fold_left (fun acc e ->
      let p = Filename.concat d e in
      if Sys.is_directory p then walk acc p
      else if Filename.check_suffix e ".ml" || Filename.check_suffix e ".t" then p :: acc
      else acc
    ) acc entries
  in walk [] dir

let cmd_doc args =
  let do_parse = List.mem "--parse" args || args = [] in
  let do_gen = List.mem "--generate" args || args = [] in
  let dir = Sys.getcwd () in
  let src_dir = Filename.concat dir "src" in
  if do_parse then begin
    List.iter (fun f -> List.iter Tdoc_registry.register (Tdoc_parser.parse_file f)) (recursive_files src_dir);
    let help_dir = Filename.concat dir "help" in
    mkdir_p help_dir;
    Tdoc_registry.to_json_file (Filename.concat help_dir "docs.json")
  end;
  if do_gen then begin
    let out_dir = Filename.concat dir "docs/reference" in
    mkdir_p out_dir;
    List.iter (fun e ->
      let ch = open_out (Filename.concat out_dir (e.Tdoc_types.name ^ ".md")) in
      output_string ch (Tdoc_markdown.generate_function_doc e); close_out ch
    ) (Tdoc_registry.get_all ())
  end

let cmd_update () =
  match Update_manager.update_flake_lock () with
  | Ok () -> Printf.printf "Updated.\n"
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let cmd_add args =
  let usage () =
    Printf.eprintf "Usage: t add <runtime> <package>\n";
    Printf.eprintf "  <runtime>  R, Python, or Julia\n";
    Printf.eprintf "  <package>  Package name to add to tproject.toml\n";
    exit 1
  in
  let has_flag s = String.length s > 2 && s.[0] = '-' && s.[1] = '-' in
  let positional = List.filter (fun s -> not (has_flag s)) args in
  (match positional with
   | [runtime; pkg] ->
       let dir = Sys.getcwd () in
       let tproject_path = Filename.concat dir "tproject.toml" in
       if not (Sys.file_exists tproject_path) then begin
         Printf.eprintf "Error: tproject.toml not found. Run 't init --project <name>' first.\n";
         exit 1
       end;
       let read_file path =
         try
           let ch = open_in path in
           Fun.protect ~finally:(fun () -> close_in_noerr ch)
             (fun () -> Ok (really_input_string ch (in_channel_length ch)))
         with Sys_error msg -> Error msg
       in
       let write_file path content =
         try
           let oc = open_out path in
           Fun.protect ~finally:(fun () -> close_out_noerr oc)
             (fun () -> output_string oc content; Ok ())
         with Sys_error msg -> Error msg
       in
       let cfg_result =
         match read_file tproject_path with
         | Error msg -> Error (Printf.sprintf "Cannot read tproject.toml: %s" msg)
         | Ok content ->
             (match Toml_parser.parse_tproject_toml ~root_dir:dir content with
             | Error msg -> Error (Printf.sprintf "Cannot parse tproject.toml: %s" msg)
             | Ok cfg -> Ok cfg)
       in
       (match cfg_result with
        | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
        | Ok cfg ->
            let (runtime_key, list_getter, list_setter) =
              match String.lowercase_ascii runtime with
              | "r" -> ("[r-dependencies]",
                        (fun c -> c.Package_types.proj_r_dependencies),
                        (fun pkg c -> { c with Package_types.proj_r_dependencies = c.Package_types.proj_r_dependencies @ [pkg] }))
              | "python" | "py" -> ("[py-dependencies]",
                                    (fun c -> c.Package_types.proj_py_dependencies),
                                    (fun pkg c -> { c with Package_types.proj_py_dependencies = c.Package_types.proj_py_dependencies @ [pkg] }))
              | "julia" | "jl" -> ("[jl-dependencies]",
                                   (fun c -> c.Package_types.proj_julia_dependencies),
                                   (fun pkg c -> { c with Package_types.proj_julia_dependencies = c.Package_types.proj_julia_dependencies @ [pkg] }))
              | "tool" -> ("[additional-tools]",
                           (fun c -> c.Package_types.proj_additional_tools),
                           (fun pkg c -> { c with Package_types.proj_additional_tools = c.Package_types.proj_additional_tools @ [pkg] }))
              | "latex" -> ("[latex]",
                            (fun c -> c.Package_types.proj_latex_packages),
                            (fun pkg c -> { c with Package_types.proj_latex_packages = c.Package_types.proj_latex_packages @ [pkg] }))
              | _ ->
                  Printf.eprintf "Error: Unknown runtime '%s'. Use R, Python, Julia, tool, or latex.\n" runtime;
                  exit 1
            in
            let existing = list_getter cfg in
            if List.mem pkg existing then
              Printf.printf "'%s' is already declared in %s.\n" pkg runtime_key
            else begin
              let new_cfg = list_setter pkg cfg in
              let new_content = Toml_parser.serialize_tproject_toml new_cfg in
              match write_file tproject_path new_content with
              | Error msg -> Printf.eprintf "Error writing tproject.toml: %s\n" msg; exit 1
              | Ok () ->
                  Printf.printf "'%s' added to %s in tproject.toml.\nRun 't update' to sync flake.nix.\n" pkg runtime_key
            end)
   | _ -> usage ())

let cmd_upgrade () =
  match Update_manager.cmd_upgrade () with
  | Ok () -> Printf.printf "Upgrade successful.\n"
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let get_nix_version () =
  try
    let ch = Unix.open_process_in "nix --version" in
    let line_result =
      try `Line (input_line ch)
      with
      | End_of_file -> `No_line
      | exn -> `Read_error exn
    in
    let close_result =
      try `Status (Unix.close_process_in ch)
      with exn -> `Close_error exn
    in
    match (line_result, close_result) with
    | (`Line line, `Status (Unix.WEXITED 0)) ->
        let parts = String.split_on_char ' ' line in
        let rec last = function [] -> "" | [x] -> x | _ :: xs -> last xs in
        last parts
    | (`Read_error exn, _) -> raise exn
    | _ -> "unknown"
  with _ -> "unknown"

(* --- Atelier TUI Variable Watcher Helper --- *)

let base_keys_ref = ref None

let write_vars_csv env =
  match Sys.getenv_opt "ATELIER_ACTIVE" with
  | Some "1" ->
      let root = Builder_utils.get_atelier_project_root () in
      Builder_utils.ensure_atelier_dir root;
      let tmp_path = Builder_utils.atelier_vars_tmp_path root in
      let final_path = Builder_utils.atelier_vars_path root in
      begin try
        let oc = open_out tmp_path in
        Fun.protect
          ~finally:(fun () -> close_out_noerr oc)
          (fun () ->
            output_string oc "name,type,value\n";
            Ast.Env.iter (fun name value ->
              let should_show =
                match value with
                | Ast.VBuiltin _ -> false
                | Ast.VLambda _ -> false
                | _ ->
                    if String.length name >= 2 && String.sub name 0 2 = "__" then false
                    else
                      match !base_keys_ref with
                      | Some bk -> not (Hashtbl.mem bk name)
                      | None -> true
              in
              if should_show then begin
                let val_str = Ast.Utils.value_to_string value in
                let val_type =
                  match value with
                  | Ast.VInt _ -> "Int"
                  | Ast.VFloat _ -> "Float"
                  | Ast.VBool _ -> "Bool"
                  | Ast.VString _ -> "String"
                  | Ast.VDataFrame _ -> "DataFrame"
                  | Ast.VList _ -> "List"
                  | Ast.VDict _ -> "Dict"
                  | Ast.VVector _ -> "Vector"
                  | Ast.VNA _ -> "NA"
                  | Ast.VError _ -> "Error"
                  | Ast.VDate _ -> "Date"
                  | Ast.VDatetime _ -> "Datetime"
                  | Ast.VFactor _ -> "Factor"
                  | Ast.VPeriod _ -> "Period"
                  | Ast.VDuration _ -> "Duration"
                  | Ast.VInterval _ -> "Interval"
                  | Ast.VFormula _ -> "Formula"
                  | Ast.VPipeline _ -> "Pipeline"
                  | Ast.VMetaPipeline _ -> "MetaPipeline"
                  | Ast.VComputedNode _ -> "ComputedNode"
                  | Ast.VNode _ -> "Node"
                  | Ast.VQuo _ -> "Quo"
                  | Ast.VLambda _ -> "Lambda"
                  | Ast.VBuiltin _ -> "Builtin"
                  | Ast.VRawCode _ -> "RawCode"
                  | Ast.VSymbol _ -> "Symbol"
                  | Ast.VIntent _ -> "Intent"
                  | _ -> "Unknown"
                in
                let escape s =
                  let s = String.concat "\\n" (String.split_on_char '\n' s) in
                  let escaped = String.concat "\"\"" (String.split_on_char '"' s) in
                  "\"" ^ escaped ^ "\""
                in
                Printf.fprintf oc "%s,%s,%s\n" (escape name) (escape val_type) (escape val_str)
              end
            ) env
          );
        Sys.rename tmp_path final_path
      with _ ->
        begin try Sys.remove tmp_path with _ -> () end
      end
  | _ -> ()

let cmd_repl ?failfast mode env =
  Packages.ensure_docs_loaded ();
  
  (* Track base environment keys to filter %objects *)
  let base_keys = Hashtbl.create 200 in
  Ast.Env.iter (fun k _ -> Hashtbl.add base_keys k ()) env;
  base_keys_ref := Some base_keys;
  base_env_ref := env;

  let nix_version = get_nix_version () in
  Printf.printf "T, a reproducibility-first orchestration engine for polyglot\n";
  Printf.printf "data science and statistical analysis.\n";
  Printf.printf "Version %s \"%s\" using Nix %s\n" version codename nix_version;
  Printf.printf "Licensed under the EUPL v1.2. No warranties.\n";
  Printf.printf "This software is in beta and is entirely LLM-generated — caveat emptor.\n";
  Printf.printf "Website: https://tstats-project.org\n";
  Printf.printf "Contributions are welcome!\n";
  Printf.printf "Type :quit or :q to exit, :help for commands.\n\n";
  Printf.printf "%s\n\n" (Import_registry.startup_rename_warning_message ());


  let scope = Symbol_table.create_scope () in
  Symbol_table.register_keywords scope;
  Symbol_table.populate_from_env scope env;

  LNoise.set_multiline true;
  LNoise.set_completion_callback (fun buffer completions ->
    let (start_pos, matches) = Completion.complete scope ~buffer ~cursor:(String.length buffer) in
    let prefix = String.sub buffer 0 start_pos in
    List.iter (fun m -> LNoise.add_completion completions (prefix ^ m)) matches
  );

  LNoise.set_hints_callback (fun buffer ->
    let cursor = String.length buffer in
    if cursor = 0 then None
    else
      let (start_pos, matches) = Completion.complete scope ~buffer ~cursor in
      match matches with
      | m :: _ ->
          let overlap = cursor - start_pos in
          if String.length m > overlap then
             let hint = String.sub m overlap (String.length m - overlap) in
             Some (hint, LNoise.White, false)
          else None
      | [] -> None
  );

  flush stdout;
  let is_tty = Unix.isatty Unix.stdin in
  let read_input prompt =
    if is_tty then LNoise.linenoise prompt
    else begin
      if prompt <> "" then Printf.printf "%s%!" prompt;
      try Some (input_line stdin) with End_of_file -> None
    end
  in

  let rec repl ?failfast env show_prompt =
    let prompt = if show_prompt then "T> " else "" in
    try
      match read_input prompt with
      | None ->
          if is_tty then print_endline "\nGoodbye."
      | Some line ->
          (* Handle TAB completion trigger for dumb terminals, but only if it's not part of valid code *)
          if String.contains line '\t' && String.trim line = "" then begin
            let tab_pos = String.index line '\t' in
            let prefix = String.sub line 0 tab_pos in
            let cursor = String.length prefix in
            let (_, matches) = Completion.complete scope ~buffer:prefix ~cursor in
            if matches = [] then
              Printf.printf "No completions.\n"
            else
              List.iter (fun m -> Printf.printf "%s\n" m) matches;
            flush stdout;
            repl env true
          end
          else
          let trimmed = String.trim line in
          if trimmed = "" then repl env true
          else begin
            if trimmed = ":quit" || trimmed = ":q" then
              print_endline "Exiting T REPL."
            else if trimmed = ":help" || trimmed = ":h" then begin
            Printf.printf "T language REPL commands:\n";
            Printf.printf "  :quit, :q     Exit the REPL\n";
            Printf.printf "  :help, :h     Show this help message\n";
            Printf.printf "  :version      Show T language and Nix versions\n";
            Printf.printf "  :packages     List all currently loaded packages\n\n";
            
            Printf.printf "Magic Commands:\n";
            print_magic_commands ();
            print_newline ();
 
            Printf.printf "Resources:\n";
            Printf.printf "  Website:      https://tstats-project.org/\n";
            Printf.printf "  Bugs/Issues:  https://github.com/b-rodrigues/tlang/issues\n\n";
 
            Printf.printf "Multi-line input:\n";
            Printf.printf "  Expressions with unclosed (, [, { or trailing |> automatically continue on the next line.\n\n";
            flush stdout;
            repl env true
            end
            else if trimmed = ":version" then begin
            Printf.printf "T language version %s\n" version;
            flush stdout;
            repl env true
            end
            else if trimmed = ":packages" then begin
            List.iter (fun (pkg : Packages.package_info) ->
              Printf.printf "  %-12s  %s\n" pkg.name pkg.description
            ) Packages.all_packages;
            print_newline ();
            flush stdout;
            repl env true
            end
            else if String.length trimmed > 10 && String.sub trimmed 0 10 = ":complete " then begin
              let arg = String.trim (String.sub trimmed 10 (String.length trimmed - 10)) in
              let cursor = String.length arg in
              let (_start_pos, matches) = Completion.complete scope ~buffer:arg ~cursor in
              Printf.printf "\n:BEGIN_COMPLETIONS:\n";
              List.iter (fun m -> Printf.printf "%s\n" m) matches;
              Printf.printf ":END_COMPLETIONS:\n";
              flush stdout;
              repl env true
            end
            else if String.length trimmed > 0 && trimmed.[0] = '%' then begin
            let (new_env, output_opt, handled) = handle_magic trimmed env mode base_keys in
            if handled then (
              (match output_opt with
               | Some out ->
                   Printf.printf "%s" out;
                   flush stdout;
                   session_transcript := MagicEntry (trimmed, out) :: !session_transcript
               | None -> ());
              write_vars_csv new_env;
              if is_tty then (
                ignore (LNoise.history_add line);
                ignore (LNoise.history_save ~filename:history_file)
              );
              repl new_env true
            ) else repl env true
            end
            else begin
            (* Multi-line input: accumulate lines while expression is incomplete *)
            let rec read_multiline acc =
              let combined = acc in
              if is_incomplete combined then begin
                try
                  match read_input ".. " with
                  | None ->
                      combined  (* Return what we have *)
                  | Some next_line ->
                      (* If the previous line ends with |> or ?|>, move it to the start of
                         the next line so the lexer recognizes the continuation *)
                      let trimmed_acc = String.trim combined in
                      let len = String.length trimmed_acc in
                      if len >= 3 && String.sub trimmed_acc (len - 3) 3 = "?|>" then
                        let prefix = String.sub combined 0 (String.length combined - 3) in
                        read_multiline (String.trim prefix ^ "\n  ?|> " ^ next_line)
                      else if len >= 2 && String.sub trimmed_acc (len - 2) 2 = "|>" then
                        let prefix = String.sub combined 0 (String.length combined - 2) in
                        read_multiline (String.trim prefix ^ "\n  |> " ^ next_line)
                      else
                        read_multiline (combined ^ "\n" ^ next_line)
                with
                | Sys.Break ->
                    raise Sys.Break
              end else
                combined
            in
            let full_input = read_multiline trimmed in
            if is_tty then (
              ignore (LNoise.history_add full_input);
              ignore (LNoise.history_save ~filename:history_file)
            );
            let (result, new_env) = parse_and_eval ?failfast mode env full_input in
            write_vars_csv new_env;
            Symbol_table.populate_from_env scope new_env;
            repl_display_value result;
            session_transcript := EvalEntry (full_input, result) :: !session_transcript;
            repl ?failfast new_env true
            end
          end
    with
    | Sys.Break ->
        print_endline "Interrupted.";
        repl ?failfast env true
  in
  repl ?failfast env true

(* --- Entry Point --- *)

let () =
  Sys.catch_break true;
  let raw_args = Array.to_list Sys.argv in
  let mode_parse =
    match Cli_args.parse_mode_args raw_args with
    | Ok parsed -> parsed
    | Error msg -> Printf.eprintf "%s\n" msg; exit 1
  in
  let unsafe = List.mem "--unsafe" raw_args in
  let failfast = mode_parse.failfast in
  let args = if unsafe then List.filter (fun s -> s <> "--unsafe") mode_parse.args else mode_parse.args in
  let args = if failfast then List.filter (fun s -> s <> "--failfast") args else args in
  (match Cli_args.validate_cli_flags ~mode_flag:mode_parse.mode_flag ~unsafe_flag:unsafe ~failfast_flag:failfast args with
   | Ok () -> ()
   | Error msg -> exit_with_error msg);
  let env = Packages.init_env () in
  Check_utils.extra_diagnostics_hook := check_type_annotations;
  (* Register interactive CLI wrappers — must be here (not in packages.ml)
     to avoid dependency cycles with Test_discovery *)
(*
--# Run a T script
--#
--# Evaluates a T script file and imports its definitions into the current environment.
--# Useful for interactive development to reload module files.
--#
--# @name t_run
--# @param filename :: String The path to the T file to execute.
--# @param failfast :: Bool Whether to fail on error (defaults to false).
--# @return :: Null
--# @example
--#   t_run("src/my_script.t")
--# @family repl
--# @export
*)
  let env = Ast.Env.add "t_run"
    (Ast.VBuiltin { b_name = Some "t_run"; b_arity = 1; b_variadic = false;
      b_func = (fun named_args env_ref ->
        let f_filename = ref None in
        let f_failfast = ref false in
        List.iter (fun (k, v) ->
          match k, v with
          | Some "filename", Ast.VString s -> f_filename := Some s
          | None, Ast.VString s -> f_filename := Some s
          | Some "failfast", Ast.VBool b -> f_failfast := b
          | _ -> ()
        ) named_args;
        match !f_filename with
        | Some filename ->
            (try
              let ch = open_in filename in
              let content = really_input_string ch (in_channel_length ch) in
              close_in ch;
              let lexbuf = Lexing.from_string content in
                (try
                 let program = Parser.program Lexer.token lexbuf in
                 let eval_env = Pipeline_script.reload_env_for_pipeline_entry ~filename program !env_ref in
                 let (v, new_env) = Eval.eval_program ~resilient:(not !f_failfast) program eval_env in
                 (match v with
                  | Ast.VError _ -> v
                  | _ ->
                     env_ref := Pipeline_script.remember_pipeline_entry_bindings ~filename program new_env;
                     Printf.printf "Ran %s successfully.\n" filename; flush stdout; Ast.(VNA NAGeneric))
               with
               | Lexer.SyntaxError msg ->
                   let pos = Lexing.lexeme_start_p lexbuf in
                   make_located_error ~file:filename Ast.SyntaxError ("Syntax error in '" ^ filename ^ "': " ^ msg) pos
               | Parser.Error ->
                   let pos = Lexing.lexeme_start_p lexbuf in
                   make_located_error ~file:filename Ast.SyntaxError (Printf.sprintf "Parse error in '%s'" filename) pos
               | Ast.Mixed_bracket_form ->
                   let pos = Lexing.lexeme_start_p lexbuf in
                   make_located_error ~file:filename Ast.SyntaxError "Mixed bracket literal (found both single elements and key-value pairs)" pos
               | Ast.Invalid_match_pattern msg ->
                   let pos = Lexing.lexeme_start_p lexbuf in
                   make_located_error ~file:filename Ast.SyntaxError msg pos
               | Sys.Break ->
                   interrupt_error ())
             with
             | Sys_error msg ->
                 Ast.VError { code = Ast.FileError; message = Printf.sprintf "t_run failed: %s" msg; context = []; location = None; na_count = 0 })
        | _ -> Ast.VError { code = Ast.TypeError; message = "t_run expects a file path string."; context = []; location = None; na_count = 0 })
    })
    env
  in
  let env = Ast.Env.add "tui_update"
    (Ast.VBuiltin { b_name = Some "tui_update"; b_arity = 0; b_variadic = false;
      b_func = (fun _named_args env_ref ->
        write_vars_csv !env_ref;
        Ast.(VNA NAGeneric))
    })
    env
  in
(*
--# Build Pipeline Internally
--#
--# Builds the `src/pipeline.t` pipeline entrypoint.
--#
--# @name t_make
--# @param filename :: String (Optional) The pipeline build script path. Must be `src/pipeline.t`.
--# @family repl
--# @export
*)
  let env = T_make_mod.register env in
(*
--# Run tests
--#
--# Runs the test suite for the current package and returns a DataFrame with results.
--# Wraps the CLI `t test` command for use within the REPL.
--#
--# @name t_test
--# @param only :: List = [] Filter to tests whose path contains any of these substrings.
--# @param not :: List = [] Exclude tests whose path contains any of these substrings.
--# @return :: DataFrame A DataFrame with columns: file, status, duration_ms, error.
--# @example
--#   results = t_test()
--#   results |> filter($status == "failed")
--#   results = t_test(only = ["arithmetic"])
--#   results = t_test(not = ["slow"])
--# @family repl
--# @export
*)
  let env = Ast.Env.add "t_test"
    (Ast.VBuiltin { b_name = Some "t_test"; b_arity = 0; b_variadic = true;
      b_func = (fun named_args _env_ref ->
        let only = ref [] in
        let not_ = ref [] in
        List.iter (fun (k, v) ->
          match k with
          | Some ("only" | "not") ->
              let lst = match v with
                | Ast.VList lst -> List.filter_map (fun (_, v) ->
                    match v with Ast.VString s -> Some s | _ -> None) lst
                | Ast.VString s -> [s]
                | _ -> []
              in
              if k = Some "not" then not_ := lst else only := lst
          | _ -> ()
        ) named_args;
        let dir = Sys.getcwd () in
        let suite_result = Test_discovery.run_suite ~verbose:false ~quiet:true
          ~only:!only ~not_:!not_ dir in
        let results_arr = Array.of_list suite_result.results in
        let n = Array.length results_arr in
        if n = 0 then begin
          Printf.printf "No test files found.\n";
          flush stdout;
          Ast.VDataFrame { arrow_table = Arrow_table.empty; group_keys = [] }
        end else begin
          let files = Array.init n (fun i ->
            Ast.VString results_arr.(i).file
          ) in
          let statuses = Array.init n (fun i ->
            Ast.VString (if results_arr.(i).success then "passed" else "failed")
          ) in
          let durations = Array.init n (fun i ->
            Ast.VFloat (results_arr.(i).duration *. 1000.0)
          ) in
          let errors = Array.init n (fun i ->
            match results_arr.(i).error_msg with
            | Some msg -> Ast.VString msg
            | None -> Ast.VNA NAGeneric
          ) in
          let columns = [
            ("file", files);
            ("status", statuses);
            ("duration_ms", durations);
            ("error", errors);
          ] in
          (match Arrow_bridge.table_from_value_columns columns n with
           | Ok arrow_table -> begin
               Printf.printf "Ran %d test(s): %d passed, %d failed.\n"
                 suite_result.total suite_result.passed suite_result.failed;
               flush stdout;
               Ast.VDataFrame { arrow_table; group_keys = [] }
           end
           | Error err -> err)
        end)
    })
    env
  in
(*
--# Generate Documentation
--#
--# Documentation tools. Call with "parse" to extract docs from `src/`,
--# or "generate" to output markdown files to `docs/reference/`.
--#
--# @name t_doc
--# @param command :: String Either "parse" or "generate".
--# @return :: Null
--# @example
--#   t_doc("parse")
--#   t_doc("generate")
--# @family repl
--# @export
*)
  let env = Ast.Env.add "t_doc"
    (Ast.VBuiltin { b_name = Some "t_doc"; b_arity = 1; b_variadic = false;
      b_func = (fun named_args _env_ref ->
        match List.map snd named_args with
        | [Ast.VString "parse"] ->
            let dir = Sys.getcwd () in
            let src_dir = Filename.concat dir "src" in
            Printf.printf "Parsing documentation from %s...\n" src_dir;
            let files = recursive_files src_dir in
            List.iter (fun f ->
              let docs = Tdoc_parser.parse_file f in
              List.iter Tdoc_registry.register docs
            ) files;
            let help_dir = Filename.concat dir "help" in
            if not (Sys.file_exists help_dir) then Unix.mkdir help_dir 0o755;
            Tdoc_registry.to_json_file (Filename.concat help_dir "docs.json");
            Printf.printf "Parsed %d functions.\n" (List.length (Tdoc_registry.get_all ()));
            flush stdout;
            Ast.(VNA NAGeneric)
        | [Ast.VString "generate"] ->
            let dir = Sys.getcwd () in
            Printf.printf "Generating Markdown in docs/reference...\n";
            let ensure_dir path =
              if Sys.file_exists path then
                (if not (Sys.is_directory path) then
                  Error (Printf.sprintf "%s exists and is not a directory" path)
                else Ok ())
              else
                (try Unix.mkdir path 0o755; Ok () with Unix.Unix_error (e, _, _) -> Error (Unix.error_message e))
            in
            let docs_dir = Filename.concat dir "docs" in
            (match ensure_dir docs_dir with Error msg -> Ast.VError { code = Ast.FileError; message = msg; context = []; location = None; na_count = 0 } | Ok () ->
            let out_dir = Filename.concat docs_dir "reference" in
            (match ensure_dir out_dir with Error msg -> Ast.VError { code = Ast.FileError; message = msg; context = []; location = None; na_count = 0 } | Ok () ->
            let entries = Tdoc_registry.get_all () in
            List.iter (fun (e : Tdoc_types.doc_entry) ->
              if e.is_export then begin
                let content = Tdoc_markdown.generate_function_doc e in
                let path = Filename.concat out_dir (e.name ^ ".md") in
                let ch = open_out path in
                output_string ch content;
                close_out ch
              end
            ) entries;
            let index_content = Tdoc_markdown.generate_index entries in
            let ch = open_out (Filename.concat out_dir "index.md") in
            output_string ch index_content;
            close_out ch;
            Printf.printf "Documentation generated in %s\n" out_dir;
            flush stdout;
            Ast.(VNA NAGeneric)))
        | [Ast.VString other] ->
            Ast.VError { code = Ast.ValueError; message = Printf.sprintf "t_doc expects \"parse\" or \"generate\", got \"%s\"." other; context = []; location = None; na_count = 0 }
        | _ -> Ast.VError { code = Ast.TypeError; message = "t_doc expects a string argument: \"parse\" or \"generate\"."; context = []; location = None; na_count = 0 })
    })
    env
  in

  match args with
  | _ :: "debug" :: [] ->
      Printf.eprintf "Usage: t debug <node_name> | t debug <file.t> <node_name>\n";
      exit 1
  | _ :: "debug" :: node_name :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_debug ~unsafe ~failfast script_mode "src/pipeline.t" node_name env
  | _ :: "debug" :: filename :: node_name :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_debug ~unsafe ~failfast script_mode filename node_name env
  | _ :: "run" :: [] ->
      Printf.eprintf "Usage: t run [--json] <file.t> | t run [--json] --expr <expr>\n";
      exit 1
  | _ :: "run" :: "--expr" :: [] ->
      Printf.eprintf "Missing expression after --expr.\n";
      exit 1
  | _ :: "run" :: "--json" :: "--expr" :: [] ->
      Printf.eprintf "Missing expression after --expr.\n";
      exit 1
  | _ :: "run" :: "--json" :: "--expr" :: expr :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_run_expr ~json:true ~failfast script_mode expr env
  | _ :: "run" :: "--expr" :: expr :: "--json" :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_run_expr ~json:true ~failfast script_mode expr env
  | _ :: "run" :: "--expr" :: expr :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_run_expr ~failfast script_mode expr env
  | _ :: "run" :: "--json" :: "--expr" :: _ ->
      Printf.eprintf "Unexpected arguments after `t run --json --expr <expr>`.\n";
      exit 1
  | _ :: "run" :: "--expr" :: _ ->
      Printf.eprintf "Unexpected arguments after `t run --expr <expr>`.\n";
      exit 1
  | _ :: "run" :: "--json" :: filename :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_run ~json:true ~unsafe ~failfast script_mode filename env
  | _ :: "run" :: filename :: "--json" :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_run ~json:true ~unsafe ~failfast script_mode filename env
  | _ :: "run" :: filename :: [] ->
      (* Default to Strict mode for scripts, but allow --mode to override *)
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_run ~unsafe ~failfast script_mode filename env
  | _ :: "run" :: _ ->
      Printf.eprintf "Unexpected arguments after `t run <file.t>`.\n";
      exit 1
  | _ :: "check" :: [] ->
      Printf.eprintf "Usage: t check [--json] [--schema] [--env] [--offline] [--watch] <file.t>\n";
      exit 1
  | _ :: "check" :: rest ->
      let json = List.mem "--json" rest in
      let schema = List.mem "--schema" rest in
      let check_env = List.mem "--env" rest in
      let offline = List.mem "--offline" rest in
      let watch = List.mem "--watch" rest in
      let filename = List.find_opt (fun s -> not (String.length s > 0 && s.[0] = '-')) rest in
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      (match filename with
       | None ->
           Printf.eprintf "Usage: t check [--json] [--schema] [--env] [--offline] [--watch] <file.t>\n";
           exit 1
       | Some f ->
           if watch then
             cmd_check_watch ~json ~schema ~env_check:check_env ~offline script_mode f env
           else
             cmd_check ~json ~schema ~env_check:check_env ~offline script_mode f env)
  | _ :: "diff" :: [] ->
      Printf.eprintf "Usage: t diff [--json] [--log-a <n>] [--log-b <n>] <file.t>\n";
      exit 1
  | _ :: "diff" :: rest ->
      let json = List.mem "--json" rest in
      let extract_int_flag flag default =
        let rec find_val = function
          | [] -> default
          | x :: y :: _ when x = flag -> (try int_of_string y with _ -> default)
          | _ :: xs -> find_val xs
        in
        find_val rest
      in
      let log_a = extract_int_flag "--log-a" 2 in
      let log_b = extract_int_flag "--log-b" 1 in
      if log_a < 1 || log_b < 1 then begin
        Printf.eprintf "Invalid rank: --log-a and --log-b must be >= 1 (got --log-a %d --log-b %d).\n" log_a log_b;
        exit 1
      end else begin
        let filename = List.find_opt (fun s -> not (String.length s > 0 && s.[0] = '-')) rest in
       (match filename with
        | None ->
            Printf.eprintf "Usage: t diff [--json] [--log-a <n>] [--log-b <n>] <file.t>\n";
            exit 1
        | Some f -> cmd_diff ~json ~log_a ~log_b f env)
      end
  | _ :: "fix" :: [] ->
      Printf.eprintf "Usage: t fix [--dry-run] <file.t>\n";
      exit 1
  | _ :: "fix" :: rest ->
      let dry_run = List.mem "--dry-run" rest in
      let filename = List.find_opt (fun s -> not (String.length s > 0 && s.[0] = '-')) rest in
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      (match filename with
       | None ->
           Printf.eprintf "Usage: t fix [--dry-run] <file.t>\n";
           exit 1
       | Some f ->
            let check_fn = fun file -> run_check ~schema:true script_mode file env in
            let result = Fix.cmd_fix ~dry_run ~check_fn f in
            if result.Fix.applied = 0 && result.Fix.would_apply = 0 && result.Fix.skipped = 0 then
              Printf.printf "No fixes to apply.\n"
            else begin
              if dry_run then
                Printf.printf "Would apply %d fix(es), skipped %d.\n" result.Fix.would_apply result.Fix.skipped
              else begin
                Printf.printf "Applied %d fix(es), skipped %d.\n" result.Fix.applied result.Fix.skipped;
                Printf.printf "Run 't check %s' to verify.\n" f
              end;
              List.iter (fun note -> Printf.printf "  - %s\n" note) result.Fix.skip_notes
            end;
            exit 0)
  | _ :: "repl" :: _ -> cmd_repl ~failfast mode_parse.mode env
  | _ :: "explain" :: rest -> cmd_explain ~failfast mode_parse.mode rest env
  | _ :: "init" :: "--package" :: rest -> cmd_init_package rest
  | _ :: "init" :: "--project" :: rest -> cmd_init_project rest
  | _ :: "test" :: rest -> cmd_test rest
  | _ :: "add" :: rest -> cmd_add rest
  | _ :: "doctor" :: _ -> cmd_doctor ()
  | _ :: "docs" :: _ -> cmd_docs ()
  | _ :: "doc" :: rest -> cmd_doc rest
  | _ :: "update" :: _ -> cmd_update ()
  | _ :: "upgrade" :: _ -> cmd_upgrade ()
  | _ :: "publish" :: _ -> cmd_publish ()
  | _ :: "export_artifacts" :: [filename; archive_path] ->
      cmd_artifact_transfer `Export filename archive_path env
  | _ :: "import_artifacts" :: [filename; archive_path] ->
      cmd_artifact_transfer `Import filename archive_path env

  | _ :: "init" :: _ ->
      Printf.eprintf "Usage: t init --package <name> | t init --project <name> [options]\n";
      Printf.eprintf "Run 't init --package --help' for more information.\n";
      exit 1
  | _ :: "export_artifacts" :: _ ->
      Printf.eprintf "Usage: t export_artifacts <pipeline.t> <archive_path>\n";
      exit 1
  | _ :: "import_artifacts" :: _ ->
      Printf.eprintf "Usage: t import_artifacts <pipeline.t> <archive_path>\n";
      exit 1
  | _ :: "--help" :: _ | _ :: "-h" :: _ -> print_help ()
  | _ :: "--version" :: _ | _ :: "-v" :: _ -> print_version ()
  | [_] ->
      (* No arguments: start the REPL (default behavior) *)
      cmd_repl ~failfast mode_parse.mode env
  | _ :: unknown :: _ ->
      Printf.eprintf "Unknown command: %s\n" unknown;
      Printf.eprintf "Run 't --help' for usage information.\n";
      exit 1
  | [] -> cmd_repl ~failfast mode_parse.mode env
