# T Language Codebase Refactoring Implementation Guide

## Current State Analysis

### Problem Overview
After scanning your codebase, I've identified the following issues:

1. **Monolithic `src/eval.ml`** (~1000+ lines)
   - Lines 1-600: Core evaluation logic
   - Lines 600-1000+: ALL builtin function implementations in one massive `builtins` list
   - Contains functions from: core, math, stats, colcraft, pipeline, Phase 1-6 features

2. **Hollow Package Files**
   - `packages/math/*.t` - Only documentation comments
   - `packages/stats/*.t` - Only documentation comments
   - `packages/colcraft/*.ml` - Mix of comments and some implementation
   - `packages/core/` - Referenced but minimal files present

3. **Monolithic Test File**
   - `tests/test_runner.ml` (~600+ lines)
   - All tests for all phases in one file
   - Difficult to run targeted test suites

## Target Architecture

```
src/
├── ast.ml                    # Keep as-is
├── lexer.mll                 # Keep as-is
├── parser.mly                # Keep as-is
├── eval.ml                   # SLIM DOWN - only core evaluation + env loading
└── packages/
    ├── loader.ml             # NEW - Package loading system
    ├── core/
    │   ├── dune              # NEW - Build config
    │   ├── print.ml          # MOVE from eval.ml builtins
    │   ├── type.ml           # MOVE from eval.ml builtins
    │   ├── length.ml         # MOVE from eval.ml builtins
    │   ├── head.ml           # MOVE from eval.ml builtins
    │   ├── tail.ml           # MOVE from eval.ml builtins
    │   ├── is_error.ml       # MOVE from eval.ml builtins
    │   ├── seq.ml            # MOVE from eval.ml builtins
    │   ├── map.ml            # MOVE from eval.ml builtins
    │   └── sum.ml            # MOVE from eval.ml builtins
    ├── base/               # NEW - Organize by phase
    │   ├── dune
    │   ├── assert.ml         # MOVE enhanced assert
    │   ├── is_na.ml          # MOVE
    │   ├── na.ml             # MOVE all na_* constructors
    │   ├── error.ml          # MOVE error construction
    │   └── error_utils.ml    # MOVE error_code, error_message, error_context
    ├── dataframe/               # NEW - Tabular/CSV
    │   ├── dune
    │   ├── read_csv.ml       # MOVE from eval.ml
    │   ├── colnames.ml       # MOVE
    │   ├── nrow.ml           # MOVE
    │   └── ncol.ml           # MOVE
    ├── pipeline/               # NEW - Pipeline introspection
    │   ├── dune
    │   ├── pipeline_nodes.ml # MOVE
    │   ├── pipeline_deps.ml  # MOVE
    │   ├── pipeline_node.ml  # MOVE
    │   └── pipeline_run.ml   # MOVE
    ├── math/
    │   ├── dune              # NEW
    │   ├── sqrt.ml           # MOVE from eval.ml (currently ~20 lines)
    │   ├── abs.ml            # MOVE from eval.ml
    │   ├── log.ml            # MOVE from eval.ml
    │   ├── exp.ml            # MOVE from eval.ml
    │   └── pow.ml            # MOVE from eval.ml
    ├── stats/
    │   ├── dune              # NEW
    │   ├── mean.ml           # MOVE from eval.ml (currently ~40 lines)
    │   ├── sd.ml             # MOVE from eval.ml
    │   ├── quantile.ml       # MOVE from eval.ml
    │   ├── cor.ml            # MOVE from eval.ml
    │   └── lm.ml             # MOVE from eval.ml (currently ~100 lines)
    ├── colcraft/
    │   ├── dune              # NEW
    │   ├── select.ml         # MOVE from eval.ml (currently ~20 lines)
    │   ├── filter.ml         # MOVE from eval.ml (currently ~30 lines)
    │   ├── mutate.ml         # MOVE from eval.ml (currently ~30 lines)
    │   ├── arrange.ml        # MOVE from eval.ml (currently ~40 lines)
    │   ├── group_by.ml       # MOVE from eval.ml (currently ~15 lines)
    │   └── summarize.ml      # MOVE from eval.ml (currently ~100 lines)
    └── explain/               # NEW - Intent & explain
        ├── dune
        ├── intent_fields.ml  # MOVE
        ├── intent_get.ml     # MOVE
        ├── explain.ml        # MOVE (~100 lines)
        └── explain_json.ml   # MOVE

tests/
├── dune                      # UPDATE
├── test_runner.ml            # SLIM DOWN - just test discovery/reporting
├── core/
│   ├── test_arithmetic.ml    # EXTRACT from test_runner.ml
│   ├── test_comparisons.ml   # EXTRACT
│   ├── test_logical.ml       # EXTRACT
│   ├── test_variables.ml     # EXTRACT
│   ├── test_functions.ml     # EXTRACT
│   ├── test_pipe.ml          # EXTRACT
│   ├── test_ifelse.ml        # EXTRACT
│   ├── test_lists.ml         # EXTRACT
│   ├── test_dicts.ml         # EXTRACT
│   └── test_builtins.ml      # EXTRACT
├── base/
│   ├── test_na_values.ml     # EXTRACT
│   ├── test_no_propagation.ml
│   ├── test_structured_errors.ml
│   └── test_enhanced_assert.ml
├── dataframe/
│   ├── test_read_csv.ml
│   ├── test_dataframe_meta.ml
│   └── test_column_access.ml
├── pipeline/
│   ├── test_basic_pipeline.ml
│   ├── test_pipeline_deps.ml
│   └── test_pipeline_cache.ml
├── colcraft/
│   ├── test_select.ml
│   ├── test_filter.ml
│   ├── test_mutate.ml
│   ├── test_arrange.ml
│   ├── test_group_by.ml
│   └── test_summarize.ml
├── math/
│   ├── test_math_funcs.ml
│   └── test_stats_funcs.ml
└── explain/
    ├── test_intent_blocks.ml
    └── test_explain.ml
```

