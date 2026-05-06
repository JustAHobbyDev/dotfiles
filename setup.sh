#!/usr/bin/env bash
# One-line web-installable bootstrap for JustAHobbyDev/dotfiles.
#
#   curl -LsSf https://raw.githubusercontent.com/JustAHobbyDev/dotfiles/main/setup.sh | bash
#
# Idempotent: re-running skips phases whose effect is already in place.
# Distro-aware: dispatches on apt (Debian/Ubuntu) or brew (Aurora Linux,
# macOS-style); on hosts with neither, the system-package install moves
# to the final next-steps checklist.

set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/JustAHobbyDev/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
HAS_APT=0
HAS_BREW=0
NEXT_STEPS=()        # extra manual items collected when no system package manager is available

# ── output helpers ─────────────────────────────────────────────────────
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
step()   { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
skip()   { printf '    \033[33m↳ %s\033[0m\n' "$*"; }
ok()     { printf '    \033[32m✓ %s\033[0m\n' "$*"; }
note()   { printf '    %s\n' "$*"; }

# ── phases ─────────────────────────────────────────────────────────────
detect_platform() {
    step "Detecting platform"
    case "$(uname -s)" in
        Linux)  ok "Linux ($(uname -m))" ;;
        Darwin) ok "macOS ($(uname -m))" ;;
        *)      echo "Unsupported OS: $(uname -s). This script supports Linux + macOS." >&2; exit 1 ;;
    esac
    if command -v apt >/dev/null 2>&1; then
        HAS_APT=1
        ok "apt available — will run apt phases"
    fi
    if command -v brew >/dev/null 2>&1; then
        HAS_BREW=1
        ok "brew available — will run brew phases"
    fi
    if [ "$HAS_APT" -eq 0 ] && [ "$HAS_BREW" -eq 0 ]; then
        skip "no apt or brew — system-package phases will move to the next-steps checklist"
    fi
}

install_system_prereqs() {
    step "Installing base packages"
    local apt_pkgs="zsh stow tmux ripgrep curl git build-essential jq fd-find pandoc ffmpeg xz-utils keychain pinentry-curses"
    # Brew list omits ripgrep/fd/gh/zoxide because Aurora's `ujust aurora-cli`
    # already installs them (see README "Aurora Linux" prereq). Also omits
    # zsh/curl/git/build-essential — Aurora ships those in its base image.
    local brew_pkgs="stow tmux jq pandoc ffmpeg keychain xz pinentry"
    if [ "$HAS_APT" -eq 1 ]; then
        sudo apt update
        # shellcheck disable=SC2086
        sudo apt install -y $apt_pkgs
        ok "base packages installed via apt"
    elif [ "$HAS_BREW" -eq 1 ]; then
        # shellcheck disable=SC2086
        brew install $brew_pkgs
        ok "base packages installed via brew"
    else
        NEXT_STEPS+=("Install via your distro's package manager: $apt_pkgs")
        skip "no apt or brew — added to next-steps"
    fi
}

