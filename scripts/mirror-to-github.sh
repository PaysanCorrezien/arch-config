#!/usr/bin/env bash
#
# mirror-to-github
# Mirror Gitea repos to private GitHub repos as off-site backups.
#
# What it does for each repo:
#   1. Creates a private GitHub repo if one doesn't already exist.
#   2. Adds a Gitea push mirror pointing at that GitHub repo if not already set.
#      The mirror runs on every commit (sync_on_commit=true) and on a schedule.
#
# Both steps are idempotent and safe to re-run.
#
# Required env (put in ~/.config/zsh/secrets.zsh):
#   GITEA_URL      Base URL of your Gitea instance, e.g. https://git.correzien.xyz
#   GITEA_USER     Your Gitea username (the owner of the repos to mirror)
#   GITEA_TOKEN    Gitea API token with write:repository scope
#   GITHUB_USER    Target GitHub username or org name
#   GITHUB_TOKEN   GitHub PAT with `repo` scope (classic) or Contents R/W (fine-grained)
#
# Optional env:
#   GITHUB_OWNER_TYPE   "user" (default) or "org" — controls which create-repo endpoint is used.
#   MIRROR_INTERVAL     Gitea mirror interval, e.g. "8h0m0s" (default).
#
# Usage:
#   mirror-to-github <repo>        Mirror a single repo
#   mirror-to-github --all         Mirror every repo owned by GITEA_USER
#   mirror-to-github --list        List repos and their current mirror status
#   mirror-to-github --dry-run ... Print what would happen without making changes
#   mirror-to-github -h | --help   Show this help

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=0

usage() {
  sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
}

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "$@"; }

require_cmd() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command '$cmd' not found in PATH"
  done
}

require_env() {
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || die "$var must be set (try ~/.config/zsh/secrets.zsh)"
  done
}

# --- API helpers -------------------------------------------------------------

# gh_api METHOD PATH [JSON_BODY]
# Returns body on stdout. Caller is responsible for inspecting status via gh_status.
gh_api() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-sS -X "$method"
    -H "Authorization: Bearer $GITHUB_TOKEN"
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28")
  [[ -n "$data" ]] && args+=(-H "Content-Type: application/json" -d "$data")
  curl "${args[@]}" "https://api.github.com$path"
}

# gh_status METHOD PATH — returns just HTTP status code
gh_status() {
  local method="$1" path="$2"
  curl -sS -o /dev/null -w "%{http_code}" -X "$method" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com$path"
}

gitea_api() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-sS -X "$method"
    -H "Authorization: token $GITEA_TOKEN"
    -H "Accept: application/json")
  [[ -n "$data" ]] && args+=(-H "Content-Type: application/json" -d "$data")
  curl "${args[@]}" "$GITEA_URL/api/v1$path"
}

# --- GitHub side -------------------------------------------------------------

gh_repo_exists() {
  local repo="$1"
  [[ "$(gh_status GET "/repos/$GITHUB_USER/$repo")" == "200" ]]
}

gh_create_repo() {
  local repo="$1" description="${2:-Mirrored from Gitea}"
  local payload
  payload=$(jq -n --arg n "$repo" --arg d "$description" \
    '{name:$n, description:$d, private:true, auto_init:false, has_issues:false, has_wiki:false, has_projects:false}')

  local endpoint
  if [[ "${GITHUB_OWNER_TYPE:-user}" == "org" ]]; then
    endpoint="/orgs/$GITHUB_USER/repos"
  else
    endpoint="/user/repos"
  fi

  if (( DRY_RUN )); then
    log "    [dry-run] POST $endpoint  (private repo $GITHUB_USER/$repo)"
    return 0
  fi

  local response
  response=$(gh_api POST "$endpoint" "$payload")
  if ! echo "$response" | jq -e '.id' >/dev/null 2>&1; then
    die "failed to create GitHub repo $GITHUB_USER/$repo: $(echo "$response" | jq -r '.message // .')"
  fi
}

# --- Gitea side --------------------------------------------------------------

gitea_push_mirror_url() {
  echo "https://github.com/$GITHUB_USER/$1.git"
}

gitea_push_mirror_exists() {
  local repo="$1"
  local target_url
  target_url=$(gitea_push_mirror_url "$repo")
  gitea_api GET "/repos/$GITEA_USER/$repo/push_mirrors" \
    | jq -e --arg url "$target_url" 'any(.[]?; .remote_address == $url)' >/dev/null
}