## Implementation Steps

### Phase 1: Set Up Package Infrastructure

**File: `src/packages/loader.ml`** (NEW)
```ocaml
(* This module will register and load all packages *)
open Ast

(* Registry of all available packages *)
let package_registry : (string * (environment -> environment)) list ref = ref []

(* Register a package loader *)
let register_package name loader =
  package_registry := (name, loader) :: !package_registry

(* Load all registered packages into environment *)
let load_all_packages env =
  List.fold_left
    (fun current_env (name, loader) ->
      loader current_env)
    env
    !package_registry
```

**Create dune files for each package directory:**
```
(library
 (name t_package_math)
 (wrapped false)
 (modules sqrt abs log exp pow)
 (libraries t_lang))
```

### Phase 2: Extract Functions from `src/eval.ml`

For each function in the `builtins` list (starting around line 600), you need to:

#### Example Migration: `sqrt` function

**CURRENT LOCATION:** `src/eval.ml` lines ~920-945
```ocaml
("sqrt", make_builtin 1 (fun args _env ->
  match args with
  | [VInt n] -> ...
  | [VFloat f] -> ...
  (* ... rest of implementation ... *)
));
```

**NEW LOCATION:** `src/packages/math/sqrt.ml`
```ocaml
open Ast

let sqrt_impl args _env =
  match args with
  | [VInt n] ->
      if n < 0 then make_error ValueError "sqrt() is undefined for negative numbers"
      else VFloat (Float.sqrt (float_of_int n))
  | [VFloat f] ->
      if f < 0.0 then make_error ValueError "sqrt() is undefined for negative numbers"
      else VFloat (Float.sqrt f)
  | [VVector arr] ->
      (* ... vector implementation ... *)
  | [VNA _] -> make_error TypeError "sqrt() encountered NA value..."
  | [_] -> make_error TypeError "sqrt() expects a number or numeric Vector"
  | _ -> make_error ArityError "sqrt() takes exactly 1 argument"

(* Registration function called by loader *)
let register env =
  Ast.Env.add "sqrt" 
    (VBuiltin { b_arity = 1; b_variadic = false; b_func = sqrt_impl })
    env
```

### Phase 3: Function Location Map

Here's EXACTLY where each function should move:

#### From `src/eval.ml` builtins list → New locations:

**Lines 601-610: print** → `src/packages/core/print.ml`  
**Lines 611-615: type** → `src/packages/core/type.ml`  
**Lines 616-625: length** → `src/packages/core/length.ml`  
**Lines 644-650: assert** → `src/packages/base/assert.ml`  
**Lines 652-657: head** → `src/packages/core/head.ml`  
**Lines 658-663: tail** → `src/packages/core/tail.ml`  
**Lines 664-668: is_error** → `src/packages/core/is_error.ml`  
**Lines 669-673: seq** → `src/packages/core/seq.ml`  
**Lines 674-681: map** → `src/packages/core/map.ml`  
**Lines 682-700: sum** → `src/packages/core/sum.ml`  

