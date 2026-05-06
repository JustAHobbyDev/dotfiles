# dotfiles

Daniel's portable shell + tooling config, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Quickstart

```
curl -LsSf https://raw.githubusercontent.com/JustAHobbyDev/dotfiles/main/setup.sh | bash
```

The one-liner runs the deterministic, machine-shaped work — system packages (apt on Debian/Ubuntu, brew on Aurora Linux), oh-my-zsh + plugins, mise, uv, this repo cloned + stowed, `install.sh` binaries, gh apt repo. It then prompts for your git identity and saves it to `~/.config/git/config.local` (mode 600, intentionally outside this repo).

When it finishes, it prints a short checklist of items that need user-specific input or password prompts: `gh auth login`, `chsh -s zsh`, and SSH signing-key generation + upload.

The script is idempotent — re-running it on the same machine reports each phase as already-in-place. On systems with neither apt nor brew (e.g. minimal Fedora/Arch installs without Homebrew), the system-package install moves to the final checklist so the same one-liner still does what it can.

Override the source via env vars: `DOTFILES_REPO=…` (a fork URL) or `DOTFILES_DIR=…` (a non-default install path).

### Aurora Linux prereq

Before the curl-pipe one-liner, run Aurora's curated CLI bundle so the bootstrap can rely on `rg`, `fd`, `gh`, `zoxide`, etc. being on PATH:

```
ujust devmode      # add developer tools layer
ujust dx-group     # add yourself to docker/libvirt groups
ujust aurora-cli   # curated brew bundle: rg, fd, gh, zoxide, …
```

Reboot or log out/in for the group changes to apply, then run `setup.sh`.

## Layout

```
~/dotfiles/
├── bootstrap.sh          # stow packages + run install.sh
├── install.sh            # install non-apt/mise/uv binaries (currently: bw)
├── git/
│   └── .gitconfig        # SSH-signed commits, sane defaults, aliases
├── mise/.config/mise/
│   └── config.toml       # node, neovim, just (managed by mise)
├── nvim/                 # (empty — config planned)
├── tmux/
│   └── .tmux.conf        # Ctrl-Space prefix, true color, minimal status bar
└── zsh/
    └── .zshrc            # oh-my-zsh + plugins + PATH + mise activate
```

Each top-level dir is a **stow package**. Files inside mirror their target location relative to `$HOME`. Stow creates the symlinks; never write or edit configs directly in `~`.

## Manual procedure (alternative to Quickstart)

If you'd rather run each step by hand than trust the one-liner. Tested on Ubuntu 24.04 and Aurora Linux; should work on most Debian-family distros and any system with Homebrew.

1. **Base packages**:
   - Debian/Ubuntu (apt):
     ```
     sudo apt update
     sudo apt install -y zsh stow tmux ripgrep curl git build-essential \
         jq fd-find pandoc ffmpeg xz-utils keychain pinentry-curses
     ```
   - Aurora Linux (after `ujust aurora-cli` — see Quickstart prereq):
     ```
     brew install stow tmux jq pandoc ffmpeg keychain xz pinentry
     ```
     `aurora-cli` already installed `rg`, `fd`, `gh`, `zoxide`; the base image ships `zsh`, `curl`, `git`, `gcc`/`make`.

