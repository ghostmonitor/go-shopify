#!/usr/bin/env bash
# .claude/scripts/update-recart-plugins.sh
#
# SessionStart hook: keeps locally-cached recart-plugins marketplace plugins
# in sync with the remote repository.
#
# - Discovers all enabled plugins from the recart-plugins marketplace
# - Uses git ls-remote to check for new versions (no full fetch unless needed)
# - Only updates plugin cache when installed SHA differs from remote
# - Atomic cache updates (copy to temp dir, then swap)

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────
MARKETPLACE_NAME="recart-plugins"
PROJECT_SETTINGS=".claude/settings.json"

PLUGINS_DIR="${HOME}/.claude/plugins"
MARKETPLACE_DIR="${PLUGINS_DIR}/marketplaces/${MARKETPLACE_NAME}"
INSTALLED_FILE="${PLUGINS_DIR}/installed_plugins.json"

# ── Logging (set PLUGIN_UPDATE_LOG=1 to enable) ─────────────────
# PLUGIN_UPDATE_LOG=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd || true)"
LOG_FILE="${SCRIPT_DIR}/update-recart-plugins.log"

log() {
  if [[ "${PLUGIN_UPDATE_LOG:-0}" == "1" ]]; then
    local ts
    ts=$(date -u +"%H:%M:%S" || true)
    echo "[${ts}] $*" >> "${LOG_FILE}"
  fi
}

# ── Helpers ───────────────────────────────────────────────────────

# Resolve the SHA for a ref (branch or tag) from a git remote.
# Usage: resolve_remote_sha <repo_or_remote_name> [git_flags...]
# Example: resolve_remote_sha origin -C /path/to/repo
# Example: resolve_remote_sha https://github.com/org/repo.git
resolve_remote_sha() {
  local target="$1"
  shift
  local sha=""

  for ref_prefix in "refs/heads" "refs/tags"; do
    sha=$(git "$@" ls-remote "${target}" "${ref_prefix}/${DESIRED_REF}" 2>/dev/null | cut -f1 || true)
    if [[ -n "${sha}" ]]; then
      echo "${sha}"
      return
    fi
  done
}

# ── Guard: project settings must exist ────────────────────────────
if [[ ! -f "${PROJECT_SETTINGS}" ]]; then
  exit 0
fi

# ── Read marketplace config from project settings ─────────────────
DESIRED_REF=$(jq -r \
  ".extraKnownMarketplaces[\"${MARKETPLACE_NAME}\"].source.ref // empty" \
  "${PROJECT_SETTINGS}" 2>/dev/null || true)

MARKETPLACE_REPO=$(jq -r \
  ".extraKnownMarketplaces[\"${MARKETPLACE_NAME}\"].source.repo // empty" \
  "${PROJECT_SETTINGS}" 2>/dev/null || true)

if [[ -z "${DESIRED_REF}" || -z "${MARKETPLACE_REPO}" ]]; then
  exit 0
fi

REPO_URL="https://github.com/${MARKETPLACE_REPO}.git"
PROJECT_PATH="$(pwd)"

# ── Discover enabled plugins from this marketplace ────────────────
ENABLED_PLUGINS=()
while IFS= read -r plugin_key; do
  plugin_name="${plugin_key%@*}"
  if [[ -n "${plugin_name}" ]]; then
    ENABLED_PLUGINS+=("${plugin_name}")
  fi
