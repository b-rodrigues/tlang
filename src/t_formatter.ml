(* src/t_formatter.ml *)
(* Canonical, comment-preserving, raw-block-preserving formatter for T source files. *)

type line_segment =
  | SegCode of string
  | SegString of string
  | SegBacktick of string
  | SegRaw of string
  | SegComment of string

let is_ident_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
  | _ -> false

(* Split a single non-raw, non-multiline-string line into code, string,
   backtick, inline raw-block, and comment segments.
   Returns (segments, opens_multiline_raw, opens_multiline_str). *)
let split_line_segments line =
  let n = String.length line in
  let segs = ref [] in
  let buf = Buffer.create n in
  let flush_code () =
    if Buffer.length buf > 0 then begin
      segs := SegCode (Buffer.contents buf) :: !segs;
      Buffer.clear buf
    end
  in
  let opens_raw = ref false in
  let opens_str = ref false in
  let i = ref 0 in
  while !i < n do
    let c = line.[!i] in
    if c = '-' && !i + 1 < n && line.[!i + 1] = '-' then begin
      flush_code ();
      segs := SegComment (String.sub line !i (n - !i)) :: !segs;
      i := n
    end else if c = '<' && !i + 1 < n && line.[!i + 1] = '{' then begin
      flush_code ();
      let start = !i in
      i := !i + 2;
      let found_close = ref false in
      while !i < n && not !found_close do
        if line.[!i] = '}' && !i + 1 < n && line.[!i + 1] = '>' then begin
          i := !i + 2;
          found_close := true
        end else incr i
      done;
      segs := SegRaw (String.sub line start (!i - start)) :: !segs;
      if not !found_close then opens_raw := true
    end else if c = '"' then begin
      flush_code ();
      let start = !i in
      incr i;
      let closed = ref false in
      while !i < n && not !closed do
        if line.[!i] = '\\' && !i + 1 < n then i := !i + 2
        else if line.[!i] = '"' then begin
          incr i;
          closed := true
        end else incr i
      done;
      segs := SegString (String.sub line start (!i - start)) :: !segs;
      if not !closed then opens_str := true
    end else if c = '`' then begin
      flush_code ();
      let start = !i in
      incr i;
      let closed = ref false in
      while !i < n && not !closed do
        if line.[!i] = '`' then begin
          incr i;
          closed := true
        end else incr i
      done;
      segs := SegBacktick (String.sub line start (!i - start)) :: !segs
    end else begin
      Buffer.add_char buf c;
      incr i
    end
  done;
  flush_code ();
  (List.rev !segs, !opens_raw, !opens_str)

let trim_trailing_space buf =
  let len = ref (Buffer.length buf) in
  while !len > 0 && Buffer.nth buf (!len - 1) = ' ' do
    decr len
  done;
  Buffer.truncate buf !len

let is_operand_end = function
  | Some c -> is_ident_char c || c = ')' || c = ']' || c = '"' || c = '`' || c = '>'
  | None -> false

(* Normalize spacing within a pure T-code segment.
   [prev] is the last character emitted before this segment (e.g. a quote or
   closing angle bracket from an adjacent string or raw block); [has_next] is
   true when another non-comment code/literal segment follows on the same line. *)
