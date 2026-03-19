# Editor Support for T

This guide describes how to set up syntax highlighting and language server (LSP) features for the T programming language in various editors.

## Syntax Highlighting

Syntax highlighting provides basic color coding for keywords, operators, strings, and T-specific features like NSE variables (`$column`) and foreign code blocks (`<{ r_code }>`).

### Vim / Neovim

You’ll find the required files [here](https://github.com/b-rodrigues/tlang/tree/main/editors/vim):

1. Copy the ftdetect file:
   ```bash
   mkdir -p ~/.vim/ftdetect
   cp editors/vim/ftdetect/t.vim ~/.vim/ftdetect/t.vim
   ```
2. Copy the syntax file:
   ```bash
   mkdir -p ~/.vim/syntax
   cp editors/vim/syntax/t.vim ~/.vim/syntax/t.vim
   ```
3. Restart Vim. Files ending in `.t` will now have syntax highlighting.

### Emacs

1. Add the `emacs/` [directory found here](https://github.com/b-rodrigues/tlang/tree/main/editors/emacs) to your `load-path` in `init.el`:
   ```elisp
   (add-to-list 'load-path "/path/to/tlang/editors/emacs")
   (require 't-mode)
   ```
2. Any `.t` file will now automatically open in `t-mode`.

### VS Code / Positron

1. Download `editors/vscode/t-lang-0.51.0.vsix` from the repository (or clone the repo).

2. Install the extension:
   ```bash
   code --install-extension editors/vscode/t-lang-0.51.0.vsix
   ```

3. Restart VS Code or Positron.

> **Building from source**: If you prefer to build the extension yourself,
> see [editors/README.md](../editors/README.md) for instructions.

### Quarto

For literate programming with executable `{t}` chunks, add Quarto to your T project tools:

```toml
[additional-tools]
packages = ["quarto"]
```

Then run `t update` and enter the project with `nix develop`. T will provision `_extensions/tlang` automatically from the Nix store.

After that, enable the `tlang` filter in your document front matter:

```yaml
---
filters:
  - tlang
---
```

The extension lives in `editors/quarto/tlang` and includes a ready-to-copy example document.

---

## Language Server Protocol (LSP)

The T language server provides advanced features like:
- **Autocompletion**: Context-aware suggestions for functions, variables, and data-frame columns (even inside pipes!).
- **Diagnostics**: Real-time syntax and semantic checks. Missing columns or invalid types are flagged immediately.
- **Hover Information**: High-fidelity tooltips showing function signatures and rich documentation (rendered from OCaml docstrings).
- **Go to Definition**: Navigate directly to where a symbol is defined, including library functions.
- **Symbol Renaming**: Safe, project-wide renaming of variables and functions.

### The LSP Binary
The `t-lsp` server is implemented in OCaml using the `linol` framework. When you enter a T project via `nix develop`, the correctly versioned binary is put in your `PATH`.

> [!IMPORTANT]
> **Launching the LSP**: For your editor to find the `t-lsp` binary, you must either:
> 1. Launch your editor from **within** a `nix develop` shell.
> 2. Use a tool like **[direnv](https://direnv.net/)** with `use flake` to automatically load the environment when you enter the project directory.

### Configuring your Editor

#### **Neovim (`nvim-lspconfig`)**
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

#### **Vim (`coc.nvim`)**
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

#### **Emacs (`eglot`)**
Add the following to your `init.el`:
```elisp
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(t-mode . ("t-lsp"))))

;; Automatically start eglot when opening a .t file
(add-hook 't-mode-hook 'eglot-ensure)
```

### Building from Source
If you are developing T itself, you can rebuild the LSP server with:
```bash
nix build .#default
```
The binary will be located at `result/bin/t-lsp`.
