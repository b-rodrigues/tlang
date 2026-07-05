let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "fetchurl / prefetch:\n";

  (* --- Type errors (REPL mode, no network) --- *)
  test "fetchurl: wrong type for url"
    "fetchurl(42)"
    {|Error(TypeError: "Function `fetchurl` expects a String URL as first argument, got Int.")|};

  test "fetchurl: no arguments"
    "fetchurl()"
    {|Error(ArityError: "Function `fetchurl` requires 1 argument, got 0.")|};

  test "prefetch: wrong type for url"
    "prefetch(42)"
    {|Error(TypeError: "Function `prefetch` expects a String URL, got Int.")|};

  test "prefetch: no arguments"
    "prefetch()"
    {|Error(ArityError: "Function `prefetch` requires 1 argument, got 0.")|};

  test "prefetch: too many arguments"
    {|prefetch("https://example.com", "extra")|}
    {|Error(ArityError: "Function `prefetch` requires 1 argument, got 2.")|};

  (* --- fetchurl is a known symbol (resolves to VSymbol, not NameError) --- *)
  test "fetchurl is a known symbol"
    "type(fetchurl)"
    {|"Symbol"|};

  (* --- Pipeline-mode VNode construction --- *)
  (* In pipeline construction mode, fetchurl(...) must return a VNode, not
     attempt a curl invocation.  We verify this by checking the type of the
     resulting node inside a pipeline block. *)
  test "fetchurl in pipeline returns Node"
    {|p = pipeline { data = fetchurl("https://example.com/data.csv", sha256 = "abc123") }
      type(p.data)|}
    {|"Node"|};

  test "fetchurl in pipeline without sha256 returns Node"
    {|p = pipeline { src = fetchurl("https://example.com/file.bin") }
      type(p.src)|}
    {|"Node"|};

  print_newline ()
