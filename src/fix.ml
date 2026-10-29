(* src/fix.ml *)
(* Mechanical application of suggested_fix from diagnostics *)

type dry_run_outcome =
  | Would_apply
  | Skipped of string option
      (* Some note = human-readable reason the fix was (or would be) skipped;
         None = skipped without an explanation (e.g. nothing to rename). *)

type dry_run_entry = {
  entry_message : string;
  entry_file : string;
  entry_outcome : dry_run_outcome;
}

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
  dry_run_entries : dry_run_entry list;
      (* Per-fix dry-run preview: message, file, and outcome for every fix when
         dry_run is true. Empty in real mode. The CLI renders these lines; the
         T function t_fix() renders its own summary, so apply_fixes itself does
         not print. *)
}

let is_word_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
  | _ -> false

(* Lexical masks for Replace_text. [blocked] marks bytes inside a `--` line
   comment or a `<{ ... }>` raw code block; [in_string] marks bytes inside a
   double-quoted string literal (quotes included). Replace_text never edits
   comments or raw blocks, and only edits a string literal when the old text
   itself starts with a quote (e.g. read_log("a") -> read_log(p.a)).
   Multi-byte UTF-8 bytes are treated as ordinary bytes; a replacement never
   splits a character because both old and new text are whole strings.
   Unclosed strings/comments simply extend to the end of the input, which can
   only make the fix more conservative. *)
let scan_lexical_masks content =
  let n = String.length content in
  let blocked = Array.make n false in
  let in_string = Array.make n false in
  let i = ref 0 in
  let in_str = ref false in
  let in_raw = ref false in
  while !i < n do
    let c = content.[!i] in
    if !in_raw then begin
      blocked.(!i) <- true;
      if c = '}' && !i + 1 < n && content.[!i + 1] = '>' then begin
        blocked.(!i + 1) <- true;
        in_raw := false;
        i := !i + 2
      end else incr i
    end else if !in_str then begin
      in_string.(!i) <- true;
      if c = '\\' && !i + 1 < n then begin
        in_string.(!i + 1) <- true;
        i := !i + 2
      end else begin
        if c = '"' then in_str := false;
        incr i
      end
    end else if c = '"' then begin
      in_string.(!i) <- true;
      in_str := true;
      incr i
    end else if c = '<' && !i + 1 < n && content.[!i + 1] = '{' then begin
      blocked.(!i) <- true;
      blocked.(!i + 1) <- true;
      in_raw := true;
      i := !i + 2
    end else if c = '-' && !i + 1 < n && content.[!i + 1] = '-' then begin
      while !i < n && content.[!i] <> '\n' do
        blocked.(!i) <- true;
        incr i
      done
    end else incr i
  done;
  (blocked, in_string)

