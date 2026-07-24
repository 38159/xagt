#!/usr/bin/env bash
# xagt installer — Linux and macOS, amd64 and arm64.
#
#   curl -o- https://raw.githubusercontent.com/38159/xagt/main/install.sh | bash
#
# Installs the prebuilt binary of the latest tag (or $XAGT_VERSION) into
# $XAGT_DIR/bin (default ~/.xagt/bin), seeds a config template, and adds the
# PATH/XAGT_CONFIG lines to your shell profile. Releases are binary-only.
set -euo pipefail

GITHUB_REPO="38159/xagt"
XAGT_DIR="${XAGT_DIR:-$HOME/.xagt}"

info() { printf 'xagt-install: %s\n' "$*"; }
fail() { printf 'xagt-install: error: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl is required"

# --- platform ---------------------------------------------------------------
case "$(uname -s)" in
  Linux)  OS=linux ;;
  Darwin) OS=darwin ;;
  *) fail "unsupported OS: $(uname -s) (linux and darwin only)" ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) fail "unsupported architecture: $(uname -m) (amd64 and arm64 only)" ;;
esac

# --- version: $XAGT_VERSION or the latest v* tag ----------------------------
VERSION="${XAGT_VERSION:-}"
if [ -z "$VERSION" ]; then
  if command -v git >/dev/null 2>&1; then
    VERSION=$(git ls-remote --tags --refs "https://github.com/$GITHUB_REPO.git" 'v*' \
      | awk -F/ '{print $NF}' | sort -V | tail -n1)
  else
    VERSION=$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/tags" \
      | grep -o '"name": *"v[^"]*"' | cut -d'"' -f4 | sort -V | tail -n1)
  fi
fi
[ -n "$VERSION" ] || fail "could not determine the latest version (set XAGT_VERSION=v0.0.1 to pin one)"

# --- already installed? offer update or remove ------------------------------
INSTALLED=""
if [ -x "$XAGT_DIR/bin/xagt" ]; then
  INSTALLED="$XAGT_DIR/bin/xagt"
elif command -v xagt >/dev/null 2>&1; then
  INSTALLED=$(command -v xagt)
fi

if [ -n "$INSTALLED" ]; then
  CURRENT=$("$INSTALLED" --version 2>/dev/null | awk '{print $2}')
  CURRENT="${CURRENT:-unknown}"
  if [ "$CURRENT" = "$VERSION" ]; then
    info "xagt $CURRENT at $INSTALLED is already the latest version"
  else
    info "xagt $CURRENT is already installed at $INSTALLED (latest: $VERSION)"
  fi
  # `curl | bash` leaves stdin holding the script, so the question is asked
  # on the terminal directly; without one, updating is the safe default.
  # [ -r /dev/tty ] passes even with no controlling terminal; actually
  # opening it is the reliable test.
  CHOICE=u
  if (exec < /dev/tty) 2>/dev/null; then
    printf 'xagt-install: [u]pdate to %s, [r]emove the installed version, or [q]uit? [u/r/q] ' "$VERSION" > /dev/tty
    read -r CHOICE < /dev/tty || CHOICE=q
    CHOICE=$(printf '%s' "$CHOICE" | tr '[:upper:]' '[:lower:]')
  else
    info "no terminal to ask on — updating to $VERSION"
  fi
  case "$CHOICE" in
    r)
      if [ -w "$INSTALLED" ] || [ -w "$(dirname "$INSTALLED")" ]; then
        rm -f "$INSTALLED"
      else
        sudo rm -f "$INSTALLED"
      fi
      info "removed $INSTALLED (config and $XAGT_DIR left untouched)"
      exit 0
      ;;
    u|'') ;;
    *) info "nothing done"; exit 0 ;;
  esac
  # An update goes to wherever the binary already lives, so a system-wide
  # install (e.g. /usr/local/bin) is updated in place rather than shadowed.
  case "$INSTALLED" in
    "$XAGT_DIR"/*) ;;
    *) BIN_OVERRIDE="$INSTALLED" ;;
  esac
fi

info "installing xagt $VERSION for $OS-$ARCH into ${BIN_OVERRIDE:-$XAGT_DIR/bin/xagt}"

# --- download the prebuilt binary, or build from source ---------------------
TARGET="${BIN_OVERRIDE:-$XAGT_DIR/bin/xagt}"
[ -n "${BIN_OVERRIDE:-}" ] || mkdir -p "$XAGT_DIR/bin"
TARBALL_URL="https://raw.githubusercontent.com/$GITHUB_REPO/$VERSION/dist/xagt-$OS-$ARCH.tar.gz"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$TARBALL_URL" -o "$TMP/xagt.tar.gz" \
  || fail "no prebuilt binary for $OS-$ARCH at $VERSION ($TARBALL_URL)"
tar -xzf "$TMP/xagt.tar.gz" -C "$TMP"
if [ -w "$(dirname "$TARGET")" ]; then
  install -m 755 "$TMP/xagt" "$TARGET"
else
  sudo install -m 755 "$TMP/xagt" "$TARGET"
fi

# --- config template (never overwrites an existing file) --------------------
# An in-place update of a system-wide install keeps its own config
# (/etc/xagt/xagt.toml) and PATH; only fresh $XAGT_DIR installs get wired up.
if [ -n "${BIN_OVERRIDE:-}" ]; then
  info "updated: $("$TARGET" --version) at $TARGET"
  exit 0
fi

CONFIG="$XAGT_DIR/xagt.toml"
if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" <<'EOF'
# xagt config — one [[agent]] table per OpenAI-compatible endpoint.
# provider openai/qwen/qwen-cn fills in apiurl; anything else needs apiurl.
# priority: "primary" answers first; a "secondary" is only asked on failure.

# per-call timeout, seconds (XAGT_TIMEOUT_SEC overrides)
timeout = 300

[[agent]]
name     = "my-gpt"
provider = "openai"
apikey   = "sk-REPLACE-ME"
model    = "gpt-4.1"
priority = "primary"

# [[agent]]
# name     = "qwen"
# provider = "qwen"
# apikey   = "sk-REPLACE-ME"
# model    = "qwen3.7-plus"
# priority = "secondary"
EOF
  chmod 600 "$CONFIG"
  info "seeded config template at $CONFIG — put your API keys there"
fi

# --- shell profile ----------------------------------------------------------
case "${SHELL:-}" in
  */zsh)  PROFILE="$HOME/.zshrc" ;;
  */bash) PROFILE="$HOME/.bashrc" ;;
  *)      PROFILE="$HOME/.profile" ;;
esac
if ! grep -qs 'XAGT_DIR' "$PROFILE"; then
  {
    printf '\n# xagt\n'
    printf 'export XAGT_DIR="%s"\n' "$XAGT_DIR"
    printf 'export PATH="$XAGT_DIR/bin:$PATH"\n'
    printf 'export XAGT_CONFIG="${XAGT_CONFIG:-$XAGT_DIR/xagt.toml}"\n'
  } >> "$PROFILE"
  info "added PATH and XAGT_CONFIG to $PROFILE"
fi

info "installed: $("$TARGET" --version) at $TARGET"
info "open a new shell (or 'source $PROFILE'), put your API key in $CONFIG, then:  xagt \"hello\""
info "later, 'xagt update' brings the installed binary to the latest release"
