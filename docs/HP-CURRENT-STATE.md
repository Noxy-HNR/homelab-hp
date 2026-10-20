# HP DL360p Gen8: current deployment

Last checked: **2026-10-20**. This is the installed machine, distinct from the future network plan in the older setup guides.

## Hardware and storage

- HP ProLiant DL360p Gen8 with the Smart Array P420i.
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
- The 10 GbE switch links and any multi-link configuration are pending the required hardware and cabling. Current transfers use the single connected path.
- OpenSSH is enabled and Samba is active. The current Samba shares are `SteamGames` at `/srv/steam` and `ModelFiles` at `/srv/models`, both restricted to the `lab` account. The mounted volumes currently report about 420 GiB free for Steam and 707 GiB free for models. Steam downloads are underway; the model copy to the server was checksum-verified in the earlier transfer run.
- Password rotation is intentionally deferred.

## Updates and firmware

- Package metadata was refreshed and one small Python package update was installed. The simulated upgrade still showed other packages held or phased, so the OS is not fully updated yet. Avoid a reboot or disruptive service restart while Steam is downloading.
- The system BIOS reports HP P71 dated 2019-05-24. The P420i firmware version and installed iLO 4 version have not been confirmed. Do not report those as updated.

## Still to verify or decide

- Confirm Windows access to the configured `SteamGames` and `ModelFiles` shares.
- Finish remaining Ubuntu updates at a convenient time, then verify installed firmware versions before choosing any update.
- Add and configure the 10 GbE links after the switch materials arrive; until then, keep the working single-cable connection.
- The dashboard, Cockpit, Restic backup plans, and managed iSCSI handoff controller are not confirmed as installed. Decide whether they are wanted for this build before installing them.

## Installer compatibility

The existing `hp/deploy.sh` and much of `docs/setup/HP.md` describe an earlier Ubuntu 24.04 layout using `/srv/homelab`, `/srv/bulk`, and a 10 GbE interface. They have **not** been adapted to this Ubuntu 26.04.1 layout. Do not run that installer on this server until its assumptions and services are reviewed against the live mounts and network.
