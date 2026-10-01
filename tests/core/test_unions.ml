(* tests/core/test_unions.ml *)
(* User-defined tagged unions (spec typesystem item 2, step 2).
   Cases always use call syntax, including nullary ones (`Missing()`):
   a bare name is a binding, never a case test. Fresh environment per
   test so type names never collide. *)

let run_tests pass_count fail_count _failures _eval_string _eval_string_env test test_env =
  Printf.printf "Unions:\n";
  let fresh () = Packages.init_env () in
  test "union baseline arithmetic"
    "1 + 2"
    "3";
  test_env (fresh ()) "declare, construct, and match a case"
    {|type ShA = Circle(Float) | Rect(Float, Float) | Missing()
s = Circle(10.0)
match(s) { Circle(r) => r, _ => 0.0 }|}
    "10.";
  test_env (fresh ()) "multi-payload case binds each position"
    {|type ShB = Circle(Float) | Rect(Float, Float) | Missing()
match(Rect(1.0, 2.0)) { Circle(r) => r, Rect(a, b) => a + b, Missing() => 0.0 }|}
    "3.";
  test_env (fresh ()) "nullary case matches with call syntax"
    {|type ShC = Circle(Float) | Missing()
match(Missing()) { Circle(r) => r, Missing() => 7.0 }|}
    "7.";
  test_env (fresh ()) "union prints as its case"
    {|type UnD = Wrap(Float) | Empty()
Wrap(1.0)|}
    "Wrap(1.)";
  test_env (fresh ()) "wrong payload type names the case"
    {|type ShE = Circle(Float)
Circle("s")|}
    "Expected Float for `Circle` of `ShE`, got String";
  test_env (fresh ()) "wrong payload count names the case"
    {|type ShF = Circle(Float)
Circle(1.0, 2.0)|}
    "expects 1 argument(s), got 2";
  test_env (fresh ()) "named payloads are rejected, not dropped"
    {|type ShG = Circle(Float)
Circle(r = 1.0)|}
    "takes positional arguments only";
  test_env (fresh ()) "union type itself is not constructible"
    {|type ShH = Circle(Float)
ShH(1.0)|}
    "cannot be constructed directly";
  test_env (fresh ()) "ambiguous case names every owner type"
    {|type ShI = Circle(Float)
type ShJ = Circle(Int)
Circle(1.0)|}
    "defined by types ShI, ShJ";
  test_env (fresh ()) "duplicate cases are rejected"
    {|type ShK = Circle(Float) | Circle(Int)|}
    "Duplicate case `Circle`";
  test_env (fresh ()) "unrelated names keep the lazy suggestion error"
    {|no_such_case_xyz(1)|}
    "not defined";
  test_env (fresh ()) "bound variable wins over a case name"
    {|type ShL = Circle(Float)
Circle = 41
Circle|}
    "41";
  test_env (fresh ()) "annotation enforces the union name"
    {|type ShM = Circle(Float)
type ShN = Square(Float)
f = \(s: ShM -> ShM) s
f(Square(1.0))|}
    "Expected ShM, got ShN";
  test_env (fresh ()) "nested union pattern inside a list pattern"
    {|type ShO = Circle(Float) | Missing()
x = [Circle(10.0), 5.0]
match(x) { [Circle(a), b] => a + b, _ => 0.0 }|}
    "15.";
  test_env (fresh ()) "non-matching case falls through to catch-all"
    {|type ShP = Circle(Float) | Missing()
match(Missing()) { Circle(r) => r, _ => "other" }|}
    "other";
  test_env (fresh ()) "pattern expansion over union values fails loudly on foreign runtimes"
    {|type ShQ = Circle(Float) | Missing()
vs = [Circle(1.0), Missing()]
p = pipeline {
  a = vs
  b = rn(command = <{ x }>, deserializer = ^json, pattern = map_pattern(a))
}
expand_pipeline(p)|}
    "cannot cross";
  (* Static diagnostics run on the parsed program directly (values never
     carry warnings, and parse errors raise past test_env). Each case
     asserts warning count plus message text; silence means zero diags.
     A parse failure fails the test explicitly instead of passing quiet. *)
  let contains_sub s sub =
    let sl = String.length s in
    let bl = String.length sub in
    if bl = 0 then true
    else
      let rec loop i =
        if i + bl > sl then false
        else if String.sub s i bl = sub then true
        else loop (i + 1)
      in
      loop 0
  in
  let check_diags name code expect_count expect_sub =
    let program =
      try
        let lexbuf = Lexing.from_string code in
        Ok (Parser.program Lexer.token lexbuf)
      with _ -> Error ()
    in
    match program with
    | Error () ->
        incr fail_count;
        Printf.printf "  ✗ %s (test code failed to parse)\n" name
    | Ok prog ->
        let diags = Check_utils.match_union_diagnostics prog "test.t" in
        let n = List.length diags in
        let sub_ok =
          match expect_sub with
          | None -> true
          | Some sub ->
              List.exists (fun d -> contains_sub d.Diagnostics.diag_message sub) diags
        in
        let sev_ok =
          List.for_all (fun d -> d.Diagnostics.diag_severity = Diagnostics.Warning) diags
        in
        if n = expect_count && sub_ok && sev_ok then begin
          incr pass_count; Printf.printf "  ✓ %s\n" name
        end else begin
          incr fail_count;
          Printf.printf "  ✗ %s (expected %d warnings, got %d)\n" name expect_count n
        end
  in
  check_diags "missing case warns naming the case"
    {|type ShR = Circle(Float) | Missing()
match(Circle(1.0)) { Missing() => 1.0 }|}
    1 (Some "misses case(s) `Circle`");
  check_diags "full coverage stays silent"
    {|type ShS = Circle(Float) | Missing()
match(Circle(1.0)) { Circle(r) => r, Missing() => 0.0 }|}
    0 None;
  check_diags "catch-all stays silent"
    {|type ShT = Circle(Float) | Missing()
match(Circle(1.0)) { Circle(r) => r, _ => 0.0 }|}
    0 None;
  check_diags "unknown case warns naming the valid set"
    {|type ShU = Circle(Float) | Missing()
match(Circle(1.0)) { Cicle(r) => r, _ => 0.0 }|}
    1 (Some "unknown case `Cicle`");
  check_diags "bare variable named like a case warns"
    {|type ShV = Circle(Float) | Missing()
match(Circle(1.0)) { Circle => 1.0, _ => 0.0 }|}
    1 (Some "did you mean `Circle()`");
  check_diags "variable scrutinee stays silent"
    {|type ShW = Circle(Float) | Missing()
match(s) { Missing() => 1.0 }|}
    0 None;
  check_diags "no unions means no warnings"
    {|match(1) { NA => "missing" }|}
    0 None;
  check_diags "variable holding a case warns on missing cases"
    {|type ShAC2 = Circle(Float) | Missing()
s = Circle(1.0)
match(s) { Circle(r) => r }|}
    1 (Some "misses case(s) `Missing`");
  check_diags "reassigned variable stays silent"
    {|type ShAD = Circle(Float) | Missing()
s = Circle(1.0)
s = 5
match(s) { Circle(r) => r }|}
    0 None;
  check_diags "lambda parameter stays silent"
    {|type ShAE = Circle(Float) | Missing()
f = \(s) match(s) { Circle(r) => r }|}
    0 None;
  check_diags "nested branch rebinding stays silent"
    {|type ShAF = Circle(Float) | Missing()
type ShAG = Wrap(Float) | Gone()
s = Circle(1.0)
if (c) { s := Wrap(1.0) }
match(s) { Circle(r) => r }|}
    0 None;
  test_env (fresh ()) "int payload coerces to Float case"
    {|type ShX = Circle(Float) | Missing()
match(Circle(1)) { Circle(r) => r, Missing() => 0.0 }|}
    "1.";
  test_env (fresh ()) "coerced case payload passes generic consistency"
    {|type ShY = Circle(Float) | Missing()
s = Circle(1)
same = \<T>(x: T, y: T -> T) x
match(s) { Circle(r) => same(r, 2.5), Missing() => 0.0 }|}
    "1.";
  test_env (fresh ()) "error payload fails case construction"
    {|type ShZ = Circle(Float) | Missing()
Circle(error("boom"))|}
    "boom";
  test_env (fresh ()) "cross-type case clash fails at declaration"
    {|type ShAA = Circle(Float) | Missing()
type ShAB = Circle(Float) |Gone()|}
    "defined by types";
  test_env (fresh ()) "builtin nominal names are rejected for unions"
    {|type Model = Circle(Float) |Missing()|}
    "built-in type name";
  test_env (fresh ()) "bare case declaration fails with call-syntax error"
    {|type ShAC = Circle(Float) | Missing|}
    "must use call syntax";
  test_env (fresh ()) "alias declaration fails with call-syntax error"
    {|type Celsius = Float|}
    "must use call syntax";
  test_env (fresh ()) "case constructor works as a value"
    {|type ShAC3 = Circle(Float) | Missing()
f = Circle
match(f(1.0)) { Circle(r) => r, Missing() => 0.0 }|}
    "1.";
  test_env (fresh ()) "cases map over collections"
    {|type ShAC4 = Circle(Float) | Missing()
map([1.0, 2.0], Circle)|}
    "[Circle(1.), Circle(2.)]";
  print_newline ()
