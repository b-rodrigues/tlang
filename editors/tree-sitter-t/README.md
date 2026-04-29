# tree-sitter-t

Tree-sitter grammar for the T programming language.

## Included assets

- `grammar.js` for generating the parser
- `queries/highlights.scm` for syntax highlighting
- `queries/injections.scm` for shell/R/Python block injection in editor integrations
- `queries/locals.scm` for local-variable scopes
- `test/corpus/` for grammar tests

Generated artifacts such as `src/parser.c`, `src/grammar.json`,
`src/node-types.json`, and `src/tree_sitter/` are intentionally not committed.
Generate them locally when your editor or tooling needs them.

## Install prerequisites

You need Node.js and the tree-sitter CLI. The easiest way to avoid a global
install is to use `npx`:

```bash
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli generate
```

If you prefer a global install:

```bash
npm install --global tree-sitter-cli
cd /absolute/path/to/tlang/editors/tree-sitter-t
tree-sitter generate
```

## Generate the parser

```bash
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli generate
```

This creates the local generated files under `src/`. They remain untracked
because only the source grammar is versioned.

## Test the grammar

```bash
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli test
```

## Editor integrations

This package is intended for tree-sitter based editors such as Neovim, Emacs 29+, Helix, and Zed.
See `../README.md` and `../../docs/editors.md` for setup notes.