# Stow fallback: when apt/brew aren't available (or didn't ship stow),
# build it from the upstream GNU tarball into ~/.local. bootstrap.sh
# can't run without stow, so this is the last line of defense before
# the bootstrap phase. Verifies the .sig against the GNU keyring, so
# needs gpg + perl + make in the base image — true on Aurora and most
# distros.
install_stow_fallback() {
    step "Checking stow availability"
    if command -v stow >/dev/null 2>&1; then
        skip "stow already on PATH at $(command -v stow)"
        return
    fi
    if [ -x "$HOME/.local/bin/stow" ]; then
        skip "stow already installed at ~/.local/bin/stow"
        return
    fi

    # Default to GNU's `-latest` alias; honor STOW_VERSION for pinning.
    local slug="${STOW_VERSION:+stow-${STOW_VERSION}}"
    slug="${slug:-stow-latest}"
    local url="https://ftp.gnu.org/gnu/stow/${slug}.tar.gz"
    local sig_url="${url}.sig"
    local keyring_url="https://ftp.gnu.org/gnu/gnu-keyring.gpg"

    local missing=()
    for cmd in perl make gpg; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        NEXT_STEPS+=("Install stow manually (missing build/verify prereqs: ${missing[*]}): $url")
        skip "missing ${missing[*]} — added to next-steps"
        return
    fi

    note "no stow on PATH — building from $url (signature-verified)"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    if ! curl -fsSL -o "$tmpdir/stow.tar.gz" "$url"; then
        echo "ERROR: stow download failed from $url" >&2
        return 1
    fi
    if ! curl -fsSL -o "$tmpdir/stow.tar.gz.sig" "$sig_url"; then
        echo "ERROR: stow signature download failed from $sig_url" >&2
        return 1
    fi
    if ! curl -fsSL -o "$tmpdir/gnu-keyring.gpg" "$keyring_url"; then
        echo "ERROR: GNU keyring download failed from $keyring_url" >&2
        return 1
    fi

    # Isolate gpg state so verification doesn't touch the user's keyring.
    mkdir -p "$tmpdir/gnupg"
    chmod 700 "$tmpdir/gnupg"
    if ! GNUPGHOME="$tmpdir/gnupg" gpg --quiet --no-default-keyring \
            --keyring "$tmpdir/gnu-keyring.gpg" \
            --verify "$tmpdir/stow.tar.gz.sig" "$tmpdir/stow.tar.gz"; then
        echo "ERROR: stow signature verification failed — refusing to install" >&2
        return 1
    fi
    ok "signature verified against GNU keyring"

    # Resolve the actual version from the tarball's top-level directory
    # (e.g. "stow-2.4.1/") — `-latest` is a symlink to the current release.
    local extracted_dir
    extracted_dir=$(tar -tzf "$tmpdir/stow.tar.gz" | head -1 | cut -d/ -f1)
    if [ -z "$extracted_dir" ]; then
        echo "ERROR: could not determine stow tarball top-level directory" >&2
        return 1
    fi
    if ! tar -xzf "$tmpdir/stow.tar.gz" -C "$tmpdir"; then
        echo "ERROR: stow tar extraction failed" >&2
        return 1
    fi
    (
        cd "$tmpdir/$extracted_dir"
        ./configure --prefix="$HOME/.local" >/dev/null
        make >/dev/null
        make install >/dev/null
    )
    ok "$extracted_dir installed to ~/.local/bin/stow"
}

install_omz() {
    step "Installing oh-my-zsh"
    if [ -d "$HOME/.oh-my-zsh" ]; then
        skip "already installed at ~/.oh-my-zsh"
        return
    fi
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended --keep-zshrc
    ok "oh-my-zsh installed"
}

install_omz_plugins() {
    step "Installing zsh plugins"
    local plugins_dir="$HOME/.oh-my-zsh/custom/plugins"
    mkdir -p "$plugins_dir"
    for repo in zsh-autosuggestions zsh-syntax-highlighting; do
        if [ -d "$plugins_dir/$repo" ]; then
            skip "$repo already cloned"
        else
            git clone --depth=1 "https://github.com/zsh-users/$repo" "$plugins_dir/$repo"
            ok "$repo cloned"
        fi
    done
}

install_mise() {
    step "Installing mise"
    if command -v mise >/dev/null 2>&1 || [ -x "$HOME/.local/bin/mise" ]; then
        skip "already on PATH or in ~/.local/bin"
        return
    fi
    curl -fsSL https://mise.run | sh
    ok "mise installed"
}

install_uv() {
    step "Installing uv"
    if command -v uv >/dev/null 2>&1 || [ -x "$HOME/.local/bin/uv" ]; then
        skip "already on PATH or in ~/.local/bin"
        return
    fi
    curl -LsSf https://astral.sh/uv/install.sh | sh
    ok "uv installed"
}

clone_dotfiles() {
    step "Cloning dotfiles to $DOTFILES_DIR"
    if [ -d "$DOTFILES_DIR/.git" ]; then
        local existing
        existing=$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || echo "(no origin)")
        skip "$DOTFILES_DIR is already a git repo (origin: $existing)"
        return
    fi
    if [ -e "$DOTFILES_DIR" ]; then
        echo "ERROR: $DOTFILES_DIR exists and is not a git repo. Move it aside and retry." >&2
        exit 1
    fi
    git clone --depth=1 "$REPO_URL" "$DOTFILES_DIR"
    ok "cloned"
}

backup_pre_stow() {
    step "Backing up files that would block stow"
    local moved=0
    for f in "$HOME/.zshrc" "$HOME/.gitconfig" "$HOME/.tmux.conf" "$HOME/.config/mise/config.toml"; do
        if [ -e "$f" ] && [ ! -L "$f" ]; then
            mv "$f" "$f.pre-stow.bak"
            ok "backed up $f → $f.pre-stow.bak"
            moved=1
        fi
    done
    [ "$moved" -eq 0 ] && skip "nothing to back up"
}

