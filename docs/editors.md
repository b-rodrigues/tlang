# Editor Support for T

This guide explains how to get useful editor support for the T programming language: opening `.t` files, getting syntax highlighting, running code in a REPL, enabling the language server, and using the bundled tree-sitter grammar where your editor supports it.

If you are new to this, start with your editor's section below and copy the commands exactly. Replace `/absolute/path/to/tlang` with the full path to your local clone of this repository.

---

## What you can install

T editor support has two separate pieces. You do **not** always need both.

| Feature | What it does | Usually needed for |
| --- | --- | --- |
| T editor mode / extension | Teaches the editor that `.t` files are T files. Usually provides basic highlighting, commands, and keybindings. | VS Code, Positron, Vim, Neovim, Emacs |
| T language server (`t-lsp`) | Provides editor features such as completion, diagnostics, hover help, and go to definition. | VS Code, Positron, Vim/Neovim LSP, Emacs eglot |
| Tree-sitter grammar | Provides modern parser-based syntax highlighting and syntax-aware editor features when the editor supports local tree-sitter grammars. | Neovim, Emacs 29+, Helix, Zed, and some advanced Vim/VS Code setups |

> [!TIP]
> If you only want to write and run T scripts, install the normal editor extension/mode first. Add tree-sitter only if your editor supports it or if you specifically want tree-sitter highlighting.

---

## Language Server Protocol (LSP)

The T language server provides advanced features like **Autocompletion** (context-aware suggestions), **Diagnostics** (real-time error checking), **Hover Information** (tooltips showing signatures/docs), and **Go to Definition**.

The `t-lsp` server is implemented in OCaml. When you enter a T project via `nix develop`, the correctly versioned binary is put in your `PATH`.

