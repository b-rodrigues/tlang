# Review: src/packages/pipeline/pipeline_inspect2.ml

**Lines**: 749
**Severity summary**: 0 critical, 4 warning, 2 info

---

## WARNING: Catch-all exception handler in `get_project_title` — silently swallows all errors

- **Line 99**: `with _ -> None` wraps file reading (`open_in`, `really_input_string`, `in_channel_length`), TOML parsing, and `Sys.file_exists` in a single catch-all. Any exception (I/O error, parse error, permission denied, out-of-memory) silently produces `None`.

  **Fix**: Replace with specific handlers:
  - `Sys_error _ -> None` for file-not-found / permission errors
  - A specific handler for TOML parse errors
  - Let unexpected exceptions propagate (or log them) so they are not silently hidden

## WARNING: Long anonymous builtin closures — `pipeline_to_dot` and `pipeline_to_mermaid`

- **Lines 418–553** (`pipeline_to_dot`): ~135 lines inside the `VBuiltin` constructor, including two nested `emit_*_diagram` helper functions (lines 433–458 and 460–536). The `emit_subgraph_diagram` helper alone is ~76 lines.

- **Lines 582–746** (`pipeline_to_mermaid`): ~164 lines inside the `VBuiltin` constructor, with `emit_flat_diagram` (~40 lines) and `emit_subgraph_diagram` (~93 lines).

  **Fix**: Move `emit_flat_diagram` and `emit_subgraph_diagram` out of the closures into top-level functions (or module-level lets) that accept the pipeline, title, and subgraph names as parameters. This improves testability and readability.

## WARNING: `String.sub` without explicit guard (invariant-dependent)

- **Lines 498, 669, 674**: `String.sub name prefix_len (String.length name - prefix_len)` relies on `name` being longer than `prefix_len`. Guarded at line 472 (`String.length name > plen`) and 649 (`String.length name > plen`), but this is an indirect invariant — the subgraph detection logic ensures only names with the prefix are processed, but a future code change could break this.

  **Fix**: Extract into a helper `strip_prefix ~name ~prefix` that validates the prefix and returns `None` or raises a structured error on unexpected input.

## WARNING: `has_error` uses `||` on strings instead of `List.mem`

- **Lines 77, 80**: `cn.cn_class = "Error" || cn.cn_class = "VError"` — functionally correct but fragile if error class names change or new error classes are added.

  **Fix**: Consider using a helper `is_error_class s = List.mem s ["Error"; "VError"]` to centralize the class name list.

## INFO: `runtime_fill` partial function with catch-all

- **Lines 64–70**: `runtime_fill` matches on specific runtime names with a catch-all `| _ -> "#859900"`. New runtimes silently get the default green color. If a user typoes a runtime name, they get an unexpected color rather than a warning.

  **Fix**: Consider logging a warning for unrecognized runtimes, or return an `option` and let the caller decide.

## INFO: `make_id_allocator` uses mutable state

- **Lines 42–61**: The ID allocator uses two `Hashtbl.t` references captured in a closure. Each call to the returned function mutates internal state. This is a pragmatic pattern for generating unique IDs across a single render pass, but the mutation is hidden inside a seemingly-pure function signature.

  **Fix**: Document the mutability in a comment. Alternatively, thread the state explicitly by returning a new allocator + ID pair on each call.
