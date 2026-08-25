#!/usr/bin/env bash
set -euo pipefail

module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install -d -m 0755 "${HOME}/.config"
install -m 0600 "${module_dir}/kwinoutputconfig.json" "${HOME}/.config/kwinoutputconfig.json"
