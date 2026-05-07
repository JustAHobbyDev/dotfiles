# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc
### bling.sh source start
test -f /usr/share/ublue-os/bling/bling.sh && source /usr/share/ublue-os/bling/bling.sh
### bling.sh source end

### fzf CTRL-R history
eval "$(fzf --bash)"

export MOZ_ENABLE_WAYLAND=1

# DOTFILES: derive from this file's resolved path if not already set.
export DOTFILES="${DOTFILES:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)}"

# Shared shell helpers (bws, rbw-setup); also sourced by zsh/.zshrc.
[ -f "$DOTFILES/lib/secrets.sh" ] && source "$DOTFILES/lib/secrets.sh"
