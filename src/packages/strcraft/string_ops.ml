open Ast

(* UTF-8 helpers: T strings index by character (code point), not byte.
   A lead byte encodes its own length; continuation bytes (0x80-0xBF) are
   merged into the preceding lead byte. Malformed bytes are treated as
   single characters so results stay total on arbitrary input. *)

let utf8_char_length c =
  let c = Char.code c in
  if c land 0x80 = 0x00 then 1
  else if c land 0xE0 = 0xC0 then 2
  else if c land 0xF0 = 0xE0 then 3
  else if c land 0xF8 = 0xF0 then 4
  else 1

let utf8_char_count s =
  let n = String.length s in
  let rec go i acc =
    if i >= n then acc
    else go (i + utf8_char_length s.[i]) (acc + 1)
  in
  go 0 0

let utf8_char_to_byte s char_index =
  let n = String.length s in
  let rec go i remaining =
    if i >= n then None
    else if remaining = 0 then Some i
    else go (i + utf8_char_length s.[i]) (remaining - 1)
  in
  go 0 char_index

let utf8_byte_to_char s byte_index =
  let n = String.length s in
  let rec go i acc =
    if i >= byte_index || i >= n then acc
    else go (i + utf8_char_length s.[i]) (acc + 1)
  in
  go 0 0

let utf8_chars s =
  let n = String.length s in
  let rec go i acc =
    if i >= n then List.rev acc
    else
      let len = utf8_char_length s.[i] in
      go (i + len) (String.sub s i len :: acc)
  in
  go 0 []

(* Split with OCaml Str.split semantics: the empty subject yields [], and
   trailing empty tokens are dropped (internal ones are kept). Preserves the
   behaviour of the legacy byte-oriented splitter under Pcre2 UTF-8. *)
let split_str_semantics re s =
  if s = "" then []
  else
    let parts = Pcre2.split ~rex:re ~max:(-1) s in
    let rec drop_trailing acc = function
      | [] -> List.rev acc
      | "" :: rest -> drop_trailing acc rest
      | x :: rest -> drop_trailing (x :: acc) rest
    in
    drop_trailing [] parts

(* Unicode-aware case mapping via the uucp Unicode character database.
   Deterministic and locale-independent (unlike C toupper/tolower), so results
   are reproducible across machines and environments. Multi-character mappings
   (e.g. U+00DF 'ß' -> "SS") are expanded; malformed UTF-8 bytes pass through
   unchanged. *)
let utf8_case_map to_case s =
  let b = Buffer.create (String.length s * 2) in
  let add_uchar _acc _ = function
    | `Uchar u ->
        (match to_case u with
         | `Self -> Uutf.Buffer.add_utf_8 b u
         | `Uchars us -> List.iter (fun u' -> Uutf.Buffer.add_utf_8 b u') us)
    | `Malformed bytes -> Buffer.add_string b bytes
  in
  ignore (Uutf.String.fold_utf_8 add_uchar () s);
  Buffer.contents b

(* Helper: Unary Vectorization *)
let vectorize_unary op args env =
  match args with
  | [Ast.VVector arr] ->
      Ast.VVector (Array.map (fun v -> 
        match op [v] env with
        | Ast.VError _ as e -> e
        | res -> res
      ) arr)
  | [Ast.VList items] ->
      Ast.VList (List.map (fun (name, v) -> 
        (name, match op [v] env with Ast.VError _ as e -> e | res -> res)
      ) items)
  | _ -> op args env

(* Helper: Binary Vectorization *)
let vectorize_binary op args env =
  match args with
  | [Ast.VVector arr1; Ast.VVector arr2] ->
      if Array.length arr1 <> Array.length arr2 then
        Error.broadcast_length_error (Array.length arr1) (Array.length arr2)
      else
        Ast.VVector (Array.map2 (fun v1 v2 -> op [v1; v2] env) arr1 arr2)
  | [Ast.VVector arr1; val2] ->
      Ast.VVector (Array.map (fun v1 -> op [v1; val2] env) arr1)
  | [val1; Ast.VVector arr2] ->
      Ast.VVector (Array.map (fun v2 -> op [val1; v2] env) arr2)
  | [Ast.VList l1; Ast.VList l2] ->
      if List.length l1 <> List.length l2 then
        Error.broadcast_length_error (List.length l1) (List.length l2)
      else
        Ast.VList (List.map2 (fun (n1, v1) (n2, v2) ->
          let name = match n1, n2 with Some s, _ -> Some s | _, Some s -> Some s | _ -> None in
          (name, op [v1; v2] env)
        ) l1 l2)
  | [Ast.VList l1; val2] ->
      Ast.VList (List.map (fun (n, v1) -> (n, op [v1; val2] env)) l1)
  | [val1; Ast.VList l2] ->
      Ast.VList (List.map (fun (n, v2) -> (n, op [val1; v2] env)) l2)
  | _ -> op args env

(* Helper: Ternary Vectorization *)
let vectorize_ternary op args env =
  match args with
  | [Ast.VVector arr1; Ast.VVector arr2; Ast.VVector arr3] ->
      let len = Array.length arr1 in
      if Array.length arr2 <> len || Array.length arr3 <> len then
        Error.value_error "Vector length mismatch in ternary operation."
      else
        Ast.VVector (Array.init len (fun i -> op [arr1.(i); arr2.(i); arr3.(i)] env))
  | [Ast.VVector arr1; val2; val3] ->
      Ast.VVector (Array.map (fun v1 -> op [v1; val2; val3] env) arr1)
  | [Ast.VList l1; val2; val3] ->
      Ast.VList (List.map (fun (n, v1) -> (n, op [v1; val2; val3] env)) l1)
  | _ -> op args env

