# tree-sitter-t

Tree-sitter grammar for the T programming language.

## Included assets

- `grammar.js` for generating the parser
- `queries/highlights.scm` for syntax highlighting
- `queries/injections.scm` for shell/R/Python block injection in editor integrations
- `queries/locals.scm` for local-variable scopes

## Generate the parser

```bash
cd editors/tree-sitter-t
npx tree-sitter-cli generate
```

## Test the grammar

```bash
cd editors/tree-sitter-t
npx tree-sitter-cli test
```

## Editor integrations

This package is intended for tree-sitter based editors such as Neovim, Emacs 29+, Helix, and Zed.
See `../README.md` and `../../docs/editors.md` for setup notes.
