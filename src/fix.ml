(* src/fix.ml *)
(* Mechanical application of suggested_fix from diagnostics *)

type fix_result = {
  file : string;
  applied : int;
  skipped : int;
  would_apply : int;
  dry_run : bool;
  diagnostics : Diagnostics.diagnostic list;
  skip_notes : string list;
      (* Human-readable reasons for skipped fixes, e.g. which lines still
         reference a node that `t fix` refuses to rename. Empty when nothing
         was skipped with an explanation. *)
}

let is_word_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
  | _ -> false

(* Does [word] appear in [content] as a standalone identifier, bounded on both
   sides by non-word characters? Unlike replace_word_bound, the preceding
   character is also checked so `count` is not matched inside `account`. *)
let contains_word ~content ~word =
  let word_len = String.length word in
  let n = String.length content in
  let rec loop i =
    if i + word_len > n then false
    else if String.sub content i word_len = word
            && (i = 0 || not (is_word_char content.[i - 1]))
            && (i + word_len >= n || not (is_word_char content.[i + word_len]))
    then true
    else loop (i + 1)
  in
  loop 0

let replace_word_bound ~content ~old ~replacement =
  let buf = Buffer.create (String.length content) in
  let old_len = String.length old in
  let i = ref 0 in
  while !i < String.length content do
    if !i + old_len <= String.length content
       && String.sub content !i old_len = old
       && (!i + old_len >= String.length content
           || not (is_word_char content.[!i + old_len]))
    then begin
      Buffer.add_string buf replacement;
      i := !i + old_len
    end else begin
      Buffer.add_char buf content.[!i];
      incr i
    end
  done;
  Buffer.contents buf

let apply_rename_column ~file ~old_name ~new_name =
  let content =
    let ch = open_in file in
    Fun.protect ~finally:(fun () -> close_in_noerr ch)
      (fun () -> really_input_string ch (in_channel_length ch))
  in
  (* Only replace $old_name and $`old_name` — the T column reference forms.
     Avoids corrupting unrelated identifiers like `valid`, `hidden`, etc.
     Uses manual word-boundary check: the character after the match must not be
     [a-zA-Z0-9_], so $id is not matched inside $identity.
     Skips references that are the RHS of rename()'s named argument
     (= $old), which are definition sites (e.g. rename(mpg2 = $mpg)).
     Other named-argument forms like mutate(flag = $mpg > 20) are genuine
     data references and ARE renamed. *)
  (* Walk backward from [pos] to check if this $col is inside a rename() call.
     Finds the nearest unmatched '(', then checks if the identifier before it
     is "rename". Handles nested calls by tracking paren depth. *)
  let is_in_rename_call content pos =
    let found = ref false in
    let depth = ref 0 in
    let j = ref (pos - 1) in
    while !j >= 0 && not !found do
      (match content.[!j] with
       | ')' -> incr depth
       | '(' ->
           if !depth = 0 then begin
             (* Found the matching open-paren — check identifier before it *)
             let k = ref (!j - 1) in
             while !k >= 0 && (let c = content.[!k] in
               c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' ||
               c >= '0' && c <= '9' || c = '_')
             do
               decr k
             done;
             let name_start = !k + 1 in
             let name_len = !j - name_start in
             found :=
               name_len = 6
               && content.[name_start] = 'r'
               && content.[name_start + 1] = 'e'
               && content.[name_start + 2] = 'n'
               && content.[name_start + 3] = 'a'
               && content.[name_start + 4] = 'm'
               && content.[name_start + 5] = 'e'
               && (!k < 0 || not (is_word_char content.[!k]));
             if not !found then j := 0 (* stop — found enclosing non-rename call *)
           end else
             decr depth
       | _ -> ());
      decr j
    done;
    !found
  in
  let replace_safely ~content ~old ~replacement =
    let buf = Buffer.create (String.length content) in
    let old_len = String.length old in
    let i = ref 0 in
    while !i < String.length content do
      if !i + old_len <= String.length content
         && String.sub content !i old_len = old
         && (!i + old_len >= String.length content
             || not (is_word_char content.[!i + old_len]))
      then begin
        (* Skip definition sites inside rename() calls: rename(new = $old).
           Only skip when preceded by = AND the = is inside rename(). *)
        let rec skip_ws j =
          if j > 0 && (content.[j-1] = ' ' || content.[j-1] = '\t') then skip_ws (j-1)
          else j
        in
        let eq_candidate = skip_ws !i in
        if eq_candidate > 0 && content.[eq_candidate - 1] = '='
           && is_in_rename_call content !i then begin
          Buffer.add_string buf old;
          i := !i + old_len
        end else begin
          Buffer.add_string buf replacement;
          i := !i + old_len
        end
      end else begin
        Buffer.add_char buf content.[!i];
        incr i
      end
    done;
    Buffer.contents buf
  in
  let dollar_old = "$" ^ old_name in
  let dollar_new = "$" ^ new_name in
  let backtick_old = "$`" ^ old_name ^ "`" in
  let backtick_new = "$`" ^ new_name ^ "`" in
  let content = replace_safely ~content ~old:dollar_old ~replacement:dollar_new in
  let content = replace_safely ~content ~old:backtick_old ~replacement:backtick_new in
  let oc = open_out file in
  Fun.protect ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc content)

