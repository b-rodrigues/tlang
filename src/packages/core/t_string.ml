open Ast

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
let register env =
  let env = Env.add "join"
    (make_builtin ~name:"join" ~variadic:true 1 (fun args _env ->
      match args with
      | [VList items] ->
          let strs = List.map (fun (_, v) -> Utils.value_to_raw_string v) items in
          VString (String.concat "" strs)
      | [VList items; VString sep] ->
          let strs = List.map (fun (_, v) -> Utils.value_to_raw_string v) items in
          VString (String.concat sep strs)
      | [VVector arr] ->
          let strs = Array.map Utils.value_to_raw_string arr |> Array.to_list in
          VString (String.concat "" strs)
      | [VVector arr; VString sep] ->
          let strs = Array.map Utils.value_to_raw_string arr |> Array.to_list in
          VString (String.concat sep strs)
      | [val_] ->
          VString (Utils.value_to_raw_string val_)
      | [val_; VString _] ->
          VString (Utils.value_to_raw_string val_)
      | _ -> Error.type_error "Function `join` expects (list/vector, [separator]) or (value, [separator])."
    ))
    env
  in
  let env = Env.add "string"
    (make_builtin ~name:"string" 1 (fun args _env ->
      match args with
      | [v] -> VString (Utils.value_to_raw_string v)
      | _ -> Error.type_error "Function `string` expects a single argument."
    ))
    env
  in
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
  let env = Env.add "strsplit"
    (make_builtin ~name:"strsplit" 2 (fun args _env ->
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
    ))
    env
  in
  env
