open Ast

let assertion_failure ?message default_message =
  match message with
  | Some msg -> Error.make_error AssertionError ("Assertion failed: " ^ msg ^ ".")
  | None -> Error.make_error AssertionError default_message

let path_arg function_name ordinal = function
  | VString path -> Ok path
  | other ->
      Error
        (Error.type_error
           (Printf.sprintf
              "Function `%s` expects a String as its %s argument, got %s."
              function_name ordinal (Utils.type_name other)))

let message_arg function_name ordinal = function
  | VString msg -> Ok msg
  | other ->
      Error
        (Error.type_error
           (Printf.sprintf
              "Function `%s` expects a String as its %s argument, got %s."
              function_name ordinal (Utils.type_name other)))

let expected_size_arg = function
  | VInt size when size >= 0 -> Ok size
  | VInt _ ->
      Error
        (Error.value_error
           "Function `assert_size_of_file` expects a non-negative file size.")
  | other ->
      Error
        (Error.type_error
           (Printf.sprintf
              "Function `assert_size_of_file` expects an Int as its second argument, got %s."
              (Utils.type_name other)))

type file_target =
  | Missing
  | NotRegular
  | RegularFile of Unix.stats

let inspect_file_target path =
  match Unix.stat path with
  | { Unix.st_kind = Unix.S_REG; _ } as stats -> RegularFile stats
  | _ -> NotRegular
  | exception Unix.Unix_error _ -> Missing

type directory_target =
  | DirectoryMissing
  | NotDirectory
  | Directory

let inspect_directory_target path =
  match Unix.stat path with
  | { Unix.st_kind = Unix.S_DIR; _ } -> Directory
  | _ -> NotDirectory
  | exception Unix.Unix_error _ -> DirectoryMissing

let optional_arity_error function_name expected received =
  Error.make_error ArityError
    (Printf.sprintf
       "Function `%s` expects %s arguments but received %d."
       function_name expected received)

