(* src/fix.ml *)
(* Mechanical application of suggested_fix from diagnostics *)

type fix_result = {
  file : string;
  applied : int;
  skipped : int;
  would_apply : int;
  diagnostics : Diagnostics.diagnostic list;
}

let apply_cast ~file ~line ~column ~cast_to =
  let lines = ref [] in
  let ch = open_in file in
  Fun.protect ~finally:(fun () -> close_in_noerr ch)
    (fun () ->
       let i = ref 1 in
       try
         while true do
           let l = input_line ch in
           if !i = line then
             let indent =
               let rec count s n =
                 if n < String.length s && s.[n] = ' ' then count s (n + 1) else n
               in
               count l 0
             in
             let pad = String.make indent ' ' in
             lines := l :: Printf.sprintf "%s|> mutate($%s = as.%s($%s))" pad column cast_to column :: !lines
           else
             lines := l :: !lines;
           incr i
         done
       with End_of_file -> ());
  let oc = open_out file in
  Fun.protect ~finally:(fun () -> close_out_noerr oc)
    (fun () ->
       List.iter (fun l -> output_string oc (l ^ "\n")) (List.rev !lines))

let is_word_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
  | _ -> false

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
                  if String.length l >= 2 then
                    for k = 0 to String.length l - 2 do
                      if l.[k] = '<' && l.[k+1] = '{' then in_raw_code := true;
                      if l.[k] = '}' && l.[k+1] = '>' then in_raw_code := false
                    done;
                  prev_line := l;
                  lines := l :: !lines
                end else
                  lines := l :: !lines
              end else
                lines := l :: !lines
            end else begin
              if not !in_raw_code then begin
                String.iter (function
                  | '(' -> incr paren_depth
                  | ')' -> decr paren_depth
                  | _ -> ()) l;
                if String.length l >= 2 then
                  for k = 0 to String.length l - 2 do
                    if l.[k] = '<' && l.[k+1] = '{' then in_raw_code := true;
                    if l.[k] = '}' && l.[k+1] = '>' then in_raw_code := false
                  done;
              end else begin
                if String.length l >= 2 then
                  for k = 0 to String.length l - 2 do
                    if l.[k] = '<' && l.[k+1] = '{' then in_raw_code := true;
                    if l.[k] = '}' && l.[k+1] = '>' then in_raw_code := false
                  done;
              end;
              if !paren_depth = 0 && not !in_raw_code then begin
                let trimmed_prev = String.trim !prev_line in
                if String.length trimmed_prev > 0 then begin
                  let last_char = trimmed_prev.[String.length trimmed_prev - 1] in
                  if last_char <> ',' && last_char <> '(' then begin
                    lines := (!prev_line ^ ",") :: List.tl !lines
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

let apply_fix ~file (fix : Diagnostics.suggested_fix) =
  match fix with
  | Cast { column; cast_to; file = _; line; target_node = _ } ->
      (match line with
       | Some l -> apply_cast ~file ~line:l ~column ~cast_to; true
       | None -> false)
  | Rename_column { old_name; new_name; file = _; line = _; target_node = _ } ->
      apply_rename_column ~file ~old_name ~new_name; true
  | Add_node_arg { node; arg; file = _; line = _; target_node = _ } ->
      apply_add_node_arg ~file ~node ~arg
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
  List.iter (fun (d : Diagnostics.diagnostic) ->
    if dry_run then begin
      Printf.printf "Would apply: %s on %s\n" d.diag_message
        (match d.diag_file with Some f -> f | None -> "<unknown>");
      let would_work = match d.diag_suggested_fix with
        | Diagnostics.Cast { line = Some _; _ } -> true
        | Diagnostics.Rename_column _ -> true
        | Diagnostics.Add_node_arg _ -> true
        | _ -> false
      in
      if would_work then incr would_apply else incr skipped
    end else begin
      let file_to_fix = match d.diag_file with
        | Some f -> f
        | None -> default_file
      in
      if apply_fix ~file:file_to_fix d.diag_suggested_fix then
        incr applied
      else
        incr skipped
    end
  ) fixes;
  { file = default_file; applied = !applied; skipped = !skipped;
    would_apply = !would_apply; diagnostics = fixes }

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
