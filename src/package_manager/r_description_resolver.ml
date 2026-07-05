open Package_types

let base_r_packages =
  [ "R"; "methods"; "utils"; "stats"; "graphics"; "grDevices"
  ; "datasets"; "grid"; "tools"; "parallel"; "compiler"; "splines"
  ; "stats4"; "tcltk"; "Matrix" ]

let is_base_r_package name =
  List.mem name base_r_packages

let parse_dcf_content content =
  let lines = String.split_on_char '\n' content in
  let rec gather keys lines =
    match lines with
    | [] -> List.rev keys
    | "" :: rest -> gather keys rest
    | line :: rest ->
      if String.length line > 0 && (line.[0] = ' ' || line.[0] = '\t') then
        match keys with
        | (k, v) :: rest_keys ->
          gather ((k, v ^ " " ^ String.trim line) :: rest_keys) rest
        | [] -> gather keys rest
      else
        match String.index_opt line ':' with
        | Some pos ->
          let key = String.trim (String.sub line 0 pos) in
          let value = String.trim (String.sub line (pos + 1) (String.length line - pos - 1)) in
          gather ((key, value) :: keys) rest
        | None -> gather keys rest
  in
  gather [] lines

let get_dcf_field fields key =
  List.assoc_opt key fields

let parse_dep_list value =
  if value = "" || value = "NA" then []
  else
    String.split_on_char ',' value
    |> List.map String.trim
    |> List.filter (fun s -> s <> "")
    |> List.map (fun s ->
      match String.index_opt s '(' with
      | Some pos -> String.trim (String.sub s 0 pos)
      | None -> s
    )
    |> List.filter (fun s -> s <> "")

let parse_description_deps content =
  let fields = parse_dcf_content content in
  let deps_from_field key =
    match get_dcf_field fields key with
    | Some value -> parse_dep_list value
    | None -> []
  in
  let imports = deps_from_field "Imports" in
  let depends = deps_from_field "Depends" in
  let linking_to = deps_from_field "LinkingTo" in
  let all = List.sort_uniq String.compare (imports @ depends @ linking_to) in
  List.filter (fun p -> not (is_base_r_package p)) all

let parse_remotes_field value =
  if value = "" || value = "NA" then []
  else
    String.split_on_char ',' value
    |> List.map String.trim
    |> List.filter (fun s -> s <> "")
    |> List.filter_map (fun s ->
      let has_unsupported_prefix =
        match String.index_opt s ':' with
        | Some pos ->
          let prefix = String.sub s 0 pos in
          prefix <> "github" && prefix <> "gitlab"
        | None -> false
      in
      if has_unsupported_prefix then None
      else
        let s = if String.starts_with ~prefix:"github::" s then
          String.sub s 8 (String.length s - 8)
        else if String.starts_with ~prefix:"gitlab::" s then
          String.sub s 8 (String.length s - 8)
        else s in
        let s = match String.index_opt s '#' with
          | Some pos -> String.trim (String.sub s 0 pos)
          | None -> s in
        let repo_part =
          let parts = String.split_on_char '/' s in
          List.fold_left (fun _ p -> p) "" parts
        in
        let final_name =
          match String.index_opt repo_part '@' with
          | Some pos -> String.trim (String.sub repo_part 0 pos)
          | None -> String.trim repo_part
        in
        if final_name <> "" then Some final_name else None
    )

let parse_namespace_deps content =
  let lines = String.split_on_char '\n' content in
  let extract_import line =
    let trimmed = String.trim line in
    if String.starts_with ~prefix:"import(" trimmed && String.ends_with ~suffix:")" trimmed && String.length trimmed >= 8 then
      let inner = String.sub trimmed 7 (String.length trimmed - 8) in
      let inner_clean =
        match String.index_opt inner '=' with
        | Some pos ->
          let before = String.sub inner 0 pos in
          let before_trimmed = String.trim before in
          if String.ends_with ~suffix:"except" before_trimmed && String.length before_trimmed >= 6 then
            String.sub before_trimmed 0 (String.length before_trimmed - 6)
          else
            before
        | None -> inner
      in
      String.split_on_char ',' inner_clean
      |> List.map String.trim
      |> List.filter_map (fun s ->
        if s = "" then None
        else
          let pkg = if String.length s >= 2 && (s.[0] = '"' || s.[0] = '\'') && (s.[String.length s - 1] = '"' || s.[String.length s - 1] = '\'') then
            String.sub s 1 (String.length s - 2)
          else s in
          if pkg <> "" then Some pkg else None
      )
    else if String.starts_with ~prefix:"importFrom(" trimmed && String.ends_with ~suffix:")" trimmed && String.length trimmed >= 12 then
      let inner = String.sub trimmed 11 (String.length trimmed - 12) in
      match String.split_on_char ',' inner with
      | pkg_part :: _ ->
        let pkg = String.trim pkg_part in
        let pkg = if String.length pkg >= 2 && (pkg.[0] = '"' || pkg.[0] = '\'') && (pkg.[String.length pkg - 1] = '"' || pkg.[String.length pkg - 1] = '\'') then
          String.sub pkg 1 (String.length pkg - 2)
        else pkg in
        if pkg <> "" then [pkg] else []
      | [] -> []
    else
      []
  in
  List.map extract_import lines
  |> List.flatten
  |> List.filter (fun p -> not (is_base_r_package p))
  |> List.sort_uniq String.compare

