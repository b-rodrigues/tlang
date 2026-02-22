(* src/packages/dataframe/clean_colnames.ml *)
(* Column name normalization pipeline.                                      *)
(* Transforms raw CSV column names into safe, consistent identifiers.       *)
(* Designed as a standalone, pure module — no dependency on CSV parsing.     *)

(* ===================================================================== *)
(* 1. Symbol expansion table                                              *)
(* ===================================================================== *)

(** Multi-byte and single-byte symbol → word replacements.
    Applied before any other transformation so that e.g. "€" becomes "euro"
    and survives the later ASCII-only filter. *)
let symbol_map = [
  (* Currency & common symbols *)
  (* Replacements are padded with underscores so expanded words are
     separated from adjacent text.  Consecutive underscores are collapsed
     and leading/trailing underscores trimmed in later pipeline stages. *)
  ("\xe2\x82\xac", "_euro_");     (* € U+20AC *)
  ("\xc2\xa3", "_pound_");        (* £ U+00A3 *)
  ("\xc2\xa5", "_yen_");          (* ¥ U+00A5 *)
  ("%", "_percent_");
  ("$", "_dollar_");
  ("&", "_and_");
  ("+", "_plus_");
  ("@", "_at_");
  ("#", "_number_");
]

(* ===================================================================== *)
(* 2. Diacritics / accent stripping table                                 *)
(* ===================================================================== *)

(** Common accented characters → ASCII equivalents (UTF-8 byte sequences).
    This covers Latin-1 Supplement and Latin Extended-A, which handles the
    vast majority of Western European accented letters. *)
let diacritics_map = [
  (* À-ß  (U+00C0 – U+00DF, encoded as 0xC3 0x80 – 0xC3 0x9F) *)
  ("\xc3\x80", "a"); (* À *)  ("\xc3\x81", "a"); (* Á *)
  ("\xc3\x82", "a"); (* Â *)  ("\xc3\x83", "a"); (* Ã *)
  ("\xc3\x84", "a"); (* Ä *)  ("\xc3\x85", "a"); (* Å *)
  ("\xc3\x86", "ae"); (* Æ *) ("\xc3\x87", "c"); (* Ç *)
  ("\xc3\x88", "e"); (* È *)  ("\xc3\x89", "e"); (* É *)
  ("\xc3\x8a", "e"); (* Ê *)  ("\xc3\x8b", "e"); (* Ë *)
  ("\xc3\x8c", "i"); (* Ì *)  ("\xc3\x8d", "i"); (* Í *)
  ("\xc3\x8e", "i"); (* Î *)  ("\xc3\x8f", "i"); (* Ï *)
  ("\xc3\x90", "d"); (* Ð *)  ("\xc3\x91", "n"); (* Ñ *)
  ("\xc3\x92", "o"); (* Ò *)  ("\xc3\x93", "o"); (* Ó *)
  ("\xc3\x94", "o"); (* Ô *)  ("\xc3\x95", "o"); (* Õ *)
  ("\xc3\x96", "o"); (* Ö *)
  ("\xc3\x98", "o"); (* Ø *)
  ("\xc3\x99", "u"); (* Ù *)  ("\xc3\x9a", "u"); (* Ú *)
  ("\xc3\x9b", "u"); (* Û *)  ("\xc3\x9c", "u"); (* Ü *)
  ("\xc3\x9d", "y"); (* Ý *)  ("\xc3\x9e", "th"); (* Þ *)
  ("\xc3\x9f", "ss"); (* ß *)
  (* à-ÿ  (U+00E0 – U+00FF, encoded as 0xC3 0xA0 – 0xC3 0xBF) *)
  ("\xc3\xa0", "a"); (* à *)  ("\xc3\xa1", "a"); (* á *)
  ("\xc3\xa2", "a"); (* â *)  ("\xc3\xa3", "a"); (* ã *)
  ("\xc3\xa4", "a"); (* ä *)  ("\xc3\xa5", "a"); (* å *)
  ("\xc3\xa6", "ae"); (* æ *) ("\xc3\xa7", "c"); (* ç *)
  ("\xc3\xa8", "e"); (* è *)  ("\xc3\xa9", "e"); (* é *)
  ("\xc3\xaa", "e"); (* ê *)  ("\xc3\xab", "e"); (* ë *)
  ("\xc3\xac", "i"); (* ì *)  ("\xc3\xad", "i"); (* í *)
  ("\xc3\xae", "i"); (* î *)  ("\xc3\xaf", "i"); (* ï *)
  ("\xc3\xb0", "d"); (* ð *)  ("\xc3\xb1", "n"); (* ñ *)
  ("\xc3\xb2", "o"); (* ò *)  ("\xc3\xb3", "o"); (* ó *)
  ("\xc3\xb4", "o"); (* ô *)  ("\xc3\xb5", "o"); (* õ *)
  ("\xc3\xb6", "o"); (* ö *)
  ("\xc3\xb8", "o"); (* ø *)
  ("\xc3\xb9", "u"); (* ù *)  ("\xc3\xba", "u"); (* ú *)
  ("\xc3\xbb", "u"); (* û *)  ("\xc3\xbc", "u"); (* ü *)
  ("\xc3\xbd", "y"); (* ý *)  ("\xc3\xbe", "th"); (* þ *)
  ("\xc3\xbf", "y"); (* ÿ *)
]

