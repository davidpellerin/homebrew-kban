#!/usr/bin/env bash
#
# kban installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/davidpellerin/homebrew-kban/main/install.sh | bash
#
# Environment variables:
#   KBAN_VERSION   Override the version to install (default: latest)
#   KBAN_PREFIX    Override the install prefix (default: ~/.local or /usr/local for root)
#

set -euo pipefail

REPO="davidpellerin/homebrew-kban"

# =============================================================================
# Colors and Logging
# =============================================================================

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

die()         { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

# =============================================================================
# Dependencies
# =============================================================================

require() {
    command -v "$1" >/dev/null 2>&1 || die "Required tool not found: $1. Please install it and try again."
}

require curl
require tar
require python3

# =============================================================================
# Resolve version
# =============================================================================

if [[ -n "${KBAN_VERSION:-}" ]]; then
    VERSION="${KBAN_VERSION}"
else
    log_info "Fetching latest kban release..."
    VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name"' \
        | sed 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/')"
    [[ -n "${VERSION}" ]] || die "Could not determine latest version. Set KBAN_VERSION to install a specific version."
fi

TARBALL_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"

# =============================================================================
# Resolve install prefix
# =============================================================================

if [[ -n "${KBAN_PREFIX:-}" ]]; then
    PREFIX="${KBAN_PREFIX}"
elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    PREFIX="/usr/local"
else
    PREFIX="${HOME}/.local"
fi

# kban needs its bin/, templates/, and web/ all under a shared home directory
# so that bin/kban can resolve ../templates and ../web correctly.
KBAN_HOME="${PREFIX}/lib/kban"
BIN_DIR="${PREFIX}/bin"

# =============================================================================
# Install
# =============================================================================

log_info "Installing kban v${VERSION} to ${KBAN_HOME}..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log_info "Downloading tarball..."
curl -fsSL "${TARBALL_URL}" -o "${TMP_DIR}/kban.tar.gz" \
    || die "Download failed. Check that v${VERSION} exists at ${TARBALL_URL}"

tar -xzf "${TMP_DIR}/kban.tar.gz" -C "${TMP_DIR}"
EXTRACTED="${TMP_DIR}/homebrew-kban-${VERSION}"

[[ -d "${EXTRACTED}" ]] || die "Unexpected archive layout — expected directory: homebrew-kban-${VERSION}"

# Remove any previous install so we get a clean slate
rm -rf "${KBAN_HOME}"
mkdir -p "${KBAN_HOME}" "${BIN_DIR}"

# Copy the three required pieces (mirrors the Homebrew formula)
cp -r "${EXTRACTED}/bin"       "${KBAN_HOME}/bin"
cp -r "${EXTRACTED}/templates" "${KBAN_HOME}/templates"
cp -r "${EXTRACTED}/web"       "${KBAN_HOME}/web"
chmod +x "${KBAN_HOME}/bin/kban"

# Create a symlink in BIN_DIR so kban is on PATH
ln -sf "${KBAN_HOME}/bin/kban" "${BIN_DIR}/kban"

log_success "kban v${VERSION} installed."

# =============================================================================
# PATH hint
# =============================================================================

if ! echo ":${PATH}:" | grep -q ":${BIN_DIR}:"; then
    echo ""
    log_warn "${BIN_DIR} is not in your PATH."
    log_info "Add the following line to your shell config (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo "    export PATH=\"${BIN_DIR}:\$PATH\""
    echo ""
    log_info "Then restart your shell or run:  source ~/.bashrc"
    echo ""
fi

log_info "Run 'kban --help' to get started."
