let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Quotation:\n";

  (* Basic expr() capturing *)
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

  (* !! unquote operator *)
  test "unquote injects value" "x = 10\neval(expr(1 + !!x))" "11";
  test "unquote injects expr" "inner = expr(1 + 1)\neval(expr(2 * !!inner))" "4";
  test "unquote outside expr gives error" "!!x" {|Error(GenericError: "!! and !!! can only be used inside expr() or other quoting contexts")|};

  (* !!! unquote-splice operator *)
  test "splice list into call" "vals = [1, 2, 3]\nexpr(sum(!!!vals))" "expr(sum(1, 2, 3))";
  test "splice named list into call" "my_args = [x: 10, y: 20]\nexpr(f(!!!my_args))" "expr(f(x = 10, y = 20))";
  test "splice list into list literal" "vals = [1, 2, 3]\nexpr([0, !!!vals, 4])" "expr([0, 1, 2, 3, 4])";
  test "splice non-list gives type error in list" "x = 42\neval(expr([!!!x]))" {|Error(TypeError: "!!! operand must evaluate to a List, Vector, or Dict, got Int")|};
  test "splice outside call or list gives type error" "x = [1, 2]\neval(expr(!!!x))" {|Error(TypeError: "!!! can only be used inside a Call, List, or Dict literal within expr()")|};

  (* roundtrip: expr + eval *)
  test "expr then eval roundtrip" "e = expr(3 * 7)\neval(e)" "21";

  (* enquo() — capture caller's argument expression *)
  test "enquo captures caller expression"
    "my_f = \\(x: Any -> Expr) enquo(x)\nmy_f(1 + 2)"
    "expr(1 + 2)";
  test "enquo captures column ref"
    "my_f = \\(col: Any -> Expr) enquo(col)\nmy_f($sepal_length)"
    "expr($sepal_length)";
  test "enquo outside call context gives NameError"
    "enquo(x)"
    {|Error(NameError: "enquo: argument `x` not found in current call context.")|};
  test "enquo with non-symbol argument gives ArityError"
    "enquo(1 + 2)"
    {|Error(ArityError: "enquo() expects exactly 1 symbol argument")|};

  (* enquos() — capture variadic caller expressions *)
  test "enquos captures variadic expressions"
    "my_f = \\(... -> List) enquos(...)\nmy_f(1 + 1, 2 + 2)"
    "[expr(1 + 1), expr(2 + 2)]";
  test "enquos captures named variadic expressions"
    "my_f = \\(... -> List) enquos(...)\nmy_f(a = 1 + 1, b = 2 + 2)"
    "[a: expr(1 + 1), b: expr(2 + 2)]";
  test "enquos with no dots returns empty list"
    "my_f = \\(... -> List) enquos(...)\nmy_f()"
    "[]";

  (* !!name := value — dynamic naming *)
  test "dynamic name from string variable"
    "col = \"age\"\neval(expr(f(!!col := 42)))"
    "f(age = 42)";
  test "dynamic name from string variable in list"
    "col = \"x\"\neval(expr([!!col := 10]))"
    "[x: 10]";
  test "dynamic name with non-string gives type error"
    "col = 99\neval(expr(f(!!col := 1)))"
    {|Error(TypeError: "!! := requires a String or Symbol as the left-hand name, got Int")|};

  print_newline ()
