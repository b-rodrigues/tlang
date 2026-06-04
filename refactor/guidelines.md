## OCaml Code Review Checklist

### Exceptions & Error Handling
- [ ] No bare `raise` / `failwith` / `invalid_arg` in business logic — should use `Result` or `option` instead
- [ ] No `List.hd`, `List.tl`, `Array.get` without bounds/pattern guard — these raise on empty/OOB
- [ ] No `Hashtbl.find` without a `find_opt` alternative — raises `Not_found`
- [ ] `try/with` blocks are narrow and specific — not wrapping huge chunks of code
- [ ] `with _ ->` or `with e ->` (catch-all) is a red flag — should match specific exceptions
- [ ] External/IO operations handle errors explicitly, not silently swallowed

### The Type System — Are You Using It?
- [ ] No `Obj.magic` anywhere — full stop
- [ ] No `Bytes.unsafe_*` or `Array.unsafe_*` unless in a hot path with a clear justification comment
- [ ] `option` values are pattern matched, not passed around and `Option.get`'d later
- [ ] `Result` values are not ignored — check for `let _ = some_result_returning_fn`
- [ ] Variant types have exhaustive pattern matches (no wildcard `_` hiding unhandled cases)
- [ ] No `ignore` on a `Result` or `option` without an explicit comment explaining why

### Mutability
- [ ] `ref` usage is local and justified — not used as a substitute for functional patterns
- [ ] Mutable record fields (`mutable`) are minimal and documented
- [ ] No global mutable state unless it's genuinely necessary (config, caches) and clearly marked
- [ ] Loops with accumulated `ref` variables — could these be `List.fold` instead?

### Module & Abstraction Hygiene
- [ ] `.mli` files exist for all significant modules — exposed interface is intentional, not accidental
- [ ] No leaking of internal types through the public interface
- [ ] Module signatures use abstract types where appropriate (not exposing the representation)
- [ ] Functors are used for parameterization, not copy-pasted modules

### Polymorphism & Type Inference Traps
- [ ] No over-reliance on polymorphic comparison (`=`, `<`, `>`) on complex types — use `compare` from a specific module or `ppx_compare`
- [ ] No structural equality (`=`) on floats — use `Float.equal` or explicit epsilon comparison
- [ ] Value restriction surprises — if something is unexpectedly monomorphized, understand why

### Effects & Purity
- [ ] Functions that perform I/O or mutation are clearly named or documented as such
- [ ] No hidden side effects inside `lazy` values or inside what looks like a pure computation
- [ ] `Printf`/logging calls are not scattered through pure business logic

### Warnings
- [ ] Code compiles with **zero warnings** — especially:
  - Warning 8: non-exhaustive pattern match
  - Warning 26/27: unused module binding / unused `open`
  - Warning 32: unused value declaration
  - Warning 39: unused functor parameter
- [ ] `-warn-error +a` (or equivalent in `dune`) is set in CI so warnings are hard errors

### Dependencies & Unsafe FFI
- [ ] C bindings (`external`) have a clear ownership/memory model documented
- [ ] No `Gc.compact` or manual GC calls without strong justification
- [ ] Foreign function calls validate inputs before passing to C

### Style Red Flags That Hide Bugs
- [ ] No deeply nested `match` inside `match` — extract to named functions
- [ ] No excessively long functions — hard to reason about control flow
- [ ] `begin/end` blocks are not masking complex branching logic
- [ ] `fun _ ->` (ignoring an argument) is intentional, not accidental
