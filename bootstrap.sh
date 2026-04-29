#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
stow -v zsh git tmux nvim mise
./install.sh
