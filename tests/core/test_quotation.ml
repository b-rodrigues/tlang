let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Quotation:\n";

  (* Basic expr() capturing — naked expression, no environment *)
  test "expr captures integer" "expr(42)" "expr(42)";
  test "expr captures addition" "expr(1 + 2)" "expr(1 + 2)";
  test "expr captures variable reference" "expr(x)" "expr(x)";
  test "expr requires exactly 1 argument" "expr()" {|Error(ArityError: "expr() expects exactly 1 argument")|};

  (* eval() *)
  test "eval evaluates expr" "eval(expr(10 + 20))" "30";
  test "eval passes through non-expr value" "eval(42)" "42";
  test "eval requires exactly 1 argument" "eval()" {|Error(ArityError: "eval() expects exactly 1 argument")|};

  (* exprs() *)
  test "exprs captures multiple expressions" "exprs(1 + 1, 2 + 2)" "[expr(1 + 1), expr(2 + 2)]";
  test "exprs supports named arguments" "exprs(x = 1 + 1, y = 2 + 2)" "[x: expr(1 + 1), y: expr(2 + 2)]";
  test "exprs empty" "exprs()" "[]";

  (* quo() — quosure: captures expression WITH the lexical environment *)
  test "quo captures integer" "quo(42)" "quo(42)";
  test "quo captures addition" "quo(1 + 2)" "quo(1 + 2)";
  test "quo requires exactly 1 argument" "quo()" {|Error(ArityError: "quo() expects exactly 1 argument")|};
  test "eval evaluates quosure" "eval(quo(10 + 20))" "30";
  test "quo preserves captured environment on eval"
    "x = 10\nq = quo(1 + x)\nx := 99\neval(q)"
    "11";

  (* quos() *)
  test "quos captures multiple quosures" "quos(1 + 1, 2 + 2)" "[quo(1 + 1), quo(2 + 2)]";
  test "quos supports named arguments" "quos(a = 1 + 1, b = 2 + 2)" "[a: quo(1 + 1), b: quo(2 + 2)]";
  test "quos empty" "quos()" "[]";

  (* !! unquote operator works with both VExpr and VQuo *)
  test "unquote injects value" "x = 10\neval(expr(1 + !!x))" "11";
  test "unquote injects expr" "inner = expr(1 + 1)\neval(expr(2 * !!inner))" "4";
  test "unquote injects quo (strips env)" "inner = quo(1 + 1)\neval(expr(2 * !!inner))" "4";
  test "unquote outside expr gives error" "x = 10\n!!x" "!!10";

  (* !!! unquote-splice operator *)
  test "splice list into call" "vals = [1, 2, 3]\nexpr(sum(!!!vals))" "expr(sum(1, 2, 3))";
  test "splice named list into call" "my_args = [x: 10, y: 20]\nexpr(f(!!!my_args))" "expr(f(x = 10, y = 20))";
  test "splice list into list literal" "vals = [1, 2, 3]\nexpr([0, !!!vals, 4])" "expr([0, 1, 2, 3, 4])";
  test "splice non-list gives type error in list" "x = 42\neval(expr([!!!x]))" {|Error(TypeError: "!!! operand must evaluate to a List, Vector, or Dict, got Int")|};
  test "splice outside call or list gives type error" "x = [1, 2]\neval(expr(!!!x))" {|Error(TypeError: "!!! can only be used inside a Call, List, or Dict literal within expr()")|};

  (* roundtrip: expr + eval *)
  test "expr then eval roundtrip" "e = expr(3 * 7)\neval(e)" "21";

  (* enquo() — returns a quosure capturing caller's expression + caller's environment *)
  test "enquo captures caller expression as quosure"
    "my_f = \\(x: Any -> Any) enquo(x)\nmy_f(1 + 2)"
    "quo(1 + 2)";
  test "enquo captures column ref as quosure"
    "my_f = \\(col: Any -> Any) enquo(col)\nmy_f($sepal_length)"
    "quo($sepal_length)";
  test "enquo captures caller environment"
    "x = 10\nmy_f = \\(e: Any -> Any) { q = enquo(e)\nx = 99\neval(q) }\nmy_f(1 + x)"
    "11";
  test "enquo outside call context gives NameError"
    "enquo(x)"
    {|Error(NameError: "enquo: argument `x` not found in current call context.")|};
  test "enquo with non-symbol argument gives ArityError"
    "enquo(1 + 2)"
    {|Error(ArityError: "enquo() expects exactly 1 symbol argument")|};

  (* enquos() — returns a list of quosures from variadic args *)
  test "enquos captures variadic as quosures"
    "my_f = \\(... -> List) enquos(...)\nmy_f(1 + 1, 2 + 2)"
    "[quo(1 + 1), quo(2 + 2)]";
  test "enquos captures named variadic as quosures"
    "my_f = \\(... -> List) enquos(...)\nmy_f(a = 1 + 1, b = 2 + 2)"
    "[a: quo(1 + 1), b: quo(2 + 2)]";
  test "enquos with no dots returns empty list"
    "my_f = \\(... -> List) enquos(...)\nmy_f()"
    "[]";

  (* !!name := value — dynamic naming *)
  test "dynamic name from string variable"
    "col = \"age\"\nexpr(f(!!col := 42))"
    "expr(f(age = 42))";
  test "dynamic name from symbol variable"
    "col = $age\nexpr(f(!!col := 42))"
    "expr(f(age = 42))";
  test "dynamic name from string variable in list"
    "col = \"x\"\nexpr([!!col := 10])"
    "expr([x: 10])";
  test "dynamic name with non-string gives type error"
    "col = 99\nexpr(f(!!col := 1))"
    {|expr(f(Error(TypeError: "!! := requires a String or Symbol as the left-hand name, got Int")))|};

  print_newline ()
