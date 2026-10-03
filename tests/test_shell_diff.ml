(* tests/test_shell_diff.ml *)
(* Differential test: T's shell dependency scanner against a real shell
   parser (`shfmt --to-json`, version in tests/shell_diff/SHFMT_VERSION).
   Each fixture in tests/shell_diff/ encodes one settled persistence
   rule; the checked-in JSON is shell truth, so the suite needs no
   parser binary and no network. Regenerate with
   scripts/regen_shell_diff.sh after editing any fixture.
   Soundness is one-sided: T must not bind more than the shell does
   (over-binding drops a later read and loses an edge). T binding
   fewer names only keeps extra edges and passes, except in the
   exact list where precision matters. *)

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
   in subshells (nothing inside persists); `&&`/`||` run in place but
   the right side is conditional and never persists outward (T treats
   it as unbound); brace groups run in the current shell and persist;
   Subshell/function/conditional bodies never persist outward; `for`
   loop variables bind; DeclClause binds assignment args only. Values
   and argument words are never walked: command substitutions are
   subshells. *)
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
       | Some true ->
           (* `&&`/`||`: left runs in place and persists; right is
              conditional and never persists outward. *)
           walk_stmt excluded x @ walk_stmt true y
       | Some false ->
           (* `|`: both sides run in pipeline subshells. *)
           walk_stmt true x @ walk_stmt true y
       | None ->
           raise (Cannot_interpret "BinaryCmd with unknown Op"))
  | Some "Subshell" -> stmts_field cmd "Stmts" true
  | Some "BraceGroup" | Some "Block" -> stmts_field cmd "Stmts" excluded
  (* Arithmetic commands read variables but bind nothing we track
     (`(( x++ ))` only reads; `(( x = 1 ))` arithmetic assignment is
     out of scope and keeps the edge). *)
  | Some "ArithmCmd" -> []
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

(* Shell variable reads from the shfmt AST: every `ParamExp` parameter
   (`$x`, `${x}`, `"hi $x"`, `$(... $x ...)`), plus bare names inside
   arithmetic (`$((x + 1))`, `(( x++ ))`) and array indexes
   (`${a[i]}`), which shfmt stores as `Lit` leaves rather than
   `ParamExp`. Heredoc bodies with `$x` arrive as `ParamExp` inside
   the redirect word and are already covered. Walked everywhere with
   no exclusions: subshell and pipeline reads still need the data.
   Only identifier-shaped names count (`$1`, `$@`, `$?` are not
   dependencies). T must show every one of them; extra T names
   (command words like `echo`) are safe over-approximation. *)
let is_read_ident s =
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

let rec collect_reads acc = collect_reads_arith false acc

and collect_reads_arith in_arith acc = function
  | `Assoc l ->
      let arith_here =
        match List.assoc_opt "Type" l with
        | Some (`String s)
          when s = "ArithmExp" || s = "ArithmCmd" || s = "BinaryArithm"
            || s = "UnaryArithm" -> true
        | _ -> in_arith
      in
      let acc =
        match List.assoc_opt "Type" l with
        | Some (`String "ParamExp") -> (
            match List.assoc_opt "Param" l with
            | Some (`Assoc pl) -> (
                match List.assoc_opt "Value" pl with
                | Some (`String v) when is_read_ident v -> v :: acc
                | _ -> acc)
            | _ -> acc)
        | Some (`String "Lit") when arith_here -> (
            match List.assoc_opt "Value" l with
            | Some (`String v) when is_read_ident v -> v :: acc
            | _ -> acc)
        | _ -> acc
      in
      List.fold_left
        (fun a (_, v) -> collect_reads_arith arith_here a v)
        acc l
  | `List l -> List.fold_left (collect_reads_arith in_arith) acc l
  | _ -> acc

let shfmt_reads json =
  List.sort_uniq String.compare (collect_reads [] json)

let subset_of small big =
  List.for_all (fun s -> List.mem s big) small

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
    "23_subshell_assign"; "24_if_else"; "25_and_right"; "26_or_right";
    "27_brace_group"; "28_dollar_read"; "29_braced_read";
    "30_quoted_read"; "31_arith_read"; "32_arith_cmd";
    "33_array_index"; "34_heredoc" ]

(* Precision list: T must match shell truth exactly here. Everywhere
   else the check is one-sided (T binds ⊆ truth): T binding fewer
   names only keeps extra edges, which is safe. `16_export_prefix`
   is the intentional divergence (real bash binds FOO, T records a
   prefix and binds nothing) and stays subset-only so it passes;
   a future T that binds FOO there also passes. The exact list is
   the precision contract, not the divergence record. *)
let exact_cases =
  [ "01_prefix"; "02_chain"; "03_array"; "04_cmdsubst"; "05_quoted";
    "06_empty"; "07_eqval"; "08_redirect"; "09_fddup";
    "13_and_list"; "14_or_list"; "15_export"; "17_export_bare";
    "18_for_loop"; "21_combined_redir"; "22_blank_eq";
    "23_subshell_assign"; "27_brace_group" ]

let skipped = []

let binds_ok_for_stem stem got want =
  if List.mem stem exact_cases then got = want else subset_of got want

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
                           if not (binds_ok_for_stem stem got want) then Error "binds mismatch" else
                              let want_reads = shfmt_reads json in
                              let got_reads = Ast.extract_code_identifiers ~lang:(Some Ast.ShLang) text in
                              let missing = List.filter (fun s -> not (List.mem s got_reads)) want_reads in
                              if missing = [] then Ok want else Error ("reads mismatch (T misses [" ^ String.concat "; " missing ^ "])"))))
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
