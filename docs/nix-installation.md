# Installing Nix for T

T is a **reproducibility-first** language, and it achieves this by making the **Nix package manager** mandatory. Nix ensures that your T environment—including the compiler, libraries, and even your R or Python dependencies—remains consistent across machines and over time.

This guide explains how to install Nix on your system using the **Determinate Systems** installer, which we recommend for its ease of use and robust uninstallation capabilities.

## Introduction

Nix is a powerful package manager for Linux and macOS. While it might seem complex at first, its integration with T means you don't have to manage environments manually. T handles the "magic," but you need the "engine" (Nix) installed first.

## Recommended Installer: Determinate Systems

We recommend the [Determinate Systems Nix Installer](https://determinate.systems/posts/determinate-nix-installer) for all supported operating systems. It is modern, handles multi-user setups cleanly, and is easy to uninstall if needed.

### Installation Command

Open your terminal and run:

```bash
curl --proto '=https' --tlsv1.2 -sSf \
    -L https://install.determinate.systems/nix | \
    sh -s -- install --no-confirm --extra-conf "
trusted-users = root $USER
substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
```

This single command installs Nix and configures everything T needs:

- **`--no-confirm`** runs the installer non-interactively, so you don't have to answer any prompts.
- **`--extra-conf`** injects configuration directly into your Nix config during installation. The three settings it applies are:
  - **`trusted-users = root $USER`** — Marks your user as a trusted Nix user. This is required for binary caches and certain Nix operations to work without permission errors.
  - **`substituters = ...`** — Tells Nix to fetch pre-built packages from the NixOS cache and the `rstats-on-nix` Cachix cache (used by T for R and Python packages), avoiding long builds from source.
  - **`trusted-public-keys = ...`** — The cryptographic keys Nix uses to verify the authenticity of packages from those caches.

Because the installer handles all of this in one step, there are **no manual post-install configuration steps** when using the Determinate Systems installer. If you installed Nix through other means, see [Already Have Nix?](#already-have-nix) below.

---

## Already Have Nix?

If you installed Nix through a method other than the Determinate Systems installer (e.g., the [official Nix installer](https://nixos.org/download/), Homebrew, your Linux distribution's package manager, or you're on NixOS), you need to manually configure two things for T to work: **trusted users** and the **binary cache**.

### Step 1: Add yourself as a trusted user

T uses binary caches that require your user to be in the `trusted-users` list. Without this, you'll get "ignoring untrusted substituter" errors.

**On NixOS**, add this to your `/etc/nixos/configuration.nix`:

```nix
nix.settings.trusted-users = [ "root" "your-username" ];
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

**On non-NixOS Linux or macOS**, edit `/etc/nix/nix.conf` (you may need `sudo`):

```bash
# Add your username to the trusted-users line
# If the line exists, append your username to it:
sudo sed -i 's/^trusted-users = .*/& your-username/' /etc/nix/nix.conf

# Or if no trusted-users line exists, add one:
echo "trusted-users = root $(whoami)" | sudo tee -a /etc/nix/nix.conf
```

Then restart the Nix daemon:

```bash
# Linux (systemd)
sudo systemctl restart nix-daemon

# macOS (launchd)
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

### Step 2: Add the binary cache

T relies on pre-built R and Python packages from the `rstats-on-nix` Cachix cache. Without this cache, `nix develop` will try to build everything from source, which can take a very long time.

**On NixOS**, add this to your `/etc/nixos/configuration.nix`:

```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://rstats-on-nix.cachix.org"
  ];
  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
  ];
};
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

**On non-NixOS Linux or macOS**, add these lines to `/etc/nix/nix.conf`:

```bash
echo "substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org" | sudo tee -a /etc/nix/nix.conf
echo "trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=" | sudo tee -a /etc/nix/nix.conf
```

Then restart the Nix daemon (same commands as above).

### Verify your configuration

After applying the changes, verify everything is set correctly:

```bash
# Check trusted users
grep "trusted-users" /etc/nix/nix.conf
# Should show: trusted-users = root your-username

# Check cache is configured
grep "rstats-on-nix" /etc/nix/nix.conf
# Should show the substituters and trusted-public-keys lines

# Check flakes are enabled
grep "experimental-features" /etc/nix/nix.conf
# Should show: experimental-features = nix-command flakes
```

---

## Operating System Specific Notes

### Linux

The Determinate Systems installer works on most modern Linux distributions (Ubuntu, Fedora, Debian, Arch, etc.). If you installed Nix through your distribution's package manager instead, follow the [Already Have Nix?](#already-have-nix) steps above.

### NixOS

On NixOS, Nix is already part of the system — **do not use the Determinate Systems installer**. Instead, configure everything in `/etc/nixos/configuration.nix`:

```nix
nix.settings = {
  trusted-users = [ "root" "your-username" ];
  experimental-features = [ "nix-command" "flakes" ];
  substituters = [
    "https://cache.nixos.org"
    "https://rstats-on-nix.cachix.org"
  ];
  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
  ];
};
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

See [Already Have Nix?](#already-have-nix) for step-by-step details on each setting.

### macOS

Nix on macOS is highly efficient but has some platform-specific nuances:

- **SDK Drift**: On macOS, Nix builds might occasionally depend on the macOS SDK from Xcode. While Nix handles this well, system updates sometimes cause "drift." If an older project stops building after a macOS update, try updating your T version or the project's nixpkgs pins.
- **Shared Libraries**: If you experience crashes related to "shared libraries," it might be due to your local R/Python user libraries interfering. T's `t init` command sets up guards to prevent this.

### Windows (WSL2)

Nix cannot run directly on Windows; it requires the **Windows Subsystem for Linux 2 (WSL2)**.

1. **Install WSL2**: Open PowerShell as Administrator and run:
   ```powershell
   wsl --install
   ```
2. **Enable systemd (Recommended)**: To support multi-user Nix in WSL2, we recommend enabling `systemd` in your Ubuntu/WSL2 shell:
   - Run `sudo nano /etc/wsl.conf`
   - Add the following:
     ```ini
     [boot]
     systemd=true
     ```
   - Save (Ctrl+O) and Exit (Ctrl+X).
   - In PowerShell, run `wsl --shutdown`, then relaunch your WSL2 terminal.
3. **Install Nix**: Run the Determinate Systems installation command inside your WSL2 terminal.

---

## Post-Installation: Enabling Flakes

T requires **Nix Flakes** to be enabled. The Determinate Systems installer usually enables these by default. You can verify by checking `~/.config/nix/nix.conf` or `/etc/nix.conf`. It should contain:

```text
experimental-features = nix-command flakes
```

If it's missing, add it with:

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

---

## Nix and Docker

Nix and Docker are often seen as alternatives, but they work exceptionally well together. While Docker manages container isolation, Nix handles the environment reproducibility *inside* or *for* those containers.

To install Nix inside a `Dockerfile` (e.g., using `ubuntu:latest` as a base), use the Determinate Systems installer with specific flags for container environments:

```dockerfile
FROM ubuntu:latest

RUN apt update && apt install -y curl

# Install Nix inside the container
RUN curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux \
  --extra-conf "sandbox = false" \
  --init none \
  --no-confirm

# Add Nix to the PATH
ENV PATH="${PATH}:/nix/var/nix/profiles/default/bin"
ENV user=root

# Optional: Configure the T binary cache
RUN mkdir -p /root/.config/nix && \
    echo "substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org" > /root/.config/nix/nix.conf && \
    echo "trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=" >> /root/.config/nix/nix.conf

CMD ["nix-shell"]
```

---

## Troubleshooting

### "command not found: nix"
The installer usually updates your shell profile. Try restarting your terminal or running:
```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### Permission Denied or "ignoring untrusted substituter"

This means your user is not in the Nix `trusted-users` list. The fix depends on how you installed Nix:

- **Determinate Systems installer**: Re-run the [Installation Command](#installation-command) — it will configure trusted users and caches in one step.
- **Official Nix installer or other method**: Follow the [Already Have Nix?](#already-have-nix) steps to manually add your user to `trusted-users` and configure the cache.
- **NixOS**: Add `nix.settings.trusted-users = [ "root" "your-username" ];` to your `configuration.nix` and run `sudo nixos-rebuild switch`.

## From Nix to your first T project

Once Nix is installed and the binary cache is configured, you are done with installation. T itself is **never installed** as a system program — it is distributed exclusively through Nix. Instead of installing T, you bootstrap a project that pins its own copy of the T toolchain.

### 1. Start a temporary shell with `t`

The `t` executable is provided by the `github:b-rodrigues/tlang` flake. Launch a temporary shell that puts `t` on your `PATH`:

```bash
nix shell --accept-flake-config github:b-rodrigues/tlang
```

This downloads the T executable (and the pinned OCaml, R, Python, and Julia runtimes it needs) and drops you into an ephemeral environment where `t` works — for as long as you stay in that shell.

### 2. Bootstrap a new project

Inside the temporary shell, scaffold a new project:

```bash
t init --project my_analysis
```

You will be prompted for basic project information (your name, the license, the Nixpkgs date, the AI Agent Context Level, and the pipeline template). This creates a `my_analysis/` directory containing the project's reproducible environment — most importantly `tproject.toml` (your dependency manifest) and `flake.nix`.

### 3. Enter the project environment

Leave the temporary shell, move into the project, and drop into the project's own development environment:

```bash
exit
cd my_analysis
nix develop
```

`nix develop` rebuilds an environment that pins the `t` version and all declared R, Python, and Julia packages from `tproject.toml`. From here on, you work inside the project environment — that is what "running T" means in practice.

### 4. Start working

You can now edit `src/pipeline.t` and run it with `t run src/pipeline.t`, or explore interactively with `t repl`. When you add dependencies to `tproject.toml`, run `t update` and re-enter `nix develop` to pick them up.

## Next Steps

Now that Nix is installed and your first project is bootstrapped, continue with:

1. **[Getting Started with T](getting-started.md)** — understand the workspace layout and available commands.
2. **[Your First Pipeline](first-pipeline.md)** — declare R, Python, and Julia packages, run `t update`, and build a hello-world polyglot pipeline.
