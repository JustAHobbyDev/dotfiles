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

# bw-logout: revoke server-side, remove env file, unset env vars
bw-logout() {
    bw logout 2>/dev/null || true
    unset BW_SESSION BWS_ACCESS_TOKEN
    rm -f "$HOME/.config/bw/session.env"
    echo "bw session revoked, env file removed, BW_SESSION/BWS_ACCESS_TOKEN unset"
}

# bws: wrap the bws binary so the BWS_ACCESS_TOKEN comes from the bw vault
# (item name `bws-access-token`) instead of being persisted to disk. The
# token is fetched once per shell, cached in the env, and cleared by
# bw-lock / bw-logout. Hitting the bw CLI on every call is too slow.
# Requires bw to be unlocked (BW_SESSION set — run `bw-unlock` first).
bws() {
    if [ -z "$BW_SESSION" ]; then
        echo "BW_SESSION not set. Run: bw-unlock" >&2
        return 1
    fi
    if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
        BWS_ACCESS_TOKEN="$(bw get password 'bws-access-token')" || return 1
        export BWS_ACCESS_TOKEN
    fi
    command bws "$@"
}

# Unlock vault and export session token for current shell
bw-unlock() {
  export BW_SESSION="$(bw unlock --raw)"
}

# Lock vault and clear session token (also clears any cached BWS_ACCESS_TOKEN)
bw-lock() {
  bw lock >/dev/null 2>&1
  unset BW_SESSION BWS_ACCESS_TOKEN
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

alias clip='iconv -f UTF-8 -t UTF-16LE | clip.exe'

# zoxide — provides `z` / `zi`. Static init script in this same dir
# (avoids the per-shell `eval "$(zoxide init zsh)"` cost). Resolved via
# .zshrc's own location so it works regardless of PWD at shell start.
[ -f "${0:A:h}/zoxide.sh" ] && source "${0:A:h}/zoxide.sh"
