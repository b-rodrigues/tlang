# Code Review — `b86f2b87`

**`fix: use Mermaid YAML frontmatter for visible title rendering`**

Two files touched: `show_plot.ml` and `pipeline_inspect2.ml`.

---

## ✅ What's good

**`pipeline_inspect2.ml`** — the fix is correct. The previous `%% title: …` comment is a Mermaid comment, not a visible title. YAML frontmatter (`---\ntitle: …\n---\n` before `graph LR`) is the proper Mermaid spec for a rendered title. Emitting frontmatter only when `title = Some t` and otherwise leaving it out is the right behaviour.

**`is_mermaid_string`** — adding `---` and `%%` as valid prefixes is necessary now that Mermaid output can lead with frontmatter or a comment before `graph`. Without this, `show_plot` would have failed to detect it as Mermaid. ✓

**`extract_mermaid_title`** — the logic is correct: checks for `---` prefix, strips it, reads the first line, checks for `title:`. The `| exception Not_found ->` arm handles the degenerate case of a single-line frontmatter with no trailing newline. That's good defensive coding.

**`render_mermaid_html ~title`** — labelled argument is idiomatic OCaml for an optional-in-spirit parameter. The fallback `"T-Lang Pipeline Dependency Graph"` keeps old behaviour for non-pipeline Mermaid strings. ✓

---

## ⚠️ Issues

**1. Minor: `extract_mermaid_title` uses `String.sub s 0 3 <> "---"` instead of `String.starts_with`**

The rest of `show_plot.ml` consistently uses `String.starts_with ~prefix:`. This one line is inconsistent:
```ocaml
if String.length s < 3 || String.sub s 0 3 <> "---" then None
```
Should be:
```ocaml
if not (String.starts_with ~prefix:"---" s) then None
```
Cleaner and removes the manual length guard.

**2. Minor: `extract_mermaid_title` only reads the first line after `---`, not the full frontmatter block**

The function reads exactly one line after stripping the opening `---`, and checks if that line is `title: …`. This means:
```
---
author: Bruno
title: My Graph
---
```
…would return `None` because the first line is `author:`, not `title:`. For now the emitter always puts `title` on the first line, so it works in practice — but the parser is fragile against any future change to frontmatter field order. A note or comment explaining this assumption would help.

**3. Trivial: title text is not HTML-escaped in `render_mermaid_html`**

```ocaml
let html_content = render_mermaid_html ~title mermaid_str in
```
`title` is interpolated directly into `<h1>%s</h1>`. If a user passes `title = "A & B"` or `title = "<script>alert(1)</script>"`, the HTML is malformed or injectable. Since this only opens a local file in the browser and isn't a web service, the risk is low — but worth a comment acknowledging it, or a simple escape for `<`, `>`, `&`.

---

## Summary

| Item | Severity |
|---|---|
| `String.sub s 0 3 <> "---"` — inconsistent with rest of file | Minor |
| `extract_mermaid_title` only checks first frontmatter line | Minor |
| Title not HTML-escaped in `<h1>` | Trivial |

The core fix is correct and complete. The YAML frontmatter approach is the right Mermaid spec, `is_mermaid_string` is correctly updated, and the `~title` label propagation through `render_and_open_mermaid` is clean.