let format_code_segment ~prev ~has_next s =
  let n = String.length s in
  let buf = Buffer.create (n + 8) in
  let last_char () =
    let len = Buffer.length buf in
    if len = 0 then prev else Some (Buffer.nth buf (len - 1))
  in
  let last_non_space () =
    let len = Buffer.length buf in
    let rec scan k =
      if k < 0 then prev
      else if Buffer.nth buf k = ' ' then scan (k - 1)
      else Some (Buffer.nth buf k)
    in
    scan (len - 1)
  in
  let ensure_space () =
    match last_char () with
    | None | Some ' ' | Some '(' | Some '[' -> ()
    | Some _ -> Buffer.add_char buf ' '
  in
  let i = ref 0 in
  while !i < n do
    let c = s.[!i] in
    if c = ' ' || c = '\t' then begin
      (match last_char () with
       | None | Some ' ' | Some '(' | Some '[' -> ()
       | Some _ -> Buffer.add_char buf ' ');
      while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done
    end else if c = ',' then begin
      trim_trailing_space buf;
      Buffer.add_char buf ',';
      if !i + 1 < n || has_next then Buffer.add_char buf ' ';
      incr i;
      while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done
    end else if c = '(' || c = '[' then begin
      Buffer.add_char buf c;
      incr i;
      while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done
    end else if c = ')' || c = ']' then begin
      trim_trailing_space buf;
      Buffer.add_char buf c;
      incr i
    end else if c = '?' && !i + 2 < n && s.[!i + 1] = '|' && s.[!i + 2] = '>' then begin
      ensure_space ();
      Buffer.add_string buf "?|>";
      if !i + 3 < n || has_next then Buffer.add_char buf ' ';
      i := !i + 3;
      while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done
    end else if (c = '|' && !i + 1 < n && s.[!i + 1] = '>')
             || (c = '=' && !i + 1 < n && (s.[!i + 1] = '=' || s.[!i + 1] = '>'))
             || (c = '!' && !i + 1 < n && s.[!i + 1] = '=')
             || (c = '<' && !i + 1 < n && s.[!i + 1] = '=')
             || (c = '>' && !i + 1 < n && s.[!i + 1] = '=')
             || (c = ':' && !i + 1 < n && s.[!i + 1] = '=')
             || (c = '-' && !i + 1 < n && s.[!i + 1] = '>')
             || (c = '&' && !i + 1 < n && s.[!i + 1] = '&')
             || (c = '|' && !i + 1 < n && s.[!i + 1] = '|') then begin
      let op = String.sub s !i 2 in
      ensure_space ();
      Buffer.add_string buf op;
      if !i + 2 < n || has_next then Buffer.add_char buf ' ';
      i := !i + 2;
      while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done
    end else if c = '=' then begin
      ensure_space ();
      Buffer.add_char buf '=';
      if !i + 1 < n || has_next then Buffer.add_char buf ' ';
      incr i;
      while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done
    end else if (c = '+' || c = '*' || c = '/')
             || (c = '-' && is_operand_end (last_non_space ())) then begin
      (* Skip scientific notation like 1e-5 or 1e+5 *)
      let is_sci =
        (c = '-' || c = '+')
        && !i > 0 && (s.[!i - 1] = 'e' || s.[!i - 1] = 'E')
        && !i >= 2 && s.[!i - 2] >= '0' && s.[!i - 2] <= '9'
      in
      if is_sci then begin
        Buffer.add_char buf c;
        incr i
      end else begin
        ensure_space ();
        Buffer.add_char buf c;
        if !i + 1 < n || has_next then Buffer.add_char buf ' ';
        incr i;
        while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done
      end
    end else if c = '{' then begin
      (match last_char () with
       | Some ch when is_ident_char ch || ch = ')' || ch = ']' -> Buffer.add_char buf ' '
       | _ -> ());
      Buffer.add_char buf '{';
      incr i
    end else begin
      Buffer.add_char buf c;
      incr i
    end
  done;
  Buffer.contents buf

let trim_right s =
  let len = String.length s in
  let i = ref (len - 1) in
  while !i >= 0 && (s.[!i] = ' ' || s.[!i] = '\t' || s.[!i] = '\r') do
    decr i
  done;
  String.sub s 0 (!i + 1)

let has_non_comment_next = function
  | [] | [SegComment _] -> false
  | SegComment _ :: _ -> false
  | _ -> true

let format_segments segs =
  let buf = Buffer.create 128 in
  let last_char () =
    let len = Buffer.length buf in
    if len = 0 then None else Some (Buffer.nth buf (len - 1))
  in
  let rec loop = function
    | [] -> ()
    | seg :: rest ->
        (match seg with
         | SegCode c ->
             let prev = last_char () in
             let has_next = has_non_comment_next rest in
             let fc = format_code_segment ~prev ~has_next c in
             if fc <> "" then begin
               (match last_char (), fc.[0] with
                | Some ' ', ' ' ->
                    Buffer.add_string buf (String.sub fc 1 (String.length fc - 1))
                | _ -> Buffer.add_string buf fc)
             end
         | SegString s | SegBacktick s | SegRaw s ->
             Buffer.add_string buf s
         | SegComment c ->
             trim_trailing_space buf;
             if Buffer.length buf > 0 then Buffer.add_char buf ' ';
             Buffer.add_string buf (trim_right c));
        loop rest
  in
  loop segs;
  String.trim (Buffer.contents buf)

(* Count leading closing delimiters and net bracket delta in code segments. *)
let bracket_counts segs =
  let leading_close = ref 0 in
  let saw_non_close = ref false in
  let delta = ref 0 in
  List.iter (function
    | SegCode c ->
        String.iter (fun ch ->
          match ch with
          | ' ' | '\t' -> ()
          | '}' | ')' | ']' ->
              if not !saw_non_close then incr leading_close;
              decr delta
          | '{' | '(' | '[' ->
              saw_non_close := true;
              incr delta
          | _ ->
              saw_non_close := true
        ) c
    | SegString _ | SegBacktick _ | SegRaw _ ->
        saw_non_close := true
    | SegComment _ -> ()
  ) segs;
  (!leading_close, !delta)