let run_git ~dir args =
  let argv = Array.append [| "git"; "-C"; dir |] (Array.of_list args) in
  let pipe_out_read, pipe_out_write = Unix.pipe () in
  let pipe_err_read, pipe_err_write = Unix.pipe () in
  let devnull = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
  try
    let pid = Unix.create_process "git" argv devnull pipe_out_write pipe_err_write in
    Unix.close pipe_out_write;
    Unix.close pipe_err_write;
    Unix.close devnull;
    let out_buf = Buffer.create 1024 in
    let err_buf = Buffer.create 1024 in
    let buf = Bytes.create 4096 in
    let start_time = Unix.gettimeofday () in
    let rec drain eof_out eof_err =
      if eof_out && eof_err then Ok ()
      else
        let elapsed = Unix.gettimeofday () -. start_time in
        if elapsed > 300.0 then (
          (try Unix.kill pid Sys.sigkill with _ -> ());
          Error "process timed out after 300 seconds"
        ) else
          let read_fds =
            let l = [] in
            let l = if not eof_out then pipe_out_read :: l else l in
            let l = if not eof_err then pipe_err_read :: l else l in
            l
          in
          match Unix.select read_fds [] [] 5.0 with
          | ready, _, _ ->
            let next_eof_out = ref eof_out in
            let next_eof_err = ref eof_err in
            if List.mem pipe_out_read ready then (
              let n = try Unix.read pipe_out_read buf 0 (Bytes.length buf) with _ -> 0 in
              if n > 0 then Buffer.add_subbytes out_buf buf 0 n
              else next_eof_out := true
            );
            if List.mem pipe_err_read ready then (
              let n = try Unix.read pipe_err_read buf 0 (Bytes.length buf) with _ -> 0 in
              if n > 0 then Buffer.add_subbytes err_buf buf 0 n
              else next_eof_err := true
            );
            drain !next_eof_out !next_eof_err
          | exception Unix.Unix_error (Unix.EINTR, _, _) ->
            drain eof_out eof_err
    in
    let drain_res = drain false false in
    Unix.close pipe_out_read;
    Unix.close pipe_err_read;
    let _, status = Unix.waitpid [] pid in
    match drain_res with
    | Error msg -> Error msg
    | Ok () ->
      match status with
      | Unix.WEXITED 0 -> Ok ()
      | Unix.WEXITED code ->
        let err = String.trim (Buffer.contents err_buf) in
        Error (Printf.sprintf "git %s failed with exit code %d: %s"
          (String.concat " " args) code
          (if err <> "" then err else "(no stderr output)"))
      | _ -> Error (Printf.sprintf "git %s terminated abnormally" (String.concat " " args))
  with exn ->
    (try Unix.close pipe_out_write with _ -> ());
    (try Unix.close pipe_err_write with _ -> ());
    (try Unix.close pipe_out_read with _ -> ());
    (try Unix.close pipe_err_read with _ -> ());
    (try Unix.close devnull with _ -> ());
    Error (Printf.sprintf "git %s raised: %s" (String.concat " " args) (Printexc.to_string exn))