run_bootstrap() {
    step "Running bootstrap.sh (stow + install.sh)"
    # Prepend ~/.local/bin so a fallback-installed stow is on PATH for bootstrap.sh.
    ( cd "$DOTFILES_DIR" && PATH="$HOME/.local/bin:$PATH" ./bootstrap.sh )
    ok "bootstrap done"
}

mise_install_pinned() {
    step "Installing pinned toolchains via mise"
    if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
        skip "mise not available — toolchains will install on first interactive shell"
        return
    fi
    PATH="$HOME/.local/bin:$PATH" mise install
    ok "toolchains installed"
}

# Kept even after the brew dispatch above: this function early-returns when
# `gh` is already on PATH, so it's a silent no-op on Aurora (where
# `ujust aurora-cli` has already installed gh) and on macOS (where brew
# installed it). Removing the apt path would break the Debian/Ubuntu
# fallback for no functional gain.
install_gh_apt_repo() {
    step "Installing gh (GitHub CLI)"
    if command -v gh >/dev/null 2>&1; then
        skip "gh already installed"
        return
    fi
    if [ "$HAS_APT" -ne 1 ]; then
        NEXT_STEPS+=("Install gh via your platform: https://cli.github.com/manual/installation")
        skip "no apt — gh added to next-steps"
        return
    fi
    sudo mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt update
    sudo apt install -y gh
    ok "gh installed"
}

prompt_for_identity() {
    step "Configuring git identity"
    local local_cfg="$HOME/.config/git/config.local"
    if [ -f "$local_cfg" ]; then
        skip "$local_cfg already exists (delete it to re-prompt)"
        return
    fi
    if [ ! -e /dev/tty ]; then
        skip "no /dev/tty available — will list as next-step"
        NEXT_STEPS+=("Create ~/.config/git/config.local with [user] name/email/signingkey (mode 600)")
        return
    fi
    note "Identity will be saved to ~/.config/git/config.local (mode 600), not committed."
    local name email signingkey
    read -rp "    Git user.name:        " name        </dev/tty
    read -rp "    Git user.email:       " email       </dev/tty
    read -rp "    SSH signingkey path (blank = no signing): " signingkey </dev/tty

    mkdir -p "$HOME/.config/git"
    chmod 700 "$HOME/.config/git"
    {
        echo "[user]"
        echo "    name = $name"
        echo "    email = $email"
        if [ -n "$signingkey" ]; then
            echo "    signingkey = $signingkey"
        fi
    } > "$local_cfg"
    chmod 600 "$local_cfg"
    ok "wrote $local_cfg"
}

print_next_steps() {
    step "Remaining manual steps"
    cat <<'CHECKLIST'

    1) Authenticate with GitHub:
         gh auth login

    2) Make zsh your default shell (prompts for password):
         chsh -s "$(command -v zsh)"
         (then log out and back in)

    3) (Optional, for verified commits) generate an SSH signing key:
         ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_signing -C "<your-email>"
         gh auth refresh -s admin:ssh_signing_key
         gh ssh-key add ~/.ssh/id_ed25519_signing.pub --type signing --title "$(hostname)-signing"
         # local verification (optional):
         printf '%s namespaces="git" %s\n' \
             "$(git config --get user.email)" \
             "$(cat ~/.ssh/id_ed25519_signing.pub)" \
             > ~/.config/git/allowed_signers
         chmod 600 ~/.config/git/allowed_signers

CHECKLIST
    if [ "${#NEXT_STEPS[@]}" -gt 0 ]; then
        echo "    4) Manual installs your distro needs (no apt/brew detected):"
        for s in "${NEXT_STEPS[@]}"; do
            echo "       • $s"
        done
        echo
    fi
    cat <<'VERIFY'
    Verify:
         exec zsh
         command -v mise nvim uv just fd jq gh

VERIFY
}

main() {
    bold "Bootstrapping dotfiles from $REPO_URL"
    detect_platform
    install_system_prereqs
    install_stow_fallback
    install_omz
    install_omz_plugins
    install_mise
    install_uv
    clone_dotfiles
    backup_pre_stow
    run_bootstrap
    mise_install_pinned
    install_gh_apt_repo
    prompt_for_identity
    print_next_steps
}

main "$@"