let line_closes_raw line =
  let n = String.length line in
  let rec find i =
    if i + 1 >= n then None
    else if line.[i] = '}' && line.[i + 1] = '>' then Some (i + 2)
    else find (i + 1)
  in
  find 0

let line_closes_string line =
  let n = String.length line in
  let rec find i =
    if i >= n then None
    else if line.[i] = '\\' && i + 1 < n then find (i + 2)
    else if line.[i] = '"' then Some (i + 1)
    else find (i + 1)
  in
  find 0

let can_parse text =
  try
    let lexbuf = Lexing.from_string text in
    ignore (Parser.program Lexer.token lexbuf);
    true
  with _ -> false

let detect_eol input =
  let n = String.length input in
  let rec find i =
    if i >= n then "\n"
    else if input.[i] = '\n' then
      if i > 0 && input.[i - 1] = '\r' then "\r\n" else "\n"
    else find (i + 1)
  in
  find 0

let format_string ?(indent_width=2) (input : string) : (string, string) result =
  let eol = detect_eol input in
  let input_parses = can_parse input in
  let raw_lines = String.split_on_char '\n' input in
  let out_lines = ref [] in
  let depth = ref 0 in
  let in_raw = ref false in
  let in_str = ref false in
  let prev_blank = ref true in
  List.iter (fun raw_line ->
    let line =
      let n = String.length raw_line in
      if n > 0 && raw_line.[n - 1] = '\r' then String.sub raw_line 0 (n - 1)
      else raw_line
    in
    if !in_raw then begin
      (* Preserve lines inside <{ ... }> verbatim. *)
      out_lines := line :: !out_lines;
      prev_blank := false;
      (match line_closes_raw line with
       | Some after_idx ->
           in_raw := false;
           let rest = String.sub line after_idx (String.length line - after_idx) in
           let segs, opens_again, opens_s = split_line_segments rest in
           let _, delta = bracket_counts segs in
           depth := max 0 (!depth + delta);
           if opens_again then in_raw := true;
           if opens_s then in_str := true
       | None -> ())
    end else if !in_str then begin
      (* Preserve lines inside a multi-line string literal verbatim. *)
      out_lines := line :: !out_lines;
      prev_blank := false;
      (match line_closes_string line with
       | Some after_idx ->
           in_str := false;
           let rest = String.sub line after_idx (String.length line - after_idx) in
           let segs, opens_r, opens_again = split_line_segments rest in
           let _, delta = bracket_counts segs in
           depth := max 0 (!depth + delta);
           if opens_r then in_raw := true;
           if opens_again then in_str := true
       | None -> ())
    end else if String.trim line = "" then begin
      if not !prev_blank then begin
        out_lines := "" :: !out_lines;
        prev_blank := true
      end
    end else begin
      let segs, opens_raw, opens_str = split_line_segments line in
      let leading_close, delta = bracket_counts segs in
      let formatted = format_segments segs in
      let is_pipe_cont =
        String.starts_with ~prefix:"|>" formatted
        || String.starts_with ~prefix:"?|>" formatted
      in
      let line_depth =
        let base = max 0 (!depth - leading_close) in
        if is_pipe_cont then base + 1 else base
      in
      let indent = String.make (line_depth * indent_width) ' ' in
      out_lines := (indent ^ formatted) :: !out_lines;
      prev_blank := false;
      depth := max 0 (!depth + delta);
      if opens_raw then in_raw := true;
      if opens_str then in_str := true
    end
  ) raw_lines;
  (* Drop trailing blank lines *)
  let rec drop_trailing_blanks = function
    | "" :: rest -> drop_trailing_blanks rest
    | xs -> List.rev xs
  in
  let final_lines = drop_trailing_blanks !out_lines in
  let formatted =
    match final_lines with
    | [] -> ""
    | _ -> String.concat eol final_lines ^ eol
  in
  if input_parses && not (can_parse formatted) then
    Error "Formatter aborted: formatted output did not parse cleanly."
  else
    Ok formatted

let format_file ?(check=false) ?(write=false) (path : string) : (bool * string, string) result =
  try
    let ch = open_in_bin path in
    let content =
      Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
        really_input_string ch (in_channel_length ch))
    in
    match format_string content with
    | Error msg -> Error msg
    | Ok formatted ->
        let changed = formatted <> content in
        if write && changed && not check then begin
          let oc = open_out_bin path in
          Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
            output_string oc formatted)
        end;
        Ok (changed, formatted)
  with Sys_error msg -> Error msg
