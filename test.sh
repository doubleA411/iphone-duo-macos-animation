#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/build/module-cache"
xcrun swiftc -module-cache-path "$ROOT/build/module-cache" \
  "$ROOT/Sources/LidMotion.swift" "$ROOT/Tests/main.swift" -o "$ROOT/build/motion-tests"
"$ROOT/build/motion-tests"