(* Implementations *)

let is_empty_scalar args _env =
  match args with
  | [VString s] -> VBool (String.length s = 0)
  | _ -> Error.type_error "is_empty expects a string."

let is_empty_impl args env = vectorize_unary is_empty_scalar args env

let substring_scalar args _env =
  match args with
  | [VString s; VInt start; VInt end_] ->
      let char_count = utf8_char_count s in
      if start < 0 || end_ > char_count || start > end_ then
        Error.value_error "Invalid substring indices."
      else
        let start_byte = Option.value (utf8_char_to_byte s start) ~default:(String.length s) in
        let end_byte = Option.value (utf8_char_to_byte s end_) ~default:(String.length s) in
        VString (String.sub s start_byte (end_byte - start_byte))
  | _ -> Error.type_error "str_substring expects (string, int, int)."

let substring_impl args env = vectorize_ternary substring_scalar args env

let char_at_scalar args _env =
  match args with
  | [VString s; VInt i] ->
      let char_count = utf8_char_count s in
      if i < 0 || i >= char_count then
        Error.value_error "Index out of bounds."
      else
        let byte = Option.value (utf8_char_to_byte s i) ~default:(String.length s) in
        VString (String.sub s byte (utf8_char_length s.[byte]))
  | _ -> Error.type_error "char_at expects (string, int)."

let char_at_impl args env = vectorize_binary char_at_scalar args env

let index_of_scalar args _env =
  match args with
  | [VString s; VString sub] ->
      let rec find i =
        try
          let idx = String.index_from s i (String.get sub 0) in
          if String.length sub + idx > String.length s then -1
          else if String.sub s idx (String.length sub) = sub then idx
          else find (idx + 1)
        with Not_found -> -1
      in
      if sub = "" then VInt 0
      else
        let byte_idx = find 0 in
        if byte_idx < 0 then VInt (-1) else VInt (utf8_byte_to_char s byte_idx)
  | _ -> Error.type_error "index_of expects (string, string)."

let index_of_impl args env = vectorize_binary index_of_scalar args env

let last_index_of_scalar args _env =
  match args with
  | [VString s; VString sub] ->
      let sub_len = String.length sub in
      let s_len = String.length s in
      if sub_len > s_len then VInt (-1)
      else if sub = "" then VInt (utf8_char_count s)
      else
        let rec find i =
          if i < 0 then -1
          else if String.sub s i sub_len = sub then i
          else find (i - 1)
        in
        let byte_idx = find (s_len - sub_len) in
        if byte_idx < 0 then VInt (-1) else VInt (utf8_byte_to_char s byte_idx)
  | _ -> Error.type_error "last_index_of expects (string, string)."

let last_index_of_impl args env = vectorize_binary last_index_of_scalar args env

let contains_scalar args env =
  match args with
  | [VString _; VString _] ->
      let index_val = index_of_scalar args env in
      (match index_val with
       | VInt i -> VBool (i >= 0)
       | _ -> index_val) 
  | _ -> Error.type_error "contains expects (string, string)."

let contains_impl args env = vectorize_binary contains_scalar args env

let starts_with_scalar args _env =
  match args with
  | [VString s; VString prefix] ->
      VBool (String.starts_with ~prefix s)
  | _ -> Error.type_error "starts_with expects (string, string)."

let starts_with_impl args env = vectorize_binary starts_with_scalar args env

let ends_with_scalar args _env =
  match args with
  | [VString s; VString suffix] ->
      VBool (String.ends_with ~suffix s)
  | _ -> Error.type_error "ends_with expects (string, string)."

let ends_with_impl args env = vectorize_binary ends_with_scalar args env

let replace_scalar args _env =
  match args with
  | [VString s; VString old; VString new_] ->
      let regex = Pcre2.regexp ~flags:[`UTF] (Pcre2.quote old) in
      VString (Pcre2.qreplace ~rex:regex ~templ:new_ s)
  | _ -> Error.type_error "str_replace expects (string, string, string)."

let replace_impl args env = vectorize_ternary replace_scalar args env

let replace_first_scalar args _env =
  match args with
  | [VString s; VString old; VString new_] ->
      let regex = Pcre2.regexp ~flags:[`UTF] (Pcre2.quote old) in
      VString (Pcre2.qreplace_first ~rex:regex ~templ:new_ s)
  | _ -> Error.type_error "replace_first expects (string, string, string)."

let replace_first_impl args env = vectorize_ternary replace_first_scalar args env

let to_lower_scalar args _env =
  match args with
  | [VString s] -> VString (utf8_case_map Uucp.Case.Map.to_lower s)
  | _ -> Error.type_error "to_lower expects a string."

let to_lower_impl args env = vectorize_unary to_lower_scalar args env

let to_upper_scalar args _env =
  match args with
  | [VString s] -> VString (utf8_case_map Uucp.Case.Map.to_upper s)
  | _ -> Error.type_error "to_upper expects a string."

let to_upper_impl args env = vectorize_unary to_upper_scalar args env

(* Helper used by trim_start and trim_end — not exported *)
let ltrim s =
  let len = String.length s in
  if len = 0 then s
  else
    let i = ref 0 in
    while !i < len && (s.[!i] = ' ' || s.[!i] = '\t' || s.[!i] = '\n' || s.[!i] = '\r') do
      incr i
    done;
    String.sub s !i (len - !i)

