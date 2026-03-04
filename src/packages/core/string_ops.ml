open Ast

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
      let len = String.length s in
      if start < 0 || end_ > len || start > end_ then
        Error.value_error "Invalid substring indices."
      else
        VString (String.sub s start (end_ - start))
  | _ -> Error.type_error "substring expects (string, int, int)."

let substring_impl args env = vectorize_ternary substring_scalar args env

let char_at_scalar args _env =
  match args with
  | [VString s; VInt i] ->
      let len = String.length s in
      if i < 0 || i >= len then
        Error.value_error "Index out of bounds."
      else
        VString (String.make 1 (String.get s i))
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
      if sub = "" then VInt 0 else VInt (find 0)
  | _ -> Error.type_error "index_of expects (string, string)."

let index_of_impl args env = vectorize_binary index_of_scalar args env

let last_index_of_scalar args _env =
  match args with
  | [VString s; VString sub] ->
      let sub_len = String.length sub in
      let s_len = String.length s in
      if sub_len > s_len then VInt (-1)
      else if sub = "" then VInt s_len
      else
        let rec find i =
          if i < 0 then -1
          else if String.sub s i sub_len = sub then i
          else find (i - 1)
        in
        VInt (find (s_len - sub_len))
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
      let regex = Str.regexp_string old in
      VString (Str.global_replace regex new_ s)
  | _ -> Error.type_error "replace expects (string, string, string)."

let replace_impl args env = vectorize_ternary replace_scalar args env

let replace_first_scalar args _env =
  match args with
  | [VString s; VString old; VString new_] ->
      let regex = Str.regexp_string old in
      VString (Str.replace_first regex new_ s)
  | _ -> Error.type_error "replace_first expects (string, string, string)."

let replace_first_impl args env = vectorize_ternary replace_first_scalar args env

let to_lower_scalar args _env =
  match args with
  | [VString s] -> VString (String.lowercase_ascii s)
  | _ -> Error.type_error "to_lower expects a string."

let to_lower_impl args env = vectorize_unary to_lower_scalar args env

let to_upper_scalar args _env =
  match args with
  | [VString s] -> VString (String.uppercase_ascii s)
  | _ -> Error.type_error "to_upper expects a string."

let to_upper_impl args env = vectorize_unary to_upper_scalar args env

(* Helper used by trim_start and trim_end — not exported *)
let ltrim s =
  let len = String.length s in
  let i = ref 0 in
  while !i < len && (s.[!i] = ' ' || s.[!i] = '\t' || s.[!i] = '\n' || s.[!i] = '\r') do
    incr i
  done;
  String.sub s !i (len - !i)

let rtrim s =
  let len = String.length s in
  let i = ref (len - 1) in
  while !i >= 0 && (s.[!i] = ' ' || s.[!i] = '\t' || s.[!i] = '\n' || s.[!i] = '\r') do
    decr i
  done;
  String.sub s 0 (!i + 1)

let trim_scalar args _env =
  match args with
  | [VString s] -> VString (String.trim s)
  | _ -> Error.type_error "trim expects a String."

let trim_impl args env = vectorize_unary trim_scalar args env

let trim_start_scalar args _env =
  match args with
  | [VString s] -> VString (ltrim s)
  | _ -> Error.type_error "trim_start expects a String."

let trim_start_impl args env = vectorize_unary trim_start_scalar args env

let trim_end_scalar args _env =
  match args with
  | [VString s] -> VString (rtrim s)
  | _ -> Error.type_error "trim_end expects a String."

let trim_end_impl args env = vectorize_unary trim_end_scalar args env

let lines_impl args _env =
  let do_lines s =
    (* Normalise \r\n to \n before splitting *)
    let normalised =
      let re = Str.regexp "\r\n" in
      Str.global_replace re "\n" s
    in
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
        (Printf.sprintf "lines expects a String or ShellResult, got %s"
           (Utils.type_name other))
  | _ -> Error.arity_error_named "lines" ~expected:1 ~received:(List.length args)

let words_impl args _env =
  let do_words s =
    let trimmed = String.trim s in
    if trimmed = "" then VList []
    else
      let re = Str.regexp "[ \t]+" in
      let parts = Str.split re trimmed in
      VList (List.map (fun w -> (None, VString w)) parts)
  in
  match args with
  | [VString s]                     -> do_words s
  | [VShellResult { sr_stdout; _ }] -> do_words sr_stdout
  | [other] ->
      Error.type_error
        (Printf.sprintf "words expects a String or ShellResult, got %s"
           (Utils.type_name other))
  | _ -> Error.arity_error_named "words" ~expected:1 ~received:(List.length args)

