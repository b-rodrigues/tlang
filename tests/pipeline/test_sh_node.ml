let run_tests pass_count fail_count _failures _eval_string eval_string_env test =
  Printf.printf "Phase 3 — Shell Runtime (runtime = sh):\n";
  let contains_substring s sub =
    let re = Str.regexp_string sub in
    try ignore (Str.search_forward re s 0); true
    with Not_found -> false
  in

  let (v_sh, _) = eval_string_env
    {|node(runtime = sh, command = "awk")|}
    (Packages.init_env ()) in
  (match v_sh with
   | Ast.VNode un when un.un_runtime = "sh" ->
        incr pass_count; Printf.printf "  ✓ node(runtime = sh, command = \"awk\") creates sh node\n"
   | other ->
        incr fail_count; Printf.printf "  ✗ node(runtime = sh) creation failed: %s\n"
          (Ast.Utils.value_to_string other));

  let (v_shn, _) = eval_string_env
    {|shn(command = "awk")|}
    (Packages.init_env ()) in
  (match v_shn with
   | Ast.VNode un when un.un_runtime = "sh" ->
       incr pass_count; Printf.printf "  ✓ shn(command = \"awk\") defaults to sh runtime\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ shn(command = \"awk\") failed: %s\n"
         (Ast.Utils.value_to_string other));

  let (v_shn_script, _) = eval_string_env
    {|shn(script = "run.sh")|}
    (Packages.init_env ()) in
  (match v_shn_script with
   | Ast.VNode un when un.un_runtime = "sh" && un.un_script = Some "run.sh" ->
       incr pass_count; Printf.printf "  ✓ shn(script = \"run.sh\") stores shell script path\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ shn(script = \"run.sh\") failed: %s\n"
         (Ast.Utils.value_to_string other));

  (* Test: sh node with list args *)
  let (v_sh_list, _) = eval_string_env
    {|node(runtime = sh, args = ["-F", ","])|}
    (Packages.init_env ()) in
  (match v_sh_list with
   | Ast.VNode un when un.un_runtime = "sh" ->
       incr pass_count; Printf.printf "  ✓ sh node with list args\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ sh node with list args failed: %s\n"
         (Ast.Utils.value_to_string other));

  (* Test: shell and shell_args storage *)
  let (v_sh_shell, _) = eval_string_env
    {|sn = node(runtime = sh, shell = "bash", shell_args = ["-lc"]); sn|}
    (Packages.init_env ()) in
  (match v_sh_shell with
   | Ast.VNode _ ->
       incr pass_count; Printf.printf "  ✓ sh node shell/shell_args storage\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ sh node shell/shell_args storage failed: %s\n"
         (Ast.Utils.value_to_string other));

  (* Test: dot access for sh node *)
  let env_sh = Packages.init_env () in
  let env_sh = Test_helpers.eval_setup eval_string_env env_sh "test_sh_node:63" {|sh_n = node(runtime = sh, shell = "bash")|} in
  
  let (v_rt, _) = eval_string_env "sh_n.runtime" env_sh in
  if Ast.Utils.value_to_string v_rt = "\"sh\"" then
    (incr pass_count; Printf.printf "  ✓ sh node .runtime returns sh\n")
  else
    (incr fail_count; Printf.printf "  ✗ sh node .runtime returns sh\n    Expected: \"sh\"\n    Got:      %s\n" (Ast.Utils.value_to_string v_rt));

  let (v_shell, _) = eval_string_env "sh_n.shell" env_sh in
  if Ast.Utils.value_to_string v_shell = "\"bash\"" then
    (incr pass_count; Printf.printf "  ✓ sh node .shell returns shell value\n")
  else
    (incr fail_count; Printf.printf "  ✗ sh_n.shell returns shell value\n    Expected: \"bash\"\n    Got:      %s\n" (Ast.Utils.value_to_string v_shell));

  let env_sh2 = Test_helpers.eval_setup eval_string_env (Packages.init_env ()) "test_sh_node:77" {|sh_n2 = node(runtime = sh)|} in
  let (v_shell2, _) = eval_string_env "sh_n2.shell" env_sh2 in
  if Ast.Utils.value_to_string v_shell2 = "NA" then
    (incr pass_count; Printf.printf "  ✓ sh node .shell returns NA when unset\n")
  else
    (incr fail_count; Printf.printf "  ✗ sh node .shell returns NA when unset\n    Expected: NA\n    Got:      %s\n" (Ast.Utils.value_to_string v_shell2));

  (* Test: auto-detect runtime as sh for .sh script *)
  let (v_sh_auto, _) = eval_string_env
    {|node(script = "deploy.sh")|}
    (Packages.init_env ()) in
  (match v_sh_auto with
   | Ast.VNode un when un.un_runtime = "sh" ->
       incr pass_count; Printf.printf "  ✓ runtime auto-detected as sh for .sh script\n"
   | _ ->
       incr fail_count; Printf.printf "  ✗ runtime auto-detection for .sh failed\n");

  (* Test: serializer defaults to text/lines for sh nodes *)
  let (v_sh_ser, _) = eval_string_env
    {|node(runtime = sh, command = "ls")|}
    (Packages.init_env ()) in
  (match v_sh_ser with
   | Ast.VNode un when (match un.un_serializer.Ast.node with Value (VString "text") | Value (VSymbol "text") | Var "text" | Value (VString "lines") | Value (VSymbol "lines") | Var "lines" -> true | _ -> false) ->
       incr pass_count; Printf.printf "  ✓ sh node stores text/lines serializer\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ sh node stores text/lines serializer failed: %s\n" (Ast.Utils.value_to_string other));

  (* Test: sh node in pipeline *)
  let (v_sh_pipeline, _) = eval_string_env
    {|pipeline {
      raw = ?<{cat data.csv}>
      processed = node(runtime = sh, command = "awk '{print $1}'", args = ["data.csv"])
    }|}
    (Packages.init_env ()) in
  (match v_sh_pipeline with
   | Ast.VPipeline p ->
       if List.assoc "processed" p.p_runtimes = "sh" then
         begin incr pass_count; Printf.printf "  ✓ sh node in pipeline has correct runtime\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ sh node in pipeline has wrong runtime: %s\n" (List.assoc "processed" p.p_runtimes) end
   | other ->
       incr fail_count; Printf.printf "  ✗ sh node in pipeline failed: %s\n" (Ast.Utils.value_to_string other));

  (* Nix Emission tests *)
  let (v_sh_nix, _) = eval_string_env
    {|pipeline {
      out = node(runtime = sh, command = "echo hello")
    }|}
    (Packages.init_env ()) in
  (match v_sh_nix with
   | Ast.VPipeline p ->
       let _nix = Nix_emit_pipeline.emit_pipeline p in
       (incr pass_count; Printf.printf "  ✓ sh node Nix emission generated\n")
   | _ ->
       incr fail_count; Printf.printf "  ✗ sh node Nix emission failed\n");

  (* Regression: pipeline_copy() writes pipeline-output/ at project root.
     It must stay out of `sources`, or every copy changes the source hash
     and all nodes rebuild on the next run. Match the actual filter clause,
     not the explanatory comment (which also names the directory). *)
  (match v_sh_nix with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       if contains_substring nix "baseName == \"pipeline-output\"" then
         begin incr pass_count; Printf.printf "  ✓ pipeline sources exclude pipeline-output/\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ pipeline sources missing pipeline-output exclusion\n" end
   | _ ->
       incr fail_count; Printf.printf "  ✗ pipeline sources exclusion check failed\n");

  (* Regression: default/^default serializers must emit real reader/writer
     calls. The emitter used to fall back to the raw string "default",
     producing `= default(...)` calls in node scripts — but no `default`
     builtin exists, and calling the bare symbol spun forever (CI timeout).
     Assert the dep read uses deserialize and no bare default call remains. *)
  (let (v_def_nix, _) = eval_string_env
    {|pipeline {
      a = node(command = 1)
      b = node(command = a + 1, deserializer = ^default, serializer = ^default)
    }|}
    (Packages.init_env ()) in
  match v_def_nix with
  | Ast.VPipeline p ->
      let nix = Nix_emit_pipeline.emit_pipeline p in
      if contains_substring nix "__dep_a = deserialize("
         && not (contains_substring nix "= default(") then
        begin incr pass_count; Printf.printf "  ✓ default serializer emits real reader/writer calls\n" end
      else
        begin incr fail_count; Printf.printf "  ✗ default serializer emission wrong (bare default call or missing deserialize)\n" end
  | _ ->
      incr fail_count; Printf.printf "  ✗ default serializer fixture failed\n");
  (* text has no read_text builtin: the reader must be read_file, never a
     bare text(...) call to nothing (same hang class as default). *)
  (let (v_text_nix, _) = eval_string_env
    {|pipeline {
      a = node(command = "hi")
      b = node(command = a, deserializer = ^text)
    }|}
    (Packages.init_env ()) in
  match v_text_nix with
  | Ast.VPipeline p ->
      let nix = Nix_emit_pipeline.emit_pipeline p in
      if contains_substring nix "__dep_a = read_file("
         && not (contains_substring nix "= text(") then
        begin incr pass_count; Printf.printf "  ✓ text deserializer emits read_file\n" end
      else
        begin incr fail_count; Printf.printf "  ✗ text deserializer emission wrong\n" end
  | _ ->
      incr fail_count; Printf.printf "  ✗ text deserializer fixture failed\n");
  (* Every runtime maps ^default to a real writer: no runtime may emit a
     bare `default(...)` call (the silent-hang class). *)
  List.iter (fun (label, rt, body, writer) ->
    let code = Printf.sprintf
      {|pipeline {
        a = node(command = 1)
        b = node(command = %s, deserializer = ^default, serializer = ^default, runtime = %s)
      }|} body rt in
    match eval_string_env code (Packages.init_env ()) with
    | (Ast.VPipeline p, _) ->
        let nix = Nix_emit_pipeline.emit_pipeline p in
        (* Space-prefixed `" writer("`: R/Julia writers sit at line start
           (`  saveRDS(`), T/Python after `=` (`res1 = serialize(`); the
           space rules out matching inside `deserialize(`. *)
        if contains_substring nix (" " ^ writer ^ "(")
           && not (contains_substring nix "= default(") then
          begin incr pass_count; Printf.printf "  ✓ %s maps default to %s\n" label writer end
        else
          begin incr fail_count; Printf.printf "  ✗ %s default mapping wrong\n" label end
    | _ ->
        incr fail_count; Printf.printf "  ✗ %s default fixture failed\n" label
  ) [("T", "T", "a + 1", "serialize"); ("R", "R", "<{ a + 1 }>", "saveRDS");
     ("Python", "Python", "<{ a + 1 }>", "serialize");
     ("Julia", "Julia", "<{ a + 1 }>", "jl_serialize")];
  (* The emitter must never silently emit a bare call for a known
     format: `^bin` is only valid for fetchurl nodes, so an R node with a
     `^bin` deserializer has no reader mapping. Expect a loud failure
     naming the format (`bin`), the role, and the runtime — not a
     `bin(...)` call that would hang at build time. (Contrast `^text`,
     which resolves through the serializer registry to a real `readLines`
     reader and keeps working.) Custom function names still pass through
     for resolution against `functions` files at build time. *)
  (let (v_text_r, _) = eval_string_env
    {|pipeline {
      a = rn(command = <{ 1 }>)
      b = rn(command = <{ a }>, deserializer = ^bin)
    }|}
    (Packages.init_env ()) in
  match v_text_r with
  | Ast.VPipeline p ->
      (match (try let _ = Nix_emit_pipeline.emit_pipeline p in None
              with Invalid_argument msg -> Some msg) with
       | Some msg
         when contains_substring msg "bin"
              && contains_substring msg "reader"
              && contains_substring msg "R" ->
           incr pass_count; Printf.printf "  ✓ unmapped known format fails loud with valid set\n"
       | Some msg ->
           incr fail_count; Printf.printf "  ✗ loud failure missing format/runtime: %s\n" msg
       | None ->
           incr fail_count; Printf.printf "  ✗ unmapped known format emitted silently\n")
  | _ ->
      incr fail_count; Printf.printf "  ✗ text-on-R fixture failed\n");
  (let (v_custom, _) = eval_string_env
    {|pipeline {
      a = node(command = 1)
      b = node(command = a + 1, deserializer = read_pkl, serializer = write_pkl, functions = ["my_ser.py"])
    }|}
    (Packages.init_env ()) in
  match v_custom with
  | Ast.VPipeline p ->
      let nix =
        (try Some (Nix_emit_pipeline.emit_pipeline p)
         with Invalid_argument _ -> None)
      in
      (match nix with
       | Some s when contains_substring s "read_pkl(" && contains_substring s "write_pkl(" ->
           incr pass_count; Printf.printf "  ✓ custom function strategies pass through\n"
       | _ ->
           incr fail_count; Printf.printf "  ✗ custom function strategies blocked or missing\n")
  | _ ->
      incr fail_count; Printf.printf "  ✗ custom strategy fixture failed\n");
  (* Regression: UV nodes need system BLAS/Fortran, nixpkgs nodes must stay
     pristine (foreign BLAS breaks scipy/seaborn). The node derivation picks
     the libs only when the project resolver is uv. This fixture has no
     custom flake, so it goes through the ld_extra branch.
     Assert the exact LD_LIBRARY_PATH line so ld_extra/src_block %s slots
     cannot silently swap (all args share one type, OCaml cannot catch it). *)
  (match v_sh_nix with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       let exact_line = "LD_LIBRARY_PATH = \"${pkgs.gcc.cc.lib}/lib:${pkgs.avahi}/lib${if pyResolver == \"uv\" then \":${pkgs.openblas}/lib:${pkgs.gfortran.cc.lib}/lib\" else \"\"}\";" in
       if contains_substring nix "if pyResolver == \"uv\" then" && contains_substring nix "pkgs.openblas"
          && contains_substring nix exact_line then
         begin incr pass_count; Printf.printf "  ✓ node LD_LIBRARY_PATH is uv-conditional\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ node LD_LIBRARY_PATH missing uv conditional or exact line\n" end
   | _ ->
       incr fail_count; Printf.printf "  ✗ node LD_LIBRARY_PATH check failed\n");

  (* Test: shell mode emission *)
  let (v_sh_shell_nix, _) = eval_string_env
    {|pipeline {
      out = node(runtime = sh, command = "echo hello", shell = "bash", shell_args = ["-lc"])
    }|}
    (Packages.init_env ()) in
  (match v_sh_shell_nix with
    | Ast.VPipeline p ->
        let nix = Nix_emit_pipeline.emit_pipeline p in
        if contains_substring nix "bash" && contains_substring nix "-lc" then
          begin incr pass_count; Printf.printf "  ✓ sh node shell mode Nix emission contains bash and -lc\n" end
        else
          begin incr fail_count; Printf.printf "  ✗ sh node shell mode Nix emission missing bash or -lc: %s\n" nix end
    | _ ->
        incr fail_count; Printf.printf "  ✗ sh node shell mode Nix emission failed\n");

  (* Test: exec-style shell args are emitted via argv-safe wrapper *)
  let (v_sh_exec_args_nix, _) = eval_string_env
    {|pipeline {
      out = node(runtime = sh, command = "printf", args = ["%s", "hello 'quoted' `backtick`"])
    }|}
    (Packages.init_env ()) in
  (match v_sh_exec_args_nix with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       if contains_substring nix "set -- " && contains_substring nix "exec " && contains_substring nix "\"$@\"" then
         begin incr pass_count; Printf.printf "  ✓ sh exec mode emits argv-safe wrapper\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ sh exec mode argv wrapper missing: %s\n" nix end
   | _ ->
       incr fail_count; Printf.printf "  ✗ sh exec mode argv wrapper test failed\n");

  (* Test: assignment-style command strings stay in shell mode *)
  let (v_sh_assignment_cmd_nix, _) = eval_string_env
    {|pipeline {
      out = node(runtime = sh, command = "FOO=1", args = ["printf"])
    }|}
    (Packages.init_env ()) in
  (match v_sh_assignment_cmd_nix with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       if contains_substring nix "FOO=1" && not (contains_substring nix "\"$@\"") then
         begin incr pass_count; Printf.printf "  ✓ sh assignment-style commands stay in shell mode\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ sh assignment-style command heuristic failed: %s\n" nix end
   | _ ->
       incr fail_count; Printf.printf "  ✗ sh assignment-style command test failed\n");

  (* Test: shell-string mode keeps args positional instead of string-joining them *)
  let (v_sh_shell_args_nix, _) = eval_string_env
    {|pipeline {
      out = node(runtime = sh, command = "printf '%s|%s' \"$1\" \"$2\"", args = ["alpha", "line1\nline2"], shell = "bash", shell_args = ["-lc"])
    }|}
    (Packages.init_env ()) in
  (match v_sh_shell_args_nix with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
        if contains_substring nix "set -- 'alpha' 'line1" &&
           contains_substring nix {|printf ${"'"}%s|%s${"'"} "$1" "$2"|} &&
           contains_substring nix ". ./node_script.sh"
       then
         begin incr pass_count; Printf.printf "  ✓ sh shell mode passes args positionally\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ sh shell mode positional args emission failed: %s\n" nix end
   | _ ->
       incr fail_count; Printf.printf "  ✗ sh shell mode positional args test failed\n");

  (* Test: shell runtime execution is hermetic *)
  let (v_sh_env_nix, _) = eval_string_env
    {|pipeline {
      out = node(runtime = sh, command = "echo hello", env_vars = [MODE: "fast"])
    }|}
    (Packages.init_env ()) in
  (match v_sh_env_nix with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       if contains_substring nix {|env -i HOME="$TMPDIR" PATH="$PATH" TMPDIR="$TMPDIR" MODE='fast'|} then
          begin incr pass_count; Printf.printf "  ✓ sh node runtime is emitted with a hermetic environment\n" end
        else
          begin incr fail_count; Printf.printf "  ✗ sh node hermetic env emission missing: %s\n" nix end
   | _ ->
       incr fail_count; Printf.printf "  ✗ sh node hermetic env test failed\n");

  test "node env_vars keys must be valid environment variable names"
    {|node(runtime = sh, command = "echo hello", env_vars = [`bad key`: "fast"])|}
    {|Error(TypeError: "Function `node` expects `env_vars` key `bad key` to be a valid environment variable name ([A-Za-z_][A-Za-z0-9_]*).")|};

  (* Test: sh exec mode execution (nix) *)
  let (v_sh_exec_nix, _) = eval_string_env
    {|pipeline {
      data = [1, 2, 3]
      out = node(runtime = sh, command = "awk", args = ["{print $1}"])
    }|}
    (Packages.init_env ()) in
  (match v_sh_exec_nix with
   | Ast.VPipeline _ ->
       incr pass_count; Printf.printf "  ✓ sh exec mode nix test\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ sh exec mode nix test: expected VPipeline, got: %s\n"
         (Ast.Utils.value_to_string other));

  (* Test: script-backed sh node runs via interpreter *)
  let (v_sh_script_nix, _) = eval_string_env
    {|pipeline {
      out = node(runtime = sh, script = "run.sh")
    }|}
    (Packages.init_env ()) in
  (match v_sh_script_nix with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       if contains_substring nix "sh" then
         begin incr pass_count; Printf.printf "  ✓ script-backed sh node runs via interpreter in Nix emission\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ script-backed sh node Nix emission missing interpreter: %s\n" nix end
   | _ ->
       incr fail_count; Printf.printf "  ✗ script-backed sh node Nix emission failed\n");

  (* Test: script-backed sh node uses explicit interpreter *)
  let (v_sh_script_bash, _) = eval_string_env
    {|pipeline {
      out = node(runtime = sh, script = "run.sh", shell = "bash")
    }|}
    (Packages.init_env ()) in
  (match v_sh_script_bash with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       if contains_substring nix "bash" then
         begin incr pass_count; Printf.printf "  ✓ script-backed sh node uses explicit bash interpreter\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ script-backed sh node explicit bash failed: %s\n" nix end
   | _ ->
       incr fail_count; Printf.printf "  ✗ script-backed sh node explicit bash failed\n");

  (* Test: nested list args rejected *)
  test "sh node rejects nested list args"
    {|node(runtime = sh, args = [["a"]])|}
    {|Error(TypeError: "Function `node` expects `args` list items to be String, Symbol, Int, Float, Bool, or NA values.")|};

  test "node args must be a dict or list"
    {|node(command = 1, args = 1)|}
    {|Error(TypeError: "Function `node` expects `args` to be a Dict or List.")|};

  (* Test: capture = "stdout" sugar *)
  let (v_sh_stdout_cap, _) = eval_string_env
    {|node(command = "echo hello", capture = "stdout")|}
    (Packages.init_env ()) in
  (match v_sh_stdout_cap with
   | Ast.VNode un ->
       let is_text e =
         match e.Ast.node with
         | Ast.Value (Ast.VString "text") | Ast.Value (Ast.VSymbol "text") | Ast.Var "text" -> true
         | _ -> false
       in
       if is_text un.un_serializer && is_text un.un_deserializer then
         begin incr pass_count; Printf.printf "  ✓ capture = \"stdout\" configures serializer/deserializer to text\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ capture = \"stdout\" failed\n" end
   | other ->
       incr fail_count; Printf.printf "  ✗ capture = \"stdout\" failed: %s\n" (Ast.Utils.value_to_string other));

  (* Test: T_INPUT_<dep> variable in Nix hermetic env *)
  let (v_sh_t_input, _) = eval_string_env
    {|pipeline {
      a = node(runtime = sh, command = "echo 1")
      b = node(runtime = sh, command = "echo 2", deps = ["a"])
    }|}
    (Packages.init_env ()) in
  (match v_sh_t_input with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       if contains_substring nix "T_INPUT_a=\"$T_NODE_a/artifact\"" &&
          contains_substring nix "T_INPUT_a = \"${a}/artifact\";" then
         begin incr pass_count; Printf.printf "  ✓ Nix emission includes T_INPUT_<dep> environment variables\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ Nix emission does not include T_INPUT_<dep> correctly: %s\n" nix end
   | _ ->
       incr fail_count; Printf.printf "  ✗ T_INPUT_<dep> Nix test failed\n");

  print_newline ()