let rtrim s =
  let len = String.length s in
  if len = 0 then s
  else
    let i = ref (len - 1) in
    while !i >= 0 && (s.[!i] = ' ' || s.[!i] = '\t' || s.[!i] = '\n' || s.[!i] = '\r') do
      decr i
    done;
    String.sub s 0 (!i + 1)

(* Pre-compiled regexes for lines/words — avoid recompiling on every call *)
let re_crlf = Pcre2.regexp ~flags:[`UTF] "\r\n"
let re_whitespace = Pcre2.regexp ~flags:[`UTF] "[ \t]+"

(*
--# Trim whitespace
--# Removes leading and trailing whitespace from a string. Vectorized.
--# @name str_trim
--# @param s :: String The string to trim.
--# @return :: String The trimmed string.
--# @family string
--# @export
*)
let trim_scalar args _env =
  match args with
  | [VString s] -> VString (String.trim s)
  | _ -> Error.type_error "str_trim expects a String."

let trim_impl args env = vectorize_unary trim_scalar args env

(*
--# Trim leading whitespace
--# @name trim_start
--# @param s :: String
--# @return :: String
--# @family string
--# @export
*)
let trim_start_scalar args _env =
  match args with
  | [VString s] -> VString (ltrim s)
  | _ -> Error.type_error "trim_start expects a String."

let trim_start_impl args env = vectorize_unary trim_start_scalar args env

(*
--# Trim trailing whitespace
--# @name trim_end
--# @param s :: String
--# @return :: String
--# @family string
--# @export
*)
let trim_end_scalar args _env =
  match args with
  | [VString s] -> VString (rtrim s)
  | _ -> Error.type_error "trim_end expects a String."

let trim_end_impl args env = vectorize_unary trim_end_scalar args env

(*
--# Split string into lines
--# Splits on \n or \r\n. Strips trailing newline. Accepts ShellResult.
--# @name str_lines
--# @param s :: String | ShellResult
--# @return :: List[String]
--# @family string
--# @seealso str_words, str_split
--# @export
*)
let lines_impl args _env =
  let do_lines s =
    (* Normalise \r\n to \n before splitting *)
    let normalised = Pcre2.qreplace ~rex:re_crlf ~templ:"\n" s in
    (* Strip a single trailing newline if present *)
    let trimmed =
      let len = String.length normalised in
      if len > 0 && normalised.[len - 1] = '\n' then
        String.sub normalised 0 (len - 1)
      else normalised
    in
    let parts = String.split_on_char '\n' trimmed in
    VList (List.map (fun line -> (None, VString line)) parts)
  in
  match args with
  | [VString s]                        -> do_lines s
  | [VShellResult { sr_stdout; _ }]    -> do_lines sr_stdout
  | [other] ->
      Error.type_error
        (Printf.sprintf "str_lines expects a String or ShellResult, got %s"
           (Utils.type_name other))
  | _ -> Error.arity_error_named "str_lines" 1 (List.length args)

(*
--# Split string into words
--# Splits on whitespace, collapsing consecutive spaces. Accepts ShellResult.
--# Note: words splits on spaces and tabs only, not newlines. For line-by-line
--# processing use str_lines() first, then str_words() on each line.
--# @name str_words
--# @param s :: String | ShellResult
--# @return :: List[String]
--# @family string
--# @seealso str_lines, str_split
--# @export
*)
let words_impl args _env =
  let do_words s =
    let trimmed = String.trim s in
    if trimmed = "" then VList []
    else
      let parts = Pcre2.split ~rex:re_whitespace ~max:(-1) trimmed in
      VList (List.map (fun w -> (None, VString w)) parts)
  in
  match args with
  | [VString s]                     -> do_words s
  | [VShellResult { sr_stdout; _ }] -> do_words sr_stdout
  | [other] ->
      Error.type_error
        (Printf.sprintf "str_words expects a String or ShellResult, got %s"
           (Utils.type_name other))
  | _ -> Error.arity_error_named "str_words" 1 (List.length args)

(*
--# Repeat a string
--# @name str_repeat
--# @param s :: String The string to repeat.
--# @param n :: Int Number of repetitions.
--# @return :: String
--# @family string
--# @export
*)
let str_repeat_scalar args _env =
  match args with
  | [VString s; VInt n] ->
      if n < 0 then
        Error.value_error "str_repeat: count must be non-negative."
      else
        let slen = String.length s in
        if slen > 0 && n > 10_000_000 / slen then
          Error.value_error (Printf.sprintf "str_repeat: result would exceed safety limit of 10,000,000 characters.")
        else
        let total_len = slen * n in
        let buf = Buffer.create total_len in
        for _ = 1 to n do Buffer.add_string buf s done;
        VString (Buffer.contents buf)
  | _ -> Error.type_error "str_repeat expects (String, Int)."

let str_repeat_impl args env = vectorize_binary str_repeat_scalar args env

