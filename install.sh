#!/usr/bin/env bash
# Installers for tools without a clean apt/mise/uv path.
# Sourceable (defines functions only) and executable (runs `main`).
# Idempotent: each installer skips work when the target is already present.
set -euo pipefail

install_7zz() {
    local install_dir="$HOME/.local/bin"
    local target="$install_dir/7zz"

    if [ -x "$target" ]; then
        local current_version
        current_version=$("$target" 2>&1 | grep -m1 '^7-Zip' || echo "unknown")
        echo "7zz already installed: $current_version"
        return 0
    fi

    mkdir -p "$install_dir"

    # Detect architecture
    local arch
    case "$(uname -m)" in
        x86_64)   arch="x64" ;;
        aarch64)  arch="arm64" ;;
        *)        echo "ERROR: unsupported architecture $(uname -m)" >&2; return 1 ;;
    esac

    # Discover the linux-<arch>.tar.xz asset URL from the latest release JSON.
    # Avoids hardcoding 7zip's "version-without-dots" filename pattern.
    local download_url
    download_url=$(curl -fsSL "https://api.github.com/repos/ip7z/7zip/releases/latest" \
        | grep -oE '"browser_download_url": "[^"]*linux-'"$arch"'\.tar\.xz"' \
        | head -1 \
        | sed -E 's/.*"browser_download_url": "([^"]+)"/\1/')

    if [ -z "$download_url" ]; then
        echo "ERROR: could not resolve 7zip linux-$arch download URL" >&2
        return 1
    fi

    echo "Installing 7zz from $download_url"

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    if ! curl -fsSL -o "$tmpdir/7zz.tar.xz" "$download_url"; then
        echo "ERROR: download failed from $download_url" >&2
        return 1
    fi

    # Extract just the 7zz binary (archive root is flat: 7zz, 7zzs, MANUAL/, etc.)
    if ! tar -xJf "$tmpdir/7zz.tar.xz" -C "$tmpdir" 7zz; then
        echo "ERROR: tar extraction failed" >&2
        return 1
    fi

    install -m 0755 "$tmpdir/7zz" "$target"
    # Convenience symlink so existing `7z`-based muscle memory works
    ln -sf 7zz "$install_dir/7z"
    echo "7zz installed to $target ($("$target" 2>&1 | grep -m1 '^7-Zip'))"
}

install_bw() {
    local install_dir="$HOME/.local/bin"
    local target="$install_dir/bw"
    local sevenz="$install_dir/7zz"

    # Skip if already installed and reasonably recent
    if [ -x "$target" ]; then
        local current_version
        current_version=$("$target" --version 2>/dev/null || echo "unknown")
        echo "bw already installed: $current_version"
        return 0
    fi

    if [ ! -x "$sevenz" ]; then
        echo "ERROR: $sevenz not found — run install_7zz first" >&2
        return 1
    fi

    mkdir -p "$install_dir"

    # Resolve latest CLI release from GitHub API
    # The Bitwarden monorepo tags releases as "cli-vX.Y.Z" — filter for those
    local latest_tag
    latest_tag=$(curl -fsSL "https://api.github.com/repos/bitwarden/clients/releases" \
        | grep -oE '"tag_name": "cli-v[0-9.]+"' \
        | head -1 \
        | sed -E 's/.*"cli-v([0-9.]+)"/\1/')

    if [ -z "$latest_tag" ]; then
        echo "ERROR: could not resolve latest bw version" >&2
        return 1
    fi

    echo "Installing bw $latest_tag"

    # Detect architecture
    local arch
    case "$(uname -m)" in
        x86_64)   arch="linux" ;;
        aarch64)  arch="linux-arm64" ;;
        *)        echo "ERROR: unsupported architecture $(uname -m)" >&2; return 1 ;;
    esac

    local url="https://github.com/bitwarden/clients/releases/download/cli-v${latest_tag}/bw-${arch}-${latest_tag}.zip"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    # Download
    if ! curl -fsSL -o "$tmpdir/bw.zip" "$url"; then
        echo "ERROR: download failed from $url" >&2
        return 1
    fi

    # Extract using our own 7zz (-bso0/-bsp0/-y => quiet, no prompts)
    if ! "$sevenz" x -bso0 -bsp0 -y -o"$tmpdir" "$tmpdir/bw.zip" >/dev/null; then
        echo "ERROR: 7zz extraction failed" >&2
        return 1
    fi

    # Install
    install -m 0755 "$tmpdir/bw" "$target"
    echo "bw installed to $target ($("$target" --version))"
}

