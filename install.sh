#!/bin/sh
set -e

REPO="resetself/workspace"
INSTALL_DIR="${HOME}/.local/bin"
BINARY="wksp"

# detect platform
case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="macos" ;;
    *)      echo "unsupported OS: $(uname -s)"; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64)  ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *)             echo "unsupported arch: $(uname -m)"; exit 1 ;;
esac

TARGET="${ARCH}-${OS}"
echo "→ platform: ${TARGET}"

# get latest release
TAG=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$TAG" ]; then
    echo "could not find latest release"
    exit 1
fi
echo "→ version: ${TAG}"

# download
URL="https://github.com/${REPO}/releases/download/${TAG}/wksp-${TARGET}.tar.gz"
echo "→ downloading ${URL}"
curl -sL "$URL" -o /tmp/wksp.tar.gz

# install
mkdir -p "$INSTALL_DIR"
tar xzf /tmp/wksp.tar.gz -C "$INSTALL_DIR"
chmod +x "${INSTALL_DIR}/${BINARY}"
rm -f /tmp/wksp.tar.gz

echo "✓ wksp installed to ${INSTALL_DIR}/${BINARY}"

# check PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qF "$INSTALL_DIR"; then
    echo
    echo "  add to your shell config:"
    echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
fi
