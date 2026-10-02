(* tests/test_julia_diff.ml *)
(* Differential test: T's Julia dependency scanner against Julia's own
   parser. tests/julia_diff/dump_symbols.jl parses every
   tests/julia_diff/case_*.jl fixture with Meta.parse and prints the
   names really present in code (strings, chars, comments and
   expression heads excluded). T's scanner must show every one of
   them: a missing name is a dropped read (the silent direction) and
   fails the test. Extra names on T's side are safe over-approximation
   (keywords, field names, backtick contents) and pass.
   Julia runs once for all fixtures. Without a julia binary the module
   reports a skip instead of failing. *)

let cases =
  [ "01_transpose"; "02_double_transpose"; "03_char"; "04_escaped_char";
    "05_string"; "06_interp_string"; "07_triple_string"; "08_comments";
    "09_block_comment"; "10_comprehension"; "11_scopes"; "12_macro";
    "13_broadcast"; "14_paren_transpose"; "15_keyword_char";
    "16_unicode"; "17_end_index"; "18_backtick" ]

(* case_16 documents a known gap: T's identifier scan is ASCII-only, so
   Unicode identifiers are invisible to it. Dumped for truth, skipped
   in the comparison until Unicode identifiers are supported. *)
let skipped = [ "16_unicode" ]

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
  if not (has_julia ()) then
    Printf.printf "  (skipped: no julia binary)\n"
  else begin
    let root = Test_helpers.find_repo_root () in
    let dir = Filename.concat root (Filename.concat "tests" "julia_diff") in
    let dumper = Filename.concat dir "dump_symbols.jl" in
    let cmd =
      Printf.sprintf "julia %s %s 2>&1"
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
                       let got =
                         Ast.extract_code_identifiers ~lang:(Some Ast.JuliaLang) text
                       in
                       let missing =
                         List.filter (fun s -> not (List.mem s got)) syms
                       in
                       if missing = [] then begin
                         incr pass_count;
                         Printf.printf "  ✓ %s [%d names]\n" stem (List.length syms)
                       end else begin
                         incr fail_count;
                         Printf.printf "  ✗ Error: %s (T misses [%s])\n" stem
                           (String.concat "; " missing)
                       end)
             end)
          cases)
  end
