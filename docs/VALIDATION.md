# Validation status

**The HP DL360p Gen8 has been installed and has live storage and network use; the remaining planned hardware and service setup is still pending.** The rest of this repository's installers and mocked tests do not prove that a Smart Array, PERC, optic, cable or Windows driver will work on the target machine. See [HP current state](HP-CURRENT-STATE.md) for the live HP record.

From a Windows clone with Python and Git for Windows installed, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\verify-source.ps1 -Applications
```

On 2026-09-24 the source verification passed: Bash and PowerShell syntax, Python compilation, the LIO and Steam controller tests, the handoff SSH identity checks, local guide links and diagrams, ignored client secrets, Windows control app guards, and **190 application tests passed, one Linux-only test was skipped**. `node --check` passed for the browser app. A local HTTP preview also signed in to the HP and Dell pages; it listed a sample GGUF, created a Dell example project, ran its test job, and found indexed text. The screenshots in `docs/assets` show that local preview, not the physical servers.

The suite does **not** install packages on the HP or Dell, create arrays, format a disk, open iSCSI sessions, configure the switch, or edit the current laptop's local AI stack. The first real installation remains the hardware acceptance test.

| Machine | First live checks needed during installation |
| --- | --- |
| HP | **Confirmed:** one P420i RAID0 logical drive; Ubuntu 26.04.1; ext4 LVM volumes mounted at `/`, `/srv/steam`, and `/srv/models`; Samba shares `SteamGames` and `ModelFiles` map to the two data mounts; Steam downloads underway; one network cable. **Pending:** verify Windows access and mount persistence after a planned reboot; install 10 GbE switch materials; confirm iLO/P420i firmware; decide whether dashboard, backup plans, and managed iSCSI handoff are needed. |
| Dell | PERC shows the correct two-HDD volume; four onboard 1G ports are bundled in Cisco and `/proc/net/bonding/bond0`; Docker, workbench project/test/search, MCP tool connection, Cockpit and Portainer work after reboot. |
| Desktop | Genuine X540-T1 driver loads, NIC fits and stays cool, Cat6A link negotiates 10 Gb/s; Windows tools install and a game launches from `S:`. |
| Laptop | USB4/Thunderbolt adapter loads and negotiates 10 Gb/s; existing `C:\AI` stack remains intact; selected GGUF loads from SMB; game launches after exclusive handoff. |
| Switch | Actual VLAN and unused ports match the candidate, 10G copper modules are accepted, optical HP port is up, Dell EtherChannel has four bundled members. |

Record failures before changing any other layer. The [main install guide](INSTALL.md) lists the order so a broken link or mount is caught before services depend on it.
