# Claude Code bash environment (non-login, non-interactive shell)
# This file is the ONLY profile loaded via $BASH_ENV.
# Keep it in sync with ~/.profile and ~/.config/fish/config.fish.

# Source ~/.cargo/env for Rust toolchain (same as login shell)
if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi

# bun global installs
if [ -d "$HOME/.bun/bin" ]; then
  export PATH="$HOME/.bun/bin:$PATH"
fi

# user local bin
if [ -d "$HOME/.local/bin" ]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# pnpm global bin (managed via dotfiles; mirror this in interactive shell rc)
export PNPM_HOME="$HOME/.local/share/pnpm"
if [ -d "$PNPM_HOME" ]; then
  case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
  esac
fi

# mise (shims mode for non-interactive)
if [ -x /usr/bin/mise ]; then
  eval "$(mise activate bash --shims)"
fi

# for Playwright tests
export DBUS_SESSION_BUS_ADDRESS=/dev/null
