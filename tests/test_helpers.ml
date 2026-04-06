(* Walk up from the current working directory until the repository marker
   `summary.md` is found; if it is absent, the search falls back to the
   filesystem root so tests fail via missing fixture paths instead. *)
let find_repo_root () =
  let rec loop dir =
    let marker = Filename.concat dir "summary.md" in
    if Sys.file_exists marker then dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then dir else loop parent
  in
  loop (Sys.getcwd ())

(* Check whether `sub` appears anywhere inside `s`. *)
let contains s sub =
  let s_len = String.length s in
  let sub_len = String.length sub in
  let rec loop idx =
    if idx + sub_len > s_len then false
    else if String.sub s idx sub_len = sub then true
    else loop (idx + 1)
  in
  sub_len = 0 || loop 0