done < <(jq -r \
  ".enabledPlugins // {} | to_entries[]
   | select(.value == true and (.key | endswith(\"@${MARKETPLACE_NAME}\")))
   | .key" \
  "${PROJECT_SETTINGS}" 2>/dev/null || true)

if [[ ${#ENABLED_PLUGINS[@]} -eq 0 ]]; then
  exit 0
fi

log "ref=${DESIRED_REF} plugins=${ENABLED_PLUGINS[*]}"

# ── Resolve remote SHA (lightweight -- no object download) ────────
if [[ -d "${MARKETPLACE_DIR}/.git" ]]; then
  REMOTE_SHA=$(resolve_remote_sha origin -C "${MARKETPLACE_DIR}")
else
  REMOTE_SHA=$(resolve_remote_sha "${REPO_URL}")
fi

if [[ -z "${REMOTE_SHA}" ]]; then
  log "WARN: could not resolve ref '${DESIRED_REF}' in ${MARKETPLACE_REPO}"
  exit 0
fi

log "remote=${REMOTE_SHA:0:8}"

# ── Determine which plugins need updating ─────────────────────────
PLUGINS_TO_UPDATE=()
for plugin_name in "${ENABLED_PLUGINS[@]}"; do
  entry_key="${plugin_name}@${MARKETPLACE_NAME}"
  cache_dir="${PLUGINS_DIR}/cache/${MARKETPLACE_NAME}/${plugin_name}"

  installed_sha=""
  if [[ -f "${INSTALLED_FILE}" ]]; then
    installed_sha=$(jq -r \
      --arg key "${entry_key}" \
      --arg proj "${PROJECT_PATH}" \
      '.plugins[$key][] | select(.projectPath == $proj) | .gitCommitSha // empty' \
      "${INSTALLED_FILE}" 2>/dev/null || true)
  fi

  if [[ "${FORCE_PLUGIN_UPDATE:-}" == "true" ]] \
    || [[ "${installed_sha}" != "${REMOTE_SHA}" ]] \
    || [[ ! -d "${cache_dir}" ]] \
    || [[ -z "$(ls -A "${cache_dir}" 2>/dev/null || true)" ]]; then
    PLUGINS_TO_UPDATE+=("${plugin_name}")
  fi
done

if [[ ${#PLUGINS_TO_UPDATE[@]} -eq 0 ]]; then
  log "all up to date"
  exit 0
fi

log "stale: ${PLUGINS_TO_UPDATE[*]}"

# ── Ensure marketplace clone exists and is at the right commit ────
if [[ ! -d "${MARKETPLACE_DIR}/.git" ]]; then
  mkdir -p "$(dirname "${MARKETPLACE_DIR}")"
  git clone --quiet "${REPO_URL}" "${MARKETPLACE_DIR}" 2>/dev/null
fi

LOCAL_SHA=$(git -C "${MARKETPLACE_DIR}" rev-parse HEAD 2>/dev/null || true)

if [[ "${LOCAL_SHA}" != "${REMOTE_SHA}" ]]; then
  git -C "${MARKETPLACE_DIR}" fetch --tags --force --quiet origin 2>/dev/null || true
  git -C "${MARKETPLACE_DIR}" checkout --quiet --force "${REMOTE_SHA}" 2>/dev/null || true
fi

RESOLVED_SHA=$(git -C "${MARKETPLACE_DIR}" rev-parse HEAD 2>/dev/null || true)

# ── Update each stale plugin ─────────────────────────────────────
if [[ ! -f "${INSTALLED_FILE}" ]]; then
  mkdir -p "$(dirname "${INSTALLED_FILE}")"
  echo '{"version":2,"plugins":{}}' > "${INSTALLED_FILE}"
fi

for plugin_name in "${PLUGINS_TO_UPDATE[@]}"; do
  plugin_source="${MARKETPLACE_DIR}/plugins/${plugin_name}"
  plugin_json="${plugin_source}/.claude-plugin/plugin.json"
  cache_dir="${PLUGINS_DIR}/cache/${MARKETPLACE_NAME}/${plugin_name}"
  entry_key="${plugin_name}@${MARKETPLACE_NAME}"

  if [[ ! -d "${plugin_source}" ]]; then
    log "WARN: plugin '${plugin_name}' not found at plugins/${plugin_name}"
    continue
  fi

  plugin_version="1.0.0"
  if [[ -f "${plugin_json}" ]]; then
    plugin_version=$(jq -r '.version // "1.0.0"' "${plugin_json}" 2>/dev/null || echo "1.0.0")
  fi

  # Atomic cache update: write to temp dir, then swap into place
  install_path="${cache_dir}/${plugin_version}"
  tmp_path="${cache_dir}/.tmp-${plugin_version}"

  rm -rf "${tmp_path}"
  mkdir -p "${tmp_path}"
  cp -r "${plugin_source}/." "${tmp_path}/"

  rm -rf "${install_path}"
  mv "${tmp_path}" "${install_path}"

  # Remove old versions after the new one is safely in place
  for old_ver in "${cache_dir}"/*/; do
    [[ -d "${old_ver}" ]] && [[ "${old_ver%/}" != "${install_path}" ]] && rm -rf "${old_ver}"
  done

  now=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

  lock_dir="${INSTALLED_FILE}.lock"
  while ! mkdir "${lock_dir}" 2>/dev/null; do sleep 0.1; done
  trap 'rmdir "${lock_dir}" 2>/dev/null || true' EXIT

  jq --arg key "${entry_key}" \
     --arg path "${install_path}" \
     --arg ver "${plugin_version}" \
     --arg sha "${RESOLVED_SHA}" \
     --arg now "${now}" \
     --arg proj "${PROJECT_PATH}" \
    '.plugins[$key] = (
      [(.plugins[$key] // [])[] | select(.projectPath != $proj)] + [{
        "scope": "project",
        "installPath": $path,
        "version": $ver,
        "installedAt": ([(.plugins[$key] // [])[] | select(.projectPath == $proj) | .installedAt][0] // $now),
        "lastUpdated": $now,
        "gitCommitSha": $sha,
        "projectPath": $proj
      }]
    )' "${INSTALLED_FILE}" > "${INSTALLED_FILE}.tmp" \
    && mv "${INSTALLED_FILE}.tmp" "${INSTALLED_FILE}"

  rmdir "${lock_dir}" 2>/dev/null || true
  trap - EXIT

  log "updated ${plugin_name} v${plugin_version} sha:${RESOLVED_SHA:0:8}"
done
