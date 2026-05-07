# ssh-agent persistence via keychain. Sourced by zsh/.zshrc and bash/.bashrc.
# Keeps one ssh-agent alive across shells/tmux sessions per machine boot.
# Prompts once for the signing key passphrase per boot; silent thereafter.
# Guard: no-ops if keychain isn't installed, so fresh-box bootstrap doesn't fail.

if command -v keychain >/dev/null && [ -f "$HOME/.ssh/id_ed25519_signing" ]; then
    eval "$(keychain --eval --quiet "$HOME/.ssh/id_ed25519_signing")"
fi
