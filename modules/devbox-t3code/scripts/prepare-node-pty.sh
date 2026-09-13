#!/usr/bin/env bash
set -euo pipefail

t3_home="${T3CODE_HOME:-${HOME}/.t3}"
runtime_versions="${t3_home}/runtime/versions"
bundled_pty="/opt/t3code-bin/resources/app.asar.unpacked/node_modules/node-pty/build/Release/pty.node"

if [[ ! -f "$bundled_pty" ]]; then
  echo "[devbox-t3code] Missing bundled node-pty module: $bundled_pty" >&2
  exit 1
fi

if [[ ! -d "$runtime_versions" ]]; then
  echo "[devbox-t3code] No downloaded T3 runtime versions at $runtime_versions; skipping node-pty repair"
  exit 0
fi

while IFS= read -r -d '' package_json; do
  node_pty_dir="${package_json%/package.json}"
  target="${node_pty_dir}/build/Release/pty.node"
  if [[ ! -f "$target" ]]; then
    install -Dm755 "$bundled_pty" "$target"
    echo "[devbox-t3code] Restored node-pty native module for ${node_pty_dir#"$runtime_versions"/}"
  fi
done < <(find "$runtime_versions" -type f -path '*/node_modules/node-pty/package.json' -print0)