2. **oh-my-zsh** (unattended; doesn't change shell or replace `.zshrc`):
   ```
   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
   ```

3. **zsh plugins**:
   ```
   git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
   git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
   ```

4. **Clone this repo and stow**:
   ```
   git clone https://github.com/JustAHobbyDev/dotfiles ~/dotfiles
   # back up any pre-existing files that would block stow:
   for f in ~/.zshrc ~/.gitconfig ~/.tmux.conf ~/.config/mise/config.toml; do
     [ -e "$f" ] && [ ! -L "$f" ] && mv "$f" "$f.pre-stow.bak"
   done
   cd ~/dotfiles && ./bootstrap.sh   # stows packages, then runs install.sh
   ```

5. **mise** (needed for the toolchains in `mise/.config/mise/config.toml`):
   ```
   curl https://mise.run | sh
   mise install   # reads stowed config; installs node, neovim, just
   ```

6. **uv** (Astral):
   ```
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

7. **gh** (official GitHub apt repo):
   ```
   sudo mkdir -p -m 755 /etc/apt/keyrings
   wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
     | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
   sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
     | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
   sudo apt update && sudo apt install -y gh
   gh auth login
   ```

8. **Switch to zsh** and verify:
   ```
   chsh -s "$(command -v zsh)"   # log out + back in to take effect
   exec zsh
   command -v mise nvim uv just fd jq gh
   ```

## Adding a new tool's config

```
mkdir -p ~/dotfiles/<tool>
# put files inside, mirroring their location under $HOME
# e.g. ~/.tmux.conf → ~/dotfiles/tmux/.tmux.conf
cd ~/dotfiles && stow -v <tool>
```

Add `<tool>` to `bootstrap.sh`'s stow list so future fresh-machine bootstraps include it.

## Notes

- Python is managed by `uv`, not mise — by intentional preference.
- `fd` is aliased to `fdfind` in `.zshrc` (Debian renames the binary). On distros that ship `fd` directly, the alias no-ops.
- mise uses *activate* mode (not shims) — `eval "$(mise activate zsh)"` adds active versions' `bin/` directly to PATH.
- `install.sh` covers binaries that don't have a clean apt/mise/uv path (currently 7zip's `7zz`, Bitwarden's `bw`, Bitwarden Secrets Manager's `bws`, and `rbw` — a faster Rust Bitwarden client). It pulls each from the upstream GitHub releases into `~/.local/bin`. It's idempotent — re-runs skip already-installed tools. Source it (`source install.sh`) to get the installer functions without running them.
- `7zz` is installed first because `bw`'s release ships as a `.zip`, which `7zz` extracts. The 7zip tarball itself is `.tar.xz` and bootstraps via `tar -xJf` (no 7z required).
- `install.sh` also drops an `unzip` guard script at `~/.local/bin/unzip` when no real unzip is on PATH. It prints a redirect to `7zz` and exits non-zero so scripts and agents that reach for `unzip` notice and adapt. (`~/dotfiles/zsh/.zshrc` has a matching alias for interactive zsh — together they cover both interactive and non-interactive callers.)

## Roadmap: portability of apt-installed tools

The bootstrap now dispatches on `apt` (Debian/Ubuntu) or `brew` (Aurora Linux), which removes the single-package-manager assumption — any host with one of those gets a clean install. Long-term direction is still to shrink even the system-package list and lean more on distro-agnostic sources.

Likely paths, in rough order of suitability:

1. **`mise`** — already used for `node`, `neovim`, `just`. It has plugins for `ripgrep`, `fd`, `jq`, `gh`, `pandoc`, `ffmpeg` and many more; pinning everything in `~/dotfiles/mise/.config/mise/config.toml` makes the toolchain reproducible cross-distro. Also resolves the brew-vs-apt-vs-aurora-cli "who installs `zoxide`" question — mise's `activate` mode prepends mise-managed bins to PATH, so its version wins regardless of what brew or apt also installed.
2. **`install.sh` (this repo)** — for tools without a mise plugin or where we want full control of the binary, follow the `7zz`/`bw` pattern: pull the upstream GitHub release into `~/.local/bin`. Good fit for `keychain` if no mise plugin emerges.
3. **`apt`/`brew` (residual)** — keep only for things that genuinely need to be system-installed (e.g. `zsh`, `stow`, `build-essential`, `xz-utils`, `curl`). These should shrink to the minimum a fresh box needs to bootstrap the rest.

No timeline; this is a north star for incremental moves, not a single migration. Each transition should land independently, with the apt/brew step removed from the README's bootstrap sequence in the same change.
