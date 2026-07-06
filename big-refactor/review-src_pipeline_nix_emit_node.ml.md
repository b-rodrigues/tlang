# Review: src/pipeline/nix_emit_node.ml

**Lines**: 2919
**Severity summary**: 0 critical, 5 warning, 7 info

---

## WARNING: Function far too long (emit_node is 2839 lines)

- **Line 80-2919**: The `emit_node` function spans 2839 lines, far exceeding the 80-line guideline. While some of this is embedded string literals (R/Python/Julia code injected into Nix build scripts), the surrounding OCaml logic is itself very long and should be decomposed into smaller helper functions. The function has 17+ parameters and a monolithic structure making it difficult to test, maintain, or reason about.

  **Fix**: Extract discrete phases into named helpers: (1) runtime configuration (`ext`, `extra_input`, `run_cmd`), (2) serializer/deserializer resolution (`ser_call`, `des_fn`), (3) dependency script generation (`deps_script_lines`), (4) assignment script generation (`assign_script_lines`), (5) injection blocks (`json_injection`, `csv_injection`, etc.), (6) final format string assembly.

---

## WARNING: Deeply nested conditionals in assign_script_lines

- **Line 2513-2753**: The `assign_script_lines` binding contains nesting up to 6 levels deep:

  ```
  match script with
  | Some script_path → if runtime = "sh" → else if runtime = "R" → ...
  | None → if runtime = "R" → if is_raw_code → else → ...
           else if runtime = "Python" → if is_raw_code → if raw_assigns_to → else → ...
                                        else → ...
           else if runtime = "Julia" → ...
           else if runtime = "sh" → match expr.Ast.node with ...
           else (* T *) → if is_raw_code → else → ...
  ```

  **Fix**: Extract each runtime branch (R/Python/Julia/sh/T) into its own helper function, e.g., `r_script_lines`, `py_script_lines`, etc. The raw-vs-expression distinction can be handled within each runtime helper.

---

## WARNING: Dead code — unused binding `_incs`

- **Line 210**: `let _incs = eval_string_list includes in`

  The variable `_incs` is never used after binding. The expression `eval_string_list includes` evaluates `includes` in an empty environment (which performs work but likely has no observable side effects), and the result is discarded entirely.

  ```ocaml
  let _incs = eval_string_list includes in
  ```

  **Fix**: Either remove the line entirely if the evaluation is unnecessary, or replace with `let _ = eval_string_list includes in` with a comment explaining why the expressions must be evaluated even though the result is unused.

---

## WARNING: Dead code — unused binding `_python_was_auto_returned`

- **Line 2447**: `let expr_s_no_imports, _python_was_auto_returned =`

  The second element of the tuple `_python_was_auto_returned` is bound but never referenced. It indicates whether the Python auto-return transformation was applied, but this information is discarded.

  ```ocaml
  let expr_s_no_imports, _python_was_auto_returned =
  ```

  **Fix**: Either remove it from the tuple return, or if the information is needed, propagate it (the caller at line 2513 passes `expr_s_no_imports` only).

---

## WARNING: Mutable accumulator in build_t_assignments

- **Line 2228-2233**: `build_t_assignments` uses a mutable `ref` cell as an accumulator for building a tree structure, rather than using `List.fold_left` or a recursive approach:

  ```ocaml
  let root = ref (Node []) in
  List.iter (fun d ->
    let safe_var = "__dep_" ^ sanitize_env_var_suffix d in
    let parts = String.split_on_char '.' d in
    root := insert !root parts safe_var
  ) deps;
  ```

  **Fix**: Use `List.fold_left` to thread the tree state through iterations:

  ```ocaml
  let root = List.fold_left (fun root d ->
    let safe_var = "__dep_" ^ sanitize_env_var_suffix d in
    let parts = String.split_on_char '.' d in
    insert root parts safe_var
  ) (Node []) deps in
  ```

---

## INFO: Misleading NA pattern — `VNA NAGeneric` instead of `VNA _`

- **Line 221**: The `env_value_to_string` function matches NA values with:

  ```ocaml
  | Ast.(VNA NAGeneric) -> None
  ```

  The `Ast.(...)` local open is redundant because `open Ast` is already in scope (line 1). More importantly, `VNA NAGeneric` matches only one of the seven NA subtypes (`NAGeneric`). The catch-all `_ -> None` on the next line correctly handles `NABool`, `NAInt`, `NAFloat`, `NAString`, `NADate`, and `NADatetime`, so the behavior is correct — but the pattern is misleading. It suggests that only `NAGeneric` merits explicit handling, when in fact all NA subtypes should map to `None`.

  **Fix**: Replace with `VNA _ -> None` and remove the redundant `Ast.(...)`:

  ```ocaml
  | VNA _ -> None
  ```