> [!IMPORTANT]
> **Launching the LSP**: For your editor to find the `t-lsp` binary, you must either launch your editor from **within** a `nix develop` shell, or use a tool like **[direnv](https://direnv.net/)** with `use flake` to automatically load the environment.

Check that the language server is visible before debugging editor configuration:

```bash
nix develop
which t-lsp
```

If `which t-lsp` prints nothing, your editor will not be able to start the T language server either.

---

## Tree-sitter grammar: build it once, then point your editor at it

T ships a reusable tree-sitter grammar in `editors/tree-sitter-t`.
Only the source grammar, queries, metadata, and grammar tests are committed.
Generated parser sources are expected to be created locally when needed.

### Step 1: install Node.js so `npx` exists

The commands below use `npx`. `npx` comes with Node.js/npm, so install Node.js first if your shell says `npx: command not found`.

The simplest one-off Nix command is:

```bash
nix-shell -p nodejs
```

That opens a temporary shell with `node`, `npm`, and `npx` available. Confirm it worked:

```bash
node --version
npm --version
npx --version
```

You can also use any normal Node.js installation method for your system. Nix is recommended because it avoids system-wide changes.

### Step 2: generate the parser files

Run these commands from your T repository clone:

```bash
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli generate
npx tree-sitter-cli test
```

When prompted by `npx` to install `tree-sitter-cli`, answer `y`.

This creates these generated files locally:

- `src/parser.c`
- `src/grammar.json`
- `src/node-types.json`
- `src/tree_sitter/`

Those files are ignored by Git and should not be committed.

### Step 3: use the generated grammar in your editor

Each editor has a slightly different way to consume a local tree-sitter grammar:

- **VS Code / Positron**: the recommended T extension works without tree-sitter. VS Code-family editors do not automatically use local tree-sitter grammars for language highlighting. If you install a third-party tree-sitter extension, point that extension at `editors/tree-sitter-t` and reuse the query files in `editors/tree-sitter-t/queries/`.
- **Neovim**: configure `nvim-treesitter` with `editors/tree-sitter-t`, then run `:TSInstallFromGrammar t`.
- **Vim**: classic Vim uses the files in `editors/vim/`. Tree-sitter requires an extra Vim tree-sitter plugin; if you use one, point it at the same grammar directory.
- **Emacs 29+**: add the grammar to `treesit-language-source-alist`, then run `M-x treesit-install-language-grammar`.

If tree-sitter setup fails, first verify that `src/parser.c` exists:

```bash
ls /absolute/path/to/tlang/editors/tree-sitter-t/src/parser.c
```

---

## VS Code / Positron

VS Code and Positron use the same extension format, so these instructions apply to both.

### What this gives you

The T VS Code extension gives you:

- `.t` file recognition
- T syntax highlighting
- LSP integration through `t-lsp`
- Commands for opening a T REPL and sending code to it
- **Cmd+Enter** on macOS or **Ctrl+Enter** on Linux/Windows to send the current line or selection to the T REPL

You do **not** need to build the tree-sitter grammar for the normal VS Code/Positron extension. The extension uses VS Code's standard grammar system and talks to `t-lsp` for language features.

### Option A: Download the `.vsix` file (recommended)

1. Download the latest release: [`t-lang-0.51.0.vsix`](https://github.com/b-rodrigues/tlang/raw/main/editors/vscode/t-lang-0.51.0.vsix) (or download from the repository assets).
2. Install the extension from the command line:

   ```bash
   code --install-extension /path/to/downloaded/t-lang-0.51.0.vsix
   ```

   In Positron, use the equivalent `positron` command if it is available:

   ```bash
   positron --install-extension /path/to/downloaded/t-lang-0.51.0.vsix
   ```

   If the command-line launcher is not available, open the editor, go to the Extensions view, click the `...` menu, and choose **Install from VSIX...**.

### Option B: Install from a cloned T repository

If you have already cloned the T repository locally:

```bash
cd /absolute/path/to/tlang
code --install-extension editors/vscode/t-lang-0.51.0.vsix
```

For Positron, replace `code` with `positron` if that command exists:

```bash
cd /absolute/path/to/tlang
positron --install-extension editors/vscode/t-lang-0.51.0.vsix
```

### Launch VS Code or Positron correctly

The most common beginner mistake is launching the editor from a normal desktop shortcut. That often means the editor cannot find `t-lsp`.

Do this instead:

```bash
cd /absolute/path/to/your-t-project
nix develop
code .
```

For Positron:

```bash
cd /absolute/path/to/your-t-project
nix develop
positron .
```

Once the editor opens, open a `.t` file. Recommended entry points are:

- For **projects**: open `src/pipeline.t`
- For **packages**: open `src/main.t`

### Use the extension

- Open the command palette with **Cmd+Shift+P** on macOS or **Ctrl+Shift+P** on Linux/Windows.
- Run **T: Run REPL** to open a T REPL inside the editor.
- Put your cursor on a line of T code and press **Cmd+Enter** or **Ctrl+Enter** to send that line to the REPL.
- Select several lines and press the same shortcut to send the selection.
- Save files with the `.t` extension so the editor knows to activate T support.

### Optional: tree-sitter in VS Code / Positron

The built-in T extension does not require tree-sitter. If you have installed a separate VS Code tree-sitter extension and it asks for a grammar path, use:

```text
/absolute/path/to/tlang/editors/tree-sitter-t
```

Use these query files if the extension asks for them:

```text
/absolute/path/to/tlang/editors/tree-sitter-t/queries/highlights.scm
/absolute/path/to/tlang/editors/tree-sitter-t/queries/injections.scm
/absolute/path/to/tlang/editors/tree-sitter-t/queries/locals.scm
```

Because third-party tree-sitter extensions differ, the exact setting names depend on the extension. If you are unsure, skip this step; the official VS Code/Positron extension is the beginner-friendly path.

---

## Vim / Neovim

Vim and Neovim can use either the classic Vim support files or tree-sitter. Beginners should install the classic support files first. Neovim users can then add tree-sitter highlighting with `nvim-treesitter`.

### Step 1: install classic Vim support files

Run these commands from the T repository root:

```bash
cd /absolute/path/to/tlang

# Detect .t files
mkdir -p ~/.vim/ftdetect
cp editors/vim/ftdetect/t.vim ~/.vim/ftdetect/t.vim

# Syntax rules
mkdir -p ~/.vim/syntax
cp editors/vim/syntax/t.vim ~/.vim/syntax/t.vim

# Filetype plugin: REPL command, send-line/send-region mappings, completion
mkdir -p ~/.vim/ftplugin
cp editors/vim/ftplugin/t.vim ~/.vim/ftplugin/t.vim
```

Open a T file:

```bash
vim example.t
```

Inside Vim, verify the filetype:

```vim
:set filetype?
```

It should print:

```text
filetype=t
```

### Step 2: use T from Vim

With `editors/vim/ftplugin/t.vim` installed, these commands and mappings are available in `.t` buffers:

| Action | Vim command or key |
| --- | --- |
| Start a T REPL terminal | `:TRepl` |
| Send the current line to the REPL | `<leader>r` in normal mode |
| Send the selected lines to the REPL | `<leader>r` in visual mode |
| Send the whole buffer to the REPL | `<leader>b` in normal mode |
| Trigger omni-completion | `Ctrl-x Ctrl-o` |

Your `<leader>` key is usually `\` unless you changed it in your Vim configuration.

### Step 3: configure LSP

The LSP setup requires `t-lsp` to be in your `PATH`. Start Vim/Neovim from `nix develop`, or configure your plugin manager to inherit the Nix environment.

#### Vim with `coc.nvim`

Open `:CocConfig` and add:

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

Then restart Vim and open a `.t` file.

#### Neovim with `nvim-lspconfig`

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

Start Neovim from a T project shell:

```bash
cd /absolute/path/to/your-t-project
nix develop
nvim src/pipeline.t
```

### Step 4: tree-sitter highlighting in Neovim

Install and enable `nvim-treesitter` using your normal Neovim plugin manager. Then add this to your `init.lua` after loading `nvim-treesitter`:

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

Then run this inside Neovim:

```vim
:TSInstallFromGrammar t
```

Open a `.t` file and run:

```vim
:InspectTree
```

If a syntax tree opens, tree-sitter is working. If `:TSInstallFromGrammar t` fails because it cannot run `npx`, leave Neovim, start a shell with Node.js, and try again:

```bash
nix-shell -p nodejs
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli generate
```

Then reopen Neovim and run `:TSInstallFromGrammar t` again.

### Vim with tree-sitter plugins

Classic Vim does not include tree-sitter by default. If you use a Vim tree-sitter plugin, configure it with:

```text
Grammar directory: /absolute/path/to/tlang/editors/tree-sitter-t
Parser source:     /absolute/path/to/tlang/editors/tree-sitter-t/src/parser.c
Queries:           /absolute/path/to/tlang/editors/tree-sitter-t/queries/
Filetype:          t
File extension:    .t
```

Plugin setting names vary, so use the plugin's documentation for the exact syntax.

---

## Emacs

Emacs support has two layers:

1. `t-mode`, the normal major mode for `.t` files.
2. Optional tree-sitter support through Emacs 29+ `treesit`.

Install `t-mode` first. Add tree-sitter afterwards if your Emacs version supports it.

### Step 1: install `t-mode`

Add the `editors/emacs/` directory to your `load-path` in `init.el`:

```elisp
(add-to-list 'load-path "/absolute/path/to/tlang/editors/emacs")
(require 't-mode)
```

Open a `.t` file. Emacs should use `t-mode` automatically. To check, run:

```text
M-x describe-mode
```

You should see `T` or `t-mode` in the mode description.

### Step 2: use the T REPL from Emacs

`t-mode` provides these commands and keybindings:

| Action | Command | Keybinding |
| --- | --- | --- |
| Start or switch to a T REPL | `M-x run-t` | `C-c C-z` |
| Send the whole buffer | `M-x t-send-buffer` | `C-c C-c` |
| Send selected region | `M-x t-send-region` | `C-c C-r` |
| Send current line | `M-x t-send-line` | `C-c C-l` |

If Emacs cannot find the `t` executable, start Emacs from a T/Nix shell:

```bash
cd /absolute/path/to/your-t-project
nix develop
emacs .
```

### Step 3: configure LSP with eglot

Add the following to your `init.el`:

```elisp
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(t-mode . ("t-lsp"))))

;; Automatically start eglot when opening a .t file
(add-hook 't-mode-hook 'eglot-ensure)
```

Again, `t-lsp` must be visible in Emacs' environment. If LSP does not start, run Emacs from `nix develop`.

### Step 4: tree-sitter parser in Emacs 29+

Emacs 29 introduced built-in tree-sitter support through `treesit`. Add this to your `init.el`:

```elisp
(when (treesit-available-p)
  (add-to-list 'treesit-language-source-alist
               '(t "/absolute/path/to/tlang/editors/tree-sitter-t")))
```

Then restart Emacs and install the grammar:

```text
M-x treesit-install-language-grammar RET t RET
```

If Emacs cannot build the grammar because `npx` or Node.js is missing, install Node.js first:

```bash
nix-shell -p nodejs
```

Then regenerate the parser manually:

```bash
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli generate
```

Finally, restart Emacs and retry:

```text
M-x treesit-install-language-grammar RET t RET
```

This makes the T parser available to `treesit`-aware packages and any custom `t-ts-mode` built on top of the bundled grammar. The bundled `t-mode` remains the safe default if you do not have a separate tree-sitter-based major mode installed.

---

## Quarto

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

## Other tree-sitter editors

The same parser package can also be reused by editors that consume local tree-sitter grammars, including:

- **Helix**
- **Zed**
- **Lapce**
- **Vim** setups that add tree-sitter through plugins

Point those editors at `editors/tree-sitter-t` and reuse the bundled query files from `queries/`.

For any editor, the important paths are:

```text
Grammar: /absolute/path/to/tlang/editors/tree-sitter-t
Queries: /absolute/path/to/tlang/editors/tree-sitter-t/queries
Parser:  /absolute/path/to/tlang/editors/tree-sitter-t/src/parser.c
```

---

## Troubleshooting checklist

### `npx: command not found`

Install Node.js, then try again:

```bash
nix-shell -p nodejs
npx --version
```

### `tree-sitter: command not found`

Use `npx tree-sitter-cli ...` instead of `tree-sitter ...`, or install the CLI globally:

```bash
npm install --global tree-sitter-cli
```

### My editor cannot find `t-lsp`

Start the editor from inside `nix develop`:

```bash
cd /absolute/path/to/your-t-project
nix develop
code .      # VS Code
positron .  # Positron
nvim .      # Neovim
emacs .     # Emacs
```

You can also check from the same shell:

```bash
which t-lsp
```

### `.t` files are not highlighted

Check that the editor knows the filetype/language is T:

- **VS Code / Positron**: look at the language indicator in the bottom-right corner. It should say `T` or `tlang`. If not, click it and choose T.
- **Vim/Neovim**: run `:set filetype?`. It should say `filetype=t`.
- **Emacs**: run `M-x describe-mode`. It should show `t-mode`.

### Tree-sitter still does not work

Check the generated parser exists:

```bash
ls /absolute/path/to/tlang/editors/tree-sitter-t/src/parser.c
```

If it does not exist, regenerate it:

```bash
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli generate
```

---

## Building from Source

If you are developing T itself, you can rebuild the LSP server with:

```bash
nix build .#default
```

The binary will be located at `result/bin/t-lsp`.
