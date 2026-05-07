export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

# PATH (uv, user-installed binaries land in ~/.local/bin)
export PATH="$HOME/.local/bin:$PATH"

# mise — toolchain manager (must come after PATH)
eval "$(mise activate zsh)"

# ── ssh-agent persistence via keychain ──────────────────────────────────
# Keeps one ssh-agent alive across shells/tmux sessions per machine boot.
# Prompts once for the signing key passphrase per boot; silent thereafter.
# Guard: no-ops if keychain isn't installed, so fresh-box bootstrap doesn't fail.
if command -v keychain >/dev/null && [ -f "$HOME/.ssh/id_ed25519_signing" ]; then
    eval "$(keychain --eval --quiet --agents ssh "$HOME/.ssh/id_ed25519_signing")"
fi

# ── Bitwarden secrets via rbw ───────────────────────────────────────────
# bws: wrap the `bws` binary so BWS_ACCESS_TOKEN comes from the rbw vault
# (item name `bws-access-token`) instead of being persisted to disk. Cached
# per shell to avoid hitting the rbw agent on every call. Requires rbw to
# be unlocked (`rbw unlock`).
bws() {
    if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
        BWS_ACCESS_TOKEN="$(rbw get bws-access-token)" || return 1
        export BWS_ACCESS_TOKEN
    fi
    command bws "$@"
}

# rbw-setup: configure rbw (faster Rust Bitwarden client with an unlock agent).
# Idempotent. Pulls the email from `bw status` if bw is already logged in;
# otherwise prompts. Picks the most reliable pinentry available for headless
# / tmux contexts. Stops short of `rbw login` / `rbw unlock` — those are
# interactive and worth running by hand once.
rbw-setup() {
    command -v rbw >/dev/null || { echo "rbw not on PATH (run install.sh)" >&2; return 1; }
    command -v jq  >/dev/null || { echo "jq not on PATH" >&2; return 1; }

    local email
    if command -v bw >/dev/null; then
        email=$(bw status 2>/dev/null | jq -r '.userEmail // empty')
    fi
    if [ -z "$email" ]; then
        read -rp "Bitwarden email: " email
    fi
    [ -n "$email" ] || { echo "no email provided" >&2; return 1; }

    rbw config set email "$email"

    # Prefer curses (works over SSH/tmux); fall back to tty.
    if command -v pinentry-curses >/dev/null; then
        rbw config set pinentry pinentry-curses
    elif command -v pinentry-tty >/dev/null; then
        rbw config set pinentry pinentry-tty
    else
        echo "WARN: no pinentry-curses/-tty on PATH" >&2
        echo "      sudo apt install pinentry-curses   # or pinentry-tty" >&2
    fi

    cat <<'NEXT'
rbw configured. To finish setup interactively (one-time):
  rbw login    # auth with Bitwarden, prompts for password
  rbw unlock   # starts rbw-agent; subsequent reads are near-instant
Then verify:
  rbw get 'bws-access-token' >/dev/null && echo OK
NEXT
}

# DOTFILES: honor the env var if already exported, otherwise derive it
# from this file's path. %x is zsh's "currently executing script" prompt
# expansion — $0 won't work here because zsh sets it to the shell name
# during startup, not to .zshrc.
export DOTFILES="${DOTFILES:-${${(%):-%x}:A:h:h}}"

# zoxide — provides `z` / `zi`. Static init script (a snapshot of
# `zoxide init zsh`) lives outside the stow tree to keep $HOME tidy.
[ -f "$DOTFILES/lib/zoxide.sh" ] && source "$DOTFILES/lib/zoxide.sh"