(* ===================================================================== *)
(* Helpers                                                                *)
(* ===================================================================== *)

(** Replace all occurrences of [from] in [s] with [to_]. *)
let replace_all ~from ~to_ s =
  let from_len = String.length from in
  if from_len = 0 then s
  else
    let buf = Buffer.create (String.length s) in
    let i = ref 0 in
    while !i <= String.length s - from_len do
      if String.sub s !i from_len = from then begin
        Buffer.add_string buf to_;
        i := !i + from_len
      end else begin
        Buffer.add_char buf s.[!i];
        i := !i + 1
      end
    done;
    (* Append remaining characters *)
    while !i < String.length s do
      Buffer.add_char buf s.[!i];
      i := !i + 1
    done;
    Buffer.contents buf

(** Is a character ASCII-alphanumeric or underscore? *)
let is_safe_char c =
  (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_'

(* ===================================================================== *)
(* Single-name cleaning pipeline                                          *)
(* ===================================================================== *)

(** Clean a single column name through the normalization pipeline.
    Stages:
    1. Symbol expansion (€ → euro, % → percent, …)
    2. Diacritics stripping (é → e, ñ → n, …)
    3. Case normalization (lowercase)
    4. Replace non-alphanumeric with underscore
    5. Collapse consecutive underscores
    6. Trim leading/trailing underscores
    7. Prefix names starting with a digit *)
let clean_one (name : string) : string =
  (* 1. Symbol expansion *)
  let s = List.fold_left (fun acc (from, to_) ->
    replace_all ~from ~to_ acc
  ) name symbol_map in
  (* 2. Diacritics stripping *)
  let s = List.fold_left (fun acc (from, to_) ->
    replace_all ~from ~to_ acc
  ) s diacritics_map in
  (* 3. Lowercase *)
  let s = String.lowercase_ascii s in
  (* 4. Replace non-safe characters with underscore *)
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    if is_safe_char c then Buffer.add_char buf c
    else Buffer.add_char buf '_'
  ) s;
  let s = Buffer.contents buf in
  (* 5. Collapse consecutive underscores *)
  let buf2 = Buffer.create (String.length s) in
  let prev_underscore = ref false in
  String.iter (fun c ->
    if c = '_' then begin
      if not !prev_underscore then Buffer.add_char buf2 '_';
      prev_underscore := true
    end else begin
      Buffer.add_char buf2 c;
      prev_underscore := false
    end
  ) s;
  let s = Buffer.contents buf2 in
  (* 6. Trim leading/trailing underscores *)
  let len = String.length s in
  let start = ref 0 in
  while !start < len && s.[!start] = '_' do incr start done;
  let stop = ref (len - 1) in
  while !stop > !start && s.[!stop] = '_' do decr stop done;
  let s =
    if !start > !stop then ""
    else String.sub s !start (!stop - !start + 1)
  in
  (* 7. Prefix names starting with a digit *)
  if String.length s > 0 && s.[0] >= '0' && s.[0] <= '9' then
    "x_" ^ s
  else
    s

(* ===================================================================== *)
(* Collision resolution                                                   *)
(* ===================================================================== *)

(*
--# Clean Column Names
--#
--# Normalizes a list of strings to be safe, consistent column names.
--# Converts symbols (like €) to text, strips diacritics, lowers the case,
--# replaces non-alphanumeric characters with underscores, and resolves duplicates.
--#
--# @name clean_names
--# @param names :: Vector[String] The column names to clean.
--# @return :: Vector[String] The cleaned column names.
--# @family dataframe
--# @export
*)
let clean_names (names : string list) : string list =
  (* Apply single-name cleaning *)
  let cleaned = List.map clean_one names in
  (* Replace empty names with col_N *)
  let cleaned = List.mapi (fun i name ->
    if name = "" then Printf.sprintf "col_%d" (i + 1) else name
  ) cleaned in
  (* Resolve collisions: track counts seen so far *)
  let seen = Hashtbl.create (List.length cleaned) in
  List.map (fun name ->
    let count =
      match Hashtbl.find_opt seen name with
      | None -> 0
      | Some n -> n
    in
    Hashtbl.replace seen name (count + 1);
    if count = 0 then name
    else Printf.sprintf "%s_%d" name (count + 1)
  ) cleaned
