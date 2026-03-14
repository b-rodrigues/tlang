type path_kind =
  | File
  | Directory

type test_options = {
  verbose : bool;
  target_dir : string;
}

let validate_path ~kind path =
  let kind_name = function
    | File -> "File"
    | Directory -> "Directory"
  in
  try
    if path = "" then
      Error (Printf.sprintf "%s path must not be empty." (kind_name kind))
    else if not (Sys.file_exists path) then
      Error (Printf.sprintf "%s not found: %s" (kind_name kind) path)
    else
      let is_directory = Sys.is_directory path in
      match kind with
      | File when is_directory ->
          Error (Printf.sprintf "Expected a file path but received a directory: %s" path)
      | Directory when not is_directory ->
          Error (Printf.sprintf "Expected a directory path but received a file: %s" path)
      | _ -> Ok ()
  with
  | Sys_error msg -> Error msg

let parse_test_args ~cwd (args : string list) : (test_options, string) result =
  let verbose = ref false in
  let target_dir = ref None in
  let rec parse = function
    | [] ->
        Ok {
          verbose = !verbose;
          target_dir = (match !target_dir with Some dir -> dir | None -> cwd);
        }
    | ("--verbose" | "-v") :: rest ->
        verbose := true;
        parse rest
    | arg :: _ when String.length arg > 0 && arg.[0] = '-' ->
        Error (Printf.sprintf "Unknown option: %s" arg)
    | arg :: rest ->
        (match !target_dir with
         | None ->
             target_dir := Some arg;
             parse rest
         | Some _ ->
             Error (Printf.sprintf "Unexpected argument: %s" arg))
  in
  parse args
