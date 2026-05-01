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

# zoxide — smarter `cd`; provides `z` / `zi`. Guard so fresh boxes pre-mise-install don't error.
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# fd-find shim: Debian/Ubuntu install the binary as `fdfind`.
# On other distros where it's already `fd`, this no-ops.
command -v fdfind >/dev/null && alias fd=fdfind

# unzip guard: this environment uses 7zz (installed by ~/dotfiles/install.sh)
# for zip extraction. The alias prints a redirect and returns non-zero so any
# script or agent that reaches for `unzip` notices and adapts.
alias unzip='printf "%s\n" \
  "Use 7zz instead of unzip in this environment:" \
  "  7zz x <archive.zip>     # extract preserving paths" \
  "  7zz e <archive.zip>     # extract flat into cwd" \
  "  7zz l <archive.zip>     # list contents" \
  "(this guard is set in ~/dotfiles/zsh/.zshrc)" >&2; false'

# ── ssh-agent persistence via keychain ──────────────────────────────────
# Keeps one ssh-agent alive across shells/tmux sessions per machine boot.
# Prompts once for the signing key passphrase per boot; silent thereafter.
# Guard: no-ops if keychain isn't installed, so fresh-box bootstrap doesn't fail.
if command -v keychain >/dev/null && [ -f "$HOME/.ssh/id_ed25519_signing" ]; then
    eval "$(keychain --eval --quiet --agents ssh "$HOME/.ssh/id_ed25519_signing")"
fi

# ── Bitwarden CLI session helpers ───────────────────────────────────────
# Auto-source persisted session if present (e.g., new pane in an existing tmux session)
[ -f "$HOME/.config/bw/session.env" ] && source "$HOME/.config/bw/session.env"

# bw-login: detect state via `bw status`, route to login/unlock/refresh,
# persist BW_SESSION to ~/.config/bw/session.env (mode 600), export in shell.
# Never prints the key itself.
bw-login() {
    local status_json key state dir="$HOME/.config/bw"

    command -v bw >/dev/null || { echo "bw not on PATH" >&2; return 1; }
    command -v jq >/dev/null || { echo "jq not on PATH" >&2; return 1; }

    status_json=$(bw status 2>/dev/null) || { echo "bw status failed" >&2; return 1; }
    state=$(printf '%s' "$status_json" | jq -r '.status')

    case "$state" in
        unauthenticated) key=$(bw login --raw)  || return 1 ;;
        locked)          key=$(bw unlock --raw) || return 1 ;;
        unlocked)
            if [ -z "${BW_SESSION:-}" ]; then
                echo "bw is unlocked but BW_SESSION is not set in this shell." >&2
                echo "Run: bw lock && bw-login   (or open a new shell to auto-source)" >&2
                return 1
            fi
            key="$BW_SESSION"
            ;;
        *) echo "unexpected bw state: $state" >&2; return 1 ;;
    esac

    [ -n "$key" ] || { echo "no session key returned" >&2; return 1; }

    mkdir -p "$dir"
    chmod 700 "$dir"
    ( umask 077; printf 'export BW_SESSION=%q\n' "$key" > "$dir/session.env" )
    chmod 600 "$dir/session.env"

    export BW_SESSION="$key"
    echo "bw session persisted to $dir/session.env (mode 600); BW_SESSION exported"
}

# bw-logout: revoke server-side, remove env file, unset env var
bw-logout() {
    bw logout 2>/dev/null || true
    unset BW_SESSION
    rm -f "$HOME/.config/bw/session.env"
    echo "bw session revoked, env file removed, BW_SESSION unset"
}

# bws-run: fetch the BWS access token from the bw vault (item name
# `bws-access-token`), scope it to a single `bws run` invocation, and exec
# the given command with project secrets injected as env vars.
# Requires bw to be unlocked (BW_SESSION set — run `bw-login` first).
bws-run() {
    if [ -z "$1" ]; then
        echo "usage: bws-run <project-id> <command...>" >&2
        return 1
    fi

    if [ -z "$BW_SESSION" ]; then
        echo "BW_SESSION not set. Run: export BW_SESSION=\$(bw unlock --raw)" >&2
        return 1
    fi

    local project_id="$1"
    shift

    BWS_ACCESS_TOKEN="$(bw get password 'bws-access-token')" \
        bws run --project-id "$project_id" -- "$@"
}

# Unlock vault and export session token for current shell
bw-unlock() {
  export BW_SESSION="$(bw unlock --raw)"
}

# Lock vault and clear session token
bw-lock() {
  bw lock >/dev/null 2>&1
  unset BW_SESSION
}

