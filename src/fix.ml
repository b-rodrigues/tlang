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
     [a-zA-Z0-9_], so $id is not matched inside $identity. *)
  let dollar_old = "$" ^ old_name in
  let dollar_new = "$" ^ new_name in
  let backtick_old = "$`" ^ old_name ^ "`" in
  let backtick_new = "$`" ^ new_name ^ "`" in
  let content = replace_word_bound ~content ~old:dollar_old ~replacement:dollar_new in
  let content = replace_word_bound ~content ~old:backtick_old ~replacement:backtick_new in
  let oc = open_out file in
  Fun.protect ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc content)

let apply_fix ~file (fix : Diagnostics.suggested_fix) =
  match fix with
  | Cast { column; cast_to; file = _; line } ->
      (match line with
       | Some l -> apply_cast ~file ~line:l ~column ~cast_to; true
       | None -> false)
  | Rename_column { old_name; new_name; file = _; line = _ } ->
      apply_rename_column ~file ~old_name ~new_name; true
  | Add_node_arg _ -> false
  | Pin_package_version _ -> false
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
