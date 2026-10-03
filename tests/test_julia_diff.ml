(* tests/test_julia_diff.ml *)
(* Differential test: T's Julia dependency scanner against Julia's own
   parser. Each tests/julia_diff/case_*.jl fixture has a checked-in
   tests/julia_diff/case_*.txt truth file (line 1: sorted unique read
   symbols, line 2: sorted unique top-level binds, both from
   Meta.parseall via dump_symbols.jl, Julia version in JULIA_VERSION).
   Regenerate with scripts/regen_julia_diff.sh. The suite never runs
   julia: no binary, startup file, depot, or network needed, so results
   are identical on every platform.
   Reads: every ASCII name in truth must be visible to T (a missing
   name is a dropped read and fails); extra T names are safe
   over-approximation. Binds: T must not bind more than truth binds
   at top level (over-binding drops a later read); binding fewer is
   safe. Truth is filtered to ASCII identifiers because T node names
   and T's identifier scan are ASCII-only (lexer ident_start), so
   Unicode names can never form edges. *)

let cases =
  [ "01_transpose"; "02_double_transpose"; "03_char"; "04_escaped_char";
    "05_string"; "06_interp_string"; "07_triple_string"; "08_comments";
    "09_block_comment"; "10_comprehension"; "11_scopes"; "12_macro";
    "13_broadcast"; "14_paren_transpose"; "15_keyword_char";
    "16_unicode"; "17_end_index"; "18_backtick"; "19_triple_transpose";
    "20_return_quote"; "21_unicode_op"; "22_try_finally"; "23_abstract";
    "24_abstract_in_module" ]

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

let words s =
  List.filter (fun w -> w <> "") (String.split_on_char ' ' s)

let lines s =
  List.filter (fun l -> l <> "") (String.split_on_char '\n' s)

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
  let root = Test_helpers.find_repo_root () in
  let dir = Filename.concat root (Filename.concat "tests" "julia_diff") in
  let on_disk =
    try Array.to_list (Sys.readdir dir) with Sys_error _ -> []
  in
  List.iter
    (fun stem ->
       if not (List.mem ("case_" ^ stem ^ ".jl") on_disk) then begin
         incr fail_count;
         Printf.printf "  ✗ Error: fixture case_%s.jl missing\n" stem
       end;
       if not (List.mem ("case_" ^ stem ^ ".txt") on_disk) then begin
         incr fail_count;
         Printf.printf "  ✗ Error: truth case_%s.txt missing (run scripts/regen_julia_diff.sh)\n" stem
       end)
    cases;
  List.iter
    (fun f ->
       let is_case n =
         String.length n > 5 && String.sub n 0 5 = "case_"
       in
       if is_case f && (Filename.check_suffix f ".jl" || Filename.check_suffix f ".txt") then begin
         let stem = Filename.chop_extension (String.sub f 5 (String.length f - 5)) in
         if not (List.mem stem cases) then begin
           incr fail_count;
           Printf.printf "  ✗ Error: fixture %s has no entry in the case list\n" f
         end
       end)
    on_disk;
  List.iter
    (fun stem ->
       let jl_name = "case_" ^ stem ^ ".jl" in
       let txt_name = "case_" ^ stem ^ ".txt" in
       match read_file (Filename.concat dir jl_name) with
       | Error msg ->
           incr fail_count;
           Printf.printf "  ✗ Error: %s (%s)\n" stem msg
       | Ok text -> (
           match read_file (Filename.concat dir txt_name) with
           | Error msg ->
               incr fail_count;
               Printf.printf "  ✗ Error: %s (%s)\n" stem msg
           | Ok truth -> (
               match lines truth with
               | sym_line :: rest ->
                   let syms = List.filter is_ascii_ident (words sym_line) in
                   let binds =
                     match rest with
                     | binds_line :: _ ->
                         List.filter is_ascii_ident (words binds_line)
                     | [] -> []
                   in
                   let got =
                     Ast.extract_code_identifiers ~lang:(Some Ast.JuliaLang) text
                   in
                   let missing =
                     List.filter (fun s -> not (List.mem s got)) syms
                   in
                   if missing <> [] then begin
                     incr fail_count;
                     Printf.printf "  ✗ Error: %s (T misses [%s])\n" stem
                       (String.concat "; " missing)
                   end else begin
                     let got_binds =
                       Ast.extract_local_bindings ~runtime:"Julia" text
                     in
                     let extra =
                       List.filter
                         (fun s -> not (List.mem s binds))
                         got_binds
                     in
                     if extra = [] then begin
                       incr pass_count;
                       Printf.printf "  ✓ %s [%d names]\n" stem
                         (List.length syms)
                     end else begin
                       incr fail_count;
                       Printf.printf "  ✗ Error: %s (T over-binds [%s])\n" stem
                         (String.concat "; " extra)
                     end
                   end
               | [] ->
                   incr fail_count;
                   Printf.printf "  ✗ Error: %s (empty truth file)\n" stem)))
    cases
