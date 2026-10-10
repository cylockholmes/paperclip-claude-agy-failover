#!/usr/bin/env bash
# Copies the wrapper to ~/.paperclip/bin and makes it executable.
set -euo pipefail
dest="${PAPERCLIP_BIN_DIR:-$HOME/.paperclip/bin}"
mkdir -p "$dest"
install -m 755 "$(dirname "$0")/bin/claude-to-agy-acp-wrapper" "$dest/claude-to-agy-acp-wrapper"
echo "Installed to $dest/claude-to-agy-acp-wrapper"
echo "Next: set it as the agentCommand for your claude_local agents (see README)."
