# Editor Support for T

This directory contains syntax highlighting and language support for the T programming language in various editors.

## Tree-sitter

The repository now ships a shared tree-sitter grammar in `tree-sitter-t/`.
It is intended for tree-sitter based editor integrations such as Neovim,
Emacs 29+, Helix, Zed, and Vim setups that use a tree-sitter plugin layer.
Only the source grammar and query files are committed; generated parser outputs
are intentionally left for local generation to keep the repository diff small
and reviewable.

### Included files

- `tree-sitter-t/grammar.js` — source grammar
- `tree-sitter-t/tree-sitter.json` — tree-sitter language metadata
- `tree-sitter-t/queries/highlights.scm` — shared highlight queries
- `tree-sitter-t/queries/injections.scm` — shell/R/Python block injections
- `tree-sitter-t/queries/locals.scm` — local-scope queries
- `tree-sitter-t/test/corpus/` — grammar tests

### Installing the tree-sitter CLI

Use either a one-off `npx` invocation:

```bash
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli generate
```

Or install the CLI globally:

```bash
npm install --global tree-sitter-cli
cd /absolute/path/to/tlang/editors/tree-sitter-t
tree-sitter generate
```

### Generating the local parser files

```bash
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli generate
npx tree-sitter-cli test
```

This creates `src/parser.c`, `src/grammar.json`, `src/node-types.json`, and
`src/tree_sitter/` locally. Those generated files are ignored by Git and do not
need to be committed.

## Vim

1. Copy `vim/ftdetect/t.vim` to `~/.vim/ftdetect/t.vim`.
2. Copy `vim/syntax/t.vim` to `~/.vim/syntax/t.vim`.
3. Copy `vim/ftplugin/t.vim` to `~/.vim/ftplugin/t.vim`.
4. (Optional) If you use a plugin manager like Vim-Plug, you can add this repository to your `.vimrc`.

### Tab Completion in Vim

**Via LSP (recommended):** See the LSP section below for `nvim-lspconfig` or `coc.nvim` setup.

**Via omni-completion (terminal REPL):** The ftplugin sets `omnifunc=TComplete`.
Open a T REPL with `:TRepl`, then press `<C-x><C-o>` in insert mode to trigger
completions against the running REPL session.

## Emacs

1. Add the `emacs/` directory to your `load-path`:
   ```elisp
   (add-to-list 'load-path "/path/to/tlang/editors/emacs")
   (require 't-mode)
   ```
2. Any `.t` file will now automatically open in `t-mode`.

### Tab Completion in Emacs

**Via LSP (recommended):** See the LSP section below for `eglot` setup.

**Via REPL (`t-inferior-mode`):** Start a REPL with `M-x run-t`, then press
`TAB` in the REPL buffer. The mode queries the running process via its
`:complete` command. The timeout is controlled by `t-completion-timeout`
(default 0.5 s); customise it with `M-x customize-variable RET t-completion-timeout`.

## VS Code / Positron

**Quick install** (pre-built):
```bash
code --install-extension vscode/t-lang-0.51.0.vsix
```

**Building from source** (requires Node.js):

1. Install dependencies:
   ```bash
   # If you don't have node/npm, use a temporary Nix shell:
   # nix shell nixpkgs#nodejs

   cd vscode/extensions/t-lang
   npm install
   ```
2. Package the extension:
   ```bash
   npx -y @vscode/vsce package --allow-missing-repository
   ```
3. Install the generated `.vsix`:
   ```bash
   code --install-extension t-lang-0.51.0.vsix
   ```
4. Restart your editor.
5. Alternatively, open `vscode/extensions/t-lang` in VS Code and press `F5` to test in a Development Host window.

### Tab Completion in VS Code

The extension automatically starts the `t-lsp` language server when a `.t` file
is opened, providing real-time completions (triggered by typing, `$`, or `.`),
hover documentation, go-to-definition, and diagnostics. Make sure `t-lsp` is
on your `PATH` (it is automatically available inside `nix develop`).

