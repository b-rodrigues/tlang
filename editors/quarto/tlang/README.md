# Quarto support for `t` code blocks

This folder contains a small Quarto filter extension that makes fenced `t` code blocks executable in Quarto documents.

## What it does

- lets you write `{t}` chunks in `.qmd` files
- runs those chunks through the existing `t` CLI
- replays earlier `t` chunks in document order so later chunks can reuse earlier definitions
- respects common chunk controls written as leading `#|` options:
  - `#| eval: false`
  - `#| echo: false`
  - `#| output: false`
  - `#| include: false`
  - `#| results: hide`

This is intentionally minimal. It is meant for literate programming and console-style output, not rich widgets or plots.

## Install into a Quarto project

From your Quarto project root:

```bash
mkdir -p _extensions/tlang
cp -R /path/to/tlang/editors/quarto/tlang/_extensions/tlang/* _extensions/tlang/
```

Make sure the `t` executable is available on your `PATH` when Quarto renders the document. If you need a specific binary, set `TLANG_BIN` before rendering:

```bash
export TLANG_BIN=/path/to/t
quarto render report.qmd
```

## Use in a document

Enable the filter in the document front matter:

```yaml
---
title: "T in Quarto"
filters:
  - tlang
---
```

Then write normal `t` chunks:

````qmd
```{t}
x = 41
```

```{t}
x + 1
```
````

## Notes

- Chunks are executed by replaying all earlier `t` chunks plus the current chunk with `t --mode strict --unsafe run`.
- Because T normally requires a pipeline for non-interactive scripts, the extension uses `--unsafe` so prose-first Quarto documents can still run exploratory chunks.
- Chunk output is rendered as plain text.