(*
--# Named string interpolation
--# Substitutes {name} placeholders using values from a Dict or named List.
--# Use {{ and }} to produce literal braces in the output.
--# @name str_format
--# @param fmt :: String The format string with {name} placeholders.
--# @param values :: Dict | List The named values to substitute.
--# @return :: String The formatted string.
--# @family string
--# @seealso str_sprintf
--# @export
*)
let str_format_impl args _env =
  match args with
  | [VString fmt; (VDict _ | VList _) as values] ->
      let lookup =
        match values with
        | VDict d ->
            List.map (fun (k, v) -> (k, Ast.Utils.value_to_raw_string v)) d
        | VList items ->
            List.filter_map (fun (name_opt, v) ->
              match name_opt with
              | Some k -> Some (k, Ast.Utils.value_to_raw_string v)
              | None   -> None
            ) items
        | _ -> (* unreachable — guarded by outer match *) []
      in
      let len = String.length fmt in
      let buf = Buffer.create len in
      let i   = ref 0 in
      let result = ref None in
      while !i < len && !result = None do
        if fmt.[!i] = '{' then begin
          (* {{ produces a literal { *)
          if !i + 1 < len && fmt.[!i + 1] = '{' then begin
            Buffer.add_char buf '{';
            i := !i + 2
          end else
            (* Find closing brace for placeholder *)
            match String.index_from_opt fmt (!i + 1) '}' with
            | None ->
                result := Some (Error.make_error ValueError
                  "str_format: unclosed '{' in format string.")
            | Some j ->
                let key = String.sub fmt (!i + 1) (j - !i - 1) in
                (match List.assoc_opt key lookup with
                 | Some v -> Buffer.add_string buf v; i := j + 1
                 | None   ->
                     result := Some (Error.make_error KeyError
                       (Printf.sprintf "str_format: no value provided for key '{%s}'." key)))
        end else if fmt.[!i] = '}' && !i + 1 < len && fmt.[!i + 1] = '}' then begin
          (* }} produces a literal } *)
          Buffer.add_char buf '}';
          i := !i + 2
        end else begin
          Buffer.add_char buf fmt.[!i];
          incr i
        end
      done;
      (match !result with
       | Some err -> err
       | None     -> VString (Buffer.contents buf))
  | [VString _; other] ->
      Error.type_error
        (Printf.sprintf "str_format expects a Dict or named List as the second argument, got %s"
           (Utils.type_name other))
  | _ -> Error.type_error "str_format expects (String, Dict) or (String, named List)."

let length_scalar args _env =
  match args with
  | [VString _] -> Error.type_error "length does not work on strings. Use str_nchar() to get the number of characters in a string."
  | [VList items] -> VInt (List.length items)
  | [VDict pairs] -> VInt (List.length pairs)
  | [VVector arr] -> VInt (Array.length arr)
  | [VDataFrame _] -> Error.type_error "length does not work on DataFrames because it is ambiguous (rows vs columns). Use nrow() or ncol() instead."
  | [VInt _ | VFloat _ | VBool _] -> Error.type_error "length expects a collection (List, Vector, or Dict). Scalar provided."
  | [VNA _] -> Error.type_error "Cannot get length of NA."
  | [VError _ as e] -> e
  | [v] -> Error.type_error (Printf.sprintf "length expects a collection (List, Vector, or Dict). Received %s" (Utils.type_name v))
  | _ -> Error.type_error "length expects a collection (List, Vector, or Dict)."

let length_impl args env = length_scalar args env

