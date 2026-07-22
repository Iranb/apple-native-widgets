#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ -x /usr/bin/python3 ]]; then
  PYTHON=/usr/bin/python3
else
  PYTHON="$(command -v python3)"
fi

exec "$PYTHON" "$ROOT/autodl_monitor.py" "$@"