---

## INFO: Duplicate `eval_expr_safe` definitions

- **Lines 62, 67-68, 144**: The helper `eval_expr_safe` is defined three times with identical bodies:

  - Line 62 (inside `is_ser`): `let eval_expr_safe e = Eval.eval_expr (ref Ast.Env.empty) e in`
  - Line 67 (inside `is_des`): implicitly redefined in the same pattern
  - Line 144 (inside `emit_node`): `let eval_expr_safe e = Eval.eval_expr (ref Ast.Env.empty) e in`

  **Fix**: Extract to a single top-level helper function `eval_in_empty_env` or similar, then reuse.

---

## INFO: `match` on `deserializer.Ast.node` uses catch-all that silently passes through unexpected node types

- **Line 2106-2112**: The `strategy_expr` matching handles `ListLit`, `DictLit`, and `Value (VDict ...)` explicitly, with `_ -> deserializer` as catch-all. If a new `expr_node` constructor is added (e.g., `ShellExpr`, `PipelineDef`, `BroadcastOp`), it would silently fall through to the default rather than produce an error.

  ```ocaml
  match deserializer.Ast.node with
  | Ast.ListLit items -> ...
  | Ast.DictLit items -> ...
  | Ast.Value (Ast.VDict items) -> ...
  | _ -> deserializer
  ```

  **Fix**: Either document that this is intentional, or add exhaustive patterns for all expected AST node types so that new constructors produce a compile-time warning/error.

---

## INFO: `List.mem` on potentially large lists (O(n²) risk)

- **Line 83**: `List.filter (fun d -> List.mem d all_pipeline_node_names) deps` — O(n × m) string comparison.
- **Line 337**: `List.mem key reserved_keys` — O(k) per key, where `reserved_keys` has 6 elements (acceptable).
- **Line 2434**: `List.mem last ['+'; '-'; '*'; '/'; '%'; '&'; '|'; '^'; '<'; '>'; ':']` — O(13) per character (acceptable), but a match expression or set would be more idiomatic.

  **Fix (line 83)**: Convert `all_pipeline_node_names` to a `String_set` (defined in `Ast`) or `Hashtbl` for O(1) lookups when the node count is large. For lines 337 and 2434, replace with pattern match expressions for clarity.

---

## INFO: Inconsistent error message capitalization in generated code

- **Lines 2561, 2564, 2790**: Emitted error messages use different capitalization styles:

  ```
  Line 2561: "Serialization failed:"         (Sentence case)
  Line 2564: "Class write failed:"           (Sentence case)
  Line 2790: "ERROR: .quarto-output not found."  (Uppercase "ERROR")
  ```

  **Fix**: Normalize to consistent style, e.g., `"error: ..."` or `"Error: ..."`.

---

## INFO: String equality uses `=` instead of `String.equal`

- **Multiple lines** (64, 149, 255, etc.): String comparisons use OCaml's polymorphic `=` operator. While this works correctly for strings (structural comparison), the codebase convention in some packages prefers `String.equal` for explicitness.

  ```ocaml
  (* Line 64 *)
  match get_format ser_val with Some sf -> sf = f | None -> false
  (* Line 255 *)
  List.exists (fun arg -> arg = "-c" || arg = "-lc" || arg = "-cl") args
  ```

  **Fix**: Replace `s1 = s2` with `String.equal s1 s2` for string comparisons, consistent with OCaml best practices and the rest of the codebase.

---

## INFO: `lookup_in_list` does not document `None`-keyed item behavior

- **Lines 2095-2099**: The `lookup_in_list` function only matches on `(Some n, e) :: _` entries, silently skipping `(None, e)` entries without explanation:

  ```ocaml
  let rec lookup_in_list target = function
    | [] -> None
    | (Some n, e) :: _ when n = target -> Some e
    | _ :: rest -> lookup_in_list target rest
  ```

  The corresponding `lookup_in_dict` (line 2100-2103) doesn't have this issue because `DictLit` entries are always `(string * expr)`. This asymmetry is undocumented and could confuse maintainers.

  **Fix**: Add a comment explaining that deserializer entries with `None` names are deliberately skipped (or handle them explicitly).
