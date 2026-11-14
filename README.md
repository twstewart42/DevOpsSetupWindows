# SYNOPSIS
Set up a Windows + WSL2 DevOps workstation in minutes, with a little help from Cowsay.

This project is heavily opinionated for what **I** want to install and manage. feel free to reuse and adjust for your own unique setup.

The same DevOps tools are installed **natively on Windows and inside WSL (Ubuntu 24.04)** from one file, [`config/mise.toml`](config/mise.toml), managed by [mise](https://mise.jdx.dev/). Python uses [uv](https://docs.astral.sh/uv/), containers use [podman](https://podman.io/) + Podman Desktop.

# Prerequisite
1. Install [Git for Windows](https://gitforwindows.org/)
2. Clone this repo

# Run
From the repo root in a user-level PowerShell:
```pwsh
PS> .\windows-setup.ps1
```
This installs mise, the AWS CLI, VS Code (with recommended extensions), Windows Terminal, Podman and Podman Desktop via winget,
installs the `config/mise.toml` tools natively on Windows (mise's shims directory, `%LOCALAPPDATA%\mise\shims`, is added to your
user PATH so they work in PowerShell, cmd and VS Code), sets up WSL2 + Ubuntu 24.04, then runs `wsl-setup.sh` inside WSL. Re-running is safe.

A few tools are limited to Linux with `os = ["linux", "macos"]` in `config/mise.toml`: ansible (no Windows control node)
and awscli (installed on Windows via winget instead).

On a machine without WSL, the first run installs it and stops: reboot if prompted, launch Ubuntu 24.04 once to create your Linux user, then run `.\windows-setup.ps1` again.

Inside an existing WSL Ubuntu you can run just `./wsl-setup.sh [git_name] [git_email]` as your normal user.

# Changing tool versions
Edit `config/mise.toml`, then:
```sh
mise install     # apply pinned versions
mise upgrade     # bump anything set to "latest"
```
If the repo is cloned inside WSL, `config/` files are symlinked into `~/.config`, so edits apply immediately.
If it lives on the Windows drive (`/mnt/c/...`), they are copied instead; re-run `./wsl-setup.sh` after editing them.
On Windows the config is copied to `~\.config\mise\config.toml`; re-run `.\windows-setup.ps1` after editing it.

# Global gitignore
Both setup scripts install [`config/gitignore_global`](config/gitignore_global) to `~/.config/git/ignore`
(Windows and WSL), git's default global excludes file, so every repo ignores `node_modules/`, `.venv/`,
Terraform state, `.env` files and editor/OS cruft. If you have a custom `core.excludesFile`, the scripts warn
because it overrides that path. Project-specific rules still belong in each repo's own `.gitignore`.


# Python with uv
```sh
uv init myproj && cd myproj
uv add requests
uv sync          # create/refresh .venv
uv run python main.py
```

# Containers
`windows-setup.ps1` installs Podman and [Podman Desktop](https://podman-desktop.io/) via winget, then creates and
starts a rootful Podman machine (`podman-machine-default`). `wsl-setup.sh` points Ubuntu's `podman` CLI at that
machine (`/mnt/wsl/podman-sockets/podman-machine-default/`), so containers you run from WSL show up in Podman Desktop.
If the machine isn't running when `wsl-setup.sh` runs, Ubuntu falls back to its own local podman; start the machine
and re-run `./wsl-setup.sh` to connect. `docker` runs `podman` via a shim in `~/.local/bin` (see [`bin/docker`](bin/docker)), so scripts and tools
that call `docker` work too, not just interactive shells.

If the machine is rootful (Podman Desktop's default), the script adds you to group 10 (`uucp`); open a new
WSL session afterwards. Check with `podman system connection list` and `podman run quay.io/podman/hello`.
