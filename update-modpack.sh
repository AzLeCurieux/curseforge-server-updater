#!/bin/bash
# curseforge-server-updater
# Automatically updates a CurseForge modpack server to the latest version.
# Supports Crafty Controller, systemd, screen, and tmux.
#
# Usage:
#   ./update-modpack.sh          check and apply update
#   ./update-modpack.sh --check  check only, exit 0 if up-to-date, 1 if update available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: .env file not found. Copy .env.example to .env and configure it."; exit 1; }
# shellcheck source=.env.example
set -a; source "$ENV_FILE"; set +a

CF_GAME_VERSION="${CF_GAME_VERSION:-1.21.1}"
SERVER_MANAGER="${SERVER_MANAGER:-none}"
RUN_BACKUP_BEFORE="${RUN_BACKUP_BEFORE:-false}"
PRESERVE_ITEMS="${PRESERVE_ITEMS:-world,server.properties,whitelist.json,ops.json,banned-players.json,banned-ips.json,eula.txt,server.jar}"
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/update-modpack.log}"
VERSION_FILE="${SCRIPT_DIR}/.installed-version"
CHECK_ONLY="${1:-}"

log()  { echo "$(date '+%Y-%m-%d %H:%M:%S')  INFO  $*" | tee -a "$LOG_FILE"; }
warn() { echo "$(date '+%Y-%m-%d %H:%M:%S')  WARN  $*" | tee -a "$LOG_FILE"; }
die()  { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR  $*" | tee -a "$LOG_FILE"; exit 1; }

notify() {
  local msg="$1"
  if [ -n "${DISCORD_WEBHOOK:-}" ]; then
    curl -sf -X POST "$DISCORD_WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "{\"content\":\"🎮 **Modpack Updater** - ${msg}\"}" > /dev/null 2>&1 || true
  fi
}

[ -n "${CF_API_KEY:-}"    ] || die "CF_API_KEY is not set in .env"
[ -n "${CF_PROJECT_ID:-}" ] || die "CF_PROJECT_ID is not set in .env"
[ -n "${SERVER_DIR:-}"    ] || die "SERVER_DIR is not set in .env"
[ -d "$SERVER_DIR"        ] || die "SERVER_DIR does not exist: $SERVER_DIR"

mkdir -p "$(dirname "$LOG_FILE")"

log "CurseForge Server Updater - project $CF_PROJECT_ID"

INSTALLED_ID=$(cat "$VERSION_FILE" 2>/dev/null || echo "none")
log "Installed server pack ID: $INSTALLED_ID"

log "Querying CurseForge API..."
FILES_JSON=$(curl -sf \
  "https://api.curseforge.com/v1/mods/${CF_PROJECT_ID}/files?gameVersion=${CF_GAME_VERSION}&pageSize=10&sortField=5&sortOrder=desc" \
  -H "x-api-key: ${CF_API_KEY}") \
  || die "Cannot reach CurseForge API. Check your CF_API_KEY and internet connectivity."

LATEST=$(echo "$FILES_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for f in data['data']:
    if not f.get('isServerPack') and f.get('serverPackFileId'):
        print(f['serverPackFileId'], f['displayName'])
        break
" 2>/dev/null) || die "No server pack found for project $CF_PROJECT_ID on game version $CF_GAME_VERSION"

LATEST_PACK_ID=$(echo "$LATEST" | cut -d' ' -f1)
LATEST_NAME=$(echo "$LATEST" | cut -d' ' -f2-)
log "Latest available: $LATEST_NAME (server pack ID: $LATEST_PACK_ID)"

if [ "$LATEST_PACK_ID" = "$INSTALLED_ID" ]; then
  log "Already up to date."
  exit 0
fi

if [ "$CHECK_ONLY" = "--check" ]; then
  log "Update available: $LATEST_NAME"
  notify "Update available: **$LATEST_NAME**"
  exit 1
fi

log "Updating: $INSTALLED_ID -> $LATEST_PACK_ID ($LATEST_NAME)"
notify "Starting update to **$LATEST_NAME**..."

if [ "$RUN_BACKUP_BEFORE" = "true" ]; then
  if [ -n "${BACKUP_SCRIPT:-}" ] && [ -x "$BACKUP_SCRIPT" ]; then
    log "Running backup script: $BACKUP_SCRIPT"
    "$BACKUP_SCRIPT" || die "Backup failed. Aborting update."
  else
    log "Creating pre-update backup..."
    BACKUP_DIR="${BACKUP_DIR:-${SCRIPT_DIR}/backups}"
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="${BACKUP_DIR}/pre-update-$(date '+%Y-%m-%d_%H-%M-%S').tar.gz"
    tar -czf "$BACKUP_FILE" -C "$SERVER_DIR" world server.properties whitelist.json ops.json 2>/dev/null || true
    log "Backup saved: $BACKUP_FILE ($(du -sh "$BACKUP_FILE" | cut -f1))"
  fi
fi

log "Getting download URL..."
DOWNLOAD_URL=$(curl -sf \
  "https://api.curseforge.com/v1/mods/${CF_PROJECT_ID}/files/${LATEST_PACK_ID}/download-url" \
  -H "x-api-key: ${CF_API_KEY}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data'])") \
  || die "Could not get download URL for file $LATEST_PACK_ID"

log "Downloading: $DOWNLOAD_URL"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

curl -fL --progress-bar "$DOWNLOAD_URL" -o "$TEMP_DIR/serverpack.zip" \
  || die "Download failed"

log "Downloaded: $(du -sh "$TEMP_DIR/serverpack.zip" | cut -f1)"

log "Stopping server (manager: $SERVER_MANAGER)..."

case "$SERVER_MANAGER" in
  crafty)
    CRAFTY_TOKEN=$(curl -sk -X POST "${CRAFTY_URL}/api/v2/auth/login" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"${CRAFTY_USER}\",\"password\":\"${CRAFTY_PASS}\"}" \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['token'])")
    curl -sk -X POST "${CRAFTY_URL}/api/v2/servers/${CRAFTY_SERVER_ID}/action/stop_server" \
      -H "Authorization: Bearer $CRAFTY_TOKEN" > /dev/null
    sleep "${STOP_WAIT_SECONDS:-15}"
    ;;
  systemd)
    sudo systemctl stop "${SYSTEMD_SERVICE:?'SYSTEMD_SERVICE not set'}"
    sleep "${STOP_WAIT_SECONDS:-5}"
    ;;
  screen)
    screen -S "${SCREEN_SESSION:?'SCREEN_SESSION not set'}" -X stuff "stop$(printf '\r')" 2>/dev/null || true
    sleep "${STOP_WAIT_SECONDS:-15}"
    ;;
  tmux)
    tmux send-keys -t "${TMUX_SESSION:?'TMUX_SESSION not set'}" "stop" Enter 2>/dev/null || true
    sleep "${STOP_WAIT_SECONDS:-15}"
    ;;
  none)
    warn "SERVER_MANAGER=none - make sure the server is stopped manually before continuing."
    read -r -p "Press ENTER when the server is stopped..." 2>/dev/null || sleep 5
    ;;
  *)
    die "Unknown SERVER_MANAGER: $SERVER_MANAGER"
    ;;
