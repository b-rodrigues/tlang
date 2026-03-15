# Implementation Plan: Maybe-Pipe Operator `?|>`

## Executive Summary

After thorough analysis of the T language repository, I've identified that:
- The standard pipe `|>` is **already implemented correctly** as a conditional pipe (short-circuits on errors)
- The maybe-pipe `?|>` is **specified but not yet implemented**
- The implementation requires changes across 4 core files plus tests

---

## Current State Assessment

### ✅ What's Already Working

**Conditional Pipe (`|>`)**
- Location: `src/eval.ml`, line ~180
- Behavior: Evaluates left side, short-circuits if error, otherwise forwards to function
- Status: **Correctly implemented per spec**

```ocaml
| Pipe ->
    let lval = eval_expr env left in
    (match lval with
     | VError _ as e -> e  (* Already short-circuits! *)
     | _ -> (* forward to function *))
```

### ❌ What's Missing

**Unconditional Pipe (`?|>`)**
- Status: **Not implemented**
- Required behavior: Always forward left value (including errors) to right function
- Use case: Explicit error recovery patterns

---

## Implementation Roadmap

### **Phase 1: Lexer Extension** (Week 1, Day 1)

**File:** `src/lexer.mll`

**Changes Required:**

1. Add new token before the pipe operator definition:

```ocaml
(* Around line 52-53, before the existing PIPE rule *)
| "?|>" { MAYBE_PIPE }
| "|>" { PIPE }
```

**Critical:** The `?|>` rule **must come before** `|>` in the lexer because OCamllex matches longest-first, but when lengths are equal, it matches first-defined.

**Testing checkpoint:**
```bash
echo 'x ?|> f' | dune exec src/repl.exe
# Should lex without "unexpected character" error
```

---

### **Phase 2: AST Definition** (Week 1, Day 1)

**File:** `src/ast.ml`

**Changes Required:**

1. Extend `binop` type (around line 83):

```ocaml
and binop = 
  | Plus | Minus | Mul | Div 
  | Eq | NEq | Gt | Lt | GtEq | LtEq 
  | And | Or 
  | Pipe 
  | MaybePipe  (* Add this *)
```

