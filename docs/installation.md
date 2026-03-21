# Installation Guide

Complete guide for installing and setting up the T programming language.

## System Requirements

### Operating System
- **Linux** (recommended): Any modern distribution (Ubuntu 20.04+, Fedora 35+, Arch, etc.)
- **macOS**: 11 (Big Sur) or later
- **Windows**: Via WSL2 (Windows Subsystem for Linux)

### Prerequisites
- **Nix package manager** 2.4 or later with flakes enabled
- **Git** for version control
- At least **2GB free disk space** for Nix store
- **Internet connection** for initial setup

## Step 1: Install Nix

T requires the **Nix package manager** with flakes enabled. We strongly recommend using the **Determinate Systems Nix Installer** for its robustness and ease of use.

### Platform-Specific Nix Installation

For detailed instructions on installing Nix on **Linux**, **macOS**, and **Windows (WSL2)**, please see our dedicated:

👉 **[Nix Installation Guide](nix-installation.md)**

Once Nix is installed and flakes are enabled, you can proceed to Step 2.

## Step 3: Clone T Repository

```bash
# Choose a directory for T (e.g., ~/projects)
mkdir -p ~/projects
cd ~/projects

# Clone the repository
git clone https://github.com/b-rodrigues/tlang.git
cd tlang
```

## Step 4: Enter Development Environment

The Nix flake provides a complete, isolated development environment:

```bash
nix develop
```

**First run** will take several minutes to:
- Download and compile OCaml toolchain
- Build Apache Arrow and dependencies
- Set up development tools (dune, menhir, etc.)

All dependencies are cached in the Nix store (`/nix/store/`) and reused for future sessions.

**Expected output:**

```
warning: creating lock file '/home/user/projects/tlang/flake.lock'
...
(nix development shell activated)
```

## Step 5: Build T

Inside the development environment:

```bash
dune build
```

This compiles:
- Lexer and parser
- Evaluator and runtime
- Standard library packages
- REPL

**Expected output:**

```
File "src/repl.ml", line 1, characters 0-0:
Building...
```

Build artifacts are placed in `_build/default/`.

## Step 6: Verify Installation

### Start the REPL

```bash
dune exec src/repl.exe
```

You should see:

```
T, a reproducibility-first orchestration engine for polyglot
data science and statistical analysis.
Version 0.51.1 "Sangoku" using Nix <nix-version>
Licensed under the EUPL v1.2. No warranties.
This software is in beta and is entirely LLM-generated — caveat emptor.
Website: https://tstats-project.org
Contributions are welcome!
Type :quit or :q to exit, :help for commands.

T> 
```

### Test Basic Operations

```t
> 2 + 3
5

> [1, 2, 3] |> sum
6

> type(42)
"Int"

> exit
```

If all commands work, installation is successful! 🎉

## Step 7: Run Tests (Optional)

Verify everything works correctly:

```bash
dune runtest
```

Expected behavior:
- All tests should pass
- Golden tests compare T output against R results
- Test execution may take 1-2 minutes

## Development Workflow

### Entering the Environment

Every time you want to work with T:

```bash
cd ~/projects/tlang
nix develop
```

### Updating Dependencies

If `flake.nix` changes (e.g., after pulling updates):

```bash
nix flake update
nix develop
```

### Cleaning Build Artifacts

```bash
dune clean
dune build
```

## Advanced Configuration

### Direnv Integration (Optional)

Automatically enter the Nix shell when entering the directory:

```bash
# Install direnv
nix-env -iA nixpkgs.direnv

# Enable direnv in your shell (bash/zsh)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc  # for bash
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc   # for zsh

# Create .envrc in tlang directory
cd ~/projects/tlang
echo "use flake" > .envrc
direnv allow
```

Now `cd tlang` automatically activates the environment.

### Binary Cache (Faster Builds)

T doesn't yet have a public binary cache, but you can set one up locally for your team:

```bash
# In nix.conf
substituters = https://cache.nixos.org/ https://your-cache.example.com/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

## Troubleshooting

### "command not found: nix"

The Nix installation may not have updated your PATH. Try:

```bash
source ~/.nix-profile/etc/profile.d/nix.sh
```

Or restart your terminal.

### "experimental-features" Error

Flakes aren't enabled. Double-check `~/.config/nix/nix.conf`:

```bash
cat ~/.config/nix/nix.conf
# Should contain: experimental-features = nix-command flakes
```

### "nix develop" Hangs

Nix is building dependencies from source. This is normal on first run. Check progress:

```bash
nix develop --show-trace
```

Or use a faster binary cache (if available).

### Build Fails with Dune Errors

Clean and rebuild:

```bash
dune clean
rm -rf _build
dune build
```

If errors persist, check:
- You're inside `nix develop` shell
- OCaml version: `ocaml --version` should be 4.14+
- Dune version: `dune --version` should be 3.0+

### Arrow FFI Issues

T uses Apache Arrow C GLib bindings. If you see linking errors:

```bash
# Inside nix develop
pkg-config --modversion arrow-glib
# Should output: 10.0.0 or similar
```

The Nix flake ensures Arrow is available; these errors usually indicate you're not in the Nix shell.

### Tests Failing

Some tests require R (for golden test comparisons). Check test logs:

```bash
dune runtest --verbose
```

Known issues:
- Floating-point precision differences across platforms
- R package availability for comparison tests

## Platform-Specific Notes

### macOS

- **Apple Silicon (M1/M2)**: Fully supported via Nix's ARM64 support
- **Rosetta**: Not required; native ARM builds are used

### WSL2

- **File permissions**: Ensure cloned repo is on Linux filesystem (`/home/user/...`), not Windows mount (`/mnt/c/...`)
- **Performance**: Native Linux filesystem is significantly faster

### NixOS

T works natively on NixOS:

```nix
# Add to configuration.nix or home-manager
environment.systemPackages = with pkgs; [
  # T will be added to nixpkgs eventually
];
```

For now, use `nix develop` as above.

## Next Steps

Now that T is installed:

1. **[Getting Started Guide](getting-started.md)** — Write your first program
2. **[Language Overview](language_overview.md)** — Learn T syntax
3. **[Examples](examples.md)** — See practical code

## Uninstalling

### Remove T Repository

```bash
rm -rf ~/projects/tlang
```

### Remove Nix Store Entries

```bash
# Remove just T's dependencies (preserves other Nix packages)
nix-store --gc

# Or remove all unused packages
nix-collect-garbage -d
```

### Uninstall Nix Completely

```bash
# For multi-user install
sudo rm -rf /nix
sudo rm /etc/profile.d/nix.sh
sudo rm /etc/nix

# For single-user install
rm -rf ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.config/nix
```

---

**Ready to start?** Head to the [Getting Started Guide](getting-started.md)!