let rec remove_path_recursively path =
  try
    let stats = Unix.lstat path in
    match stats.st_kind with
    | Unix.S_DIR ->
      Sys.readdir path
      |> Array.iter (fun name -> remove_path_recursively (Filename.concat path name));
      Unix.rmdir path
    | _ ->
      Sys.remove path
  with Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let rec fetch_commit ~cache_root ~url ~rev ~name =
  let cache_dir = Filename.concat cache_root (Printf.sprintf "%s-%s" name rev) in
  if Sys.file_exists cache_dir then begin
    match run_git ~dir:cache_dir ["rev-parse"; "HEAD"] with
    | Ok _ -> Ok cache_dir
    | Error _ ->
      remove_path_recursively cache_dir;
      fetch_commit ~cache_root ~url ~rev ~name
  end   else begin
    (try Unix.mkdir cache_root 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    (try Unix.mkdir cache_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    match run_git ~dir:cache_dir ["init"] with
    | Error msg -> Error msg
    | Ok () ->
      match run_git ~dir:cache_dir ["remote"; "add"; "origin"; url] with
      | Error msg -> Error msg
      | Ok () ->
        let fetch_result =
          match run_git ~dir:cache_dir ["fetch"; "--depth"; "1"; "origin"; rev] with
          | Ok () -> Ok ()
          | Error _ ->
            run_git ~dir:cache_dir ["fetch"; "--depth"; "1"; "origin"]
        in
        (match fetch_result with
         | Error msg -> Error msg
         | Ok () ->
           match run_git ~dir:cache_dir ["checkout"; "FETCH_HEAD"] with
           | Error msg -> Error msg
           | Ok () -> Ok cache_dir)
  end

let find_file_recursively ~filename ~checkout_dir ~subdir =
  let search_dir = match subdir with
    | Some s -> Filename.concat checkout_dir s
    | None -> checkout_dir
  in
  let direct = Filename.concat search_dir filename in
  if Sys.file_exists direct then Some direct
  else
    let rec search path =
      let entries = try Some (Sys.readdir path) with _ -> None in
      match entries with
      | None -> None
      | Some entries ->
        let found = ref None in
        Array.iter (fun e ->
          let full = Filename.concat path e in
          if e = filename then found := Some full
          else if Sys.is_directory full && e <> ".git" && e <> "_pipeline" then
            match search full with
            | Some p -> found := Some p
            | None -> ()
        ) entries;
        !found
    in
    search search_dir

let find_description_path ~checkout_dir ~subdir =
  find_file_recursively ~filename:"DESCRIPTION" ~checkout_dir ~subdir

let find_namespace_path ~checkout_dir ~subdir =
  find_file_recursively ~filename:"NAMESPACE" ~checkout_dir ~subdir

let read_file path =
  try
    let ch = open_in path in
    let content =
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    Ok content
  with exn ->
    Error (Printf.sprintf "Failed to read %s: %s" path (Printexc.to_string exn))

let auto_detect_one ~cache_root ~(dep : r_git_dependency) ~(all_git_deps : r_git_dependency list) : r_git_dependency =
  if dep.rgd_cran_inputs <> [] || dep.rgd_git_inputs <> [] then
    dep
  else begin
    let all_git_names = List.map (fun d -> d.rgd_name) all_git_deps in
    match fetch_commit ~cache_root ~url:dep.rgd_git_url ~rev:dep.rgd_rev ~name:dep.rgd_name with
    | Error msg ->
      Printf.eprintf "Warning: Failed to fetch %s (%s) for auto-detection: %s\n%!"
        dep.rgd_name dep.rgd_git_url msg;
      dep
    | Ok checkout_dir ->
      begin
        match find_description_path ~checkout_dir ~subdir:dep.rgd_subdir with
        | None ->
          Printf.eprintf "Warning: No DESCRIPTION file found for %s — skipping auto-detection\n%!" dep.rgd_name;
          dep
        | Some desc_path ->
          match read_file desc_path with
          | Error msg ->
            Printf.eprintf "Warning: %s\n%!" msg;
            dep
          | Ok desc_content ->
            let desc_deps = parse_description_deps desc_content in
            let fields = parse_dcf_content desc_content in
            let remote_pkgs =
              match get_dcf_field fields "Remotes" with
              | Some r -> parse_remotes_field r
              | None -> []
            in
            let namespace_deps =
              match find_namespace_path ~checkout_dir ~subdir:dep.rgd_subdir with
              | Some ns_path ->
                (match read_file ns_path with
                 | Ok ns_content -> parse_namespace_deps ns_content
                 | Error _ -> [])
              | None -> []
            in
            let all_deps = List.sort_uniq String.compare (desc_deps @ namespace_deps @ remote_pkgs) in
            let git_deps, cran_deps =
              List.partition (fun pkg -> List.mem pkg all_git_names) all_deps
            in
            List.iter (fun pkg ->
              if not (List.mem pkg all_git_names) && (String.contains pkg '/' || String.contains pkg ':') then
                Printf.eprintf "Warning: Transitive dependency %S looks like a Git remote but is not declared in tproject.toml or renv.lock. It will be treated as a CRAN package.\n%!" pkg
            ) all_deps;
            { dep with
              rgd_cran_inputs = cran_deps;
              rgd_git_inputs = git_deps;
            }
      end
  end

let auto_detect_all ~cache_root ~(deps : r_git_dependency list) : r_git_dependency list =
  List.map (fun dep ->
    auto_detect_one ~cache_root ~dep ~all_git_deps:deps
  ) deps