2. No changes needed to `Utils.value_to_string` (pipe operators don't appear in value representations)

**Testing checkpoint:**
```bash
dune build
# Should compile cleanly
```

---

### **Phase 3: Parser Integration** (Week 1, Day 2)

**File:** `src/parser.mly`

**Changes Required:**

1. Add token declaration (around line 16):

```ocaml
%token PIPE
%token MAYBE_PIPE  (* Add this *)
```

2. Add precedence rule (around line 31):

```ocaml
/* PRECEDENCE AND ASSOCIATIVITY (lowest to highest) */
%left PIPE MAYBE_PIPE  (* Add MAYBE_PIPE to same precedence as PIPE *)
%left OR
```

3. Extend grammar rule in `pipe_expr` (around line 72):

```ocaml
pipe_expr:
  | e = or_expr { e }
  | left = pipe_expr PIPE right = or_expr
    { BinOp { op = Pipe; left; right } }
  | left = pipe_expr MAYBE_PIPE right = or_expr
    { BinOp { op = MaybePipe; left; right } }
  ;
```

**Testing checkpoint:**
```bash
echo 'x = 5 ?|> f' | dune exec src/repl.exe
# Should parse without syntax error
# Will fail at runtime (expected - eval not implemented yet)
```

---

### **Phase 4: Evaluator Implementation** (Week 1, Day 3)

**File:** `src/eval.ml`

**Changes Required:**

Add new case in `eval_binop` function (around line 175, after the existing Pipe case):

```ocaml
and eval_binop env op left right =
  (* Existing Pipe case remains unchanged *)
  match op with
  | Pipe ->
      let lval = eval_expr env left in
      (match lval with
       | VError _ as e -> e  (* Conditional: short-circuit *)
       | _ ->
         match right with
         | Call { fn; args } ->
             let fn_val = eval_expr env fn in
             eval_call env fn_val ((None, Value lval) :: args)
         | _ ->
             let fn_val = eval_expr env right in
             eval_call env fn_val [(None, Value lval)]
      )
  
  (* NEW: Unconditional pipe - always forwards, even errors *)
  | MaybePipe ->
      let lval = eval_expr env left in
      (* No short-circuit check - always forward *)
      (match right with
       | Call { fn; args } ->
           let fn_val = eval_expr env fn in
           eval_call env fn_val ((None, Value lval) :: args)
       | _ ->
           let fn_val = eval_expr env right in
           eval_call env fn_val [(None, Value lval)]
      )
  
  | _ -> (* other operators *)
```

**Key Differences:**
- `|>`: Checks for `VError _` and returns it immediately
- `?|>`: **No error check** - always evaluates right side with left value

**Testing checkpoint:**
```bash
dune exec src/repl.exe
T> result = error("test error")
T> result ?|> print
# Should print: Error(GenericError: "test error")
# and NOT short-circuit
```

---

### **Phase 5: Comprehensive Testing** (Week 1, Days 4-5)

**File:** `tests/phase8/test_maybe_pipe.ml` (new file)

Create comprehensive test suite:

```ocaml
(* tests/phase8/test_maybe_pipe.ml *)
open Ast

let test_conditional_pipe_short_circuits () =
  let env = Eval.initial_env () in
  let code = {|
    result = error("boom")
    result |> print
  |} in
  let (v, _) = Eval.eval_program (parse code) env in
  (* Should return error, not call print *)
  assert (is_error_value v)

let test_maybe_pipe_forwards_errors () =
  let env = Eval.initial_env () in
  let code = {|
    handle_error = \(x) if is_error(x) "recovered" else x
    result = error("boom")
    result ?|> handle_error
  |} in
  let (v, _) = Eval.eval_program (parse code) env in
  (* Should call handle_error with the error *)
  match v with
  | VString "recovered" -> ()
  | _ -> failwith "Maybe-pipe did not forward error"

let test_maybe_pipe_forwards_normal_values () =
  let env = Eval.initial_env () in
  let code = {|
    double = \(x) x * 2
    5 ?|> double
  |} in
  let (v, _) = Eval.eval_program (parse code) env in
  match v with
  | VInt 10 -> ()
  | _ -> failwith "Maybe-pipe did not forward normal value"

let test_pipe_chain_with_both_operators () =
  let env = Eval.initial_env () in
  let code = {|
    recovery = \(x) if is_error(x) 0 else x
    increment = \(x) x + 1
    
    error("fail") 
      ?|> recovery    -- forwards error, gets 0
      |> increment    -- forwards 0 (not error), gets 1
  |} in
  let (v, _) = Eval.eval_program (parse code) env in
  match v with
  | VInt 1 -> ()
  | _ -> failwith "Mixed pipe chain failed"

let () =
  test_conditional_pipe_short_circuits ();
  test_maybe_pipe_forwards_errors ();
  test_maybe_pipe_forwards_normal_values ();
  test_pipe_chain_with_both_operators ();
  print_endline "✓ All maybe-pipe tests passed"
```

**Add to** `tests/dune`:

```lisp
(test
 (name test_maybe_pipe)
 (modules test_maybe_pipe)
 (libraries t_lang)
)
```

---

### **Phase 6: Integration Examples** (Week 2, Day 1)

**File:** `examples/error_recovery.t` (new file)

```t
-- examples/error_recovery.t
-- Demonstrates error recovery patterns with ?|>

print("=== Error Recovery with Maybe-Pipe ===")
print("")

-- Pattern 1: Provide default value on error
print("Pattern 1: Default Value Recovery")
safe_divide = \(a, b) if (b == 0) error("DivZero") else a / b
with_default = \(result) if is_error(result) 0 else result

value1 = safe_divide(10, 2) ?|> with_default
print(value1)  -- 5

value2 = safe_divide(10, 0) ?|> with_default
print(value2)  -- 0
print("")

-- Pattern 2: Error logging and recovery
print("Pattern 2: Log and Recover")
log_and_default = \(x) {
  if is_error(x) {
    print("Error occurred: ")
    print(error_message(x))
    "FALLBACK"
  } else {
    x
  }
}

read_csv("missing.csv") ?|> log_and_default |> print
print("")

-- Pattern 3: Chaining recovery handlers
print("Pattern 3: Chained Recovery")
try_parse_int = \(s) error("not implemented")  -- stub
try_parse_float = \(s) error("not implemented")  -- stub
default_zero = \(x) if is_error(x) 0 else x

result = "abc" 
  ?|> try_parse_int 
  ?|> try_parse_float 
  ?|> default_zero

print(result)  -- 0
print("")

print("=== Examples Complete ===")
```

---

### **Phase 7: Documentation Updates** (Week 2, Day 2)

**Files to Update:**

1. **`ALPHA.md`** - Add to "Frozen Syntax" section:
   ```markdown
   ### Operators
   ```t
   |>              -- Conditional pipe (short-circuits on error)
   ?|>             -- Unconditional pipe (forwards errors)
   ```
   ```

2. **`docs/language_overview.md`** - Add dedicated section on pipe semantics

3. **`examples/ci_test.t`** - Add test cases for both pipe operators

---

## Risk Assessment & Mitigation

### **Risk 1: Breaking Existing Code**
- **Likelihood:** Low
- **Impact:** None (new operator, no conflicts)
- **Mitigation:** Existing `|>` behavior unchanged

### **Risk 2: Precedence Conflicts**
- **Likelihood:** Low
- **Impact:** Medium
- **Mitigation:** Both pipes at same precedence level, left-associative

### **Risk 3: Confusion Between Operators**
- **Likelihood:** Medium
- **Impact:** Low
- **Mitigation:** Clear documentation, explicit naming, good error messages

---

## Implementation Checklist

### Week 1
- [ ] **Day 1:** Lexer token definition
- [ ] **Day 1:** AST binop extension  
- [ ] **Day 2:** Parser grammar rules
- [ ] **Day 3:** Evaluator implementation
- [ ] **Day 4-5:** Core test suite

### Week 2
- [ ] **Day 1:** Integration examples
- [ ] **Day 2:** Documentation updates
- [ ] **Day 3:** CI integration
- [ ] **Day 4:** Code review and refinement
- [ ] **Day 5:** Merge to main

---

## Success Criteria

The implementation is **complete** when:

✅ `x ?|> f` lexes and parses correctly  
✅ Errors are forwarded to functions (not short-circuited)  
✅ Normal values work with both `|>` and `?|>`  
✅ All test cases pass  
✅ CI test suite includes maybe-pipe coverage  
✅ Examples demonstrate error recovery patterns  
✅ Documentation explains semantic differences clearly  

---

## Notes for Implementers

### Critical Design Decision Already Made
The spec defines `|>` as conditional and `?|>` as unconditional. **Do not swap these semantics.** The current implementation of `|>` is correct per spec.

### Why This Matters
The maybe-pipe enables **Railway-Oriented Programming** patterns in T:
- Errors become explicit values, not exceptions
- Recovery logic is composable
- Error handling is type-safe and inspectable

### LLM Implementation Guidance
If implementing with LLM assistance:
1. Start with lexer (safest, most isolated)
2. Test each phase before proceeding
3. The evaluator change is the most critical—ensure `MaybePipe` has **no** error check
4. Use the test suite to validate behavior incrementally
