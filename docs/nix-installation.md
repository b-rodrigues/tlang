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
     sh -s -- install
```

---

## Operating System Specific Notes

### Linux

The command above works on most modern Linux distributions (Ubuntu, Fedora, Debian, Arch, etc.).

> [!TIP]
> **Disk Space**: Nix stores everything in `/nix`. If your root partition is small, you might want to mount `/nix` on a larger partition.

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

T requires **Nix Flakes** to be enabled. The Determinate Systems installer usually enables these by default. You can verify by checking `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`. It should contain:

```text
experimental-features = nix-command flakes
```

If it's missing, add it with:

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

---

## Binary Caches (Cachix)

To avoid building everything from source, we recommend configuring binary caches.

### Automatic Support in T Projects

When you initialize a T project (using `t init`), the generated `flake.nix` automatically includes the `rstats-on-nix` binary cache. This means that for project-specific operations, Nix will automatically attempt to fetch pre-built binaries.

### Global Configuration (Recommended)

To benefit from the binary cache even outside of T projects (e.g., when running `nix shell github:b-rodrigues/tlang`), you can configure the cache globally in your system's `nix.conf`:

```text
substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=
```

> [!NOTE]
> If you used the Determinate Systems installer, you should add these to `/etc/nix/nix.conf`. You may need `sudo` to edit this file.

---

## Nix and Docker

Nix and Docker are often seen as alternatives, but they work exceptionally well together. While Docker manages container isolation, Nix handles the environment reproducibility *inside* or *for* those containers.

### 1. Using Nix Inside Docker

You might want to install Nix inside a Docker container for CI/CD pipelines (like GitHub Actions) or to serve applications with a strictly defined environment.

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

### 2. Building Docker Images with Nix

Instead of writing a `Dockerfile`, you can use Nix to **build** a Docker image. This is the ultimate way to achieve reproducibility, as Nix builds the entire image layer by layer from its own store, resulting in extremely lightweight and predictable images.

A simple Nix expression to build a T application image might look like this:

```nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.dockerTools.buildImage {
  name = "t-analysis-app";
  tag = "latest";
  
  # Include T and any other required tools
  contents = [ pkgs.tlang pkgs.bashInteractive ];
  
  config = {
    Cmd = [ "t" "run" "scripts/pipeline.t" ];
    WorkingDir = "/my-project";
  };
}
```

You can build this image by running `nix-build docker.nix` and then load it into Docker with `docker load < result`.

---

## Troubleshooting

### "command not found: nix"
The installer usually updates your shell profile. Try restarting your terminal or running:
```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### Permission Denied
If you encounter permission issues when using Nix, ensure your user is in the `trusted-users` list in `/etc/nix/nix.conf`:
```text
trusted-users = root @wheel your_username
```

## Next Steps

Now that Nix is installed, you are ready to [Get Started with T](getting-started.md)!
