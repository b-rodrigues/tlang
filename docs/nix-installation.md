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

## Configuring Trusted Users

Nix restricts certain operations (like using binary caches) to "trusted users." If
you see warnings like `ignoring untrusted substituter` when running `nix shell` or
`nix develop`, you need to add yourself as a trusted user.

### Linux (Ubuntu, Debian)

```bash
sudo nano /etc/nix/nix.conf
```

Add your username to the `trusted-users` line:

```text
trusted-users = root your_username
```

Restart the Nix daemon:

```bash
sudo systemctl restart nix-daemon.service
```

> [!NOTE]
> If you used the Determinate Systems installer, the daemon is managed by systemd. If
> `nix-daemon.service` is not found, try `sudo determinate-nixd restart` or check
> available units with `systemctl list-units | grep nix`.

### Linux (Fedora, RHEL, CentOS)

```bash
sudo nano /etc/nix/nix.conf
# Add: trusted-users = root your_username
sudo systemctl restart nix-daemon.service
```

If `nix-daemon.service` is not found, try `sudo systemctl restart nix`.

### Linux (Arch, Manjaro)

```bash
sudo nano /etc/nix/nix.conf
# Add: trusted-users = root your_username
sudo systemctl restart nix-daemon.service
```

### macOS

```bash
echo "trusted-users = root $USER" | sudo tee -a /etc/nix/nix.custom.conf
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

This works for both the standard installer and the Determinate Systems installer.

### NixOS

On NixOS, add the following to your `configuration.nix`:

```nix
nix.trustedUsers = [ "root" "your_username" ];
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

### Windows (WSL2)

Inside your WSL2 terminal, follow the Linux instructions above for your WSL2 distribution (usually Ubuntu). After editing `nix.conf`, restart the daemon:

```bash
sudo systemctl restart nix-daemon.service
```

> [!NOTE]
> If systemd is not enabled in your WSL2 setup, you need to enable it first. See the
> [Windows (WSL2)](#windows-wsl2) section above.

---

## Binary Caches (Cachix)

To avoid building everything from source, we recommend configuring binary caches.

### Automatic Support in T Projects

When you initialize a T project (using `t init`), the generated `flake.nix` automatically includes the `rstats-on-nix` binary cache. This means that for project-specific operations, Nix will automatically attempt to fetch pre-built binaries.

### Global Configuration (Recommended)

To benefit from the binary cache even outside of T projects (e.g., when running `nix shell --accept-flake-config github:b-rodrigues/tlang`), you can configure the cache globally in your system's `nix.conf`:

```text
substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=
```

> [!NOTE]
> If you used the Determinate Systems installer, you should add these to `/etc/nix/nix.conf`. You may need `sudo` to edit this file.

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
See [Configuring Trusted Users](#configuring-trusted-users) above.

## Next Steps

Now that Nix is installed, you are ready to [Get Started with T](getting-started.md)!
