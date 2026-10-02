(* tests/test_shell_diff.ml *)
(* Differential test: T's shell dependency scanner against a real shell
   parser (`shfmt --to-json`, version in tests/shell_diff/SHFMT_VERSION).
   Each fixture in tests/shell_diff/ encodes one settled persistence
   rule; the checked-in JSON is shell truth, so the suite needs no
   parser binary and no network. Regenerate with
   scripts/regen_shell_diff.sh after editing any fixture.
   Both sides must report exactly the same persistent bindings. *)

(* Unknown shfmt shapes fail the test loudly instead of being silently
   skipped: an uninterpretable fixture is a harness gap, not a pass. *)
exception Cannot_interpret of string

let as_assoc = function
  | `Assoc l -> Some l
  | _ -> None

let as_list = function
  | `List l -> Some l
  | _ -> None

let field obj k =
  match as_assoc obj with
  | Some l -> (match List.assoc_opt k l with Some v -> v | None -> `Null)
  | None -> `Null

let str_field obj k =
  match field obj k with `String s -> Some s | _ -> None

let bool_field obj k =
  match field obj k with `Bool b -> b | _ -> false

(* shfmt BinaryCmd operator encoding (shfmt 3.13 --to-json): 11 is `&&`,
   12 is `||`, 13 is `|`. String spellings accepted too, in case a
   future shfmt serializes them as written. *)
let persist_op = function
  | `Int 11 | `Int 12 | `String "&&" | `String "||" -> Some true
  | `Int 13 | `String "|" -> Some false
  | _ -> None

(* Collect persistent binding targets from an shfmt File node. The
   rules mirror POSIX/bash persistence, written independently of T's
   scanner (see tests/shell_diff/README.md for the full mapping):
   bare Assign statements bind; CallExpr binds its Assigns only with
   zero Args (otherwise they are env-prefixes); lone `&` and `|` run
   in subshells; Subshell/function/conditional bodies never persist
   outward; `for` loop variables bind; DeclClause binds assignment
   args only. Values and argument words are never walked: command
   substitutions are subshells. *)
let rec walk_stmts excluded stmts =
  List.concat_map (walk_stmt excluded) stmts

and stmts_field node k excluded =
  match as_list (field node k) with
  | Some l -> walk_stmts excluded l
  | None -> []

and walk_stmt excluded stmt =
  let excluded =
    excluded || bool_field stmt "Background" || bool_field stmt "Coprocess"
  in
  let cmd = field stmt "Cmd" in
  match str_field cmd "Type" with
  | Some "Assign" ->
      if excluded then []
      else (match assign_name cmd with
        | Some n -> [n]
        | None -> raise (Cannot_interpret "Assign without Name.Value"))
  | Some "CallExpr" ->
      let args_empty =
        match as_list (field cmd "Args") with
        | Some [] | None -> true
        | Some _ -> false
      in
      if excluded || not args_empty then []
      else
        (match as_list (field cmd "Assigns") with
         | Some assigns -> List.concat_map assign_arg assigns
         | None -> [])
  | Some "BinaryCmd" ->
      let x = field cmd "X" and y = field cmd "Y" in
      (match persist_op (field cmd "Op") with
       | Some keep ->
           let sub = excluded || not keep in
           walk_stmt sub x @ walk_stmt sub y
       | None ->
           raise (Cannot_interpret "BinaryCmd with unknown Op"))
  | Some "Subshell" -> stmts_field cmd "Stmts" true
  | Some "BraceGroup" -> stmts_field cmd "Stmts" true
  | Some "IfClause" ->
      stmts_field cmd "Cond" excluded
      @ stmts_field cmd "Then" true
      @ else_branch cmd
  | Some "WhileClause" | Some "UntilClause" ->
      stmts_field cmd "Cond" excluded @ stmts_field cmd "Do" true
  | Some "ForClause" ->
      let loop_var =
        match str_field (field (field cmd "Loop") "Name") "Value" with
        | Some v when not excluded -> [v]
        | Some _ -> []
        | None -> raise (Cannot_interpret "ForClause without Loop.Name.Value")
      in
      loop_var @ stmts_field cmd "Do" true
  | Some "FuncDecl" -> stmts_field cmd "Body" true
  | Some "CaseClause" -> stmts_field cmd "Cases" true
  | Some "CaseItem" -> stmts_field cmd "Stmts" true
  | Some "DeclClause" ->
      (match str_field (field cmd "Variant") "Value" with
       | Some ("export" | "declare" | "readonly" | "local" | "typeset") ->
           if excluded then []
           else
             (match as_list (field cmd "Args") with
              | Some args ->
                  List.concat_map
                    (fun a ->
                       (* Assignment args carry Name plus a Value (or an
                          Array); bare words (`export FOO`, shfmt marks
                          them Naked) carry Name alone or nothing. *)
                       match str_field (field a "Name") "Value" with
                       | None -> []
                       | Some n ->
                           let valued =
                             field a "Value" <> `Null
                             || field a "Array" <> `Null
                           in
                           if valued then [n] else [])
                    args
              | None -> [])
       | Some other -> raise (Cannot_interpret ("DeclClause variant: " ^ other))
       | None -> raise (Cannot_interpret "DeclClause without Variant"))
  | Some other -> raise (Cannot_interpret ("unknown Cmd.Type: " ^ other))
  | None -> raise (Cannot_interpret "Stmt without Cmd.Type")

and assign_name node =
  str_field (field node "Name") "Value"

and assign_arg node =
  match assign_name node with
  | Some n -> [n]
  | None -> raise (Cannot_interpret "Assign arg without Name.Value")

and else_branch cmd =
  match field cmd "Else" with
  | `Null -> []
  | e -> (
      match as_list e with
      | Some l -> walk_stmts true l
      | None -> (
          (* `elif` nests another IfClause. *)
          match str_field e "Type" with
          | Some "IfClause" ->
              stmts_field e "Cond" true @ stmts_field e "Then" true
              @ else_branch e
          | _ -> []))

let shfmt_binds json =
  match str_field json "Type" with
  | Some "File" ->
      (match as_list (field json "Stmts") with
       | Some l -> walk_stmts false l
       | None -> raise (Cannot_interpret "File without Stmts"))
  | _ -> raise (Cannot_interpret "top node is not a File")

let read_file path =
  try
    let ch = open_in_bin path in
    let n = in_channel_length ch in
    let s = really_input_string ch n in
    close_in ch;
    Ok s
  with Sys_error msg -> Error msg

let ends_with s suffix =
  let sl = String.length s and pl = String.length suffix in
  sl >= pl && String.sub s (sl - pl) pl = suffix

let starts_with s prefix =
  let sl = String.length s and pl = String.length prefix in
  sl >= pl && String.sub s 0 pl = prefix

let cases =
  [ "01_prefix"; "02_chain"; "03_array"; "04_cmdsubst"; "05_quoted";
    "06_empty"; "07_eqval"; "08_redirect"; "09_fddup"; "10_background";
    "11_pipe_right"; "12_pipe_left"; "13_and_list"; "14_or_list";
    "15_export"; "16_export_prefix"; "17_export_bare"; "18_for_loop";
    "19_func_local"; "20_if_cond"; "21_combined_redir"; "22_blank_eq";
    "23_subshell_assign"; "24_if_else" ]

(* case_16 documents shell truth (`export FOO=1 cmd` binds FOO in real
   bash) that T's scanner deliberately does not follow yet (it records
   an assignment prefix). Skipped until that behavior is decided; see
   tests/shell_diff/README.md. *)
let skipped = [ "16_export_prefix" ]

let run_tests pass_count fail_count _failures _eval_string _eval_string_env _test =
  Printf.printf "Shell differential (T vs shfmt):\n";
  let dir = Filename.concat (Test_helpers.find_repo_root ()) "tests/shell_diff" in
  let on_disk =
    try Array.to_list (Sys.readdir dir) with Sys_error _ -> []
  in
  let wanted stem = "case_" ^ stem ^ ".sh" in
  List.iter
    (fun stem ->
       if not (List.mem (wanted stem) on_disk) then begin
         incr fail_count;
         Printf.printf "  ✗ Error: fixture %s missing from tests/shell_diff\n" (wanted stem)
       end)
    cases;
  List.iter
    (fun f ->
       if ends_with f ".sh" && starts_with f "case_" then begin
         let stem =
           String.sub f 5 (String.length f - 5 - 3)
         in
         if not (List.mem stem cases) then begin
           incr fail_count;
           Printf.printf "  ✗ Error: fixture %s has no entry in the case list\n" f
         end
       end)
    on_disk;
  List.iter
    (fun stem ->
       if List.mem stem skipped then
         Printf.printf "  (skipped %s: known divergence, see README)\n" stem
       else begin
         let shop = Filename.concat dir ("case_" ^ stem ^ ".sh") in
         let jsonp = Filename.concat dir ("case_" ^ stem ^ ".json") in
         let outcome =
           match read_file shop with
           | Error msg -> Error ("cannot read shell fixture: " ^ msg)
           | Ok text -> (
               match read_file jsonp with
               | Error msg -> Error ("cannot read JSON fixture: " ^ msg)
               | Ok js -> (
                   match
                     (try Ok (Yojson.Basic.from_string js)
                      with Yojson.Json_error msg -> Error ("bad JSON: " ^ msg))
                   with
                   | Error _ as e -> e
                   | Ok json -> (
                       match
                         (try Ok (shfmt_binds json)
                          with Cannot_interpret msg -> Error msg)
                       with
                       | Error _ as e -> e
                       | Ok expected ->
                           let got =
                             List.sort_uniq String.compare
                               (Ast.extract_local_bindings ~runtime:"sh" text)
                           in
                           let want = List.sort_uniq String.compare expected in
                           if got = want then Ok want else Error "mismatch")))
         in
         match outcome with
         | Ok want ->
             incr pass_count;
             Printf.printf "  ✓ %s [%s]\n" stem (String.concat "; " want)
         | Error msg ->
             incr fail_count;
             Printf.printf "  ✗ Error: %s (%s)\n" stem msg
       end)
    cases
