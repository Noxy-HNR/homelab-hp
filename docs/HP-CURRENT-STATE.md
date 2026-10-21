# HP DL360p Gen8: current deployment

Last checked: **2026-10-21**. This is the installed machine, distinct from the future network plan in the older setup guides.

## Hardware and storage

- HP ProLiant DL360p Gen8 with the Smart Array P420i.
- One Intel Xeon E5-2620 at 2.00 GHz (6 cores, 12 threads); Ubuntu reports 26 GiB of RAM available to the OS.
- One **1.364 TiB logical drive** configured as RAID0 from five 300 GB SAS disks. One failed disk was left out before the logical drive was created.
- Ubuntu Server **26.04.1 LTS** is installed on that logical drive. The disk uses LVM and ext4:

| Mount | Logical volume | Size |
| --- | --- | ---: |
| `/` | `ubuntu-lv` | 100 GiB |
| `/boot` | disk partition | 2 GiB |
| `/srv/steam` | `steam` | 500 GiB |
| `/srv/models` | `models` | 794.82 GiB |

The Steam and models areas are separate logical volumes on the **same RAID0 array**. They are not separate physical arrays and RAID0 provides no disk-failure protection.

## Network and services

- One server network cable is in use. The last verified Ubuntu address was `192.168.1.241/24` on `eno1`.
- PCI inventory shows four Broadcom BCM5719 1 GbE controllers. `eno1` currently negotiates 1,000 Mb/s full duplex. This inventory did not show a 10 GbE controller.
- The 10 GbE switch links and any multi-link configuration are pending the required hardware and cabling. Current transfers use the single connected path.
- UFW is active. It allows TCP 22 (SSH), 445 (SMB) and 8088 (homelab-app) from `192.168.1.0/24` only; anything else from the LAN, including the llama-server port 10000, is blocked until a rule is added.
- OpenSSH is enabled and Samba is active. The current Samba shares are `SteamGames` at `/srv/steam` and `ModelFiles` at `/srv/models`, both restricted to the `lab` account. The mounted volumes currently report about 420 GiB free for Steam and 707 GiB free for models. Steam downloads are underway; the model copy to the server was checksum-verified in the earlier transfer run.
- On the current Windows PC, `S:` maps to `\\192.168.1.241\SteamGames` and `M:` maps to `\\192.168.1.241\ModelFiles`; both mappings report `OK`, and TCP port 445 is reachable.
- Password rotation for `lab` (Linux and Samba) is still pending.

## Services

- Docker 29.1 is installed. The [always-on stack](ALWAYS-ON.md) runs Relay Station as `hp-always-on-relay-station-1` (healthy).
- `llama-server.service` runs llama.cpp v0.7.0 (`/opt/llama.cpp/current`) as the `llama` account on port 10000 with Cyber-Tiel-Coder-35B-A3B (UD-IQ3_XXS, 13 GB) mmapped from `/srv/models/Models`. Every request except `/health` needs the key in `/etc/homelab/llama-server/api-keys`.
- Measured on 2026-10-21 with 6 threads: prompt processing about 12.6 tokens/s, generation about 5.2 tokens/s, and about 14.3 GB of memory in use against the 18 GB service cap.
- The `llama` account reads models through POSIX ACLs on `/srv/models` and `/srv/models/Models` (including a default ACL for new files). On this Ubuntu release `/usr/bin/test` comes from uutils coreutils and ignores ACLs, so `runuser -u llama -- test -r FILE` reports a false failure. Check access with `runuser -u llama -- head -c1 FILE` instead.
- `homelab-app.service` (port 8088) and `smbd` are active.

## Updates and firmware

- On 2026-10-21 `apt-get upgrade` had nothing it would install. The 13 remaining updates (the systemd 259.9 stack, cloud-init 26.2 and `ubuntu-server-minimal`) are Ubuntu phased updates, at 30% and 10% rollout. Unattended upgrades are enabled and will install them as the rollout reaches this machine. No reboot is pending.
- The last boot was 2026-10-21 02:10 UTC. After it, both Windows mappings (`S:` and `M:`) reconnected on first access.
- Firmware read from the running system: system BIOS **P71 2019-05-24**, iLO 4 **2.82** (from `ipmitool mc info`), Smart Array P420i **3.54** (from the `hpsa` driver). The controller firmware is far behind HP's last P420i release. The array is RAID0 with no redundancy, so do not flash the controller without a current backup of anything that cannot be recreated.

## Still to verify or decide

- Decide whether to update the P420i firmware (back up first).
- Decide whether to open TCP 10000 to `192.168.1.0/24` so PCs can reach llama-server.
- Add and configure the 10 GbE links after the switch materials arrive; until then, keep the working single-cable connection.
- The CPU model server (`llama-server`, [CPU model server](features/LLM.md)) was deployed on 2026-10-21 with the `Cyber-Tiel-Coder-35B-A3B` model already on the share. Port 10000 needs a `ufw` rule for the LAN; re-running its installer adds one.
- Frigate in the always-on stack is optional and not enabled. See [Always-on services](ALWAYS-ON.md).
- The dashboard, Cockpit, Restic backup plans, and managed iSCSI handoff controller are not confirmed as installed. Decide whether they are wanted for this build before installing them.

## Installer compatibility

The existing `hp/deploy.sh` and much of `docs/setup/HP.md` describe an earlier Ubuntu 24.04 layout using `/srv/homelab`, `/srv/bulk`, and a 10 GbE interface. They have **not** been adapted to this Ubuntu 26.04.1 layout. Do not run that installer on this server until its assumptions and services are reviewed against the live mounts and network.