let str_repeat_scalar args _env =
  match args with
  | [VString s; VInt n] ->
      if n < 0 then
        Error.value_error "str_repeat: count must be non-negative."
      else
        let buf = Buffer.create (String.length s * n) in
        for _ = 1 to n do Buffer.add_string buf s done;
        VString (Buffer.contents buf)
  | _ -> Error.type_error "str_repeat expects (String, Int)."

let str_repeat_impl args env = vectorize_binary str_repeat_scalar args env

let str_format_impl args _env =
  match args with
  | [VString fmt; VDict _] | [VString fmt; VList _] ->
      (* Normalise: VList named items and VDict both become (string * string) list *)
      let lookup =
        match List.nth args 1 with
        | VDict d ->
            List.map (fun (k, v) -> (k, Ast.Utils.value_to_raw_string v)) d
        | VList items ->
            List.filter_map (fun (name_opt, v) ->
              match name_opt with
              | Some k -> Some (k, Ast.Utils.value_to_raw_string v)
              | None   -> None
            ) items
        | _ -> []
      in
      let len = String.length fmt in
      let buf = Buffer.create len in
      let i   = ref 0 in
      let result = ref None in
      while !i < len && !result = None do
        if fmt.[!i] = '{' then begin
          (* Find closing brace *)
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
  | [VString _] -> Error.type_error "length does not work on strings. Use nchar() to get the number of characters in a string."
  | [VList items] -> VInt (List.length items)
  | [VDict pairs] -> VInt (List.length pairs)
  | [VVector arr] -> VInt (Array.length arr)
  | [VNA _] -> Error.type_error "Cannot get length of NA."
  | [VError _] -> Error.type_error "Cannot get length of Error."
  | _ -> Error.type_error "length expects a collection (List, Vector, or Dict)."

let length_impl args env = length_scalar args env

let nchar_scalar args _env =
  match args with
  | [VString s] -> VInt (String.length s)
  | _ -> Error.type_error "nchar expects a string."

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
  | _ -> Error.type_error "sprintf expects a format string as the first argument."

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
  | _ -> Error.type_error "Function `join` expects (list/vector, [separator]) or (value, [separator])."

let string_impl args _env =
  match args with
  | [v] -> VString (Ast.Utils.value_to_raw_string v)
  | _ -> Error.type_error "Function `string` expects a single argument."

let strsplit_impl args _env =
  let do_split s sep =
    let parts =
      if sep = "" then
        List.init (String.length s) (fun i -> VString (String.make 1 s.[i]))
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
  | [_; _] -> Error.type_error "Function `strsplit` expects (String, String)."
  | _      -> Error.arity_error_named "strsplit" ~expected:2 ~received:(List.length args)

(*
--# Format a string
--#
--# Formats a string using C-style format specifiers.
--# Supports %s (string), %d (integer), %f (float), and %% (literal %).
--#
--# @name sprintf
--# @param fmt :: String The format string.
--# @param ... :: Any Values to substitute in the format string.
--# @return :: String The formatted string.
--# @example
--#   sprintf("Hello, %s!", "world")
--#   -- Returns = "Hello, world!"
--#   sprintf("Value = %d", 42)
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
--# Returns the number of characters in a string. Vectorized.
--#
--# @name nchar
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
--# For getting the number of characters in a string, use nchar() instead.
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
--#
--# @name substring
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
--# Alias for `substring`. Returns the part of the string between `start` and `end` indices.
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
--# Returns the index of the first occurrence of `sub` in `s`, or -1 if not found.
--#
--# @name index_of
--# @param s :: String The search string.
--# @param sub :: String The substring to find.
--# @return :: Int The index of the first occurrence.
--# @family string
--# @export
*)

(*
--# Find last index of substring
--#
--# Returns the index of the last occurrence of `sub` in `s`, or -1 if not found.
--#
--# @name last_index_of
--# @param s :: String The search string.
--# @param sub :: String The substring to find.
--# @return :: Int The index of the last occurrence.
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
--# @name replace
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
--# Converts all characters in the string to lowercase.
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
--# Converts all characters in the string to uppercase.
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
--# @name join
--# @param items :: List | Vector The items to join.
--# @param sep :: String [Optional] The separator string. Defaults to "".
--# @return :: String The joined string.
--# @example
--#   join(["a", "b", "c"], "-")
--#   -- Returns = "a-b-c"
--#   join(["a", "b", "c"])
--#   -- Returns = "abc"
--# @family core
--# @seealso string
--# @export
*)

(*
--# Convert to string
--#
--# Converts any value to its string representation.
--#
--# @name string
--# @param x :: Any The value to convert.
--# @return :: String The string representation.
--# @example
--#   string(123)
--#   -- Returns = "123"
--# @family core
--# @seealso join
--# @export
*)