let compile_regexp function_name pattern =
  try Ok (Pcre2.regexp ~flags:[`UTF] pattern)
  with
  | Pcre2.Error (Pcre2.BadPattern (msg, _)) ->
      Error (Error.value_error (Printf.sprintf "Function `%s` received an invalid regex: %s" function_name msg))
  | Pcre2.Error _ ->
      Error (Error.value_error (Printf.sprintf "Function `%s` received an invalid regex." function_name))

(* Prefer the first capture group when present; otherwise fall back to the
   full regex match so plain patterns still behave intuitively. *)
let regex_match_value m =
  try Pcre2.get_substring m 1 with
  | Invalid_argument _ | Not_found -> Pcre2.get_substring m 0

let all_regex_matches re s =
  let len = String.length s in
  let rec loop pos acc =
    if pos > len then
      List.rev acc
    else
      match Pcre2.exec ~rex:re ~pos s with
      | m ->
          let matched = regex_match_value m in
          let end_pos = snd (Pcre2.get_substring_ofs m 0) in
          (* On a zero-width match, advance past the next code point so UTF-8
             strings are never torn mid-character. At end-of-string (pos = len)
             fall back to pos + 1 so the loop always makes progress and cannot
             re-match the same trailing empty match forever. *)
          let next_pos =
            if end_pos = pos then
              (if pos < len then pos + utf8_char_length s.[pos] else pos + 1)
            else end_pos
          in
          loop next_pos (matched :: acc)
      | exception Not_found -> List.rev acc
  in
  loop 0 []

let str_extract_scalar args _env =
  match args with
  | [VString s; VString pattern] ->
      (match compile_regexp "str_extract" pattern with
       | Error err -> err
       | Ok re ->
           (match Pcre2.exec ~rex:re s with
            | m -> VString (regex_match_value m)
            | exception Not_found -> VNA NAString))
  | [VNA _; _] | [_; VNA _] -> VNA NAString
  | _ -> Error.type_error "str_extract expects (String, String)."

let str_extract_impl args env = vectorize_binary str_extract_scalar args env

let str_extract_all_scalar args _env =
  match args with
  | [VString s; VString pattern] ->
      (match compile_regexp "str_extract_all" pattern with
       | Error err -> err
       | Ok re ->
           all_regex_matches re s
           |> List.map (fun matched -> (None, VString matched))
           |> fun items -> VList items)
  | [VNA _; _] | [_; VNA _] -> VList []
  | _ -> Error.type_error "str_extract_all expects (String, String)."

let str_extract_all_impl args env = vectorize_binary str_extract_all_scalar args env

let str_detect_scalar args _env =
  match args with
  | [VString s; VString pattern] ->
      (match compile_regexp "str_detect" pattern with
       | Error err -> err
       | Ok re -> VBool (Pcre2.pmatch ~rex:re s))
  | [VNA _; _] | [_; VNA _] -> VNA NABool
  | _ -> Error.type_error "str_detect expects (String, String)."

let str_detect_impl args env = vectorize_binary str_detect_scalar args env

let str_count_scalar args _env =
  match args with
  | [VString s; VString pattern] ->
      (match compile_regexp "str_count" pattern with
       | Error err -> err
       | Ok re -> VInt (List.length (all_regex_matches re s)))
  | [VNA _; _] | [_; VNA _] -> VNA NAInt
  | _ -> Error.type_error "str_count expects (String, String)."

let str_count_impl args env = vectorize_binary str_count_scalar args env

let string_named_or_positional function_name name named_args position default =
  let positional = List.filter_map (function None, v -> Some v | _ -> None) named_args in
  match List.find_map (function Some n, v when n = name -> Some v | _ -> None) named_args with
  | Some (VString s) -> Ok s
  | Some v ->
      Error
        (Error.type_error
           (Printf.sprintf "Argument `%s` to `%s` must be String, got %s."
              name function_name (Utils.type_name v)))
  | None ->
      (match List.nth_opt positional position with
       | Some (VString s) -> Ok s
       | Some v ->
           Error
             (Error.type_error
                (Printf.sprintf "Argument `%s` to `%s` must be String, got %s."
                   name function_name (Utils.type_name v)))
       | None -> Ok default)

let repeat_to_length pad needed =
  (* Pad to a target character width, never splitting a multi-byte character. *)
  if needed <= 0 then ""
  else
    let pad_chars = utf8_chars pad in
    let pad_char_count = List.length pad_chars in
    let buf = Buffer.create (max 16 (needed * 4)) in
    let rec loop remaining =
      if remaining <= 0 then
        Buffer.contents buf
      else if remaining >= pad_char_count then begin
        List.iter (Buffer.add_string buf) pad_chars;
        loop (remaining - pad_char_count)
      end else begin
        List.iteri (fun i c -> if i < remaining then Buffer.add_string buf c) pad_chars;
        Buffer.contents buf
      end
    in
    loop needed

let map_string_value function_name fn value =
  let rec apply = function
    | VVector arr -> VVector (Array.map apply arr)
    | VList items -> VList (List.map (fun (name, item) -> (name, apply item)) items)
    | VNA _ -> VNA NAString
    | VString s -> fn s
    | _ ->
        Error.type_error
          (Printf.sprintf "Function `%s` expects a String or Vector[String]." function_name)
  in
  apply value

let str_pad_impl named_args _env =
  let positional = List.filter_map (function None, v -> Some v | _ -> None) named_args in
  match positional with
  | [value; VInt width]
  | [value; VInt width; _]
  | [value; VInt width; _; _] ->
      (match string_named_or_positional "str_pad" "side" named_args 2 "left",
             string_named_or_positional "str_pad" "pad" named_args 3 " " with
       | Error err, _ | _, Error err -> err
       | Ok side, Ok pad ->
           if width < 0 then
             Error.value_error "Function `str_pad` width must be non-negative."
           else if pad = "" then
             Error.value_error "Function `str_pad` pad must not be empty."
           else
             map_string_value "str_pad" (fun s ->
               let len = utf8_char_count s in
               if len >= width then
                 VString s
               else
                 let needed = width - len in
                 let pad_text = repeat_to_length pad needed in
                 match side with
                 | "left" -> VString (pad_text ^ s)
                 | "right" -> VString (s ^ pad_text)
                 | "both" ->
                     let left = needed / 2 in
                     let right = needed - left in
                     VString (repeat_to_length pad left ^ s ^ repeat_to_length pad right)
                 | _ ->
                     Error.value_error
                       (Printf.sprintf "Function `str_pad` side must be \"left\", \"right\", or \"both\", got %S." side)
             ) value)
  | [_; _] ->
      Error.type_error "Function `str_pad` expects (String, Int, side = String, pad = String)."
  | values -> Error.arity_error_named "str_pad" 2 (List.length values)

let str_trunc_impl named_args _env =
  let positional = List.filter_map (function None, v -> Some v | _ -> None) named_args in
  match positional with
  | [value; VInt width]
  | [value; VInt width; _]
  | [value; VInt width; _; _] ->
      (match string_named_or_positional "str_trunc" "side" named_args 2 "right",
             string_named_or_positional "str_trunc" "ellipsis" named_args 3 "..." with
       | Error err, _ | _, Error err -> err
       | Ok side, Ok ellipsis ->
           if width < 0 then
             Error.value_error "Function `str_trunc` width must be non-negative."
           else
             map_string_value "str_trunc" (fun s ->
               let chars = utf8_chars s in
               let len = List.length chars in
               let ellipsis_chars = utf8_chars ellipsis in
               let ellipsis_len = List.length ellipsis_chars in
               let take_prefix n =
                 List.filteri (fun i _ -> i < n) chars |> String.concat ""
               in
               let take_suffix n =
                 List.filteri (fun i _ -> i >= len - n) chars |> String.concat ""
               in
               if len <= width then
                 VString s
               else if width <= ellipsis_len then
                 VString (String.concat "" (List.filteri (fun i _ -> i < width) ellipsis_chars))
               else
                 let keep = width - ellipsis_len in
                 match side with
                 | "right" -> VString (take_prefix keep ^ ellipsis)
                 | "left" -> VString (ellipsis ^ take_suffix keep)
                 | "center" ->
                     let left_keep = keep / 2 in
                     let right_keep = keep - left_keep in
                     VString (take_prefix left_keep ^ ellipsis ^ take_suffix right_keep)
                 | _ ->
                     Error.value_error
                       (Printf.sprintf "Function `str_trunc` side must be \"left\", \"right\", or \"center\", got %S." side)
             ) value)
  | [_; _] ->
      Error.type_error "Function `str_trunc` expects (String, Int, side = String, ellipsis = String)."
  | values -> Error.arity_error_named "str_trunc" 2 (List.length values)

let str_flatten_impl named_args _env =
  let positional = List.filter_map (function None, v -> Some v | _ -> None) named_args in
  match string_named_or_positional "str_flatten" "collapse" named_args 1 "" with
  | Error err -> err
  | Ok collapse ->
      let flatten values =
        values
        |> List.map Ast.Utils.value_to_raw_string
        |> String.concat collapse
        |> fun s -> VString s
      in
      (match positional with
       | [VVector arr] -> flatten (Array.to_list arr)
       | [VList items] -> flatten (List.map snd items)
       | [value] -> VString (Ast.Utils.value_to_raw_string value)
       | values ->
           Error.arity_error_named "str_flatten" 1 (List.length values))

let nchar_scalar args _env =
  match args with
  | [VString s] -> VInt (utf8_char_count s)
  | _ -> Error.type_error "str_nchar expects a string."

let nchar_impl args env = vectorize_unary nchar_scalar args env
 
let sprintf_impl args _env =
  match args with
  | VString fmt :: vals ->
      let len = String.length fmt in
      let res = Buffer.create len in
      let rec go i items =
        if i >= len then
          VString (Buffer.contents res)
        else if fmt.[i] = '%' then
          if i + 1 >= len then
            Error.value_error "Incomplete format specifier at end of string."
          else
            match fmt.[i+1] with
            | '%' -> Buffer.add_char res '%'; go (i + 2) items
            | 's' | 'd' | 'f' ->
                (match items with
                 | v :: rest ->
                     Buffer.add_string res (Ast.Utils.value_to_raw_string v);
                     go (i + 2) rest
                 | [] -> Error.value_error "Not enough arguments for format string.")
            | c -> Error.value_error (Printf.sprintf "Unsupported format specifier: %%%c. Supported: %%s, %%d, %%f, %%%%" c)
        else (
          Buffer.add_char res fmt.[i];
          go (i + 1) items
        )
      in
      go 0 vals
  | _ -> Error.type_error "str_sprintf expects a format string as the first argument."

let join_impl args _env =
  match args with
  | [VList items] ->
      let strs = List.map (fun (_, v) -> Ast.Utils.value_to_raw_string v) items in
      VString (String.concat "" strs)
  | [VList items; VString sep] ->
      let strs = List.map (fun (_, v) -> Ast.Utils.value_to_raw_string v) items in
      VString (String.concat sep strs)
  | [VVector arr] ->
      let strs = Array.map Ast.Utils.value_to_raw_string arr |> Array.to_list in
      VString (String.concat "" strs)
  | [VVector arr; VString sep] ->
      let strs = Array.map Ast.Utils.value_to_raw_string arr |> Array.to_list in
      VString (String.concat sep strs)
  | [val_] ->
      VString (Ast.Utils.value_to_raw_string val_)
  | [val_; VString _] ->
      VString (Ast.Utils.value_to_raw_string val_)
  | _ -> Error.type_error "Function `str_join` expects (list/vector, [separator]) or (value, [separator])."

let string_impl args _env =
  match args with
  | [v] -> VString (Ast.Utils.value_to_raw_string v)
  | _ -> Error.type_error "Function `to_string` expects a single argument."

let strsplit_impl args _env =
  let do_split s sep =
    let parts =
      if sep = "" then
        List.map (fun c -> VString c) (utf8_chars s)
      else if String.length sep = 1 then
        List.map (fun p -> VString p) (String.split_on_char sep.[0] s)
      else begin
        let sep_len = String.length sep in
        let s_len   = String.length s   in
        let find_from start =
          let rec find i =
            if i + sep_len > s_len then None
            else if String.sub s i sep_len = sep then Some i
            else find (i + 1)
          in find start
        in
        let rec loop acc start =
          match find_from start with
          | None   -> List.rev (VString (String.sub s start (s_len - start)) :: acc)
          | Some i -> loop (VString (String.sub s start (i - start)) :: acc) (i + sep_len)
        in
        loop [] 0
      end
    in
    VList (List.map (fun v -> (None, v)) parts)
  in
  match args with
  | [VString s; VString sep]                     -> do_split s sep
  | [VShellResult { sr_stdout; _ }; VString sep] -> do_split sr_stdout sep
  | [_; _] -> Error.type_error "Function `str_split` expects (String, String)."
  | _      -> Error.arity_error_named "str_split" 2 (List.length args)

(*
--# Format a string
--#
--# Formats a string using C-style format specifiers.
--# Supports %s (string), %d (integer), %f (float), and %% (literal %).
--#
--# @name str_sprintf
--# @param fmt :: String The format string.
--# @param ... :: Any Values to substitute in the format string.
--# @return :: String The formatted string.
--# @example
--#   str_sprintf("Hello, %s!", "world")
--#   -- Returns = "Hello, world!"
--#   str_sprintf("Value = %d", 42)
--#   -- Returns: "Value = 42"
--# @family string
--# @export
*)

(*
--# Check if string is empty
--#
--# Returns true if the string has length 0.
--#
--# @name is_empty
--# @param s :: String The string to check.
--# @return :: Bool True if empty, false otherwise.
--# @family string
--# @export
*)

(*
--# Get character count
--#
--# Returns the number of characters (Unicode code points) in a string.
--# Multi-byte UTF-8 characters count as a single character. Vectorized.
--#
--# @name str_nchar
--# @param x :: String | Vector[String] The input string(s).
--# @return :: Int | Vector[Int] The number of characters.
--# @family string
--# @export
*)

(*
--# Get length
--#
--# Returns the number of elements in a collection (List, Vector, Dict).
--# This function is NOT vectorized - it always returns the count of elements.
--# For getting the number of characters in a string, use str_nchar() instead.
--#
--# @name length
--# @param x :: List | Vector | Dict The collection to measure.
--# @return :: Int The number of elements.
--# @family core
--# @export
*)

(*
--# Extract substring
--#
--# Returns the part of the string between `start` and `end` indices.
--# Indices are character-based (Unicode code points), so multi-byte UTF-8
--# characters are never split.
--#
--# @name str_substring
--# @param s :: String The input string.
--# @param start :: Int The starting index (inclusive).
--# @param end :: Int The ending index (exclusive).
--# @return :: String The extracted substring.
--# @family string
--# @export
*)

(*
--# Extract slice
--#
--# Alias for `str_substring`. Returns the part of the string between `start` and `end` indices.
--#
--# @name slice
--# @param s :: String The input string.
--# @param start :: Int The starting index (inclusive).
--# @param end :: Int The ending index (exclusive).
--# @return :: String The extracted substring.
--# @family string
--# @export
*)

(*
--# Get character at index
--#
--# Returns a single-character string at the specified index.
--# Index is character-based (Unicode code point), so a multi-byte UTF-8
--# character is returned whole.
--#
--# @name char_at
--# @param s :: String The input string.
--# @param i :: Int The index (0-based).
--# @return :: String The character at the index.
--# @family string
--# @export
*)

(*
--# Find index of substring
--#
--# Returns the character index of the first occurrence of `sub` in `s`,
--# or -1 if not found. Indices are character-based (Unicode code points),
--# matching `str_substring` and `char_at`.
--#
--# @name index_of
--# @param s :: String The search string.
--# @param sub :: String The substring to find.
--# @return :: Int The character index of the first occurrence.
--# @family string
--# @export
*)

(*
--# Find last index of substring
--#
--# Returns the character index of the last occurrence of `sub` in `s`,
--# or -1 if not found. Indices are character-based (Unicode code points).
--#
--# @name last_index_of
--# @param s :: String The search string.
--# @param sub :: String The substring to find.
--# @return :: Int The character index of the last occurrence.
--# @family string
--# @export
*)

(*
--# Check if string contains substring
--#
--# Returns true if `sub` is present in `s`.
--#
--# @name contains
--# @param s :: String The search string.
--# @param sub :: String The substring to find.
--# @return :: Bool True if found, false otherwise.
--# @family string
--# @export
*)

(*
--# Check if string starts with prefix
--#
--# Returns true if `s` starts with the specified `prefix`.
--#
--# @name starts_with
--# @param s :: String The string to check.
--# @param prefix :: String The prefix to look for.
--# @return :: Bool True if s starts with prefix.
--# @family string
--# @export
*)

(*
--# Check if string ends with suffix
--#
--# Returns true if `s` ends with the specified `suffix`.
--#
--# @name ends_with
--# @param s :: String The string to check.
--# @param suffix :: String The suffix to look for.
--# @return :: Bool True if s ends with suffix.
--# @family string
--# @export
*)

(*
--# Replace all occurrences
--#
--# Replaces all occurrences of `old` with `new_` in `s`.
--#
--# @name str_replace
--# @param s :: String The input string.
--# @param old :: String The substring to replace.
--# @param new_ :: String The replacement string.
--# @return :: String The modified string.
--# @family string
--# @export
*)

(*
--# Replace first occurrence
--#
--# Replaces only the first occurrence of `old` with `new_` in `s`.
--#
--# @name replace_first
--# @param s :: String The input string.
--# @param old :: String The substring to replace.
--# @param new_ :: String The replacement string.
--# @return :: String The modified string.
--# @family string
--# @export
*)

(*
--# Convert to lowercase
--#
--# Converts all characters in the string to lowercase, using the Unicode
--# character database (deterministic and locale-independent). Multi-character
--# mappings are expanded.
--#
--# @name to_lower
--# @param s :: String The string to convert.
--# @return :: String The lowercase string.
--# @family string
--# @export
*)

(*
--# Convert to uppercase
--#
--# Converts all characters in the string to uppercase, using the Unicode
--# character database (deterministic and locale-independent). Multi-character
--# mappings are expanded (e.g. `ß` becomes `SS`).
--#
--# @name to_upper
--# @param s :: String The string to convert.
--# @return :: String The uppercase string.
--# @family string
--# @export
*)

(*
--# Join strings with a separator
--#
--# Concatenates items of a List or Vector into a single string, separated by `sep`.
--#
--# @name str_join
--# @param items :: List | Vector The items to join.
--# @param sep :: String [Optional] The separator string. Defaults to "".
--# @return :: String The joined string.
--# @example
--#   str_join(["a", "b", "c"], "-")
--#   -- Returns = "a-b-c"
--#   str_join(["a", "b", "c"])
--#   -- Returns = "abc"
--# @family string
--# @seealso to_string
--# @export
*)

(*
--# Convert to string
--#
--# Converts any value to its string representation.
--#
--# @name to_string
--# @param x :: Any The value to convert.
--# @return :: String The string representation.
--# @example
--#   to_string(123)
--#   -- Returns = "123"
--# @family string
--# @seealso str_join
--# @export
*)

(*
--# Split a string on a delimiter
--#
--# Splits a string into a list of substrings on each occurrence of `sep`.
--# If `sep` is empty, splits into individual characters (Unicode code
--# points — multi-byte characters are never split).
--# Works transparently on ShellResult values (splits stdout).
--#
--# @name str_split
--# @param x :: String | ShellResult The string to split.
--# @param sep :: String The delimiter to split on.
--# @return :: List[String] A list of substrings.
--# @example
--#   str_split("a,b,c", ",")
--#   -- Returns = ["a", "b", "c"]
--#   files = ?<{ls}>; str_split(files, "\n")
--# @family string
--# @seealso str_join
--# @export
*)


(*
--# Extract the first regex match
--#
--# Returns the first regular-expression match found in each string.
--#
--# @name str_extract
--# @family string
--# @export
*)
(*
--# Extract all regex matches
--#
--# Returns every regular-expression match found in each string.
--#
--# @name str_extract_all
--# @family string
--# @export
*)
(*
--# Test whether a regex matches
--#
--# Returns true when a regular expression matches a string.
--#
--# @name str_detect
--# @family string
--# @export
*)
(*
--# Pad strings to a target width
--#
--# Pads strings on the left, right, or both sides until they reach a requested
--# width. Width is measured in characters (Unicode code points), so multi-byte
--# UTF-8 strings are padded correctly and never split.
--#
--# @name str_pad
--# @family string
--# @export
*)
(*
--# Truncate strings for display
--#
--# Shortens strings to a maximum character width and appends an ellipsis when
--# needed. Width is measured in characters (Unicode code points), so multi-byte
--# UTF-8 strings are never split mid-character.
--#
--# @name str_trunc
--# @family string
--# @export
*)
(*
--# Flatten a collection of strings
--#
--# Concatenates string collections into a single string with an optional separator.
--#
--# @name str_flatten
--# @family string
--# @export
*)
(*
--# Count regex matches
--#
--# Counts how many times a regular expression matches within each string.
--#
--# @name str_count
--# @family string
--# @export
*)
let register env =
  let env = Env.add "is_empty" (make_builtin ~name:"is_empty" 1 is_empty_impl) env in
  let env = Env.add "length" (make_builtin ~name:"length" 1 length_impl) env in
  let env = Env.add "str_nchar" (make_builtin ~name:"str_nchar" 1 nchar_impl) env in
  let env = Env.add "str_substring" (make_builtin ~name:"str_substring" 3 substring_impl) env in
  let env = Env.add "slice" (make_builtin ~name:"slice" 3 substring_impl) env in
  let env = Env.add "char_at" (make_builtin ~name:"char_at" 2 char_at_impl) env in
  let env = Env.add "index_of" (make_builtin ~name:"index_of" 2 index_of_impl) env in
  let env = Env.add "last_index_of" (make_builtin ~name:"last_index_of" 2 last_index_of_impl) env in
  let env = Env.add "contains" (make_builtin ~name:"contains" 2 contains_impl) env in
  let env = Env.add "starts_with" (make_builtin ~name:"starts_with" 2 starts_with_impl) env in
  let env = Env.add "ends_with" (make_builtin ~name:"ends_with" 2 ends_with_impl) env in
  let env = Env.add "str_replace" (make_builtin ~name:"str_replace" 3 replace_impl) env in
  let env = Env.add "replace_first" (make_builtin ~name:"replace_first" 3 replace_first_impl) env in
  let env = Env.add "to_lower" (make_builtin ~name:"to_lower" 1 to_lower_impl) env in
  let env = Env.add "to_upper" (make_builtin ~name:"to_upper" 1 to_upper_impl) env in
  let env = Env.add "str_trim"    (make_builtin ~name:"str_trim"    1 trim_impl)        env in
  let env = Env.add "trim_start"  (make_builtin ~name:"trim_start"  1 trim_start_impl)  env in
  let env = Env.add "trim_end"    (make_builtin ~name:"trim_end"    1 trim_end_impl)    env in
  let env = Env.add "str_lines"   (make_builtin ~name:"str_lines"   1 lines_impl)       env in
  let env = Env.add "str_words"   (make_builtin ~name:"str_words"   1 words_impl)       env in
  let env = Env.add "str_repeat"  (make_builtin ~name:"str_repeat"  2 str_repeat_impl)  env in
  let env = Env.add "str_format"  (make_builtin ~name:"str_format"  2 str_format_impl)  env in
  let env = Env.add "str_extract" (make_builtin ~name:"str_extract" 2 str_extract_impl) env in
  let env = Env.add "str_extract_all" (make_builtin ~name:"str_extract_all" 2 str_extract_all_impl) env in
  let env = Env.add "str_detect" (make_builtin ~name:"str_detect" 2 str_detect_impl) env in
  let env = Env.add "str_pad" (make_builtin_named ~name:"str_pad" ~variadic:true 2 str_pad_impl) env in
  let env = Env.add "str_trunc" (make_builtin_named ~name:"str_trunc" ~variadic:true 2 str_trunc_impl) env in
  let env = Env.add "str_flatten" (make_builtin_named ~name:"str_flatten" ~variadic:true 1 str_flatten_impl) env in
  let env = Env.add "str_count" (make_builtin ~name:"str_count" 2 str_count_impl) env in
  let env = Env.add "str_sprintf" (make_builtin ~name:"str_sprintf" ~variadic:true 1 sprintf_impl) env in
  let env = Env.add "str_join" (make_builtin ~name:"str_join" ~variadic:true 1 join_impl) env in
  let env = Env.add "to_string" (make_builtin ~name:"to_string" 1 string_impl) env in
  let env = Env.add "str_split" (make_builtin ~name:"str_split" 2 strsplit_impl) env in
  env
