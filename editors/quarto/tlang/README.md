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

In a T project, declare Quarto in `tproject.toml`:

```toml
[additional-tools]
packages = ["quarto"]
```

Then sync the flake and enter the project shell from the project root:

```bash
t update
nix develop
```

When `quarto` is requested as an additional tool, T auto-provisions `_extensions/tlang` from the Nix store as you enter the project shell, so Quarto can resolve the `tlang` filter without running `quarto add`.

Make sure the `t` executable is available on your `PATH` when Quarto renders the document. If you need a specific binary, set `TLANG_BIN` before rendering:

```bash
export TLANG_BIN=/path/to/t
quarto render report.qmd
```

> [!WARNING]
> This extension executes T chunks with `t --mode strict --unsafe run`.
> `--unsafe` disables T's normal requirement that non-interactive scripts must contain `build_pipeline()` or `populate_pipeline()` calls.
> Use this only for trusted Quarto documents. Every `{t}` chunk is executed during render and can run whatever T code the document contains, including code that reads or writes local files through the surrounding project. Do not render untrusted `.qmd` files with this extension.

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
- Because T normally requires a pipeline for non-interactive scripts, the extension uses `--unsafe` to allow Quarto chunks that are not wrapped in `build_pipeline()` or `populate_pipeline()` calls.
- Chunk output is rendered as plain text.