install_bws() {
    local install_dir="$HOME/.local/bin"
    local target="$install_dir/bws"
    local sevenz="$install_dir/7zz"

    if [ -x "$target" ]; then
        local current_version
        current_version=$("$target" --version 2>/dev/null || echo "unknown")
        echo "bws already installed: $current_version"
        return 0
    fi

    if [ ! -x "$sevenz" ]; then
        echo "ERROR: $sevenz not found — run install_7zz first" >&2
        return 1
    fi

    mkdir -p "$install_dir"

    # Resolve latest bws release from the bitwarden/sdk-sm monorepo.
    # That repo tags multiple products (rust-v*, python-v*, bws-v*, dotnet-v*);
    # filter for bws-v* specifically.
    local latest_tag
    latest_tag=$(curl -fsSL "https://api.github.com/repos/bitwarden/sdk-sm/releases" \
        | grep -oE '"tag_name": "bws-v[0-9.]+"' \
        | head -1 \
        | sed -E 's/.*"bws-v([0-9.]+)"/\1/')

    if [ -z "$latest_tag" ]; then
        echo "ERROR: could not resolve latest bws version" >&2
        return 1
    fi

    echo "Installing bws $latest_tag"

    # Detect architecture (Rust target triples)
    local arch
    case "$(uname -m)" in
        x86_64)   arch="x86_64-unknown-linux-gnu" ;;
        aarch64)  arch="aarch64-unknown-linux-gnu" ;;
        *)        echo "ERROR: unsupported architecture $(uname -m)" >&2; return 1 ;;
    esac

    local url="https://github.com/bitwarden/sdk-sm/releases/download/bws-v${latest_tag}/bws-${arch}-${latest_tag}.zip"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    if ! curl -fsSL -o "$tmpdir/bws.zip" "$url"; then
        echo "ERROR: download failed from $url" >&2
        return 1
    fi

    if ! "$sevenz" x -bso0 -bsp0 -y -o"$tmpdir" "$tmpdir/bws.zip" >/dev/null; then
        echo "ERROR: 7zz extraction failed" >&2
        return 1
    fi

    install -m 0755 "$tmpdir/bws" "$target"
    echo "bws installed to $target ($("$target" --version))"
}

install_rbw() {
    local install_dir="$HOME/.local/bin"
    local target="$install_dir/rbw"

    if [ -x "$target" ]; then
        local current_version
        current_version=$("$target" --version 2>/dev/null || echo "unknown")
        echo "rbw already installed: $current_version"
        return 0
    fi

    # Upstream ships linux_amd64 only. On other archs, suggest cargo install.
    case "$(uname -m)" in
        x86_64) ;;
        *) echo "ERROR: rbw upstream ships linux_amd64 only; no binary for $(uname -m)" >&2
           echo "       fallback: cargo install rbw" >&2
           return 1 ;;
    esac

    mkdir -p "$install_dir"

    # Tags are bare versions ("1.15.0"), no `v` prefix.
    local latest_tag
    latest_tag=$(curl -fsSL "https://api.github.com/repos/doy/rbw/releases/latest" \
        | grep -oE '"tag_name": "[0-9.]+"' \
        | head -1 \
        | sed -E 's/.*"([0-9.]+)"/\1/')

    if [ -z "$latest_tag" ]; then
        echo "ERROR: could not resolve latest rbw version" >&2
        return 1
    fi

    echo "Installing rbw $latest_tag"

    local url="https://github.com/doy/rbw/releases/download/${latest_tag}/rbw_${latest_tag}_linux_amd64.tar.gz"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    if ! curl -fsSL -o "$tmpdir/rbw.tar.gz" "$url"; then
        echo "ERROR: download failed from $url" >&2
        return 1
    fi

    # Tarball is flat: rbw, rbw-agent, completion/
    if ! tar -xzf "$tmpdir/rbw.tar.gz" -C "$tmpdir"; then
        echo "ERROR: tar extraction failed" >&2
        return 1
    fi

    install -m 0755 "$tmpdir/rbw"       "$target"
    install -m 0755 "$tmpdir/rbw-agent" "$install_dir/rbw-agent"
    echo "rbw installed to $target ($("$target" --version))"
}

install_unzip_guard() {
    local install_dir="$HOME/.local/bin"
    local target="$install_dir/unzip"

    # If our guard is already in place, nothing to do
    if [ -x "$target" ]; then
        echo "unzip guard already installed: $target"
        return 0
    fi

    # If a real unzip exists on PATH (e.g., apt-installed), don't shadow it
    if command -v unzip >/dev/null 2>&1; then
        echo "unzip already on PATH at $(command -v unzip) — guard not installed"
        return 0
    fi

    mkdir -p "$install_dir"
    cat > "$target" <<'EOF'
#!/usr/bin/env sh
# Guard script: redirects callers to 7zz instead of unzip.
# Managed by ~/dotfiles/install.sh — delete this file to disable the guard.
{
  echo "Use 7zz instead of unzip in this environment:"
  echo "  7zz x <archive.zip>     # extract preserving paths"
  echo "  7zz e <archive.zip>     # extract flat into cwd"
  echo "  7zz l <archive.zip>     # list contents"
  echo "(guard script at ~/.local/bin/unzip; managed by ~/dotfiles/install.sh)"
} >&2
exit 1
EOF
    chmod 0755 "$target"
    echo "unzip guard installed at $target"
}

main() {
    # Prerequisite check — keep error messages actionable for fresh-machine bootstrap
    local missing=()
    for cmd in curl tar xz; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        # Map binary names to apt package names where they differ
        local apt_pkgs=()
        for cmd in "${missing[@]}"; do
            case "$cmd" in
                xz) apt_pkgs+=("xz-utils") ;;
                *)  apt_pkgs+=("$cmd") ;;
            esac
        done
        echo "ERROR: missing prerequisites: ${missing[*]}" >&2
        echo "       on Debian/Ubuntu: sudo apt install -y ${apt_pkgs[*]}" >&2
        exit 1
    fi

    install_7zz
    install_bw
    install_bws
    install_rbw
    install_unzip_guard
}

# Run main only when executed directly; sourcing this file just defines functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