let scan_raw_delimiters l in_raw_code =
  if String.length l >= 2 then
    for k = 0 to String.length l - 2 do
      if l.[k] = '<' && l.[k+1] = '{' then in_raw_code := true;
      if l.[k] = '}' && l.[k+1] = '>' then in_raw_code := false
    done

let apply_add_node_arg ~file ~node ~arg =
  let lines = ref [] in
  let ch = open_in file in
  let result = Fun.protect ~finally:(fun () -> close_in_noerr ch)
    (fun () ->
       let found = ref false in
       let paren_depth = ref 0 in
       let in_raw_code = ref false in
       let last_arg_indent = ref 0 in
       let prev_line = ref "" in
       (try
          while true do
            let l = input_line ch in
            if not !found then begin
              let trimmed = String.trim l in
              let prefix = node ^ " = " in
              if String.length trimmed >= String.length prefix
                 && String.sub trimmed 0 (String.length prefix) = prefix then begin
                let rest = String.sub trimmed (String.length prefix) (String.length trimmed - String.length prefix) in
                let rest_stripped = String.trim rest in
                if List.exists (fun fn -> String.length rest_stripped >= String.length fn + 1
                    && String.sub rest_stripped 0 (String.length fn) = fn
                    && rest_stripped.[String.length fn] = '(')
                    ["node"; "pyn"; "rn"; "jln"; "qn"; "shn"] then begin
                  found := true;
                  String.iter (function
                    | '(' when not !in_raw_code -> incr paren_depth
                    | ')' when not !in_raw_code -> decr paren_depth
                    | _ -> ()) l;
                  scan_raw_delimiters l in_raw_code;
                  prev_line := l;
                  lines := l :: !lines
                end else
                  lines := l :: !lines
              end else
                lines := l :: !lines
            end else begin
              if not !in_raw_code then
                String.iter (function
                  | '(' -> incr paren_depth
                  | ')' -> decr paren_depth
                  | _ -> ()) l;
              scan_raw_delimiters l in_raw_code;
              if !paren_depth = 0 && not !in_raw_code then begin
                let trimmed_prev = String.trim !prev_line in
                if String.length trimmed_prev > 0 then begin
                  let last_char = trimmed_prev.[String.length trimmed_prev - 1] in
                  if last_char <> ',' && last_char <> '(' then begin
                    (* Replace the head of lines (prev_line) with a comma-terminated version.
                       Guard: lines is guaranteed non-empty here because found=true requires
                       having pushed at least the definition line, but be defensive. *)
                    match !lines with
                    | _ :: rest -> lines := (!prev_line ^ ",") :: rest
                    | [] -> ()
                  end
                end;
                let pad = String.make !last_arg_indent ' ' in
                lines := l :: Printf.sprintf "%s%s" pad arg :: !lines
              end else begin
                let trimmed_l = String.trim l in
                if trimmed_l <> "" && trimmed_l.[0] <> '-' then begin
                  let rec count s n =
                    if n < String.length s && s.[n] = ' ' then count s (n + 1) else n
                  in
                  last_arg_indent := count l 0
                end;
                prev_line := l;
                lines := l :: !lines
              end
            end
          done
        with End_of_file -> ());
       !found)
  in
  if result then begin
    let oc = open_out file in
    Fun.protect ~finally:(fun () -> close_out_noerr oc)
      (fun () ->
         List.iter (fun l -> output_string oc (l ^ "\n")) (List.rev !lines))
  end;
  result

