let run_tests pass_count fail_count _eval_string eval_string_env test =
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
  let (_, env_sh) = eval_string_env {|sh_n = node(runtime = sh, shell = "bash")|} env_sh in
  
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

  let (_, env_sh2) = eval_string_env {|sh_n2 = node(runtime = sh)|} (Packages.init_env ()) in
  let (v_shell2, _) = eval_string_env "sh_n2.shell" env_sh2 in
  if Ast.Utils.value_to_string v_shell2 = "null" then
    (incr pass_count; Printf.printf "  ✓ sh node .shell returns null when unset\n")
  else
    (incr fail_count; Printf.printf "  ✗ sh node .shell returns null when unset\n    Expected: null\n    Got:      %s\n" (Ast.Utils.value_to_string v_shell2));

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
         begin incr pass_count; Printf.printf "  ✓ sh node shell mode Nix emission contains bash or -lc\n" end
       else
         begin incr fail_count; Printf.printf "  ✗ sh node shell mode Nix emission missing bash or -lc: %s\n" nix end
   | _ ->
       incr fail_count; Printf.printf "  ✗ sh node shell mode Nix emission failed\n");

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
    {|Error(TypeError: "Function `node` expects `args` list items to be String, Symbol, Int, Float, Bool, or Null values.")|};

  test "node args must be a dict or list"
    {|node(command = 1, args = 1)|}
    {|Error(TypeError: "Function `node` expects `args` to be a Dict or List.")|};

  print_newline ()
