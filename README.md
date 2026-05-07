<div align="center">

# CurseForge Server Updater

**A lightweight Bash script that keeps your CurseForge modpack server up-to-date automatically.**  
No Docker required. Works with any server manager.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](update-modpack.sh)
[![CurseForge](https://img.shields.io/badge/API-CurseForge-F16436?logo=curseforge&logoColor=white)](https://console.curseforge.com)
[![Minecraft](https://img.shields.io/badge/Minecraft-1.20%2B-62B47A?logo=minecraft&logoColor=white)](https://minecraft.net)

</div>

## What it does

When you run it, this script:

1. **Checks** the CurseForge API for a new server pack release
2. **Skips** silently if you're already on the latest version
3. **Backs up** your world and key configs before touching anything
4. **Downloads** the new server pack via the authenticated CurseForge API
5. **Stops** your server (via Crafty, systemd, screen, or tmux)
6. **Applies** the update : overwriting mods and configs, **never** your world
7. **Restarts** the server; mods re-download automatically on first boot

Works with any CurseForge modpack that publishes a **server pack** file (All of Create, ATM, Vault Hunters, FTB, etc.).

## Requirements

| Tool | Purpose |
|---|---|
| `bash` >= 4 | Script runtime |
| `curl` | CurseForge API + download |
| `unzip` | Extract server pack |
| `rsync` | Apply files while skipping preserved items |
| `python3` | Parse API JSON responses |

All standard on Debian/Ubuntu. Install any missing:
```bash
sudo apt install curl unzip rsync python3
```

## Getting a CurseForge API Key

You need a free CurseForge API key — takes under 2 minutes.

1. Go to [console.curseforge.com](https://console.curseforge.com) and sign in.
2. In the left sidebar, click **API Keys**.
3. Click **Generate API Key** and give it a name (e.g. `mc-server`).
4. Copy the key immediately - it's only shown once.

> Free tier: 10,000 requests/day, more than enough for daily checks.

## Finding Your Project ID

Open the modpack page on CurseForge. The **Project ID** is in the **About** panel on the right side of the page.

## Installation

```bash
git clone https://github.com/AzLeCurieux/curseforge-server-updater.git
cd curseforge-server-updater
chmod +x update-modpack.sh

# Pick the right template:
cp .env.example .env             # systemd, screen, or tmux
# or
cp .env.example.crafty .env      # Crafty Controller

nano .env
chmod 600 .env
```

## Configuration

All settings live in `.env`. Minimum required:

```bash
CF_API_KEY=your_api_key_here
CF_PROJECT_ID=1518930
SERVER_DIR=/opt/minecraft/server
SERVER_MANAGER=systemd
```

### Full .env reference

#### CurseForge

| Variable | Required | Description |
|---|---|---|
| `CF_API_KEY` | yes | Your CurseForge API key |
| `CF_PROJECT_ID` | yes | Modpack project ID |
| `CF_GAME_VERSION` | yes | Minecraft version (e.g. `1.21.1`) |

#### Server

| Variable | Default | Description |
|---|---|---|
| `SERVER_DIR` | yes | Absolute path to your server directory |
| `PRESERVE_ITEMS` | see below | Comma-separated files/folders to never overwrite |
| `SERVER_USER` | | OS user that owns server files (for permission fix) |

Default preserved items:
```
world, server.properties, whitelist.json, ops.json,
banned-players.json, banned-ips.json, eula.txt,
server.jar, user_jvm_args.txt
```

#### Server Manager

| Variable | Default | Description |
|---|---|---|
| `SERVER_MANAGER` | `none` | `crafty` \| `systemd` \| `screen` \| `tmux` \| `none` |
| `STOP_WAIT_SECONDS` | `15` | Seconds to wait after stop command |
| `SYSTEMD_SERVICE` | | Service name (if `systemd`) |
| `SCREEN_SESSION` | | Session name (if `screen`) |
| `TMUX_SESSION` | | Session name (if `tmux`) |

#### Crafty Controller

| Variable | Description |
|---|---|
| `CRAFTY_URL` | Crafty base URL, e.g. `https://127.0.0.1:8443` |
| `CRAFTY_USER` | Crafty admin username |
| `CRAFTY_PASS` | Crafty admin password |
| `CRAFTY_SERVER_ID` | Server UUID (from Crafty UI or database) |

#### Backup

| Variable | Default | Description |
|---|---|---|
| `RUN_BACKUP_BEFORE` | `false` | Create a backup before updating |
| `BACKUP_DIR` | `./backups` | Where to save automatic backups |
| `BACKUP_SCRIPT` | | Path to a custom backup script |

#### Notifications

| Variable | Description |
|---|---|
| `DISCORD_WEBHOOK` | Discord webhook URL for update notifications |

## Usage

```bash
# Check only, nothing is changed
./update-modpack.sh --check
# exit 0 = up to date  |  exit 1 = update available

# Check and apply the update
sudo ./update-modpack.sh
```

Example output:
```
2026-05-07 10:00:01  INFO  CurseForge Server Updater - project 1518930
2026-05-07 10:00:01  INFO  Installed server pack ID: 6601234
2026-05-07 10:00:02  INFO  Querying CurseForge API...
2026-05-07 10:00:02  INFO  Latest available: All of Create Aeronautics - v1.4 (ID: 6669879)
2026-05-07 10:00:02  INFO  Updating: 6601234 -> 6669879 (All of Create Aeronautics - v1.4)
2026-05-07 10:00:03  INFO  Running backup script...
2026-05-07 10:00:45  INFO  Backup saved: pre-update-2026-05-07_10-00-03.tar.gz (118MB)
2026-05-07 10:00:45  INFO  Getting download URL...
2026-05-07 10:00:46  INFO  Downloading: https://edge.forgecdn.net/files/...
2026-05-07 10:00:49  INFO  Downloaded: 7.9M
2026-05-07 10:00:49  INFO  Stopping server (manager: crafty)...
2026-05-07 10:01:05  INFO  Extracting server pack...
2026-05-07 10:01:05  INFO  Applying update...
2026-05-07 10:01:05  INFO  Clearing old mods/ directory...
2026-05-07 10:01:06  INFO  Files updated.
2026-05-07 10:01:06  INFO  Patching variables.txt...
2026-05-07 10:01:06  INFO  Starting server (manager: crafty)...
2026-05-07 10:01:07  INFO  Update complete: All of Create Aeronautics - v1.4
2026-05-07 10:01:07  INFO  Note: mods will be re-downloaded by ServerStarterJar on next startup.
```

## Automating with cron

```bash
sudo crontab -e
```

```cron
# Check and apply modpack updates every day at 04:00
0 4 * * * /path/to/curseforge-server-updater/update-modpack.sh >> /var/log/mc-updater.log 2>&1
```

Check-only (alert via Discord, update manually):
```cron
0 4 * * * /path/to/curseforge-server-updater/update-modpack.sh --check
```

## How the update works

The script queries the CurseForge API for the latest server pack file ID. If it differs from what's stored in `.installed-version`, it downloads the pack (typically 7-15 MB), stops the server, clears the `mods/` directory, and rsyncs the new files while skipping anything in `PRESERVE_ITEMS`. On next startup, the server launcher (ServerStarterJar or equivalent) re-downloads the actual mod JARs from CurseForge CDN.

> **Why only ~8 MB?** Modern packs ship a lightweight bootstrap: a manifest + small launcher JAR. The mods (~300-600 MB) download on first boot. That's also why `mods/` gets cleared on each update — to force the launcher to fetch the correct new versions.

## Crafty Controller

Use `.env.example.crafty` as your starting point.

**Finding your Server UUID:**

From the Crafty URL:
```
https://your-crafty:8443/panel/server_detail?id=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Or from the terminal:
```bash
sqlite3 /path/to/crafty/config/db/crafty.sqlite \
  "SELECT server_uuid, server_name FROM servers;"
```

See [docs/crafty-setup.md](docs/crafty-setup.md) for the full Crafty guide.

## ServerStarterJar & variables.txt

Many CurseForge server packs use [ServerStarterJar](https://github.com/neoforged/ServerStarterJar) to bootstrap the server. Each update ships a new `variables.txt` that can reset settings you customized.

Use `VARS_PATCHES` in `.env` to re-apply your settings after every update:

```bash
VARS_PATCHES=SKIP_JAVA_CHECK=true
JAVA="/usr/bin/java"
SERVERSTARTERJAR_FORCE_FETCH=false
WAIT_FOR_USER_INPUT=false
```

## Discord Notifications

Set `DISCORD_WEBHOOK` in `.env`:

```bash
DISCORD_WEBHOOK=https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
```

You'll get a message when a new version is found, when an update completes, or when an error occurs.

## Comparison with docker-minecraft-server

| | docker-minecraft-server | **This script** |
|---|---|---|
| Requires Docker | yes | no |
| Works with Crafty Controller | no | yes |
| Works with systemd / screen / tmux | no | yes |
| Standalone (no image rebuild) | no | yes |
| Custom backup before update | no | yes |
| Discord notifications | no | yes |
| Update check only (--check) | no | yes |

Use [`itzg/docker-minecraft-server`](https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/mod-platforms/auto-curseforge/) if you run a pure Docker setup. Use this script if you manage your server with Crafty, systemd, or any other non-Docker tool.

## Troubleshooting

**`No server pack found`**  
The modpack may not publish a server pack. Check the modpack's Files page for an entry labeled "Server Pack".

**`Could not get download URL`**  
Your `CF_API_KEY` may be invalid or expired. Regenerate it at [console.curseforge.com](https://console.curseforge.com).

**Update re-applies every run**  
The `.installed-version` file is missing. Run once without `--check` to create it, or set it manually:
```bash
echo "CURSEFORGE_FILE_ID" > .installed-version
```

**Mods not downloading on startup**  
Check that `WAIT_FOR_USER_INPUT=false` and `RESTART=false` are set in `variables.txt`.

**Permission denied on server files**  
Run with `sudo`, or set `SERVER_USER` in `.env`.

## Contributing

Issues and PRs welcome. When reporting a bug, include your `SERVER_MANAGER` value, relevant log lines, and the modpack project ID.

## License

[MIT](LICENSE) © 2026 AzLeCurieux