esac

EXTRACT_DIR="$TEMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"
log "Extracting server pack..."
unzip -q "$TEMP_DIR/serverpack.zip" -d "$EXTRACT_DIR"

log "Applying update..."

IFS=',' read -ra PRESERVE_ARRAY <<< "$PRESERVE_ITEMS"
RSYNC_EXCLUDES=()
for item in "${PRESERVE_ARRAY[@]}"; do
  item=$(echo "$item" | xargs)
  RSYNC_EXCLUDES+=("--exclude=$item")
done

log "Clearing old mods/ directory..."
rm -rf "${SERVER_DIR}/mods"

rsync -a "${RSYNC_EXCLUDES[@]}" "$EXTRACT_DIR/" "$SERVER_DIR/"
log "Files updated."

VARS_FILE="${SERVER_DIR}/variables.txt"
if [ -f "$VARS_FILE" ] && [ -n "${VARS_PATCHES:-}" ]; then
  log "Patching variables.txt..."
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    sed -i "s|^${key}=.*|${key}=${val}|" "$VARS_FILE" 2>/dev/null || true
  done <<< "$VARS_PATCHES"
fi

if [ -f "$VARS_FILE" ]; then
  sed -i 's/^WAIT_FOR_USER_INPUT=.*/WAIT_FOR_USER_INPUT=false/' "$VARS_FILE" 2>/dev/null || true
  sed -i 's/^RESTART=.*/RESTART=false/'                         "$VARS_FILE" 2>/dev/null || true
fi

if [ -n "${SERVER_USER:-}" ]; then
  chown -R "${SERVER_USER}:${SERVER_USER}" "$SERVER_DIR" 2>/dev/null || true
fi

log "Starting server (manager: $SERVER_MANAGER)..."

case "$SERVER_MANAGER" in
  crafty)
    curl -sk -X POST "${CRAFTY_URL}/api/v2/servers/${CRAFTY_SERVER_ID}/action/start_server" \
      -H "Authorization: Bearer $CRAFTY_TOKEN" > /dev/null
    ;;
  systemd)
    sudo systemctl start "${SYSTEMD_SERVICE}"
    ;;
  screen)
    screen -dmS "${SCREEN_SESSION}" bash "${SERVER_DIR}/start.sh" 2>/dev/null || true
    ;;
  tmux)
    tmux new-session -ds "${TMUX_SESSION}" "bash ${SERVER_DIR}/start.sh" 2>/dev/null || true
    ;;
  none)
    log "SERVER_MANAGER=none - start the server manually."
    ;;
esac

echo "$LATEST_PACK_ID" > "$VERSION_FILE"

log "Update complete: $LATEST_NAME"
log "Note: mods will be re-downloaded by ServerStarterJar on next startup."
notify "Update complete: **$LATEST_NAME** - mods downloading on startup."