(* Renames a pipeline node definition line whose name collides with a builtin
   or runtime symbol. Only lines matching `name = node(` / `pyn(` / `rn(` /
   `jln(` / `qn(` / `shn(` are candidates — this confines the edit to actual
   node definitions inside pipeline blocks.

   Safety: downstream references to the node (`deps = [count]`, sibling
   expressions like `model = count + 1`, or the node's name inside another
   node's raw code block) cannot be rewritten safely at the text level — e.g. a
   bare `count` inside `command = <{ df |> count(cyl) }>` is R's dplyr::count,
   not a reference to the node. Rather than silently leaving such references
   dangling (which would re-bind `count` to the builtin after the rename), we
   REFUSE to apply the rename when the old name appears as a bare identifier
   anywhere in the file outside the definition line and its own raw-code block.
   The fix is then reported as skipped and the user renames references manually.

   The definition node's OWN raw code block is exempt: occurrences there (e.g.
   the node's own R code using `count` as dplyr::count) are not references to
   the node. Literal-value nodes (`pipeline { count = 0 }`) have no constructor
   to gate on, so they are not auto-renamed and return false.

   Limitation: a raw block that closes mid-line may hide a reference on the
   remainder of that line from this check. In practice such an occurrence can
   only live inside the definition node's own argument block, where `old_name`
   is the node itself — i.e. a self-reference (a dependency cycle), which is an
   invalid pipeline regardless. *)
(* Outcome of scanning a file for a node rename, shared by the real apply and
   the dry-run probe so both agree on whether a rename would go through. *)
type rename_node_outcome =
  | Renamed of string list * int
      (* all_lines, 0-based index of the definition line — the rename is clean *)
  | Refused of int list
      (* 1-based line numbers of blocking references outside the node's block *)
  | NotFound

(* Scans [file] for a constructor-form definition of [old_name] and checks
   whether the rename can be applied safely, without modifying the file.

   Refuses (Refused lines) if the old name appears as a bare identifier
   anywhere outside the definition node's own block (its definition line plus
   the rest of its `node(...)` call, including its own raw code block).
   Occurrences inside the def node's own block are its own configuration or own
   code (e.g. R's dplyr::count) — never references to the node. Anything
   outside — deps lists, sibling expressions, other nodes' raw blocks,
   top-level bindings — refuses the rename. Paren depth is tracked across
   lines (ignoring parens inside raw code) so a multi-line `node(...)` call
   keeps its own block. Returns NotFound when there is no constructor-form
   definition or the file cannot be opened. *)
let scan_rename_node ~file ~old_name : rename_node_outcome =
  try
    let ch = open_in file in
    let all_lines = Fun.protect ~finally:(fun () -> close_in_noerr ch)
      (fun () ->
         let lines = ref [] in
         (try
            while true do lines := input_line ch :: !lines done
          with End_of_file -> ());
         List.rev !lines)
    in
    (* Phase A: locate the constructor-form definition line. *)
    let def_index = ref None in
    List.iteri (fun i l ->
      if !def_index = None then begin
        let trimmed = String.trim l in
        let prefix = old_name ^ " = " in
        if String.length trimmed >= String.length prefix
           && String.sub trimmed 0 (String.length prefix) = prefix then begin
          let rest = String.sub trimmed (String.length prefix) (String.length trimmed - String.length prefix) in
          let rest_stripped = String.trim rest in
          if List.exists (fun fn -> String.length rest_stripped >= String.length fn + 1
              && String.sub rest_stripped 0 (String.length fn) = fn
              && rest_stripped.[String.length fn] = '(')
              ["node"; "pyn"; "rn"; "jln"; "qn"; "shn"] then
            def_index := Some i
        end
      end
    ) all_lines;
    match !def_index with
    | None -> NotFound
    | Some di ->
        (* Phase B: collect blocking references outside the def node's own
           block. *)
        let in_raw = ref false in
        let paren_depth = ref 0 in
        let in_def_block = ref false in
        let blocking = ref [] in
        let scan_state l =
          if not !in_raw then
            String.iter (function
              | '(' -> incr paren_depth
              | ')' -> decr paren_depth
              | _ -> ()) l;
          scan_raw_delimiters l in_raw
        in
        List.iteri (fun i l ->
          if i = di then begin
            in_def_block := true;
            scan_state l;
            if !paren_depth = 0 then in_def_block := false
          end else if !in_def_block && !paren_depth > 0 then begin
            scan_state l;
            if !paren_depth = 0 then in_def_block := false
          end else begin
            (* Before the definition line or past the def node's block: this
               line may reference the node. *)
            if contains_word ~content:l ~word:old_name then
              blocking := (i + 1) :: !blocking
          end
        ) all_lines;
        if !blocking = [] then Renamed (all_lines, di)
        else Refused (List.rev !blocking)
  with Sys_error _ -> NotFound

(* Renames a pipeline node definition line whose name collides with a builtin
   or runtime symbol. See scan_rename_node for the refusal semantics: when the
   old name is referenced elsewhere in the file the file is left untouched and
   false is returned (the fix is reported as skipped), so no reference is ever
   silently re-bound to the builtin. Literal-value nodes
   (`pipeline { count = 0 }`) have no constructor to gate on, so they are not
   auto-renamed and return false. *)
let apply_rename_node ~file ~old_name ~new_name =
  match scan_rename_node ~file ~old_name with
  | Refused _ | NotFound -> false
  | Renamed (all_lines, di) ->
      (* Phase C: rewrite the definition line in place. *)
      let rewritten =
        List.mapi (fun i l ->
          if i = di then begin
            let trimmed = String.trim l in
            let indent_len = String.length l - String.length trimmed in
            let indent = String.sub l 0 indent_len in
            let rest = String.sub trimmed (String.length old_name) (String.length trimmed - String.length old_name) in
            indent ^ new_name ^ rest
          end else l
        ) all_lines
      in
      let oc = open_out file in
      Fun.protect ~finally:(fun () -> close_out_noerr oc)
        (fun () -> List.iter (fun l -> output_string oc (l ^ "\n")) rewritten);
      true

(* Human-readable reason for a refused rename, or None when the rename is clean
   or there is nothing to rename. Used to tell the user which lines still
   reference the node so they can rename them manually. *)
let rename_node_refusal_note ~file ~old_name : string option =
  match scan_rename_node ~file ~old_name with
  | Refused lines ->
      Some (Printf.sprintf
        "Node `%s` is still referenced on %s %s of %s — rename the node and its references manually."
        old_name
        (if List.length lines = 1 then "line" else "lines")
        (String.concat ", " (List.map string_of_int lines))
        file)
  | Renamed _ | NotFound -> None

let apply_fix ~file (fix : Diagnostics.suggested_fix) =
  (* NOTE: t fix applies ALL non-NoFix suggestions regardless of confidence.
     Confidence is informational for agents/tools to decide whether to auto-apply
     or review first. The fix-kind filtering below (Suggest_identifier -> false,
     Run_command -> false) is based on fix type, not confidence level. *)
  match fix with
  | Rename_column { old_name; new_name; _ } ->
      apply_rename_column ~file ~old_name ~new_name; true
  | Add_node_arg { node; arg; _ } ->
      apply_add_node_arg ~file ~node ~arg
  | Rename_node { old_name; new_name; _ } ->
      apply_rename_node ~file ~old_name ~new_name
  | Suggest_identifier _ -> false
  | Run_command _ -> false
  | NoFix -> false

(* Sort fixes by descending line within each file, so bottom-up application
   avoids line-number drift when multiple fixes target the same file. *)
let sort_fixes_by_descending_line fixes =
  List.sort (fun a b ->
    let fa = Option.value ~default:"" a.Diagnostics.diag_file in
    let fb = Option.value ~default:"" b.Diagnostics.diag_file in
    let cmp = String.compare fa fb in
    if cmp <> 0 then cmp
    else
      let la = Option.value ~default:0 a.Diagnostics.diag_line in
      let lb = Option.value ~default:0 b.Diagnostics.diag_line in
      compare lb la
  ) fixes

let apply_fixes ~dry_run ~default_file (fixes : Diagnostics.diagnostic list) =
  let applied = ref 0 in
  let skipped = ref 0 in
  let would_apply = ref 0 in
  let skip_notes = ref [] in
  let add_note (d : Diagnostics.diagnostic) =
    match d.diag_suggested_fix with
    | Diagnostics.Rename_node { old_name; _ } ->
        let file_to_fix = match d.diag_file with
          | Some f -> f
          | None -> default_file
        in
        (match rename_node_refusal_note ~file:file_to_fix ~old_name with
         | Some note -> skip_notes := note :: !skip_notes
         | None -> ())
    | _ -> ()
  in
  List.iter (fun (d : Diagnostics.diagnostic) ->
    if dry_run then begin
      Printf.printf "Would apply: %s on %s\n" d.diag_message
        (match d.diag_file with Some f -> f | None -> "<unknown>");
      let would_work = match d.diag_suggested_fix with
        | Diagnostics.Rename_column _ -> true
        | Diagnostics.Add_node_arg _ -> true
        (* Dry-run probes the file through scan_rename_node so it agrees with
           the real apply: a Rename_node whose target is referenced elsewhere
           in the file is reported as skipped, not would-apply. *)
        | Diagnostics.Rename_node { old_name; _ } ->
            let file_to_fix = match d.diag_file with
              | Some f -> f
              | None -> default_file
            in
            (match scan_rename_node ~file:file_to_fix ~old_name with
             | Renamed _ -> true
             | _ -> false)
        | _ -> false
      in
      if would_work then incr would_apply
      else begin
        incr skipped;
        add_note d
      end
    end else begin
      let file_to_fix = match d.diag_file with
        | Some f -> f
        | None -> default_file
      in
      if apply_fix ~file:file_to_fix d.diag_suggested_fix then
        incr applied
      else begin
        incr skipped;
        add_note d
      end
    end
  ) fixes;
  { file = default_file; applied = !applied; skipped = !skipped;
    would_apply = !would_apply; dry_run; diagnostics = fixes;
    skip_notes = List.rev !skip_notes }

(* cmd_fix accepts a check function to avoid circular dependency with Repl.
   The caller (repl.ml) passes run_check ~schema:true. *)
let cmd_fix ?(dry_run = false) ~check_fn file =
  let check_result = check_fn file in
  let fixes = Diagnostics.check_result_entries check_result
    |> List.filter_map (fun d ->
      match d.Diagnostics.diag_suggested_fix with
      | Diagnostics.NoFix -> None
      | _ -> Some d
    )
    |> sort_fixes_by_descending_line
  in
  apply_fixes ~dry_run ~default_file:file fixes
