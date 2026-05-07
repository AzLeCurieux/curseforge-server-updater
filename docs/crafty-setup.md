# Crafty Controller Setup

This guide explains how to configure `curseforge-server-updater` with [Crafty Controller](https://craftycontrol.com).

## Prerequisites

- Crafty Controller installed and running
- A server configured in Crafty with a CurseForge modpack that provides a server pack
- Admin credentials for Crafty

## Step 1: Find your Server UUID

The script needs your server's UUID to call the Crafty API.

**From the Crafty URL:**  
Open your server in Crafty and look at the URL:
```
https://your-crafty:8443/panel/server_detail?id=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```
The UUID is the value of the `id` parameter.

**From the database:**
```bash
sqlite3 /path/to/crafty/config/db/crafty.sqlite \
  "SELECT server_uuid, server_name FROM servers;"
```

## Step 2: Configure .env

```bash
cp .env.example.crafty .env
nano .env
```

Fill in:

```env
CF_API_KEY=your_curseforge_api_key
CF_PROJECT_ID=1518930
CF_GAME_VERSION=1.21.1

SERVER_DIR=/srv/crafty/servers/your-server-name
SERVER_MANAGER=crafty

CRAFTY_URL=https://127.0.0.1:8443
CRAFTY_USER=admin
CRAFTY_PASS=your_admin_password
CRAFTY_SERVER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

RUN_BACKUP_BEFORE=true
BACKUP_SCRIPT=/srv/crafty/backup-complet.sh
```

## Step 3: Run

```bash
# Dry run first
sudo ./update-modpack.sh --check

# Apply update
sudo ./update-modpack.sh
```

## Notes

- The script connects to Crafty at `127.0.0.1:8443`. If Crafty runs in Docker, make sure port 8443 is bound to the host.
- The script uses Crafty's REST API (`/api/v2/servers/{id}/action/stop_server` and `start_server`).
- If you run Crafty in Docker, `SERVER_DIR` should be the host-side bind-mount path, not the container path.

## Scheduling

Add to root's crontab to run nightly at 04:00:

```bash
sudo crontab -e
```

```cron
0 4 * * * /path/to/curseforge-server-updater/update-modpack.sh >> /srv/crafty/logs/update-modpack.log 2>&1
```
