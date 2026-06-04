let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Quotation:\n";

  (* Basic to_expr() capturing — naked expression, no environment *)
  test "expr captures integer" "to_expr(42)" "to_expr(42)";
  test "expr captures addition" "to_expr(1 + 2)" "to_expr(1 + 2)";
  test "expr captures variable reference" "to_expr(x)" "to_expr(x)";
  test "expr requires exactly 1 argument" "to_expr()" {|Error(ArityError: "to_expr() expects exactly 1 argument")|};

  (* eval() *)
  test "eval evaluates expr" "eval(to_expr(10 + 20))" "30";
  test "eval passes through non-expr value" "eval(42)" "42";
  test "eval requires exactly 1 argument" "eval()" {|Error(ArityError: "eval() expects exactly 1 argument")|};

  (* to_exprs() *)
  test "exprs captures multiple expressions" "to_exprs(1 + 1, 2 + 2)" "[to_expr(1 + 1), to_expr(2 + 2)]";
  test "exprs supports named arguments" "to_exprs(x = 1 + 1, y = 2 + 2)" "[x: to_expr(1 + 1), y: to_expr(2 + 2)]";
  test "exprs empty" "to_exprs()" "[]";

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
  test "unquote injects value" "x = 10\neval(to_expr(1 + !!x))" "11";
  test "unquote injects expr" "inner = to_expr(1 + 1)\neval(to_expr(2 * !!inner))" "4";
  test "unquote injects quo (strips env)" "inner = quo(1 + 1)\neval(to_expr(2 * !!inner))" "4";
  test "unquote outside expr gives error" "x = 10\n!!x" "!!10";

  (* !!! unquote-splice operator *)
  test "splice list into call" "vals = [1, 2, 3]\nto_expr(sum(!!!vals))" "to_expr(sum(1, 2, 3))";
  test "splice named list into call" "my_args = [x: 10, y: 20]\nto_expr(f(!!!my_args))" "to_expr(f(x = 10, y = 20))";
  test "splice list into list literal" "vals = [1, 2, 3]\nto_expr([0, !!!vals, 4])" "to_expr([0, 1, 2, 3, 4])";
  test "splice non-list gives type error in list" "x = 42\neval(to_expr([!!!x]))" {|Error(TypeError: "!!! operand must evaluate to a List, Vector, or Dict, got Int")|};
  test "splice outside call or list gives type error" "x = [1, 2]\neval(to_expr(!!!x))" {|Error(TypeError: "!!! can only be used inside a Call, List, or Dict literal within to_expr()")|};

  (* roundtrip: expr + eval *)
  test "expr then eval roundtrip" "e = to_expr(3 * 7)\neval(e)" "21";

  (* enquo() — returns a quosure capturing caller's expression + caller's environment *)
  test "enquo captures caller expression as quosure"
    "my_f = \\(x: Any -> Any) enquo(x)\nmy_f(1 + 2)"
    "quo(1 + 2)";
  test "enquo captures column ref as quosure"
    "my_f = \\(col: Any -> Any) enquo(col)\nmy_f($sepal_length)"
    "quo($sepal_length)";
  test "enquo captures caller environment"
    "x = 10\nmy_f = \\(e: Any -> Any) { q = enquo(e)\nx := 99\neval(q) }\nmy_f(1 + x)"
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
    "col = \"age\"\nto_expr(f(!!col := 42))"
    "to_expr(f(age = 42))";
  test "dynamic name from symbol variable"
    "col = $age\nto_expr(f(!!col := 42))"
    "to_expr(f(age = 42))";
  test "dynamic name from string variable in list"
    "col = \"x\"\nto_expr([!!col := 10])"
    "to_expr([x: 10])";
  test "to_symbol converts string to symbol"
    "to_symbol(\"age\")"
    "age";
  test "to_symbol preserves symbol input"
    "to_symbol($age)"
    "$age";
  test "to_symbol supports string-driven quoting"
    "col = \"age\"\nto_expr(select(df, !!to_symbol(col)))"
    "to_expr(select(df, age))";
  test "to_symbol supports dynamic names"
    "col = \"age\"\nto_expr(f(!!to_symbol(col) := 42))"
    "to_expr(f(age = 42))";
  test "to_symbol rejects empty names"
    "to_symbol(\"   \")"
    {|Error(ValueError: "Function `to_symbol` expects a non-empty String or Symbol.")|};
  test "to_symbol rejects non-string inputs"
    "to_symbol(99)"
    {|Error(TypeError: "Function `to_symbol` expects a String or Symbol.")|};
  test "dynamic name with non-string gives type error"
    "col = 99\nto_expr(f(!!col := 1))"
    {|to_expr(f(Error(TypeError: "!! := requires a String or Symbol as the left-hand name, got Int")))|};

  print_newline ()