(*
--# Assert Condition
--#
--# Checks if a condition is true, raising an error if false.
--#
--# @name assert
--# @param condition :: Bool The condition to check.
--# @param message :: String (Optional) Custom error message.
--# @return :: Bool True if successful.
--# @example
--#   assert(1 == 1)
--#   assert(x > 0, "x must be positive")
--# @family base
--# @seealso error, is_error
--# @export
*)
let register env =
  let env =
    Env.add "assert"
      (make_builtin ~name:"assert" ~variadic:true 1 (fun args _env ->
        match args with
        | [v] ->
            if is_na_value v then
              Error.make_error AssertionError "Assertion received NA."
            else if Utils.is_truthy v then VBool true
            else Error.make_error AssertionError "Assertion failed."
        | [v; VString msg] ->
            if is_na_value v then
              Error.make_error AssertionError ("Assertion received NA: " ^ msg ^ ".")
            else if Utils.is_truthy v then VBool true
            else Error.make_error AssertionError ("Assertion failed: " ^ msg ^ ".")
        | [_; other] ->
            Error.type_error
              (Printf.sprintf
                 "Function `assert` expects a String as its second argument, got %s."
                 (Utils.type_name other))
        | _ ->
            Error.make_error ArityError
              (Printf.sprintf
                 "Function `assert` expects 1 or 2 arguments but received %d."
                 (List.length args))))
      env
  in
  (*
  --# Assert File Exists
  --#
  --# Checks that a regular file exists at the given path.
  --#
  --# @name assert_file_exists
  --# @param path :: String The file path to check.
  --# @param message :: String (Optional) Custom assertion message.
  --# @return :: Bool True if the file exists.
  --# @example
  --#   assert_file_exists("output.csv")
  --#   assert_file_exists("report.html", "report generation failed")
  --# @family base
  --# @seealso assert, file_exists
  --# @export
  *)
  let env =
    Env.add "assert_file_exists"
      (make_builtin ~name:"assert_file_exists" ~variadic:true 1 (fun args _env ->
        let exists path message =
          match inspect_file_target path with
          | RegularFile _ -> VBool true
          | Missing ->
              assertion_failure ?message
                (Printf.sprintf "Expected file `%s` to exist." path)
          | NotRegular ->
              assertion_failure ?message
                (Printf.sprintf "Expected `%s` to be a regular file." path)
        in
        match args with
        | [path_value] ->
            (match path_arg "assert_file_exists" "first" path_value with
             | Ok path -> exists path None
             | Error err -> err)
        | [path_value; message_value] ->
            (match
               ( path_arg "assert_file_exists" "first" path_value,
                 message_arg "assert_file_exists" "second" message_value )
             with
             | Ok path, Ok message -> exists path (Some message)
             | Error err, _ | _, Error err -> err)
        | _ ->
            optional_arity_error "assert_file_exists" "1 or 2" (List.length args)))
      env
  in
  (*
  --# Assert Directory Exists
  --#
  --# Checks that a directory exists at the given path.
  --#
  --# @name assert_dir_exists
  --# @param path :: String The directory path to check.
  --# @param message :: String (Optional) Custom assertion message.
  --# @return :: Bool True if the directory exists.
  --# @example
  --#   assert_dir_exists("results")
  --#   assert_dir_exists("artifacts", "artifact directory was not created")
  --# @family base
  --# @seealso assert, dir_exists
  --# @export
  *)
  let env =
    Env.add "assert_dir_exists"
      (make_builtin ~name:"assert_dir_exists" ~variadic:true 1 (fun args _env ->
        let exists path message =
          match inspect_directory_target path with
          | Directory -> VBool true
          | DirectoryMissing ->
              assertion_failure ?message
                (Printf.sprintf "Expected directory `%s` to exist." path)
          | NotDirectory ->
              assertion_failure ?message
                (Printf.sprintf "Expected `%s` to be a directory." path)
        in
        match args with
        | [path_value] ->
            (match path_arg "assert_dir_exists" "first" path_value with
             | Ok path -> exists path None
             | Error err -> err)
        | [path_value; message_value] ->
            (match
               ( path_arg "assert_dir_exists" "first" path_value,
                 message_arg "assert_dir_exists" "second" message_value )
             with
             | Ok path, Ok message -> exists path (Some message)
             | Error err, _ | _, Error err -> err)
        | _ ->
            optional_arity_error "assert_dir_exists" "1 or 2" (List.length args)))
      env
  in
  (*
  --# Assert File Size
  --#
  --# Checks that a regular file exists and has the expected size in bytes.
  --#
  --# @name assert_size_of_file
  --# @param path :: String The file path to check.
  --# @param size :: Int The expected size in bytes.
  --# @param message :: String (Optional) Custom assertion message.
  --# @return :: Bool True if the file exists and has the expected size.
  --# @example
  --#   assert_size_of_file("output.csv", 128)
  --#   assert_size_of_file("report.html", 0, "report should be empty")
  --# @family base
  --# @seealso assert_file_exists
  --# @export
  *)
  let env =
    Env.add "assert_size_of_file"
      (make_builtin ~name:"assert_size_of_file" ~variadic:true 2 (fun args _env ->
        let matches_size path expected_size message =
          match inspect_file_target path with
          | Missing ->
              assertion_failure ?message
                (Printf.sprintf "Expected file `%s` to exist." path)
          | NotRegular ->
              assertion_failure ?message
                (Printf.sprintf "Expected `%s` to be a regular file." path)
          | RegularFile stats ->
              if stats.Unix.st_size = expected_size then VBool true
              else
                assertion_failure ?message
                  (Printf.sprintf
                     "Expected file `%s` to have size %d bytes but found %d bytes."
                     path expected_size stats.Unix.st_size)
        in
        match args with
        | [path_value; size_value] ->
            (match
               ( path_arg "assert_size_of_file" "first" path_value,
                 expected_size_arg size_value )
             with
             | Ok path, Ok expected_size -> matches_size path expected_size None
             | Error err, _ | _, Error err -> err)
        | [path_value; size_value; message_value] ->
            (match
               ( path_arg "assert_size_of_file" "first" path_value,
                 expected_size_arg size_value,
                 message_arg "assert_size_of_file" "third" message_value )
             with
             | Ok path, Ok expected_size, Ok message ->
                 matches_size path expected_size (Some message)
             | Error err, _, _ | _, Error err, _ | _, _, Error err -> err)
        | _ ->
            optional_arity_error "assert_size_of_file" "2 or 3" (List.length args)))
      env
  in
  (*
  --# Assert File Is Non-Empty
  --#
  --# Checks that a regular file exists and contains at least one byte.
  --#
  --# @name assert_non_empty_file
  --# @param path :: String The file path to check.
  --# @param message :: String (Optional) Custom assertion message.
  --# @return :: Bool True if the file exists and is non-empty.
  --# @example
  --#   assert_non_empty_file("output.csv")
  --#   assert_non_empty_file("plot.png", "plot was not written")
  --# @family base
  --# @seealso assert_file_exists, assert_size_of_file
  --# @export
  *)
  let env =
    Env.add "assert_non_empty_file"
      (make_builtin ~name:"assert_non_empty_file" ~variadic:true 1 (fun args _env ->
        let non_empty path message =
          match inspect_file_target path with
          | Missing ->
              assertion_failure ?message
                (Printf.sprintf "Expected file `%s` to exist." path)
          | NotRegular ->
              assertion_failure ?message
                (Printf.sprintf "Expected `%s` to be a regular file." path)
          | RegularFile stats ->
              if stats.Unix.st_size > 0 then VBool true
              else
                assertion_failure ?message
                  (Printf.sprintf "Expected file `%s` to be non-empty." path)
        in
        match args with
        | [path_value] ->
            (match path_arg "assert_non_empty_file" "first" path_value with
             | Ok path -> non_empty path None
             | Error err -> err)
        | [path_value; message_value] ->
            (match
               ( path_arg "assert_non_empty_file" "first" path_value,
                 message_arg "assert_non_empty_file" "second" message_value )
             with
             | Ok path, Ok message -> non_empty path (Some message)
             | Error err, _ | _, Error err -> err)
        | _ ->
            optional_arity_error "assert_non_empty_file" "1 or 2" (List.length args)))
      env
  in
  env
