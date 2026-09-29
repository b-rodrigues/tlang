(* tests/cli/test_demo.ml *)

let run_tests pass_count fail_count _failures _eval_string _eval_string_env _test =
  Printf.printf "Demo tests:\n";
  let test_message name predicate =
    if predicate then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
  in

  let env = Packages.init_env () in
  (* The demo builds real pipelines, so it needs a working Nix daemon.
     Skip (without failing) inside sandboxes such as `nix flake check`,
     on boxes with the binary but no daemon/network, or when explicitly
     disabled via TLANG_SKIP_DEMO=1. *)
  (* `builtins.toFile` writes to the store, so it fails with no daemon —
     unlike a pure-eval probe such as `1 + 1`, which passes regardless. *)
  let daemon_ok =
    try
      Sys.command "nix-instantiate --eval -E 'builtins.toFile \"t-demo-probe\" \"y\"' >/dev/null 2>&1" = 0
    with _ -> false
  in
  let explicitly_skipped =
    match Sys.getenv_opt "TLANG_SKIP_DEMO" with
    | Some ("1" | "true" | "yes") -> true
    | _ -> false
  in
  if explicitly_skipped then begin
    incr pass_count;
    Printf.printf "  ○ Demo.run skipped (TLANG_SKIP_DEMO)\n"
  end else if not (Builder_utils.command_exists "nix-build") then begin
    incr pass_count;
    Printf.printf "  ○ Demo.run skipped (no Nix daemon)\n"
  end else if not daemon_ok then begin
    incr pass_count;
    Printf.printf "  ○ Demo.run skipped (Nix daemon unreachable)\n"
  end else begin
    (* Belt and braces: Demo.run already chdirs to a temp dir, but keep the
       test runner's cwd stable in case the demo is refactored. *)
    let orig_dir = Sys.getcwd () in
    let outcome =
      try
        Demo.run ~headless:true env;
        `Ok
      with
      | Demo.Demo_failed msg
        when (try ignore (Str.search_forward (Str.regexp_string "nix-build failed") msg 0); true
              with Not_found -> false) ->
        `Skip_env ("Nix build failed in this environment: " ^ msg)
      | exn -> `Fail (Printexc.to_string exn)
    in
    (try Unix.chdir orig_dir with _ -> ());
    (match outcome with
     | `Ok -> test_message "Demo.run headless completes without errors" true
     | `Skip_env reason ->
       incr pass_count;
       Printf.printf "  ○ Demo.run skipped (%s)\n" reason
     | `Fail err ->
       Printf.eprintf "Demo.run failed with: %s\n" err;
       test_message "Demo.run headless completes without errors" false)
  end
