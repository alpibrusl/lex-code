#!/usr/bin/env bash
# lex-code — one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/alpibrusl/lex-code/main/install.sh | bash
#
# Installs the pinned Lex toolchain (only if `lex` isn't already on PATH —
# an existing install is trusted as-is, never silently replaced), fetches
# lex-code's own package dependencies (lex-llm, lex-agent, ...), and
# installs the `lex-code` binary via the repo's own `make install`. Safe
# to re-run; nothing it does is destructive.
#
# Override the install prefix (default /usr/local, same as `make install`):
#   LEX_CODE_PREFIX=~/.local curl -fsSL .../install.sh | bash

set -euo pipefail

REPO="https://github.com/alpibrusl/lex-code"
PREFIX="${LEX_CODE_PREFIX:-/usr/local}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

command -v git  >/dev/null 2>&1 || die "git is required"
command -v make >/dev/null 2>&1 || die "make is required"
command -v curl >/dev/null 2>&1 || die "curl is required"

# ── platform → lex-lang release target triple ────────────────────────────────
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Darwin) plat_os="apple-darwin" ;;
  Linux)  plat_os="unknown-linux-gnu" ;;
  *) die "unsupported OS: $os (macOS and Linux only — on Windows, use WSL)" ;;
esac
case "$arch" in
  arm64|aarch64) plat_arch="aarch64" ;;
  x86_64|amd64)  plat_arch="x86_64" ;;
  *) die "unsupported architecture: $arch" ;;
esac
target="${plat_arch}-${plat_os}"

# `shasum` (macOS) vs `sha256sum` (most Linux) — pick whichever exists.
if command -v shasum >/dev/null 2>&1; then
  sha256_check() { shasum -a 256 -c "$1"; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha256_check() { sha256sum -c "$1"; }
else
  die "need shasum or sha256sum to verify the downloaded toolchain"
fi

# Most systems ship `/usr/bin/lex` as `flex` (the classic lexer
# generator) — nothing to do with the Lex toolchain. `command -v lex`
# alone can't tell them apart, so confirm the binary actually
# identifies itself as `lex` before trusting it.
is_real_lex() {
  command -v lex >/dev/null 2>&1 || return 1
  [ "$(lex --version 2>/dev/null | head -1 | awk '{print $1}')" = "lex" ]
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

info "Fetching lex-code..."
git clone --depth 1 --quiet "$REPO" "$workdir/lex-code"
cd "$workdir/lex-code"

lex_version="$(grep '^lex ' lex.toml | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "$lex_version" ] || die "couldn't read the pinned lex version from lex.toml"

# ── the Lex toolchain itself — only if nothing is on PATH already ───────────
if is_real_lex; then
  info "lex already on PATH ($(lex --version 2>/dev/null | head -1)) — leaving it alone"
else
  info "Installing lex $lex_version ($target)..."
  asset="lex-v${lex_version}-${target}.tar.gz"
  base_url="https://github.com/alpibrusl/lex-lang/releases/download/v${lex_version}"
  ( cd "$workdir" \
    && curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused -o "$asset"        "$base_url/$asset" \
    && curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused -o "$asset.sha256" "$base_url/$asset.sha256" \
    && sha256_check "$asset.sha256" >/dev/null \
    && tar -xzf "$asset" ) \
    || die "couldn't download or verify $asset — see $base_url"
  bindir="$PREFIX/bin"
  mkdir -p "$bindir"
  cp "$workdir/lex-v${lex_version}-${target}/lex" "$bindir/lex"
  chmod +x "$bindir/lex"
  case ":$PATH:" in
    *":$bindir:"*) ;;
    *) info "note: $bindir isn't on your PATH yet — add it to your shell profile" ;;
  esac
  export PATH="$bindir:$PATH"
fi

info "Resolving package dependencies (lex-llm, lex-agent, ...)..."
lex pkg install

info "Installing lex-code to $PREFIX..."
make install PREFIX="$PREFIX"

echo
info "Done. Run lex-code:"
echo "    lex-code --ollama \"implement list.zip\"   # fully local, no key"
echo "    lex-code --opencode                        # OPENCODE_API_KEY required"
