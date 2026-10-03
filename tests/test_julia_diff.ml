(* tests/test_julia_diff.ml *)
(* Differential test: T's Julia dependency scanner against Julia's own
   parser. tests/julia_diff/dump_symbols.jl parses every
   tests/julia_diff/case_*.jl fixture with Meta.parse and prints the
   names really present in code (strings, chars, comments and
   expression heads excluded) plus the names bound unconditionally at
   top level. Reads: T must show every ASCII name Julia sees (a
   missing name is a dropped read and fails); extra T names are safe
   over-approximation. Binds: T must not bind more than Julia binds
   at top level (over-binding drops a later read); T binding fewer is
   safe. Truth is filtered to ASCII identifiers because T node names
   and T's identifier scan are ASCII-only (lexer ident_start), so
   Unicode names can never form edges.
   Julia runs once for all fixtures. Without a julia binary the module
   skips locally but fails when CI is set. *)

let cases =
  [ "01_transpose"; "02_double_transpose"; "03_char"; "04_escaped_char";
    "05_string"; "06_interp_string"; "07_triple_string"; "08_comments";
    "09_block_comment"; "10_comprehension"; "11_scopes"; "12_macro";
    "13_broadcast"; "14_paren_transpose"; "15_keyword_char";
    "16_unicode"; "17_end_index"; "18_backtick"; "19_triple_transpose";
    "20_return_quote"; "21_unicode_op"; "22_try_finally"; "23_abstract";
    "24_abstract_in_module" ]

let skipped = []

(* T node names are ASCII-only, so only ASCII truth names can form
   edges. Filter the Julia side to ASCII before comparing; Unicode
   names (case_16 `β`) are truth-only and never fail. *)
let is_ascii_ident s =
  let n = String.length s in
  if n = 0 then false
  else
    let first_ok = match s.[0] with
      | 'A'..'Z' | 'a'..'z' | '_' -> true | _ -> false
    in
    if not first_ok then false
    else
      let rec loop i =
        if i >= n then true
        else match s.[i] with
          | 'A'..'Z' | 'a'..'z' | '0'..'9' | '_' -> loop (i + 1)
          | _ -> false
      in
      loop 1

let split_once tab line =
  match String.index_opt line tab with
  | Some i ->
      (String.sub line 0 i, String.sub line (i + 1) (String.length line - i - 1))
  | None -> (line, "")

let words s =
  List.filter (fun w -> w <> "") (String.split_on_char ' ' s)

let lines s =
  List.filter (fun l -> l <> "") (String.split_on_char '\n' s)

let run_capture cmd =
  try
    let ch = Unix.open_process_in cmd in
    let buf = Buffer.create 1024 in
    (try
       while true do
         Buffer.add_channel buf ch 1
       done
     with End_of_file -> ());
    match Unix.close_process_in ch with
    | Unix.WEXITED 0 -> Ok (Buffer.contents buf)
    | Unix.WEXITED n -> Error (Printf.sprintf "exit %d: %s" n (Buffer.contents buf))
    | Unix.WSIGNALED n -> Error (Printf.sprintf "signal %d" n)
    | Unix.WSTOPPED n -> Error (Printf.sprintf "stopped %d" n)
  with Sys_error msg -> Error msg

let has_julia () =
  match run_capture "julia --version" with
  | Ok _ -> true
  | Error _ -> false

let read_file path =
  try
    let ch = open_in_bin path in
    let n = in_channel_length ch in
    let s = really_input_string ch n in
    close_in ch;
    Ok s
  with Sys_error msg -> Error msg

let run_tests pass_count fail_count _failures _eval_string _eval_string_env _test =
  Printf.printf "Julia differential (T vs Meta.parse):\n";
  if not (has_julia ()) then begin
    match Sys.getenv_opt "CI" with
    | Some _ ->
        incr fail_count;
        Printf.printf "  ✗ Error: no julia binary under CI\n"
    | None ->
        Printf.printf "  (skipped: no julia binary)\n"
  end else begin
    let root = Test_helpers.find_repo_root () in
    let dir = Filename.concat root (Filename.concat "tests" "julia_diff") in
    let dumper = Filename.concat dir "dump_symbols.jl" in
    (* Clean Julia: the dev-shell startup.jl guards must never break
       this driver (`julia --version` skips startup, scripts do not). *)
    let cmd =
      Printf.sprintf "julia --startup-file=no %s %s 2>&1"
        (Filename.quote dumper) (Filename.quote dir)
    in
    match run_capture cmd with
    | Error msg ->
        incr fail_count;
        Printf.printf "  ✗ Error: julia driver failed (%s)\n" msg
    | Ok out -> (
        let table =
          List.filter_map
            (fun line ->
               let (stem, syms) = split_once '\t' line in
               if stem = "" then None else Some (stem, words syms))
            (lines out)
        in
        let on_disk =
          try Array.to_list (Sys.readdir dir) with Sys_error _ -> []
        in
        List.iter
          (fun stem ->
             if not (List.mem ("case_" ^ stem ^ ".jl") on_disk) then begin
               incr fail_count;
               Printf.printf "  ✗ Error: fixture case_%s.jl missing\n" stem
             end)
          cases;
        List.iter
          (fun stem ->
             if List.mem stem skipped then
               Printf.printf "  (skipped %s: known gap, see README)\n" stem
             else begin
               let jl_name = "case_" ^ stem ^ ".jl" in
               match read_file (Filename.concat dir jl_name) with
               | Error msg ->
                   incr fail_count;
                   Printf.printf "  ✗ Error: %s (%s)\n" stem msg
               | Ok text -> (
                   let full = "case_" ^ stem in
                   match List.assoc_opt full table with
                   | None ->
                       incr fail_count;
                       Printf.printf "  ✗ Error: %s (no driver output)\n" stem
                   | Some syms ->
                       let syms_ascii =
                         List.filter is_ascii_ident syms
                       in
                       let got =
                         Ast.extract_code_identifiers ~lang:(Some Ast.JuliaLang) text
                       in
                       let missing =
                         List.filter (fun s -> not (List.mem s got)) syms_ascii
                       in
                       if missing <> [] then begin
                         incr fail_count;
                         Printf.printf "  ✗ Error: %s (T misses [%s])\n" stem
                           (String.concat "; " missing)
                       end else (
                         match List.assoc_opt (full ^ "@binds") table with
                         | None ->
                             incr fail_count;
                             Printf.printf "  ✗ Error: %s (no binds output)\n" stem
                         | Some binds ->
                             let binds_ascii =
                               List.filter is_ascii_ident binds
                             in
                             let got_binds =
                               Ast.extract_local_bindings ~runtime:"Julia" text
                             in
                             let extra =
                               List.filter
                                 (fun s -> not (List.mem s binds_ascii))
                                 got_binds
                             in
                             if extra = [] then begin
                               incr pass_count;
                               Printf.printf "  ✓ %s [%d names]\n" stem
                                 (List.length syms_ascii)
                             end else begin
                               incr fail_count;
                               Printf.printf "  ✗ Error: %s (T over-binds [%s])\n" stem
                                 (String.concat "; " extra)
                             end))
             end)
          cases)
  end
