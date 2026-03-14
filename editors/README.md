# Editor Support for T

This directory contains syntax highlighting and language support for the T programming language in various editors.

## Vim

1. Copy `vim/ftdetect/t.vim` to `~/.vim/ftdetect/t.vim`.
2. Copy `vim/syntax/t.vim` to `~/.vim/syntax/t.vim`.
3. (Optional) If you use a plugin manager like Vim-Plug, you can add this repository to your `.vimrc`.

## Emacs

1. Add the `emacs/` directory to your `load-path`:
   ```elisp
   (add-to-list 'load-path "/path/to/tlang/editors/emacs")
   (require 't-mode)
   ```
2. Any `.t` file will now automatically open in `t-mode`.

## VS Code

1. Copy the `vscode/t-lang` folder to your VS Code extensions directory:
   - Windows: `%USERPROFILE%\.vscode\extensions`
   - macOS/Linux: `~/.vscode/extensions`
2. Restart VS Code.
3. Alternatively, you can open the `vscode/t-lang` folder in VS Code and press `F5` to test it in a "Development Host" window.

## Quarto

If you want executable `{t}` blocks in Quarto documents, add `quarto` to `[additional-tools]` in `tproject.toml`, run `t update`, and enter the project with `nix develop`. T will provision `_extensions/tlang` automatically from the Nix store; then enable the `tlang` filter in your document front matter.

See `quarto/tlang/README.md` for installation and usage details.

## LSP (Language Server Protocol)

The T language server is implemented in `src/lsp_server.ml`. When you build the project via Nix, a wrapped binary called `t-lsp` is created. This binary is pre-configured with the correct library paths for all dependencies (Arrow, GLib, etc.).

If you use `nix develop`, `t-lsp` will be in your `PATH` automatically.

### 🧩 VS Code

The T VS Code extension is in `editors/vscode/t-lang`. You can install it by copying the folder to your `.vscode/extensions` directory.

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
