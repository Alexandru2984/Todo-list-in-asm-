#!/usr/bin/env bash
# Compatibility entry point. The Python suite uses only disposable storage.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 -m unittest discover -s tests -p 'test_*.py' -v