(*
--# Split a string on a delimiter
--#
--# Splits a string into a list of substrings on each occurrence of `sep`.
--# If `sep` is empty, splits into individual characters.
--# Works transparently on ShellResult values (splits stdout).
--#
--# @name strsplit
--# @param x :: String | ShellResult The string to split.
--# @param sep :: String The delimiter to split on.
--# @return :: List[String] A list of substrings.
--# @example
--#   strsplit("a,b,c", ",")
--#   -- Returns = ["a", "b", "c"]
--#   files = ?<{ls}>; strsplit(files, "\n")
--# @family core
--# @seealso join
--# @export
*)

(*
--# Trim whitespace
--# Removes leading and trailing whitespace from a string. Vectorized.
--# @name trim
--# @param s :: String The string to trim.
--# @return :: String The trimmed string.
--# @family string
--# @export
*)

(*
--# Trim leading whitespace
--# @name trim_start
--# @param s :: String
--# @return :: String
--# @family string
--# @export
*)

(*
--# Trim trailing whitespace
--# @name trim_end
--# @param s :: String
--# @return :: String
--# @family string
--# @export
*)

(*
--# Split string into lines
--# Splits on \n or \r\n. Strips trailing newline. Accepts ShellResult.
--# @name lines
--# @param s :: String | ShellResult
--# @return :: List[String]
--# @family string
--# @seealso words, strsplit
--# @export
*)

(*
--# Split string into words
--# Splits on whitespace, collapsing consecutive spaces. Accepts ShellResult.
--# @name words
--# @param s :: String | ShellResult
--# @return :: List[String]
--# @family string
--# @seealso lines, strsplit
--# @export
*)

(*
--# Repeat a string
--# @name str_repeat
--# @param s :: String The string to repeat.
--# @param n :: Int Number of repetitions.
--# @return :: String
--# @family string
--# @export
*)

(*
--# Named string interpolation
--# Substitutes {name} placeholders using values from a Dict or named List.
--# @name str_format
--# @param fmt :: String The format string with {name} placeholders.
--# @param values :: Dict | List The named values to substitute.
--# @return :: String The formatted string.
--# @family string
--# @seealso sprintf
--# @export
*)

let register env =
  let env = Env.add "is_empty" (make_builtin ~name:"is_empty" 1 is_empty_impl) env in
  let env = Env.add "length" (make_builtin ~name:"length" 1 length_impl) env in
  let env = Env.add "nchar" (make_builtin ~name:"nchar" 1 nchar_impl) env in
  let env = Env.add "substring" (make_builtin ~name:"substring" 3 substring_impl) env in
  let env = Env.add "slice" (make_builtin ~name:"slice" 3 substring_impl) env in
  let env = Env.add "char_at" (make_builtin ~name:"char_at" 2 char_at_impl) env in
  let env = Env.add "index_of" (make_builtin ~name:"index_of" 2 index_of_impl) env in
  let env = Env.add "last_index_of" (make_builtin ~name:"last_index_of" 2 last_index_of_impl) env in
  let env = Env.add "contains" (make_builtin ~name:"contains" 2 contains_impl) env in
  let env = Env.add "starts_with" (make_builtin ~name:"starts_with" 2 starts_with_impl) env in
  let env = Env.add "ends_with" (make_builtin ~name:"ends_with" 2 ends_with_impl) env in
  let env = Env.add "replace" (make_builtin ~name:"replace" 3 replace_impl) env in
  let env = Env.add "replace_first" (make_builtin ~name:"replace_first" 3 replace_first_impl) env in
  let env = Env.add "to_lower" (make_builtin ~name:"to_lower" 1 to_lower_impl) env in
  let env = Env.add "to_upper" (make_builtin ~name:"to_upper" 1 to_upper_impl) env in
  let env = Env.add "trim"        (make_builtin ~name:"trim"        1 trim_impl)        env in
  let env = Env.add "trim_start"  (make_builtin ~name:"trim_start"  1 trim_start_impl)  env in
  let env = Env.add "trim_end"    (make_builtin ~name:"trim_end"    1 trim_end_impl)    env in
  let env = Env.add "lines"       (make_builtin ~name:"lines"       1 lines_impl)       env in
  let env = Env.add "words"       (make_builtin ~name:"words"       1 words_impl)       env in
  let env = Env.add "str_repeat"  (make_builtin ~name:"str_repeat"  2 str_repeat_impl)  env in
  let env = Env.add "str_format"  (make_builtin ~name:"str_format"  2 str_format_impl)  env in
  let env = Env.add "sprintf" (make_builtin ~name:"sprintf" ~variadic:true 1 sprintf_impl) env in
  let env = Env.add "join" (make_builtin ~name:"join" ~variadic:true 1 join_impl) env in
  let env = Env.add "string" (make_builtin ~name:"string" 1 string_impl) env in
  let env = Env.add "strsplit" (make_builtin ~name:"strsplit" 2 strsplit_impl) env in
  env
