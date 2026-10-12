#!/usr/bin/env bash
# Install nginx-vhost to a bin directory on PATH.
set -euo pipefail

PREFIX="${PREFIX:-/usr/local/bin}"
SRC="$(cd "$(dirname "$0")" && pwd)/nginx-vhost"

[ -f "$SRC" ] || { echo "error: nginx-vhost not found next to install.sh" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ] && [ ! -w "$PREFIX" ]; then
  echo "==> installing to $PREFIX (needs sudo)"
  exec sudo install -m 0755 "$SRC" "$PREFIX/nginx-vhost"
fi

install -m 0755 "$SRC" "$PREFIX/nginx-vhost"
echo "==> installed $PREFIX/nginx-vhost"
echo "    try: nginx-vhost help"