(* Byte range [start, stop) of the 1-based line [line], or None when the file
   has fewer lines. The line's terminating newline is excluded. *)
let line_span content line =
  if line < 1 then None
  else begin
    let n = String.length content in
    let rec go i current =
      if current = line then
        match String.index_from_opt content i '\n' with
        | Some j -> Some (i, j)
        | None -> Some (i, n)
      else if i >= n then None
      else
        match String.index_from_opt content i '\n' with
        | Some j -> go (j + 1) (current + 1)
        | None -> None
    in
    go 0 1
  end

(* A match may start at [i] only on a word boundary: no word character before
   a word-initial old text (`p.mode` must not match inside `xp.mode`). *)
let left_boundary_ok content i old_text =
  String.length old_text > 0
  && (not (is_word_char old_text.[0])
      || i = 0
      || not (is_word_char content.[i - 1]))

(* A match may end at [i + len] only on a word boundary: no word character
   after a word-final old text, and no `(` so a bare identifier is not
   rewritten inside an existing call (`Missing` must not match inside
   `Missing()` or `MissingValue`, `^arrow` must not match inside `^arrow_ipc`). *)
let right_boundary_ok content i old_text =
  let m = String.length old_text in
  if m = 0 || not (is_word_char old_text.[m - 1]) then true
  else
    let after = i + m in
    after >= String.length content
    || (not (is_word_char content.[after]) && content.[after] <> '(')

(* Every byte of the candidate match must be editable text: not in a comment
   or raw block, and not inside a string literal unless the old text itself
   starts with a quote. *)
let match_is_editable ~blocked ~in_string ~content ~old_text i =
  let m = String.length old_text in
  let allow_string = m > 0 && old_text.[0] = '"' in
  let rec ok k =
    if k >= m then true
    else if blocked.(i + k) then false
    else if in_string.(i + k) && not allow_string then false
    else ok (k + 1)
  in
  ok 0 &&
  left_boundary_ok content i old_text &&
  right_boundary_ok content i old_text

(* Start offsets of every replaceable occurrence of [old_text], in order.
   When [line] is given the search is confined to that line, so the same old
   text in another node (or in a later diagnostic) is left untouched. When
   [column] is also given, only one occurrence is returned: the first at or
   after that 1-based source column, or the nearest earlier one. A quoted
   argument like "a" can appear more than once on a line, and only the
   diagnosed occurrence must change. *)
let replace_positions ~content ~old_text ~line ?column () =
  let m = String.length old_text in
  if m = 0 then []
  else begin
    let (blocked, in_string) = scan_lexical_masks content in
    let n = String.length content in
    let start, stop =
      match line with
      | None -> (0, n)
      | Some l ->
          (match line_span content l with
           | Some (a, b) -> (a, b)
           | None -> (0, 0))
    in
    let rec loop i acc =
      if i + m > stop then List.rev acc
      else if String.sub content i m = old_text
              && match_is_editable ~blocked ~in_string ~content ~old_text i
      then loop (i + m) (i :: acc)
      else loop (i + 1) acc
    in
    let positions = loop start [] in
    (* `column` is a 1-based source column within its line, while positions are
       absolute byte offsets. Convert to an absolute target; without a line the
       column carries no usable position. *)
    let column_target =
      match line, column with
      | Some _, Some col -> Some (start + max 1 col - 1)
      | _ -> None
    in
    match column_target with
    | None -> positions
    | Some target ->
        (* Prefer the first occurrence at or after the diagnosed column — the
           fix text sits at or after the construct the diagnostic names. Fall
           back to the nearest earlier occurrence when it does not. *)
        let first_after =
          List.find_opt (fun pos -> pos >= target) positions
        in
        let nearest =
          List.fold_left (fun acc pos ->
            let distance = abs (pos - target) in
            match acc with
            | None -> Some (pos, distance)
            | Some (_, best) when distance < best -> Some (pos, distance)
            | _ -> acc) None positions
        in
        (match first_after, nearest with
         | Some pos, _ -> [pos]
         | None, Some (pos, _) -> [pos]
         | None, None -> [])
  end

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

(* Walk backward from [pos] to check if this $col is inside a rename() call.
   Finds the nearest unmatched '(', then checks if the identifier before it
   is "rename". Handles nested calls by tracking paren depth. Shared by the
   real apply and the dry-run probe so both agree on what counts as a
   renameable reference. *)
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

(* Is the `$col` occurrence at [pos] a rename() definition site
   (`rename(new = $old)`), which the apply leaves untouched? Only when
   preceded by `=` (modulo spaces/tabs) AND inside a rename() call. *)
let is_rename_def_site content pos =
  let rec skip_ws j =
    if j > 0 && (content.[j-1] = ' ' || content.[j-1] = '\t') then skip_ws (j-1)
    else j
  in
  let eq_candidate = skip_ws pos in
  eq_candidate > 0 && content.[eq_candidate - 1] = '='
  && is_in_rename_call content pos

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
        if is_rename_def_site content !i then begin
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

(* Does [trimmed_line] define [node] as a pipeline node, i.e. `node = node(` /
   `pyn(` / `rn(` / `jln(` / `qn(` / `shn(`? Shared by the dry-run probe and
   the real apply so both agree on which lines count as node definitions. *)
let is_node_definition ~node ~trimmed_line =
  let prefix = node ^ " = " in
  if String.length trimmed_line >= String.length prefix
     && String.sub trimmed_line 0 (String.length prefix) = prefix then begin
    let rest = String.sub trimmed_line (String.length prefix) (String.length trimmed_line - String.length prefix) in
    let rest_stripped = String.trim rest in
    List.exists (fun fn -> String.length rest_stripped >= String.length fn + 1
        && String.sub rest_stripped 0 (String.length fn) = fn
        && rest_stripped.[String.length fn] = '(')
      ["node"; "pyn"; "rn"; "jln"; "qn"; "shn"]
  end else false

(* Lightweight probe for the Rename_column dry-run: does [file] contain a
   renameable column reference to [old_name] (`$old` or `` $`old` ``)?
   Some true = reference found, Some false = file readable but no reference,
   None = file unreadable. Mirrors the match logic in apply_rename_column —
   including the rename() definition-site skip — so the preview agrees with
   what the real apply would change. *)
let scan_rename_column ~file ~old_name : bool option =
  try
    let ch = open_in file in
    let content = Fun.protect ~finally:(fun () -> close_in_noerr ch)
      (fun () -> really_input_string ch (in_channel_length ch))
    in
    let dollar_old = "$" ^ old_name in
    let backtick_old = "$`" ^ old_name ^ "`" in
    let has_dollar =
      let old_len = String.length dollar_old in
      let n = String.length content in
      let rec loop i =
        if i + old_len > n then false
        else if String.sub content i old_len = dollar_old
                && (i + old_len >= n || not (is_word_char content.[i + old_len]))
                && not (is_rename_def_site content i)
        then true
        else loop (i + 1)
      in
      loop 0
    in
    let has_backtick =
      let old_len = String.length backtick_old in
      let n = String.length content in
      let rec loop i =
        if i + old_len > n then false
        else if String.sub content i old_len = backtick_old then true
        else loop (i + 1)
      in
      loop 0
    in
    Some (has_dollar || has_backtick)
  with Sys_error _ -> None

(* Lightweight probe for the Add_node_arg dry-run: does [file] define [node]?
   Some true = defined, Some false = file readable but no node definition found,
   None = file unreadable (matches Rename_node's NotFound outcome). *)
let scan_add_node_arg ~file ~node : bool option =
  try
    let found = ref false in
    let ch = open_in file in
    Fun.protect ~finally:(fun () -> close_in_noerr ch)
      (fun () ->
         (try
            while not !found do
              let l = input_line ch in
              if is_node_definition ~node ~trimmed_line:(String.trim l) then
                found := true
            done
          with End_of_file -> ());
         Some !found)
  with Sys_error _ -> None

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
              if is_node_definition ~node ~trimmed_line:(String.trim l) then begin
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
      if !def_index = None
         && is_node_definition ~node:old_name ~trimmed_line:(String.trim l) then
        def_index := Some i
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

(* Decide, without modifying the file, whether applying [d]'s suggested fix
   would succeed, and if not, produce a human-readable skip note. Rename_node
   probes the file through scan_rename_node so the dry-run agrees with the real
   apply: a target still referenced elsewhere in the file is reported as
   skipped, not would-apply. Fix kinds that are never auto-applied
   (Suggest_identifier, Run_command, NoFix) always report Skipped with an
   explanatory note so the user knows what to do manually. *)
let scan_replace_text ~file ~old_text ?line ?column () : bool option =
  try
    let ch = open_in file in
    let content = Fun.protect ~finally:(fun () -> close_in_noerr ch)
      (fun () -> really_input_string ch (in_channel_length ch))
    in
    Some (replace_positions ~content ~old_text ~line ?column () <> [])
  with Sys_error _ -> None

let apply_replace_text ~file ~old_text ~new_text ?line ?column () =
  try
    let ch = open_in file in
    let content = Fun.protect ~finally:(fun () -> close_in_noerr ch)
      (fun () -> really_input_string ch (in_channel_length ch))
    in
    match replace_positions ~content ~old_text ~line ?column () with
    | [] -> false
    | positions ->
        let m = String.length old_text in
        let buf = Buffer.create (String.length content + 64) in
        let last = ref 0 in
        List.iter (fun pos ->
          Buffer.add_string buf (String.sub content !last (pos - !last));
          Buffer.add_string buf new_text;
          last := pos + m
        ) positions;
        Buffer.add_string buf
          (String.sub content !last (String.length content - !last));
        let oc = open_out file in
        Fun.protect ~finally:(fun () -> close_out_noerr oc)
          (fun () -> output_string oc (Buffer.contents buf));
        true
  with Sys_error _ -> false

let dry_run_outcome ~default_file (d : Diagnostics.diagnostic) =
  let file_to_fix = match d.diag_file with Some f -> f | None -> default_file in
  match d.diag_suggested_fix with
  | Diagnostics.Rename_column { old_name; _ } ->
      (* Probe the file so the dry-run agrees with the real apply: a rename
         whose column reference is absent is skipped, not would-apply. *)
      (match scan_rename_column ~file:file_to_fix ~old_name with
       | Some true -> Would_apply
       | Some false ->
           Skipped (Some (Printf.sprintf
             "Column `$%s` not found in %s — nothing to rename." old_name file_to_fix))
       | None -> Skipped None)
  | Diagnostics.Add_node_arg { node; _ } ->
      (* Probe the file so the dry-run agrees with the real apply: a fix whose
         node is no longer defined in the file is skipped, not would-apply. *)
      (match scan_add_node_arg ~file:file_to_fix ~node with
       | Some true -> Would_apply
       | Some false ->
           Skipped (Some (Printf.sprintf
             "Node `%s` is not defined in %s — add the argument manually." node file_to_fix))
       | None -> Skipped None)
  | Diagnostics.Rename_node { old_name; _ } ->
      (match scan_rename_node ~file:file_to_fix ~old_name with
       | Renamed _ -> Would_apply
       | Refused lines ->
           Skipped (Some (Printf.sprintf
             "Node `%s` is still referenced on %s %s of %s — rename the node and its references manually."
             old_name
             (if List.length lines = 1 then "line" else "lines")
             (String.concat ", " (List.map string_of_int lines))
             file_to_fix))
       | NotFound -> Skipped None)
  | Diagnostics.Replace_text { old_text; line; column; _ } ->
      (match scan_replace_text ~file:file_to_fix ~old_text ?line ?column () with
       | Some true -> Would_apply
       | Some false ->
           Skipped (Some (Printf.sprintf
             "Text `%s` not found in %s — nothing to replace." old_text file_to_fix))
       | None -> Skipped None)
  | Diagnostics.Suggest_identifier { name; _ } ->
      Skipped (Some (Printf.sprintf
        "Identifier `%s` needs manual rename (t fix does not apply it)." name))
  | Diagnostics.Run_command { command; description; _ } ->
      Skipped (Some (Printf.sprintf "Manual step required: %s — run: %s." description command))
  | Diagnostics.NoFix -> Skipped None

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
  | Replace_text { old_text; new_text; line; column; _ } ->
      apply_replace_text ~file ~old_text ~new_text ?line ?column ()
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

(* Identical Replace_text suggestions repeated for the same file and line are
   one edit, not two. Dedupe before both dry-run and the real apply so the
   preview and the applied/skipped counts always agree. *)
let dedupe_replace_text (fixes : Diagnostics.diagnostic list) =
  let seen = Hashtbl.create 8 in
  List.filter (fun (d : Diagnostics.diagnostic) ->
    match d.diag_suggested_fix with
    | Diagnostics.Replace_text { old_text; new_text; line; column; _ } ->
        let key = Printf.sprintf "%s\000%s\000%s\000%s\000%s"
          (Option.value ~default:"" d.diag_file)
          old_text new_text
          (match line with Some l -> string_of_int l | None -> "")
          (match column with Some c -> string_of_int c | None -> "")
        in
        if Hashtbl.mem seen key then false
        else begin Hashtbl.add seen key (); true end
    | _ -> true) fixes

let apply_fixes ~dry_run ~default_file (fixes : Diagnostics.diagnostic list) =
  let fixes = dedupe_replace_text fixes in
  let applied = ref 0 in
  let skipped = ref 0 in
  let would_apply = ref 0 in
  let skip_notes = ref [] in
  let dry_run_entries = ref [] in
  let file_label (d : Diagnostics.diagnostic) =
    match d.diag_file with Some f -> f | None -> "<unknown>"
  in
  let record_skip_note (d : Diagnostics.diagnostic) =
    match dry_run_outcome ~default_file d with
    | Would_apply -> ()
    | Skipped (Some note) -> skip_notes := note :: !skip_notes
    | Skipped None -> ()
  in
  List.iter (fun (d : Diagnostics.diagnostic) ->
    if dry_run then begin
      (* One probe per fix: the outcome drives both the per-fix entry and the
         summary counts, so the preview agrees with what the real apply would do.
         Rendering of the entries is left to the caller (the CLI prints them;
         t_fix() renders its own summary) so apply_fixes itself stays side-effect
         free and t_fix() does not leak raw lines to stdout. *)
      match dry_run_outcome ~default_file d with
      | Would_apply ->
          incr would_apply;
          dry_run_entries := { entry_message = d.diag_message; entry_file = file_label d; entry_outcome = Would_apply } :: !dry_run_entries
      | Skipped note ->
          incr skipped;
          (match note with
           | Some n -> skip_notes := n :: !skip_notes
           | None -> ());
          dry_run_entries := { entry_message = d.diag_message; entry_file = file_label d; entry_outcome = Skipped note } :: !dry_run_entries
    end else begin
      let file_to_fix = match d.diag_file with Some f -> f | None -> default_file in
      if apply_fix ~file:file_to_fix d.diag_suggested_fix then
        incr applied
      else begin
        incr skipped;
        record_skip_note d
      end
    end
  ) fixes;
  { file = default_file; applied = !applied; skipped = !skipped;
    would_apply = !would_apply; dry_run; diagnostics = fixes;
    skip_notes = List.rev !skip_notes;
    dry_run_entries = List.rev !dry_run_entries }

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

(** Machine-readable form of a fix result, for `t fix --json` and agents.
    Additive: text output is unchanged. Per-entry outcomes carry the
    human message plus a machine outcome; full diagnostics (with fix
    kind JSON) ride along so agents need no text parsing. *)
let fix_result_to_yojson (r : fix_result) =
  let entry_to_yojson e =
    let outcome, note = match e.entry_outcome with
      | Would_apply -> ("would_apply", None)
      | Skipped n -> ("skipped", n)
    in
    `Assoc [
      ("message", `String e.entry_message);
      ("file", `String e.entry_file);
      ("outcome", `String outcome);
      ("note", (match note with Some n -> `String n | None -> `Null));
    ]
  in
  `Assoc [
    ("schema_version", `String "1");
    ("file", `String r.file);
    ("dry_run", `Bool r.dry_run);
    ("applied", `Int r.applied);
    ("skipped", `Int r.skipped);
    ("would_apply", `Int r.would_apply);
    ("skip_notes", `List (List.map (fun s -> `String s) r.skip_notes));
    ("entries", `List (List.map entry_to_yojson r.dry_run_entries));
    ("diagnostics", `List (List.map Diagnostics.diagnostic_to_yojson r.diagnostics));
  ]
