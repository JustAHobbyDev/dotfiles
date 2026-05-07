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

# DOTFILES: honor the env var if already exported, otherwise derive it
# from this file's path. %x is zsh's "currently executing script" prompt
# expansion — $0 won't work here because zsh sets it to the shell name
# during startup, not to .zshrc.
export DOTFILES="${DOTFILES:-${${(%):-%x}:A:h:h}}"

# Shared shell helpers (bws, rbw-setup); also sourced by bash/.bashrc.
[ -f "$DOTFILES/lib/secrets.sh" ] && source "$DOTFILES/lib/secrets.sh"

# zoxide — provides `z` / `zi`. Static init script (a snapshot of
# `zoxide init zsh`) lives outside the stow tree to keep $HOME tidy.
[ -f "$DOTFILES/lib/zoxide.sh" ] && source "$DOTFILES/lib/zoxide.sh"
