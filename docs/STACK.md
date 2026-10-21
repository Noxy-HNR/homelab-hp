# What each machine runs

The goal is local AI on the laptop and desktop, a shared model library, a direct server-hosted Steam game drive, and a Linux development/MCP machine. The NAS and Dell do not need CPU or RAM upgrades for the first build. The photographed ImageStream **PCIE-ETH-GIGX6** has six SFP cages and is not counted as a 10 GbE SFP+ NIC; its GIGX6 label suggests gigabit ports, pending a live PCI ID check.

## HP DL360p Gen8 — always on

- **OS and storage (deployed):** Ubuntu Server 26.04.1 LTS on the P420i's single 1.364 TiB logical drive, configured as RAID0 across five 300 GB SAS disks. LVM provides a 100 GiB ext4 root, a 500 GiB ext4 Steam volume at `/srv/steam`, and the remaining 794.82 GiB ext4 models volume at `/srv/models`; `/boot` is 2 GiB. These are separate logical volumes on the same RAID0 array, not independent or redundant disks.
- **Network (deployed):** one server network cable is connected. Ubuntu has used `192.168.1.241/24` on `eno1`; the switch-based 10 GbE links and multi-link setup are pending the required materials. No aggregate bandwidth is configured.
- **CPU and NIC inventory:** one Xeon E5-2620 (6 cores/12 threads); four Broadcom BCM5719 1 GbE controllers are visible to Ubuntu. The active link is 1 Gb/s full duplex; no 10 GbE controller appeared in the PCI inventory.
- **Software (verified so far):** OpenSSH is enabled, Samba is active, and Steam game downloads are in progress on the Steam storage. The model files were copied to the models storage. The app dashboard, Cockpit, Restic backup plans, and the managed iSCSI handoff controller are not confirmed as installed.
- **Next steps:** finish validating the Samba share names/access from the client, complete OS updates when convenient, and later install the 10 GbE hardware before attempting any multi-link configuration. Firmware versions for iLO and P420i still need confirmation.
- **Network services:** SSH and Samba are active. Samba exposes `SteamGames` (`/srv/steam`) and `ModelFiles` (`/srv/models`) to the `lab` account. The Steam downloads are in progress and the model library is stored on the server. No multi-link network setup is active.
- **Always-on containers (planned):** [`hp/always-on`](../hp/always-on/compose.yaml) moves the Relay Station Telegram bot off the Windows PC and adds an opt-in Frigate recorder, sized for the current 28 GB of RAM. See [Always-on services](ALWAYS-ON.md); Docker is not yet confirmed installed.
- **Current-use detail:** this Windows PC maps `S:` to `SteamGames` and `M:` to `ModelFiles`; see [HP current state](HP-CURRENT-STATE.md).

## Dell R710 — turn on for development

- **OS/storage:** Ubuntu Server 24.04 LTS amd64 on one PERC RAID0 virtual disk made from two 300 GB 2.5-inch HDDs in owned 3.5-inch bay adapters. This is about 559 GiB before formatting.
- **Network:** four built-in 1 GbE RJ45 ports over owned Cat5e patch leads to four 1 GbE copper SFP modules in the Cisco. Netplan `bond0` and a matching Cisco LACP EtherChannel provide up to 4 Gb/s across multiple flows; an individual transfer uses one 1 Gb/s member.
- **Software from `dell/deploy.sh`:** OpenSSH, Git/Git LFS, Python/venv/pipx, C/C++ toolchain, CMake, Ninja, ripgrep, htop, smartmontools, Docker Engine from Docker's Ubuntu repository, Compose, Buildx, Cockpit and Portainer CE.
- **Workbench:** a web app on port 8090 creates a Python starter project or imports a public GitHub repository, queues named test/build jobs, keeps bounded logs, and searches registered project text. Project sources live under `/srv/homelab-projects`.
- **MCP:** the workbench's real project and job tools bind to Dell loopback port 8765. A PC reaches them through an SSH tunnel and uses the Dell app token. Additional independent MCP services may use Docker Compose.
- **LAN services:** workbench HTTP 8090, SSH 22, Cockpit HTTPS 9090, Portainer HTTPS 9443. The MCP endpoint is reachable only through the local SSH tunnel. The Dell's containers restart when it boots, but the server must be on to use them.
- **Daily use:** use the workbench, VS Code Remote-SSH or terminal SSH for Linux projects; keep active source trees and container data on Dell storage.

## Windows desktop — local tools and 10G gaming client

- **OS/hardware:** keep Windows 11, GTX 1050 Ti, 700 W PSU and local SSD. Add one genuine used Intel X540-T1 10GBASE-T RJ45 PCIe x8 card in the free x16 slot with the proper bracket and airflow. One pure-copper Cat6A cable goes to one Cisco 10GBASE-T SFP+ module.
- **Software from `desktop/install.ps1`:** Git, VS Code, PowerShell 7, uv, Steam, Windows Subsystem for Linux with Ubuntu, Docker Desktop, a small local Ollama/Qwen3 assistant, and the Homelab Control Center shortcut when both server IPs are supplied. The local model directory stays on a local fixed drive.
- **Steam:** use the shared iSCSI volume as `S:` only while the desktop owns it. `GameDrive.ps1` handles attach/release. It does not format the volume.

## Windows laptop — main AI client

- **OS/hardware:** keep Windows 11 and the existing native llama.cpp, Switchboard, model, recorder and GPU settings. Add a USB4/Thunderbolt 10GBASE-T RJ45 adapter with Windows driver. Its own Cat6A cable goes to a separate copper module in the Cisco.
- **Software from `laptop/install.ps1`:** add Git, VS Code, PowerShell 7, uv and Steam if missing. Supplying both server IPs also creates the Homelab Control Center shortcut. The installer does not replace the laptop's current `C:\AI` model stack.
- **Models:** store larger GGUF files in `\\HP-IP\Models` and register selected files as links in `C:\AI\models` with `laptop/NetworkModels.ps1`. The laptop loads the selected file over SMB and runs inference locally. Keep the lightweight fallback model on the laptop for offline use.
- **MCP:** Switchboard stays local on the laptop. Dell MCP services are optional additions through SSH forwarding.
- **Steam:** attach the same `S:` volume only after a clean release from the desktop.

## Cisco 3850-24XS — LAN switch

- Keep its current IOS XE and uplink. Use one SFP+ port for HP fiber, one 10GBASE-T module for each PC, and four 1 GbE copper SFP ports for Dell LACP. The example port numbers and VLAN in `switch/candidate.txt` are **placeholders** to adapt at the console.
- A four-port LACP group does not need QSFP. No firmware upgrade is included in the first deployment.

## Limits and recovery

The HP and Dell HDD arrays are RAID0: one member failure loses the entire corresponding array. GitHub backs up only code you commit and push. Keep an independent copy of irreplaceable files, credentials, game saves, and configuration exports. The scripts are safe to re-run when their existing managed files match, and stop on a conflicting configuration instead of overwriting it.
