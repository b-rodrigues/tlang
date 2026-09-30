(* tests/core/test_records.ml *)
(* User-defined nominal closed records (spec typesystem item 2, step 1).
   Uses a fresh environment per test so type names never collide across
   cases; `test_env` substring matching keeps assertions on the explicit
   contract language (field names, valid sets, type names). *)

let run_tests pass_count fail_count _failures _eval_string _eval_string_env test test_env =
  Printf.printf "Records:\n";
  let fresh () = Packages.init_env () in
  (* Baseline eval still works through the shared helper. *)
  test "record baseline arithmetic"
    "1 + 2"
    "3";
  test_env (fresh ()) "declare, construct, and read a field"
    {|type PtA = { x: Float, y: Float }
p = PtA(x = 1.0, y = 2.0)
p.x|}
    "1.";
  test_env (fresh ()) "record prints with its type name"
    {|type PtB = { x: Float, y: Float }
p = PtB(x = 1.0, y = 2.0)
p|}
    "PtB(x = 1., y = 2.)";
  test_env (fresh ()) "positional construction matches field order"
    {|type PtC = { x: Float, y: Float }
p = PtC(1.0, 2.0)
p.y|}
    "2.";
  test_env (fresh ()) "wrong field type names the field and both types"
    {|type PtD = { x: Float, y: Float }
PtD(x = "s", y = 1.0)|}
    "Expected Float for field `x` of `PtD`, got String";
  test_env (fresh ()) "missing field names the valid set"
    {|type PtE = { x: Float, y: Float }
PtE(x = 1.0)|}
    "Missing field `y` for type `PtE`";
  test_env (fresh ()) "unknown field names the valid set"
    {|type PtF = { x: Float }
PtF(x = 1.0, z = 2.0)|}
    "Unknown field `z` for type `PtF`";
  test_env (fresh ()) "mixed positional and named arguments are rejected"
    {|type PtG = { x: Float, y: Float }
PtG(1.0, y = 2.0)|}
    "either all positional or all named";
  test_env (fresh ()) "missing dot field names the valid set"
    {|type PtH = { x: Float }
p = PtH(x = 1.0)
p.z|}
    "Field `z` not found in `PtH`";
  test_env (fresh ()) "nominal: same shape, different type"
    {|type PtI = { x: Float }
type PrI = { x: Float }
a = PtI(x = 1.0)
b = PrI(x = 1.0)
a == b|}
    "false";
  test_env (fresh ()) "nominal: annotation rejects the twin type"
    {|type PtJ = { x: Float }
type PrJ = { x: Float }
f = \(p: PtJ -> PtJ) p
f(PrJ(x = 1.0))|}
    "Expected PtJ, got PrJ";
  test_env (fresh ()) "annotation accepts its own type"
    {|type PtK = { x: Float }
f = \(p: PtK -> PtK) p
q = f(PtK(x = 1.0))
q.x|}
    "1.";
  test_env (fresh ()) "type name reports through type()"
    {|type PtL = { x: Float }
type(PtL(x = 1.0))|}
    "PtL";
  test_env (fresh ()) "redeclaration is rejected"
    {|type PtM = { x: Float }
type PtM = { x: Int }|}
    "already defined";
  test_env (fresh ()) "duplicate fields are rejected"
    {|type PtN = { x: Float, x: Int }|}
    "Duplicate field `x`";
  test_env (fresh ()) "NA flows through fields"
    {|type PtO = { x: Float, y: Float }
p = PtO(x = NA, y = 1.0)
p.x|}
    "NA";
  test_env (fresh ()) "match wildcard still works on records"
    {|type PtP = { x: Float }
match(PtP(x = 1.0)) { _ => "wild" }|}
    "wild";
  test_env (fresh ()) "match variable binds the record"
    {|type PtQ = { x: Float }
match(PtQ(x = 1.0)) { v => v.x }|}
    "1.";
  (* Syntax errors raise during parsing, so `test_env` cannot express
     them (it reports EXCEPTION). Assert the structured path directly:
     `parse_and_eval` must return the declaration message as a VError. *)
  let (v_syntax, _) =
    Check_utils.parse_and_eval Typecheck.Strict (Packages.init_env ())
      {|foo Bar = { x: Float }|}
  in
  let rendered = Ast.Utils.value_to_string v_syntax in
  let found =
    try ignore (Str.search_forward (Str.regexp_string "Only `type") rendered 0); true
    with Not_found -> false
  in
  (match v_syntax with
   | Ast.VError _ when found ->
       incr pass_count; Printf.printf "  ✓ non-type two-identifier statement stays a syntax error\n"
   | _ ->
       incr fail_count;
       Printf.printf "  ✗ non-type two-identifier statement stays a syntax error\n    Got: %s\n" rendered);
  test_env (fresh ()) "type() builtin keeps working"
    "type(1)"
    "Int";
  test_env (fresh ()) "pattern expansion over records fails loudly on foreign runtimes"
    {|type PtR = { x: Float }
rs = [PtR(x = 1.0), PtR(x = 2.0)]
p = pipeline {
  a = rs
  b = rn(command = <{ x }>, deserializer = ^json, pattern = map_pattern(a))
}
expand_pipeline(p)|}
    "cannot cross";
  test_env (fresh ()) "pattern expansion over records stays fine on T runtimes"
    {|type PtS = { x: Float }
rs = [PtS(x = 1.0), PtS(x = 2.0)]
p = pipeline {
  a = rs
  b = node(command = <{ a }>, pattern = map_pattern(a))
}
expand_pipeline(p)|}
    "Pipeline";
  print_newline ()