gitea_add_push_mirror() {
  local repo="$1"
  local target_url
  target_url=$(gitea_push_mirror_url "$repo")
  local payload
  payload=$(jq -n \
    --arg url "$target_url" \
    --arg user "$GITHUB_USER" \
    --arg pass "$GITHUB_TOKEN" \
    --arg interval "${MIRROR_INTERVAL:-8h0m0s}" \
    '{remote_address:$url, remote_username:$user, remote_password:$pass, interval:$interval, sync_on_commit:true}')

  if (( DRY_RUN )); then
    log "    [dry-run] POST $GITEA_URL/api/v1/repos/$GITEA_USER/$repo/push_mirrors"
    return 0
  fi

  local response
  response=$(gitea_api POST "/repos/$GITEA_USER/$repo/push_mirrors" "$payload")
  # Success: response carries remote_name + created. Errors carry .message instead.
  if ! echo "$response" | jq -e '.remote_name' >/dev/null 2>&1; then
    die "failed to add push mirror on $GITEA_USER/$repo: $(echo "$response" | jq -r '.message // .')"
  fi
}

list_gitea_repos() {
  # Return all repos owned by GITEA_USER (paginated).
  local uid page=1 limit=50
  uid=$(gitea_api GET "/user" | jq -r '.id')
  [[ "$uid" =~ ^[0-9]+$ ]] || die "could not resolve Gitea user id (token likely invalid)"

  while :; do
    local body count
    body=$(gitea_api GET "/repos/search?uid=$uid&limit=$limit&page=$page&exclusive=true&archived=false")
    count=$(echo "$body" | jq '.data | length')
    [[ "$count" -gt 0 ]] || break
    echo "$body" | jq -r '.data[].name'
    [[ "$count" -lt "$limit" ]] && break
    ((page++))
  done
}

# --- Operations --------------------------------------------------------------

mirror_one() {
  local repo="$1"
  log "==> $repo"

  if gh_repo_exists "$repo"; then
    log "    GitHub: $GITHUB_USER/$repo already exists"
  else
    log "    GitHub: creating private repo $GITHUB_USER/$repo"
    gh_create_repo "$repo"
  fi

  if gitea_push_mirror_exists "$repo"; then
    log "    Gitea:  push mirror already configured"
  else
    log "    Gitea:  adding push mirror -> github.com/$GITHUB_USER/$repo"
    gitea_add_push_mirror "$repo"
  fi
}

cmd_list() {
  printf '%-40s %-10s %-10s\n' "REPO" "GITHUB" "MIRROR"
  printf '%-40s %-10s %-10s\n' "----" "------" "------"
  while IFS= read -r repo; do
    local gh="missing" mr="missing"
    gh_repo_exists "$repo" && gh="present"
    gitea_push_mirror_exists "$repo" && mr="present"
    printf '%-40s %-10s %-10s\n' "$repo" "$gh" "$mr"
  done < <(list_gitea_repos)
}

cmd_all() {
  local count=0 failed=0
  while IFS= read -r repo; do
    ((count++)) || true
    if ! mirror_one "$repo"; then
      ((failed++)) || true
      log "    FAILED on $repo, continuing..."
    fi
  done < <(list_gitea_repos)
  log ""
  log "Done. $count repos processed, $failed failure(s)."
  (( failed == 0 ))
}

# --- Entrypoint --------------------------------------------------------------

main() {
  local positional=()
  while (($#)); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --all)     positional+=("__all__"); shift ;;
      --list)    positional+=("__list__"); shift ;;
      --) shift; while (($#)); do positional+=("$1"); shift; done ;;
      -*) die "unknown flag: $1 (use --help)" ;;
      *)  positional+=("$1"); shift ;;
    esac
  done

  [[ "${#positional[@]}" -gt 0 ]] || { usage; exit 1; }

  require_cmd curl jq
  require_env GITEA_URL GITEA_USER GITEA_TOKEN GITHUB_USER GITHUB_TOKEN

  local target="${positional[0]}"
  case "$target" in
    __list__) cmd_list ;;
    __all__)  cmd_all ;;
    *)        mirror_one "$target" ;;
  esac
}

main "$@"
