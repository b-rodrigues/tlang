open Package_types

let base_r_packages =
  [ "R"; "methods"; "utils"; "stats"; "graphics"; "grDevices"
  ; "datasets"; "grid"; "tools"; "parallel"; "compiler"; "splines"
  ; "stats4"; "tcltk"; "Matrix" ]

let is_base_r_package name =
  List.mem name base_r_packages

let read_renv_lock ~project_root =
  let path = Filename.concat project_root "renv.lock" in
  if not (Sys.file_exists path) then
    Error (Printf.sprintf "renv.lock not found at %s" path)
  else
    try
      let ch = open_in path in
      let content =
        Fun.protect
          ~finally:(fun () -> close_in_noerr ch)
          (fun () -> really_input_string ch (in_channel_length ch))
      in
      try
        Ok (Yojson.Safe.from_string content)
      with Yojson.Json_error msg ->
        Error (Printf.sprintf "Failed to parse renv.lock: %s" msg)
    with exn ->
      Error (Printf.sprintf "Failed to read renv.lock: %s" (Printexc.to_string exn))

let get_string member json =
  match json with
  | `Assoc pairs ->
    (try Some (List.assoc member pairs) with Not_found -> None)
  | _ -> None

let get_string_value member json =
  match get_string member json with
  | Some (`String s) -> Some s
  | _ -> None

let get_string_list member json =
  match get_string member json with
  | Some (`List items) ->
    Some (List.filter_map (fun item -> match item with `String s -> Some s | _ -> None) items)
  | _ -> None

let parse_renv_lock_json json =
  let packages_json =
    match get_string "Packages" json with
    | Some (`Assoc pkgs) -> pkgs
    | _ -> []
  in
  let r_version =
    match get_string "R" json with
    | Some r_json ->
      (match get_string_value "Version" r_json with
       | Some v -> v
       | None -> "unknown")
    | None -> "unknown"
  in
  let parse_package (name, pkg_json) =
    let source = get_string_value "Source" pkg_json |> Option.value ~default:"" in
    let requirements =
      let raw = get_string_list "Requirements" pkg_json in
      match raw with Some r -> r | None -> []
    in
    let remote_host = get_string_value "RemoteHost" pkg_json in
    let remote_username = get_string_value "RemoteUsername" pkg_json in
    let remote_repo = get_string_value "RemoteRepo" pkg_json in
    let remote_sha = get_string_value "RemoteSha" pkg_json in
    let remotes = get_string_value "Remotes" pkg_json in
    let remote_subdir = get_string_value "RemoteSubdir" pkg_json in
    (name, source, requirements, remote_host, remote_username, remote_repo, remote_sha, remotes, remote_subdir)
  in
  let parsed_packages = List.map parse_package packages_json in
  (r_version, parsed_packages)

let sanitize_remote_string s =
  let s =
    if String.starts_with ~prefix:"github::" s then
      String.sub s 8 (String.length s - 8)
    else if String.starts_with ~prefix:"gitlab::" s then
      String.sub s 8 (String.length s - 8)
    else s
  in
  match String.split_on_char '@' s with
  | name_part :: _ -> name_part
  | [] -> s

let split_packages ~project_root : (string list * r_git_dependency list, string) result =
  match read_renv_lock ~project_root with
  | Error msg -> Error msg
  | Ok json ->
    let (_r_version, parsed_packages) = parse_renv_lock_json json in

    let cran_pkgs = ref [] in
    let git_pkgs = ref [] in
    let unsupported = ref [] in

    List.iter (fun (name, source, requirements, remote_host, remote_username, remote_repo, remote_sha, remotes, remote_subdir) ->
      match source with
      | "Repository" | "Bioconductor" ->
        cran_pkgs := name :: !cran_pkgs
      | "GitHub" | "GitLab" as src ->
        (match remote_username, remote_repo, remote_sha with
         | Some user, Some repo, Some sha ->
           let default_host = if src = "GitHub" then "api.github.com" else "gitlab.com" in
           let host = Option.value remote_host ~default:default_host in
           if host = "api.github.com" || host = "gitlab.com" then
             let url = if host = "api.github.com" then
               Printf.sprintf "https://github.com/%s/%s" user repo
             else
               Printf.sprintf "https://gitlab.com/%s/%s" user repo
             in
             let build_inputs = List.filter (fun p -> not (is_base_r_package p)) requirements in
             let remotes_list =
               match remotes with
               | Some r when r <> "" ->
                 let parts = String.split_on_char '\n' r in
                 List.concat_map (fun line ->
                   String.split_on_char ',' line
                 ) parts
                 |> List.map String.trim
                 |> List.filter (fun s -> s <> "")
               | _ -> []
             in
             git_pkgs := (name, url, sha, build_inputs, remotes_list, user, repo, remote_subdir) :: !git_pkgs
           else
             unsupported := name :: !unsupported
         | _ ->
           unsupported := name :: !unsupported
        )
      | _ ->
        unsupported := name :: !unsupported
    ) parsed_packages;

    let git_pkgs_list = List.rev !git_pkgs in

    let resolve_remotes (name, url, sha, build_inputs, remotes_list, _user, _repo, subdir) =
      let resolved =
        List.filter_map (fun remote ->
          let sanitized = sanitize_remote_string remote in
          match String.split_on_char '/' sanitized with
          | [remote_user; remote_repo_name] ->
            List.find_opt (fun (n, _, _, _, _, ru, rr, _) ->
              ru = remote_user && rr = remote_repo_name && n <> name
            ) git_pkgs_list
            |> Option.map (fun (n, _, _, _, _, _, _, _) -> n)
          | _ -> None
        ) remotes_list
      in
      let all_inputs = build_inputs @ resolved in
      let is_git_pkg_name pkg_name =
        List.exists (fun (n, _, _, _, _, _, _, _) -> n = pkg_name) git_pkgs_list
      in
      let git_inputs =
        List.filter is_git_pkg_name all_inputs
        |> List.sort_uniq String.compare
      in
      let cran_inputs =
        List.filter (fun p -> not (is_git_pkg_name p)) all_inputs
        |> List.sort_uniq String.compare
      in
      { rgd_name = name
      ; rgd_git_url = url
      ; rgd_rev = sha
      ; rgd_cran_inputs = cran_inputs
      ; rgd_git_inputs = git_inputs
      ; rgd_subdir = subdir
      }
    in

    let git_deps = List.map resolve_remotes git_pkgs_list in

    List.iter (fun name ->
      Printf.eprintf "Warning: renv.lock package %S has unsupported source and will be skipped\n%!" name
    ) (List.rev !unsupported);

    Ok (List.rev !cran_pkgs, git_deps)

let read_and_split_cran_packages ~project_root : string list =
  match split_packages ~project_root with
  | Ok (cran, _) -> cran
  | Error _ -> []

let read_and_split_git_packages ~project_root : r_git_dependency list =
  match split_packages ~project_root with
  | Ok (_, git) -> git
  | Error _ -> []

