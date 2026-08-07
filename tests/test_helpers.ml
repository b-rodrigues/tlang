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

(* Run a named property under several fixed seeds, asserting PASS under each.
   This hardens property tests against seed-dependent flakiness: a property
   must hold across the whole seed set, not just the canonical seed.
   An optional `preamble` binds env values (e.g. a lookup dataframe) before
   the property runs. *)
let prop_test_seeded ?(preamble = "") test_env env label prop gen n seeds =
  List.iter
    (fun seed ->
      let script =
        Printf.sprintf "set_seed(%d)\n%s\nprop_test(%s, %s, n = %d)" seed preamble prop gen n
      in
      test_env env (Printf.sprintf "%s (seed %d)" label seed) script "PASS")
    seeds

(* Evaluate a setup script that must succeed. If the evaluation produces a
   VError (e.g. a variable binding silently failed and a stale value would be
   reused by later assertions), print the failing label and raise so the
   failure is loud instead of being silently dropped. Returns the updated
   environment. This is the guard that backs the `let (_, env) = eval_string_env`
   migration sweep across the test suite. *)
let eval_setup eval_string_env env label script =
  let (result, env) = eval_string_env script env in
  match result with
  | Ast.VError _ ->
    Printf.printf "  ✗ [setup:%s] evaluation failed:\n    %s\n"
      label (Ast.Utils.value_to_string result);
    failwith (Printf.sprintf "eval_setup: %s produced a VError result" label)
  | _ -> env
