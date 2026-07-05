let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "fetchurl / prefetch:\n";

  (* --- Type errors (REPL mode, no network) --- *)
  test "fetchurl: wrong type for url"
    "fetchurl(42)"
    {|Error(TypeError: "Function `fetchurl` expects a String URL as first argument, got Int.")|};

  test "fetchurl: no arguments"
    "fetchurl()"
    {|Error(ArityError: "[L1:C1] Function `fetchurl` expects 1 arguments but received 0.")|};

  test "prefetch: wrong type for url"
    "prefetch(42)"
    {|Error(TypeError: "Function `prefetch` expects a String URL, got Int.")|};

  test "prefetch: no arguments"
    "prefetch()"
    {|Error(ArityError: "[L1:C1] Function `prefetch` expects 1 arguments but received 0.")|};

  test "prefetch: too many arguments"
    {|prefetch("https://example.com", "extra")|}
    {|Error(ArityError: "[L1:C1] Function `prefetch` expects 1 arguments but received 2.")|};

  (* --- fetchurl is a builtin function --- *)
  test "fetchurl is a builtin function"
    "type(fetchurl)"
    {|"BuiltinFunction"|};

  (* --- sha256 type checking --- *)
  test "fetchurl: sha256 wrong type"
    {|fetchurl("https://example.com", sha256 = 42)|}
    {|Error(TypeError: "Function `fetchurl`: `sha256` expects a String, got Int.")|};

  (* --- Pipeline-mode node construction --- *)
  (* In pipeline construction mode, fetchurl(...) must create a node, not
     attempt a curl invocation.  We verify this by checking the type of the
     resulting node inside a pipeline block. *)
  test "fetchurl in pipeline returns ComputedNode"
    {|p = pipeline { data = fetchurl("https://example.com/data.csv", sha256 = "abc123") }
      type(p.data)|}
    {|"ComputedNode"|};

  print_newline ()
