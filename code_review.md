
---

## Review of REPL Variable Watcher & Atelier TUI Diagram/Plot Integration

This review covers the latest commits in `tlang` (`62d19640`, `62aae502`, `9c5cce5d`) and the local unstaged/staged additions in `atelier` that implement Ratatui 0.30 integration, the async Diagram renderer, and the directory-watching Plot viewer.

### ⚠️ Issues & Suggestions (Status: All Resolved ✅)

| # | Severity | Description | Status |
|---|---|---|---|
| 1 | 🔴 High | Race Condition / Partial Reads of Variable CSV | ✅ Resolved (atomic temp-file write & rename) |
| 2 | ⚠️ Medium | Fragile Manual CSV Parsing | ✅ Resolved (escapes newlines in OCaml) |
| 3 | ⚠️ Medium | Main-Thread Image Decoding and File IO blocking TUI | ✅ Resolved (asynchronous decoding in background threads) |
| 4 | 🟡 Low | Thread Accumulation in Diagram Renderer | ✅ Resolved (throttling & pending render queue) |
| 5 | 🟡 Low | Syscall Overhead in Render Loop | ✅ Resolved (rate-limited checks to 300ms/500ms) |

---

### Verification Details

#### 1. Race Condition / Partial Reads of Variable CSV ✅
In `tlang/src/repl.ml`, the environment variables are now written to `tmp_path` first, then atomically renamed:
```ocaml
let tmp_path = "/tmp/atelier-vars.csv.tmp" in
let final_path = "/tmp/atelier-vars.csv" in
...
close_out oc;
Sys.rename tmp_path final_path
```
This guarantees that the TUI never reads a partially written/truncated file.

#### 2. Fragile Manual CSV Parsing ✅
In `tlang/src/repl.ml`, values containing newlines are pre-processed to escape newlines before writing:
```ocaml
let escape s =
  let s = String.concat "\\n" (String.split_on_char '\n' s) in
  let escaped = String.concat "\"\"" (String.split_on_char '"' s) in
  "\"" ^ escaped ^ "\""
```
This prevents newline-delimited value representations from breaking the line parser in `atelier/src/pane/vars.rs`.

#### 3. Main-Thread Image Decoding and File IO ✅
* **DiagramPane**: Image loading/decoding has been offloaded to the background thread spawned in `src/renderer.rs`. The channel returns a `RenderState::DoneDecoded(DynamicImage)`, so the UI thread only performs the rapid protocol generation (`self.picker.new_resize_protocol(dyn_img)`).
* **PlotPane**: Employs `load_image_async` to offload image reading and decoding to a background worker thread. When the image is loaded, it sends `LoadResult::Loaded(dyn_img)` back to the UI thread.

#### 4. Thread Accumulation in Diagram Renderer ✅
In `DiagramPane::check_updates()`, if a render is already in progress, the pane flags `self.pending_render = true` and defers spawning the new render thread until the current one completes:
```rust
if self.render_in_progress {
    self.pending_render = true;
    return;
}
```
This guarantees at most one rendering thread is active at any time.

#### 5. Syscall Overhead in Render Loop ✅
* **DiagramPane**: File metadata check rate-limited to 300ms using `self.last_check_time.elapsed() < Duration::from_millis(300)`.
* **PlotPane**: Scan rate-limited to 500ms using `self.last_scan_time.elapsed() < Duration::from_millis(500)`.

---

## Verdict
All recommended fixes have been implemented successfully in both repositories. Both `tlang` and `atelier` compile and build cleanly in their respective Nix/development environments.

---

## Review of commit `5a617e5` (feat: lazy LLM spawn with path prompt, no restart on context change)

This commit transitions the LLM pane (`LlmPane`) to utilize lazy spawning with an interactive project path input prompt on startup, and prevents restarting the LLM/opencode PTY process when the active context changes.

### ✅ What's Good

* **State Machine for Lazy Spawning**: The addition of `LlmState::AwaitingPath` is a clean way to model the interactive setup phase before the PTY is spawned.
* **Persistent LLM Session (No Process Re-spawning)**: In `push_context_inner`, the code no longer calls `self.spawn_or_refresh(ctx.hash)`. Instead, it updates the context markdown file and writes the new context directly to the running process's stdin (in `"stdin"` context mode). This keeps the session alive, preserving shell history, scrollback, and process state.
* **Fallback Repository Directory**: Properly defaults to the current working directory of the shell (`std::env::current_dir()`) if no repository path is provided via CLI argument.
* **Character Input Sanitization**: Standard Unix path characters are correctly validated before being appended to the input buffer, preventing terminal control code injections.

### ⚠️ Minor Suggestions (Status: Resolved / Noted)

* **Cursor indicator in Path prompt**: ✅ Resolved. A blinking block cursor (`▊`) has been added to the end of the path input field to provide visual typing feedback.
* **`stdin` Context Mode with Interactive Shells**: (Noted) Writing large context buffers directly to PTY stdin while an interactive shell is running could pollute the shell prompt or execute unintended commands if the shell is not actively blocking on a read. This is mitigated because it is a user-configurable option (`context_mode = "stdin"`), but users should be aware.