## Quarto

If you want executable `{t}` blocks in Quarto documents, add `quarto` to `[additional-tools]` in `tproject.toml`, run `t update`, and enter the project with `nix develop`. T will provision `_extensions/tlang` automatically from the Nix store; then enable the `tlang` filter in your document front matter.

See `quarto/tlang/README.md` for installation and usage details.

## LSP (Language Server Protocol)

The T language server is implemented in `src/lsp_server.ml`. When you build the project via Nix, a wrapped binary called `t-lsp` is created. This binary is pre-configured with the correct library paths for all dependencies (Arrow, GLib, etc.).

If you use `nix develop`, `t-lsp` will be in your `PATH` automatically.

### Performance Notes

The LSP server caches document line arrays on every edit so that completion,
hover, and go-to-definition requests resolve in O(1) per line lookup instead
of re-splitting the document text. Completion context detection uses
short-circuit evaluation — only the matching context (member, function
argument, column reference, or symbol) is computed.

### 🧩 VS Code / Positron

The T VS Code extension is in `editors/vscode/extensions/t-lang`. Install it by
running `npm install`, packaging with `npx @vscode/vsce package`, and then
`code --install-extension t-lang-0.51.0.vsix`. The extension starts `t-lsp` automatically.

### 🧩 Vim / Neovim

#### Neovim (`nvim-lspconfig`)
Add this to your `init.lua`:
```lua
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

if not configs.tlang then
  configs.tlang = {
    default_config = {
      cmd = { "t-lsp" },
      filetypes = {'t'},
      root_dir = lspconfig.util.root_pattern('tproject.toml', '.git'),
      settings = {},
    }
  }
end
lspconfig.tlang.setup{}
```

#### Neovim tree-sitter
For tree-sitter based highlighting, point Neovim at the source grammar:
```lua
local parser_config = require('nvim-treesitter.parsers').get_parser_configs()

parser_config.t = {
  install_info = {
    url = "/absolute/path/to/tlang/editors/tree-sitter-t",
    files = { "src/parser.c" },
    generate_requires_npm = true,
    requires_generate_from_grammar = true,
  },
  filetype = "t",
}

vim.treesitter.language.register("t", "t")
```

Then install it with `:TSInstallFromGrammar t`.
Replace `/absolute/path/to/tlang` with your local clone path.
If you prefer, you can first run `npx tree-sitter-cli generate` in your local
`/absolute/path/to/tlang/editors/tree-sitter-t` checkout and then install as
usual.

#### Vim (`coc.nvim`)
Add this to your `:CocConfig`:
```json
{
  "languageserver": {
    "tlang": {
      "command": "t-lsp",
      "filetypes": ["t"],
      "rootPatterns": ["tproject.toml", ".git"]
    }
  }
}
```

### 🧩 Emacs (`eglot`)
Add the following to your `init.el`:
```elisp
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(t-mode . ("t-lsp"))))

;; Automatically start eglot when opening a .t file
(add-hook 't-mode-hook 'eglot-ensure)
```

### 🧩 Emacs tree-sitter (`treesit`)
Emacs 29+ can build the bundled grammar directly from source:
```elisp
(add-to-list 'treesit-language-source-alist
             '(t "/absolute/path/to/tlang/editors/tree-sitter-t"))

(unless (treesit-language-available-p 't)
  (treesit-install-language-grammar 't))
```
Replace `/absolute/path/to/tlang` with your local clone path.
Make sure the `tree-sitter` CLI is installed locally first.

You can then use the parser from a custom `t-ts-mode`, Combobulate-style
navigation packages, or any package that consumes installed tree-sitter
grammars.

### 🧩 Other tree-sitter editors

- **Helix**: point `language-configuration.json` / `languages.toml` at `editors/tree-sitter-t`
- **Zed**: use the bundled grammar as a local tree-sitter language source
- **Vim** with tree-sitter plugins: reuse the same parser and query files from `tree-sitter-t/`
