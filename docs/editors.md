# Editor Support for T

This guide describes how to set up syntax highlighting and language server (LSP) features for the T programming language in various editors.

## 🌈 Syntax Highlighting

Syntax highlighting provides basic color coding for keywords, operators, strings, and T-specific features like NSE variables (`$column`) and foreign code blocks (`<{ r_code }>`).

### Vim / Neovim

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

1. Add the `emacs/` directory to your `load-path` in `init.el`:
   ```elisp
   (add-to-list 'load-path "/path/to/tlang/editors/emacs")
   (require 't-mode)
   ```
2. Any `.t` file will now automatically open in `t-mode`.

### VS Code

1. Copy the `editors/vscode/t-lang` folder to your VS Code extensions directory:
   - **Linux/macOS**: `~/.vscode/extensions/`
   - **Windows**: `%USERPROFILE%\.vscode\extensions\`
2. Restart VS Code.

### Quarto

For literate programming with executable `{t}` chunks, install the extension from your Quarto project with:

```bash
quarto add /path/to/tlang/editors/quarto/tlang
```

Then enable the `tlang` filter in your document front matter:

```yaml
---
filters:
  - tlang
---
```

The extension lives in `editors/quarto/tlang` and includes a ready-to-copy example document.

---

## ⚡ Language Server Protocol (LSP)

The T language server provides advanced features like:
- **Autocompletion**: Suggests functions, variables, and columns.
- **Diagnostics**: Real-time syntax and basic semantic error reporting.
- **Hover Information**: Shows types and documentation for variables and functions.

### The LSP Binary
When you install the `t-lang` package via Nix (or use `nix develop`), the `t-lsp` binary is automatically added to your path. This binary is pre-configured with all necessary dependencies.

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

### 🏗️ Building from Source
If you are developing T itself, you can rebuild the LSP server with:
```bash
nix build .#default
```
The binary will be located at `result/bin/t-lsp`.
