#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER_REPO_URL="${PROVIDER_REPO_URL:-https://github.com/lmbalcao/terraform-provider-openwrt.git}"
PROVIDER_DIR="${PROVIDER_DIR:-$ROOT_DIR/../terraform-provider-openwrt}"
PROVIDER_BRANCH="${PROVIDER_BRANCH:-wip/openwrt-ubus-fallback}"
PROVIDER_BINARY_NAME="${PROVIDER_BINARY_NAME:-terraform-provider-openwrt}"
BUILD_COMMIT_FILE="${BUILD_COMMIT_FILE:-$PROVIDER_DIR/.build_commit}"
BINARY_PATH="$PROVIDER_DIR/$PROVIDER_BINARY_NAME"
FETCH_REF="HEAD"
CLONED=no
PULLED=no
BUILT=no

log() {
  echo "[sync-openwrt-provider] $*"
}
die() {
  log "ERROR: $*"
  exit 1
}
resolve_go() {
  if [[ -n "${GO_BIN:-}" && -x "$GO_BIN" ]]; then
    echo "$GO_BIN"
    return 0
  fi
  if command -v go >/dev/null 2>&1; then
    command -v go
    return 0
  fi
  for candidate in "$ROOT_DIR/.tools/bin/go" "/tmp/go/bin/go"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_repo() {
  mkdir -p "$(dirname "$PROVIDER_DIR")"
  if [[ ! -e "$PROVIDER_DIR" ]]; then
    log "clone: $PROVIDER_REPO_URL -> $PROVIDER_DIR"
    git clone --branch "$PROVIDER_BRANCH" --single-branch "$PROVIDER_REPO_URL" "$PROVIDER_DIR"
    CLONED=yes
    FETCH_REF="HEAD"
    return
  fi
  [[ -d "$PROVIDER_DIR/.git" ]] || die "$PROVIDER_DIR exists but is not a git repository"
  local tracked_changes
  tracked_changes="$(git -C "$PROVIDER_DIR" status --porcelain --untracked-files=no)"
  if [[ -n "$tracked_changes" ]]; then
    die "provider repo has tracked local changes; aborting before fetch/pull"
  fi
  if [[ "$(git -C "$PROVIDER_DIR" rev-parse --abbrev-ref HEAD)" != "$PROVIDER_BRANCH" ]]; then
    if git -C "$PROVIDER_DIR" show-ref --verify --quiet "refs/heads/$PROVIDER_BRANCH"; then
      git -C "$PROVIDER_DIR" switch "$PROVIDER_BRANCH" >/dev/null
    else
      die "missing local branch $PROVIDER_BRANCH"
    fi
  fi
  log "fetch: origin"
  if git -C "$PROVIDER_DIR" fetch origin --prune; then
    FETCH_REF="origin/$PROVIDER_BRANCH"
  else
    log "fetch: skipped, origin is unreachable; using local $PROVIDER_BRANCH"
    FETCH_REF="HEAD"
  fi
}

ensure_binary() {
  local local_commit remote_commit go_bin current_commit built_commit
  built_commit=""
  local_commit="$(git -C "$PROVIDER_DIR" rev-parse HEAD)"
  remote_commit="$(git -C "$PROVIDER_DIR" rev-parse "$FETCH_REF")"
  if [[ "$FETCH_REF" != "HEAD" && "$local_commit" != "$remote_commit" ]]; then
    log "pull: $local_commit -> $remote_commit"
    git -C "$PROVIDER_DIR" pull --ff-only origin "$PROVIDER_BRANCH"
    PULLED=yes
  else
    log "pull: skipped, already up to date"
  fi
  go_bin="$(resolve_go)" || die "go is required to build the provider"
  current_commit="$(git -C "$PROVIDER_DIR" rev-parse HEAD)"
  if [[ -f "$BUILD_COMMIT_FILE" ]]; then
    built_commit="$(tr -d "[:space:]" < "$BUILD_COMMIT_FILE")"
  fi
  if [[ ! -x "$BINARY_PATH" ]]; then
    log "build: binary missing"
    ( cd "$PROVIDER_DIR" && "$go_bin" build -o "$PROVIDER_BINARY_NAME" )
    echo "$current_commit" > "$BUILD_COMMIT_FILE"
    BUILT=yes
  elif [[ "$current_commit" != "$built_commit" ]]; then
    log "build: commit changed ($built_commit -> $current_commit)"
    ( cd "$PROVIDER_DIR" && "$go_bin" build -o "$PROVIDER_BINARY_NAME" )
    echo "$current_commit" > "$BUILD_COMMIT_FILE"
    BUILT=yes
  else
    log "build: skipped, binary already matches $current_commit"
  fi
  log "summary: clone=$CLONED pull=$PULLED build=$BUILT commit=$current_commit bin=$BINARY_PATH"
}
main() {
  command -v git >/dev/null 2>&1 || die "git is required"
  ensure_repo
  ensure_binary
}
main "$@"
