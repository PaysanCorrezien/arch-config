#!/usr/bin/env bash
set -euo pipefail

#  _                     _                         _
# | |__   ___  _ __ ___ | |__   ___   __ _ _ __ ___| |__
# | '_ \ / _ \| '_ ` _ \| '_ \ / _ \ / _` | '__/ __| '_ \
# | | | | (_) | | | | | | |_) | (_) | (_| | | | (__| | | |
# |_| |_|\___/|_| |_| |_|_.__/ \___/ \__,_|_|  \___|_| |_|

# Quick bootstrap for this repo on a fresh CachyOS install.
# Installs git, base-devel, fzf, paru, and dcli.

REPO_URL="${ARCH_CONFIG_REPO_URL:-https://github.com/PaysanCorrezien/arch-config}"
TARGET_DIR="${ARCH_CONFIG_DIR:-$HOME/.config/arch-config}"
HOST_NAME="${ARCH_CONFIG_HOST:-homebot}"

echo "==> Installing prerequisites (git, base-devel, fzf)..."
sudo pacman -Syu --needed --noconfirm git base-devel fzf

install_paru() {
	if command -v paru >/dev/null 2>&1; then
		return 0
	fi

	echo "==> Installing paru from AUR..."
	tmp_dir="$(mktemp -d)"
	trap 'rm -rf "${tmp_dir}"' EXIT
	git clone --depth 1 https://aur.archlinux.org/paru.git "${tmp_dir}/paru"
	(cd "${tmp_dir}/paru" && makepkg -si --noconfirm)
}

install_dcli() {
	if command -v dcli >/dev/null 2>&1; then
		return 0
	fi

	install_paru
	echo "==> Installing dcli from AUR (dcli-arch-git)..."
	paru -S --needed --noconfirm dcli-arch-git
}

if [ -d "${TARGET_DIR}/.git" ]; then
	echo "Repo already exists at ${TARGET_DIR}."
else
	mkdir -p "$(dirname "${TARGET_DIR}")"
	git clone "${REPO_URL}" "${TARGET_DIR}"
fi

install_dcli

cd "${TARGET_DIR}"

# Pick host if not provided
if [ -z "${ARCH_CONFIG_HOST:-}" ]; then
	echo "==> Available hosts:"
	mapfile -t hosts < <(ls hosts/*.yaml 2>/dev/null | xargs -n1 basename | sed 's/\\.yaml$//')
	if [ "${#hosts[@]}" -eq 0 ]; then
		echo "No hosts found in ${TARGET_DIR}/hosts."
		exit 1
	fi

	select host_choice in "${hosts[@]}"; do
		if [ -n "${host_choice}" ]; then
			HOST_NAME="${host_choice}"
			break
		fi
		echo "Invalid selection."
	done
fi

# Point dcli at the chosen host
cat >config.yaml <<EOF_CFG
# dcli configuration pointer
# This file points to the active host configuration
# The full configuration lives in hosts/${HOST_NAME}.yaml

# Active host
host: ${HOST_NAME}
EOF_CFG

# Sync configuration
exec dcli sync
