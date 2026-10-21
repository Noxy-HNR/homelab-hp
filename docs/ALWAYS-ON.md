# Always-on services on the HP

This page moves the services that should run all day off the Windows PC and onto the HP, using the Docker Compose stack in [`hp/always-on`](../hp/always-on/compose.yaml). It is written for the HP as it is installed today: Ubuntu 26.04.1, **28 GB of RAM** (about 26 GiB visible to Ubuntu), one Xeon E5-2620, no GPU, and one RAID0 logical drive. See [HP current state](HP-CURRENT-STATE.md).

Nothing here creates arrays, partitions, filesystems or logical volumes.

## What moves and what stays

This inventory comes from [Noxy-HNR/ai-workspace](https://github.com/Noxy-HNR/ai-workspace) on `main` (2026-10-21).

| PC service | Port on the PC | Decision | Why |
| --- | --- | --- | --- |
| **Relay Station** (Telegram bot, `TelegramBot/`) | 9095 | **Moves to the HP** | A long-polling bot only answers while its host is on. It is Python standard library only and needs about 100 MB of RAM. |
| **Frigate** (camera recordings) | none yet | **New on the HP, opt-in** | No Frigate config exists in either repository. The stack includes a disabled template so recordings start on the always-on machine, not the PC. |
| Local AI dashboard (`dashboard-server.ps1`) | 9090 | Stays on the PC | It starts and stops the PC's own `llama-server.exe` and edits `C:\AI\Config\models.json`. It has nothing to manage on the HP. |
| llama-server (CUDA) | 10000 | Stays on the PC | It needs the PC's GPU. A CPU llama-server on the HP is a separate piece of work. |
| Request-logging proxy (`llama-proxy.py`) | 10001 | Stays on the PC | It is a debugging aid with the PC's llama-server address and `C:\AI\logs` path built in. Moving it would add a network hop to every request. |
| cptr | 8000 | Stays on the PC | Its tools are Windows filesystem, command and browser automation on the PC itself. |
| On-device inference (`Tools/npu-services`) | 8788 | Stays on the PC | It runs on the PC's Intel iGPU and NPU. |
| Homelab app (`services/homelab`) | 8088 on the HP | Already running on the HP | A live check on 2026-10-21 found it as a systemd service from `/opt/homelab/apps`. This stack leaves it alone. |

The **retrieval proxy** is not in either repository. It lives only on the PC as `C:\AI\rag\rag_proxy.py` (started by `C:\AI\rag\start-rag.ps1`) and listens on `127.0.0.1:8090` in front of a llama-server on port 8080. It **stays on the PC for now**. Every request it handles goes to that GPU model, so moving it alone would add a network round trip and still need the PC on. Move it together with its model once a model runs on the HP, after its source is committed to ai-workspace so it can be built here like Relay Station. Port 8090 does not clash with anything in this stack.

## Ports

A live check on 2026-10-21 found ports 22 (SSH), 139 and 445 (Samba) and 8088 (homelab app) in use on the HP. This stack does not use any of them. It adds 9095 (loopback only), and with Frigate also 5000 (loopback only), 8971, 8554 and 8555 on `HP_LAN_IP`.

## Resource budget at 28 GB

| Service | Memory limit | CPU limit | Data |
| --- | ---: | ---: | --- |
| Relay Station | 512 MiB | 1 core | `/srv/services/relay-station` (a few MB) |
| Frigate (optional) | 4 GiB, plus 256 MB shared memory and a 1 GB tmpfs cache | 4 cores | config in `/srv/services/frigate/config`, recordings in `FRIGATE_MEDIA_DIR` |
| **Total** | **about 6 GiB** | | |

That leaves about 20 GiB for Ubuntu, the Samba page cache and a CPU llama-server. When the 96 GB upgrade lands, raise `FRIGATE_MEMORY` and `FRIGATE_CPUS` in `.env` only if Frigate's own stats show it needs more.

## Storage

Everything sits on the P420i **RAID0** logical drive. One failed disk loses all of it, so the backup step below is not optional.

The LVM volume group is fully allocated: `/` has 100 GiB, `/srv/steam` 500 GiB and `/srv/models` 795 GiB. Service state therefore goes to `/srv/services` on the root volume. That is fine for Relay Station. For Frigate, the template keeps 3 days of motion-only recording, roughly 20 to 40 GiB per camera. If you want longer retention, give recordings their own logical volume and point `FRIGATE_MEDIA_DIR` at it. Shrinking `/srv/models` to make room means unmounting it and running `resize2fs` before `lvreduce`, so plan it as a separate, backed-up maintenance step.

## 1. Install Docker Engine

Docker is not confirmed as installed on the HP. Ubuntu's own packages are the simplest choice on 26.04:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 git
sudo systemctl enable --now docker
docker compose version
```

Docker's own repository also works if it lists Ubuntu 26.04 by the time you install. Do not add your login to the `docker` group unless you accept that it is equivalent to root.

## 2. Get the code and settings

```bash
sudo git clone https://github.com/Noxy-HNR/ai-workspace /opt/ai-workspace
cd ~/homelab-stack/hp/always-on        # your clone of this repository
sudo bash prepare-host.sh install      # first run creates .env (mode 600) and stops
sudoedit .env                          # check HP_LAN_IP, paths, TZ
sudo bash prepare-host.sh plan         # read the warnings
sudo bash prepare-host.sh install      # creates /srv/services/... and the Frigate config copy
```

`.env` is ignored by Git. It holds camera credentials only. The Telegram bot token is not in `.env`; it travels inside Relay Station's database in the next step.

## 3. Move Relay Station

Only one machine may poll a Telegram bot at a time. A second poller gets `409 Conflict` from Telegram, and the data-folder lock cannot detect another computer.

**Step 1. On the PC**, stop the bot: use **Stop** on the Relay Station card in the dashboard at `http://127.0.0.1:9090`, or run `powershell -File C:\AI\TelegramBot\stop-telegram-bot.ps1`. Confirm nothing listens on 9095: `Get-NetTCPConnection -LocalPort 9095 -State Listen` returns nothing.

**Step 2. Copy the database** from the PC. It holds the token, settings, users and chat history:

```powershell
# HP_LOGIN is your Ubuntu login on the HP
scp C:\AI\TelegramBot\data\bot.db HP_LOGIN@192.168.1.241:/tmp/bot.db
```

**Step 3. On the HP**, put it in place and start the service:

```bash
cd ~/homelab-stack/hp/always-on
sudo docker compose build --pull       # build first, so a failed build leaves nothing half-moved
sudo install -m 600 -o 10001 -g 10001 /tmp/bot.db /srv/services/relay-station/bot.db && rm /tmp/bot.db
sudo docker compose up -d
sudo docker compose ps                 # relay-station shows (healthy) within a minute
```

To start fresh instead, skip the copy and paste the @BotFather token in Settings after step 4.

**Step 4. Open the console** through SSH (replace `HP_LOGIN` with your Ubuntu login on the HP). The console is loopback-only on the HP by design and has no password of its own:

```powershell
ssh -L 9095:127.0.0.1:9095 HP_LOGIN@192.168.1.241
```

Then browse to `http://127.0.0.1:9095` on the PC.

**Step 5. Point it at a model.** The saved LLM URL `http://127.0.0.1:10000/v1` now means the HP itself. Pick one:
- A llama-server on the HP: keep the loopback URL with the HP server's port. No remote setting is needed.
- The PC's llama-server: set the URL to `http://PC_IP:10000/v1` and turn on **Allow remote model endpoint**. The PC's llama-server must listen on its LAN address instead of `127.0.0.1`, and the bot replies with its model-error message whenever the PC is off.

Use **Test LLM** and **Test Telegram** in the console, then send the bot a message.

**Step 6. On the PC**, stop using the Relay Station card's **Start** button and the **Relay Station - Telegram Bot** shortcut. Either one starts a second poller. Keep `C:\AI\TelegramBot\data\bot.db` for a few days as the rollback copy.

## 4. Add Frigate (optional)

**Step 1.** Edit `/srv/services/frigate/config/config.yml`: replace `192.0.2.10` and the stream paths with your camera's, and set `enabled: true`. Use the camera's low-resolution sub stream for `detect`.

**Step 2.** Put the camera login in `.env` as `FRIGATE_RTSP_USER` and `FRIGATE_RTSP_PASSWORD`. Frigate substitutes them into the config, so the password never appears in `config.yml`.

**Step 3.** Start it and read the first admin password:

```bash
sudo docker compose --profile nvr up -d
sudo docker compose logs frigate | grep -i password
```

**Step 4.** Open `https://192.168.1.241:8971` (self-signed certificate), sign in and change the password. Port 5000, the unauthenticated API, is bound to the HP's loopback only.

Every later `docker compose` command that should start, stop, rebuild or update Frigate needs `--profile nvr`.

The E5-2620 has AVX but not AVX2. Frigate's CPU object detector works without AVX2, but it is slow, which is why the template keeps detection at 5 fps on a sub stream. Leave Frigate's optional semantic search, face recognition and licence-plate features off on this CPU. If the container restarts in a loop, look for `Illegal instruction` in `sudo docker compose logs frigate`. That means a component needs a newer instruction set, so stay on the pinned version and report it instead of upgrading blind.

## 5. Verify

- `sudo docker compose --profile nvr ps` shows every service `(healthy)`.
- After a planned reboot, both containers come back on their own (`restart: unless-stopped`, and Docker is enabled at boot).
- `free -g` still shows well over 10 GiB available with everything running.
- Send the bot a message with the PC switched off. It replies if its model runs on the HP.

## Updates

```bash
sudo git -C /opt/ai-workspace pull --ff-only
cd ~/homelab-stack && git pull --ff-only && cd hp/always-on
sudo docker compose --profile nvr build --pull
sudo docker compose --profile nvr pull
sudo docker compose --profile nvr up -d
```

Frigate's version is pinned in `.env` as `FRIGATE_VERSION`. Read Frigate's release notes before raising it, since config keys change between releases.

## Backups

RAID0 makes these copies the only protection. Take a consistent copy of the bot database while it runs, then copy it off the HP:

```bash
sudo apt install -y sqlite3
sudo sqlite3 /srv/services/relay-station/bot.db ".backup '/srv/services/relay-station-backup.db'"
```

Copy that file and `/srv/services/frigate/config/config.yml` to the PC or the Dell. Recordings are not backed up by this page.

## Roll back

1. On the HP: `sudo docker compose --profile nvr down`. Data folders are kept.
2. Copy `/srv/services/relay-station/bot.db` back to `C:\AI\TelegramBot\data\bot.db` on the PC if the bot ran on the HP long enough to collect new chats.
3. Start Relay Station from the PC dashboard again.
