# iOS Forensics on Linux

Complete operational guide and automated workflow for forensic data extraction from iOS devices using Linux tooling.

## Overview

This repository provides a comprehensive, production-ready toolkit for conducting authorized iOS forensic analysis on Linux. No jailbreak required.

**Tools used:**
- `pymobiledevice3` — Core iOS communication (USB multiplexer, developer mode)
- `UX Play` — AirPlay screen mirroring on Linux
- `Mobile Verification Toolkit (MVT)` — IOC scanning (sysdiagnose, backups)
- `libimobiledevice` — Backup, device info, file access
- `Wireshark` — PCAP analysis
- `exiftool` — Metadata extraction

## Contents

| File | Description |
|------|-------------|
| `iOS_Linux_Forensics_Guide.md` | Complete 10-phase operational guide |
| `ios_forensics_workflow.sh` | Interactive menu-driven automation script |

## Quick Start

```bash
# Clone and run
git clone https://github.com/TheRealBrofessor/ios-linux-forensics.git
cd ios-linux-forensics
chmod +x ios_forensics_workflow.sh
./ios_forensics_workflow.sh
```

## Phases Covered

1. **Environment Setup** — Install `pymobiledevice3` + dependencies via pipx/apt
2. **Screen Mirroring** — AirPlay via UX Play (UFW + Avahi)
3. **Developer Profiles** — Wi-Fi, Bluetooth, Location (72hr expiry, one-at-a-time install)
4. **WiFi Capture** — PCAP with DNS/plaintext endpoint visibility
5. **Bluetooth Capture** — HCI packets in PCAPNG format
6. **Sysdiagnose** — Full device diagnostic + MVT IOC scan
7. **Crash Logs** — List, parse, shell, clear, flush
8. **AFC Shell** — File system access + pull files
9. **GPS Metadata** — Extract coordinates → Google Maps URL
10. **Encrypted Backup** — iTunes backup + MVT analysis (optional)

## Requirements

- Ubuntu 22.04+ / Debian 12+
- iPhone with USB cable
- Apple ID enrolled in Apple Developer Program (free tier)
- iPhone + Linux on same WiFi (for mirroring)
- **Authorization:** Only run on devices you own or have explicit written permission to test

## Legal

⚠️ **FOR AUTHORIZED TESTING ONLY — OWN DEVICES ONLY**

Unauthorized access violates computer misuse laws globally. Keep research ethical.

## License

MIT License — see [LICENSE](LICENSE)

## References

- [pymobiledevice3](https://github.com/doronzo/pymobiledevice3)
- [MVT](https://github.com/mvt-project/mvt)
- [UX Play](https://github.com/uxplay/uxplay)
- [Apple Developer](https://developer.apple.com)