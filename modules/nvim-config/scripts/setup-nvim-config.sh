#!/usr/bin/env bash
# Post-install setup script for Neovim config

set -euo pipefail

echo "=== Neovim Config Setup ==="
echo

target_user="${SUDO_USER:-$USER}"
if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
  user_home="$(getent passwd "${target_user}" | cut -d: -f6)"
else
  user_home="$HOME"
fi

run_user_cmd() {
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "${target_user}" XDG_RUNTIME_DIR="/run/user/$(id -u "${target_user}")" "$@"
  else
    "$@"
  fi
}

repo_url="https://github.com/PaysanCorrezien/config.nvim"
repo_dir="${user_home}/.config/nvim"
spell_dir="${repo_dir}/spell"
spell_lang="fr"

echo "-> Ensuring ${repo_dir} is synced from ${repo_url}"

if [ -L "${repo_dir}" ]; then
  echo "-> Found symlink at ${repo_dir}; removing it"
  rm -f "${repo_dir}"
fi

download_spellfile() {
  local lang="$1"
  local ext="$2"
  local url="https://ftp.nluug.nl/vim/runtime/spell/${lang}.utf-8.${ext}"
  local dest="${spell_dir}/${lang}.utf-8.${ext}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}" -o "${dest}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${dest}" "${url}"
  else
    echo "[WARN] curl/wget not found; cannot download ${url}"
    return 1
  fi
}

fix_spellfiles() {
  mkdir -p "${spell_dir}"
  for ext in spl sug; do
    local file="${spell_dir}/${spell_lang}.utf-8.${ext}"
    if [ -L "${file}" ]; then
      echo "-> Removing symlinked spellfile ${file}"
      rm -f "${file}"
    fi
    if [ ! -f "${file}" ]; then
      echo "-> Downloading ${spell_lang} spellfile (${ext})"
      if download_spellfile "${spell_lang}" "${ext}"; then
        echo "[OK] Downloaded ${file}"
      fi
    fi
  done
}

if [ -d "${repo_dir}" ] && [ ! -d "${repo_dir}/.git" ]; then
  backup_dir="${repo_dir}.backup-$(date +%Y%m%d_%H%M%S)"
  echo "-> Found non-git config at ${repo_dir}; moving to ${backup_dir}"
  mv "${repo_dir}" "${backup_dir}"
fi

if [ ! -d "${repo_dir}/.git" ]; then
  run_user_cmd mkdir -p "${user_home}/.config"
  run_user_cmd git clone --depth 1 "${repo_url}" "${repo_dir}"
  echo "[OK] Config cloned"
else
  if run_user_cmd git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(run_user_cmd git -C "${repo_dir}" status --porcelain)" ]; then
      echo "[WARN] Local changes detected in ${repo_dir}; skipping pull"
    else
      run_user_cmd git -C "${repo_dir}" fetch --quiet || true
      if run_user_cmd git -C "${repo_dir}" rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
        local_head="$(run_user_cmd git -C "${repo_dir}" rev-parse HEAD)"
        upstream_head="$(run_user_cmd git -C "${repo_dir}" rev-parse @{u})"
        if [ "${local_head}" != "${upstream_head}" ]; then
          run_user_cmd git -C "${repo_dir}" pull --ff-only || true
          echo "[OK] Config updated from remote"
        else
          echo "[OK] Config already up to date"
        fi
      else
        echo "[WARN] No upstream configured for ${repo_dir}; skipping pull"
      fi
    fi
  else
    echo "[WARN] ${repo_dir} is not a valid git repo; skipping pull"
  fi
fi

echo
echo "-> Ensuring spellfiles are local (no Nix store symlinks)"
fix_spellfiles

echo
echo "=== Neovim Config Setup Complete ==="