**Lines 704-707: is_na** → `src/packages/base/is_na.ml`  
**Lines 708: na** → `src/packages/base/na.ml`  
**Lines 709-712: na_bool, na_int, na_float, na_string** → `src/packages/base/na.ml` (same file)  

**Lines 716-728: error** → `src/packages/base/error.ml`  
**Lines 729-733: error_code** → `src/packages/base/error_utils.ml`  
**Lines 734-738: error_message** → `src/packages/base/error_utils.ml`  
**Lines 739-744: error_context** → `src/packages/base/error_utils.ml`  

**Lines 750-760: read_csv** → `src/packages/dataframe/read_csv.ml`  
**Lines 762-768: colnames** → `src/packages/dataframe/colnames.ml`  
**Lines 770-776: nrow** → `src/packages/dataframe/nrow.ml`  
**Lines 778-784: ncol** → `src/packages/dataframe/ncol.ml`  

**Lines 790-795: pipeline_nodes** → `src/packages/pipeline/pipeline_nodes.ml`  
**Lines 797-803: pipeline_deps** → `src/packages/pipeline/pipeline_deps.ml`  
**Lines 805-813: pipeline_node** → `src/packages/pipeline/pipeline_node.ml`  
**Lines 815-820: pipeline_run** → `src/packages/pipeline/pipeline_run.ml`  

**Lines 826-850: select** → `src/packages/colcraft/select.ml`  
**Lines 853-890: filter** → `src/packages/colcraft/filter.ml`  
**Lines 893-925: mutate** → `src/packages/colcraft/mutate.ml`  
**Lines 928-970: arrange** → `src/packages/colcraft/arrange.ml`  
**Lines 973-990: group_by** → `src/packages/colcraft/group_by.ml`  
**Lines 994-1100: summarize** → `src/packages/colcraft/summarize.ml`  

**Lines 920-945: sqrt** → `src/packages/math/sqrt.ml`  
**Lines 948-970: abs** → `src/packages/math/abs.ml`  
**Lines 973-1000: log** → `src/packages/math/log.ml`  
**Lines 1003-1025: exp** → `src/packages/math/exp.ml`  
**Lines 1028-1055: pow** → `src/packages/math/pow.ml`  

**Lines 1108-1135: mean** → `src/packages/stats/mean.ml`  
**Lines 1138-1165: sd** → `src/packages/stats/sd.ml`  
**Lines 1168-1200: quantile** → `src/packages/stats/quantile.ml`  
**Lines 1203-1245: cor** → `src/packages/stats/cor.ml`  
**Lines 1248-1310: lm** → `src/packages/stats/lm.ml`  

**Lines 1315-1325: intent_fields** → `src/packages/explain/intent_fields.ml`  
**Lines 1328-1337: intent_get** → `src/packages/explain/intent_get.ml`  
**Lines 1340-1465: explain** → `src/packages/explain/explain.ml`  
**Lines 1468-1480: explain_json** → `src/packages/explain/explain_json.ml`  

### Phase 4: Update `src/eval.ml`

**Remove:** Entire `builtins` list (lines ~600-1500)

**Keep:** 
- Helper functions: `make_builtin`, `make_error`, `is_error_value`, `is_na_value`, `parse_csv_*`, `extract_nums_arr`
- Core evaluation functions: `eval_expr`, `eval_binop`, `eval_unop`, etc.

**Add at end:**
```ocaml
let initial_env () : environment =
  (* Load all packages *)
  Loader.load_all_packages Env.empty
```

### Phase 5: Create Package Registration

**Each package directory needs an `init.ml` file:**

Example: `src/packages/math/init.ml`
```ocaml
(* Register all math package functions *)
let register_package env =
  env
  |> Sqrt.register
  |> Abs.register
  |> Log.register
  |> Exp.register
  |> Pow.register

(* Auto-register with loader *)
let () = Loader.register_package "math" register_package
```

### Phase 6: Split Test File

The test file `tests/test_runner.ml` has clear sections marked by comments. Extract each section:

**Current Structure (line numbers):**
- Lines 25-60: Arithmetic tests → `tests/core/test_arithmetic.ml`
- Lines 62-75: Comparisons → `tests/core/test_comparisons.ml`
- Lines 77-85: Logical → `tests/core/test_logical.ml`
- Lines 87-95: Variables → `tests/core/test_variables.ml`
- Lines 97-110: Functions → `tests/core/test_functions.ml`
- Lines 112-125: Pipe → `tests/core/test_pipe.ml`
- Lines 127-132: If/Else → `tests/core/test_ifelse.ml`
- Lines 134-145: Lists → `tests/core/test_lists.ml`
- Lines 147-155: Dicts → `tests/core/test_dicts.ml`
- Lines 157-170: Builtins → `tests/core/test_builtins.ml`
- Lines 175-200: Phase 1 NA Values → `tests/base/test_na_values.ml`
- Lines 202-215: Phase 1 No Propagation → `tests/base/test_no_propagation.ml`
- Lines 220-245: Phase 1 Structured Errors → `tests/base/test_structured_errors.ml`
- Lines 247-260: Phase 1 Enhanced Assert → `tests/base/test_enhanced_assert.ml`
- Lines 270-340: Phase 2 tests → Split into `tests/dataframe/test_*.ml`
- Lines 345-430: Phase 3 tests → Split into `tests/pipeline/test_*.ml`
- Lines 435-550: Phase 4 tests → Split into `tests/phase4/test_*.ml`
- Lines 555-620: Phase 5 tests → Split into `tests/phase5/test_*.ml`
- Lines 625-700: Phase 6 tests → Split into `tests/explain/test_*.ml`

**New test file structure:** Each test file should export a `run_tests` function:
```ocaml
(* tests/core/test_arithmetic.ml *)
let run_tests pass_count fail_count =
  Printf.printf "Arithmetic:\n";
  test "integer addition" "1 + 2" "3" pass_count fail_count;
  test "integer subtraction" "10 - 3" "7" pass_count fail_count;
  (* ... etc ... *)
  print_newline ()
```

**New `tests/test_runner.ml`:**
```ocaml
let () =
  let pass_count = ref 0 in
  let fail_count = ref 0 in
  
  Test_arithmetic.run_tests pass_count fail_count;
  Test_comparisons.run_tests pass_count fail_count;
  (* ... call all test modules ... *)
  
  (* Print summary *)
  let total = !pass_count + !fail_count in
  Printf.printf "=== Results: %d/%d passed ===\n" !pass_count total;
  if !fail_count > 0 then exit 1
```

## Migration Checklist

For each function migration:

1. ☐ Copy implementation from `src/eval.ml` builtins list
2. ☐ Create new `.ml` file in appropriate package directory
3. ☐ Wrap in module with `register` function
4. ☐ Update package's `init.ml` to call registration
5. ☐ Update package's `dune` file to include module
6. ☐ Remove from `src/eval.ml` builtins list
7. ☐ Test that function still works
8. ☐ Delete corresponding `.t` comment file in `packages/`

## Testing Strategy

After each package migration:
```bash
dune build
dune exec src/repl.exe  # Verify function is available
dune test               # Run all tests
```

## Build System Updates

**Root `dune` file needs:**
```
(dirs src tests packages)
```

**Update `src/dune`:**
```ocaml
(library
 (name t_lang)
 (wrapped false)
 (modules ast lexer parser eval)
 (libraries menhirLib))

(library
 (name t_packages)
 (wrapped false)
 (modules_without_implementation loader)
 (libraries t_lang t_package_core t_package_math t_package_stats 
            t_package_colcraft t_package_base t_package_dataframe 
            t_package_pipeline t_package_explain))
```

## Estimated Effort

- **Package infrastructure:** 2-3 hours
- **Core functions migration:** 4-6 hours
- **Phase 1-6 functions migration:** 8-10 hours  
- **Math package migration:** 2-3 hours
- **Stats package migration:** 4-5 hours
- **Colcraft package migration:** 5-6 hours
- **Test splitting:** 6-8 hours
- **Testing and debugging:** 4-6 hours

**Total: 35-50 hours** for complete refactoring

## Benefits After Refactoring

1. **Maintainability:** Each function in its own file (~20-50 lines each)
2. **Discoverability:** Clear package structure matches documentation
3. **Testing:** Targeted test suites, faster feedback
4. **Extensibility:** Easy to add new packages/functions
5. **Documentation:** Function files can have detailed comments
6. **Collaboration:** Multiple engineers can work on different packages simultaneously

## Next Steps

1. Start with `src/packages/loader.ml` and infrastructure
2. Migrate one small package completely (e.g., `core`) as proof of concept
3. Test thoroughly before continuing
4. Migrate remaining packages in order of Phase (1→2→3→4→5→6)
5. Split tests after functions are migrated
6. Final integration testing
