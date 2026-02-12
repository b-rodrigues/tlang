(* src/package_manager/documentation_manager.ml *)
(* Handles documentation validation and access *)



(** Check if documentation structure is valid *)
let validate_docs dir =
  let docs_dir = Filename.concat dir "docs" in
  let index_file = Filename.concat docs_dir "index.md" in
  if not (Sys.file_exists docs_dir && Sys.is_directory docs_dir) then
    Error "Documentation directory 'docs/' not found."
  else if not (Sys.file_exists index_file) then
    Error "Documentation index 'docs/index.md' not found."
  else
    Ok ()

(** Attempt to open documentation in the system browser/viewer *)
let open_docs dir =
  let readme = Filename.concat dir "README.md" in
  let index = Filename.concat (Filename.concat dir "docs") "index.md" in
  let target = if Sys.file_exists index then index else readme in
  
  if not (Sys.file_exists target) then
    Printf.eprintf "No documentation found to open (checked docs/index.md and README.md).\n"
  else
    let cmd = 
      if Sys.os_type = "Win32" then Printf.sprintf "start %s" target
      else if Sys.os_type = "Unix" then
        (* Heuristic for Linux/macOS *)
        if Sys.command "which xdg-open > /dev/null 2>&1" = 0 then
          Printf.sprintf "xdg-open %s" target
        else if Sys.command "which open > /dev/null 2>&1" = 0 then
          Printf.sprintf "open %s" target
        else
          ""
      else ""
    in
    if cmd <> "" then
      ignore (Sys.command cmd)
    else
      Printf.printf "Could not detect a way to open the file automatically.\nDocumentation location: %s\n" target
