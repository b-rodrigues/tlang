open Ast

(* Helper: Unary Vectorization *)
let vectorize_unary op args env =
  match args with
  | [VVector arr] ->
      VVector (Array.map (fun v -> 
        match op [v] env with
        | VError _ as e -> e
        | res -> res
      ) arr)
  | _ -> op args env

(* Helper: Binary Vectorization *)
let vectorize_binary op args env =
  match args with
  | [VVector arr1; VVector arr2] ->
      if Array.length arr1 <> Array.length arr2 then
        Error.broadcast_length_error (Array.length arr1) (Array.length arr2)
      else
        VVector (Array.map2 (fun v1 v2 -> op [v1; v2] env) arr1 arr2)
  | [VVector arr1; val2] ->
      VVector (Array.map (fun v1 -> op [v1; val2] env) arr1)
  | [val1; VVector arr2] ->
      VVector (Array.map (fun v2 -> op [val1; v2] env) arr2)
  | _ -> op args env

(* Helper: Ternary Vectorization *)
let vectorize_ternary op args env =
  match args with
  | [VVector arr1; VVector arr2; VVector arr3] ->
     (* Full broadcast logic is complex, for now assuming congruent shapes or scalars *)
     let len = Array.length arr1 in
     if Array.length arr2 <> len || Array.length arr3 <> len then
       Error.value_error "Vector length mismatch in ternary operation."
     else
       VVector (Array.init len (fun i -> op [arr1.(i); arr2.(i); arr3.(i)] env))
  | [VVector arr1; val2; val3] ->
      VVector (Array.map (fun v1 -> op [v1; val2; val3] env) arr1)
  (* Add other combinations as needed, e.g. substring(vec, scalar, scalar) is common *)
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

let length_scalar args _env =
  match args with
  | [VString _] -> Error.type_error "length does not work on strings. Use nchar() to get the number of characters in a string."
  | [VList items] -> VInt (List.length items)
  | [VDict pairs] -> VInt (List.length pairs)
  | [VVector arr] -> VInt (Array.length arr)
  | _ -> Error.type_error "length expects a collection (List, Vector, or Dict)."

let length_impl args env =
  (* length should always return the count of elements in a collection,
     never vectorize. Use nchar for getting character counts of strings. *)
  length_scalar args env

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
--# Get length
--#
--# Returns the number of elements in a collection (List, Vector, Dict).
--# This function is NOT vectorized - it always returns the count of elements.
--# For getting the number of characters in a string, use nchar() instead.
--#
--# @name length
--# @param x :: List | Vector | Dict The collection to measure.
--# @return :: Int The number of elements.
--# @family string
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

let register env =
  let env = Env.add "is_empty" (make_builtin 1 is_empty_impl) env in
  let env = Env.add "length" (make_builtin 1 length_impl) env in
  let env = Env.add "substring" (make_builtin 3 substring_impl) env in
  let env = Env.add "slice" (make_builtin 3 substring_impl) env in
  let env = Env.add "char_at" (make_builtin 2 char_at_impl) env in
  let env = Env.add "index_of" (make_builtin 2 index_of_impl) env in
  let env = Env.add "last_index_of" (make_builtin 2 last_index_of_impl) env in
  let env = Env.add "contains" (make_builtin 2 contains_impl) env in
  let env = Env.add "starts_with" (make_builtin 2 starts_with_impl) env in
  let env = Env.add "ends_with" (make_builtin 2 ends_with_impl) env in
  let env = Env.add "replace" (make_builtin 3 replace_impl) env in
  let env = Env.add "replace_first" (make_builtin 3 replace_first_impl) env in
  let env = Env.add "to_lower" (make_builtin 1 to_lower_impl) env in
  let env = Env.add "to_upper" (make_builtin 1 to_upper_impl) env in
  env
