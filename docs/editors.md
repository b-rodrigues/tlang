# Editor Support for T

This guide describes how to set up syntax highlighting and language server (LSP) features for the T programming language in various editors.

---

## Language Server Protocol (LSP)

The T language server provides advanced features like **Autocompletion** (context-aware suggestions), **Diagnostics** (real-time error checking), **Hover Information** (tooltips showing signatures/docs), and **Go to Definition**.

The `t-lsp` server is implemented in OCaml. When you enter a T project via `nix develop`, the correctly versioned binary is put in your `PATH`.

> [!IMPORTANT]
> **Launching the LSP**: For your editor to find the `t-lsp` binary, you must either launch your editor from **within** a `nix develop` shell, or use a tool like **[direnv](https://direnv.net/)** with `use flake` to automatically load the environment.

---

## Editor Configuration

### VS Code / Positron

You can install the T language extension in two ways:

#### Option A: Download the `.vsix` file (Recommended)
1. Download the latest release: [`t-lang-0.51.1.vsix`](https://github.com/b-rodrigues/tlang/raw/main/editors/vscode/t-lang-0.51.1.vsix) (or download from the repository assets).
2. Install the extension using the command line:
   ```bash
   code --install-extension /path/to/downloaded/t-lang-0.51.1.vsix
   ```
   *Alternatively, in VS Code, go to the Extensions view, click the `...` menu, and select **Install from VSIX...***

#### Option B: From a cloned T repository
If you have already cloned the T repository locally:
```bash
code --install-extension editors/vscode/t-lang-0.51.1.vsix
```

#### Launching the Editor
Start VS Code or Positron from the same nix shell where you run `t`:
```bash
nix develop
code .
```

Once VS Code opens, we recommend opening the main entry point for your workspace:
- For **projects**: Open `src/pipeline.t`
- For **packages**: Open `src/main.t`

> **Tip**: You can use **Cmd+Enter** (macOS) or **Ctrl+Enter** (Linux/Windows) to send the current line or selection to the T REPL, exactly like in RStudio.

---

### Vim / Neovim

#### 1. Syntax Highlighting
Copy the support files into your `.vim` directory:
```bash
# Detect .t files
mkdir -p ~/.vim/ftdetect
cp editors/vim/ftdetect/t.vim ~/.vim/ftdetect/t.vim

# Syntax rules
mkdir -p ~/.vim/syntax
cp editors/vim/syntax/t.vim ~/.vim/syntax/t.vim
```

#### 2. LSP (via coc.nvim or nvim-lspconfig)

**For Vim (`coc.nvim`)**, add this to your `:CocConfig`:
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

**For Neovim (`nvim-lspconfig`)**, add this to your `init.lua`:
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

---

### Emacs

#### 1. Syntax Highlighting
Add the `editors/emacs/` directory to your `load-path` in `init.el`:
```elisp
(add-to-list 'load-path "/path/to/tlang/editors/emacs")
(require 't-mode)
```

#### 2. LSP (via eglot)
Add the following to your `init.el`:
```elisp
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(t-mode . ("t-lsp"))))

;; Automatically start eglot when opening a .t file
(add-hook 't-mode-hook 'eglot-ensure)
```

---

### Quarto

For literate programming with executable `{t}` chunks, add Quarto to your T project tools in `tproject.toml`:

```toml
[additional-tools]
packages = ["quarto"]
```

Then run `t update` and enter the project with `nix develop`. T will provision `_extensions/tlang` automatically. Enable the `tlang` filter in your document front matter:

```yaml
---
filters:
  - tlang
---
```

---

## Building from Source

If you are developing T itself, you can rebuild the LSP server with:
```bash
nix build .#default
```
The binary will be located at `result/bin/t-lsp`.
