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
    let diag_list : Diagnostics.diagnostic list =
      let error_diags = match result with
        | VError err -> [Diagnostics.of_verror ~file:filename err]
        | _ -> []
      in
      let pipeline_diags = List.concat_map (fun (_name, p) ->
        let wire_diags = Diagnostics.of_pipeline_result ~file:filename p in
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
      Buffer.add_string buf
        (Printf.sprintf "%s [%s] %s\n"
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
