# iOS Forensics on Linux: Complete Operational Guide

**Target:** Ubuntu/Debian Linux  
**Device:** iPhone (USB + WiFi)  
**Authorization:** Owner-only / explicit permission required

---

## ⚠️ Scope & Legal
This guide covers forensic data extraction from iOS devices using Linux tooling.  
**Only run on devices you own or have explicit written authorization to test.**  
Unauthorized access violates computer misuse laws globally. Keep research ethical.

---

## 📋 Prerequisites
- Linux machine (Ubuntu 22.04+/Debian 12+)
- iPhone with Lightning/USB-C cable
- Apple ID enrolled in Apple Developer Program (free tier sufficient)
- iPhone and Linux on same WiFi network (for AirPlay mirroring)
- Basic terminal competence

---

## 🛠️ Phase 1: Environment Setup

### 1.1 Install pymobiledevice3
```bash
sudo apt update && sudo apt install -y pipx
pipx ensurepath
pipx install pymobiledevice3
pipx upgrade pymobiledevice3   # ensure latest
```

### 1.2 Install Supporting Tools
```bash
sudo apt install -y \
    uxplay \
    wireshark \
    libimage-exiftool-perl \
    libimobiledevice-utils \
    avahi-daemon
```

### 1.3 Verify Device Connection
```bash
pymobiledevice3 doctor
ideviceinfo -s
```
**Expected:** Device model, iOS version, pairing status, USB multiplexer (usbmuxd) active.

---

## 📱 Phase 2: Screen Mirroring (AirPlay via UX Play)

### 2.1 Configure Firewall
```bash
sudo ufw allow 5353/udp                    # mDNS/Bonjour
sudo ufw allow 35000:35002/udp             # AirPlay data
sudo ufw allow 35000:35002/tcp             # AirPlay control
sudo ufw status verbose                    # verify
```

### 2.2 Start mDNS Responder
```bash
sudo systemctl start avahi-daemon.service
sudo systemctl status avahi-daemon.service --no-pager
```

### 2.3 Launch AirPlay Receiver
```bash
uxplay -d Linux -p 35000
```
*Keep this terminal open. The receiver advertises as "Linux" on port 35000.*

### 2.4 Connect iPhone
1. iPhone → Control Center (swipe down top-right)
2. Tap **Screen Mirroring** (two overlapping rectangles)
3. Select **"Linux"**
4. Terminal shows connection request with device ID — mirroring active

### 2.5 Teardown (Run When Done)
```bash
# Ctrl+C in UX Play terminal first, then:
sudo ufw delete allow 5353/udp
sudo ufw delete allow 35000:35002/udp
sudo ufw delete allow 35000:35002/tcp
sudo ufw status verbose
sudo systemctl stop avahi-daemon.service
```

---

## 🔐 Phase 3: Apple Developer Profiles (Enhanced Logging)

**Profiles unlock expanded logging for WiFi, Bluetooth, and Location.**  
**Install ONE AT A TIME — batch installs fail.**  
**Profiles expire after 72 hours. Re-download as needed.**

### 3.1 Enroll / Sign In
On iPhone (via mirrored screen or directly):
1. Safari → `developer.apple.com` → Sign in with Apple ID
2. Enroll in Apple Developer Program (free tier)

### 3.2 Download & Install Profiles
Navigate to **Profiles and Logs** (upper right). For each profile:

| Profile | Purpose |
|---------|---------|
| Wi-Fi Performance Diagnostics (iOS) | Full DNS/plaintext endpoint visibility |
| Bluetooth Logging (iOS) | Expanded HCI packet capture |
| Location (iOS) | Enhanced GPS/location metadata |

**Per-profile install flow:**
1. Tap profile → **Allow** download
2. Settings → General → VPN & Device Management
3. Tap downloaded profile → **Install** → Passcode → **Install** (top-right) → **Done**
4. Repeat for next profile

---

## 🌐 Phase 4: WiFi Traffic Capture (PCAP)

### 4.1 Capture
```bash
pymobiledevice3 pcap -d -o ios.pcap
```
- `-d` = developer mode (requires Wi-Fi profile)
- Runs until `Ctrl+C`
- Output: `ios.pcap` in current directory

### 4.2 Inspect
```bash
ls -lh ios.pcap
capinfos ios.pcap
wireshark ios.pcap &
```

### 4.3 Filter for Plaintext Endpoints
In Wireshark display filter: `dns`  
Reveals all domains visited in plaintext (GitHub, YouTube, tracking, etc.)

---

## 📶 Phase 5: Bluetooth HCI Capture

### 5.1 Capture
```bash
pymobiledevice3 bluetooth logger -f pcapng -o ble.pcapng
```
- `-f pcapng` = required format for HCI
- Requires Bluetooth Logging profile active
- Runs until `Ctrl+C`

### 5.2 Generate Traffic
On iPhone: Enable Bluetooth → Connect devices (headphones, remote shutter, etc.) → Use apps that trigger BT.

### 5.3 Inspect
```bash
file ble.pcapng
capinfos ble.pcapng | less
wireshark ble.pcapng &
```

---

## 💥 Phase 6: Sysdiagnose (Full Device Diagnostic)

### 6.1 Prepare & Trigger
```bash
mkdir crash && cd crash
pymobiledevice3 crash sysdiagnose -o .
```
**Output:** `Press power volume up and volume down for a quarter of a second.`

### 6.2 On iPhone: Button Combo
Simultaneously hold **Power + Volume Up + Volume Down** for ~250ms.  
Phone vibrates, shows "sysdiagnose in progress." Wait 2–5 minutes.

### 6.3 Auto-Download
Tarball downloads to `./crash/sysdiagnose_<timestamp>.tar.gz`

### 6.4 Analyze with MVT
```bash
mkdir -p results
mvt-ios check-sysdiagnose -o results ./sysdiagnose_*.tar.gz
```
- Scans for indicators of compromise (spyware, anomalies)
- Structured output in `./results/`

---

## 📂 Phase 7: Crash Log Management

```bash
pymobiledevice3 crash ls          # list all crash logs
pymobiledevice3 crash parse       # parse latest crash
pymobiledevice3 crash shell       # interactive shell in crash directory
pymobiledevice3 crash clear       # clear crash logs
pymobiledevice3 crash flush       # flush crash logs
```

---

## 🗂️ Phase 8: AFC Shell (File System Access)

### 8.1 Enter Shell
```bash
pymobiledevice3 afc shell
```
*You are now in a shell on the iPhone with sandboxed app data access.*

### 8.2 Navigate & Exit
```bash
# Inside AFC shell:
cd /DCIM/100APPLE   # Camera Roll example
ls
exit                # returns to Linux terminal
```

### 8.3 Pull File to Linux
```bash
pymobiledevice3 afc pull /DCIM/100APPLE/IMG_1234.HEIC .
```
*Pulls to current directory (`.`). Adjust remote path as needed.*

---

## 📍 Phase 9: Extract GPS Metadata from Photos

### 9.1 Direct Extraction
```bash
exiftool -GPSLatitude -GPSLongitude IMG_1234.HEIC
```

### 9.2 Generate Google Maps URL
```bash
lat=$(exiftool -GPSLatitude -s3 IMG_1234.HEIC)
lon=$(exiftool -GPSLongitude -s3 IMG_1234.HEIC)
[[ -n $lat && -n $lon ]] && echo "https://www.google.com/maps/search/?api=1&query=${lat},${lon}"
```
Open the URL to see exact photo location.

---

## 🔄 Phase 10: Encrypted iTunes Backup (Optional)

### 10.1 Create Backup
```bash
idevicebackup2 backup --encryption "your_password" ./backup_dir
```

### 10.2 Decrypt & Analyze with MVT
```bash
mvt-ios decrypt-backup -p "your_password" -o ./decrypted ./backup_dir
mvt-ios check-backup -o ./results ./decrypted
```

---

## 📚 Command Reference

| Command | Purpose |
|---------|---------|
| `pymobiledevice3 doctor` | Device health check |
| `pymobiledevice3 pcap -d -o file.pcap` | WiFi packet capture |
| `pymobiledevice3 bluetooth logger -f pcapng -o file.pcapng` | Bluetooth HCI capture |
| `pymobiledevice3 crash sysdiagnose -o dir` | Trigger & download sysdiagnose |
| `pymobiledevice3 crash ls` | List crash logs |
| `pymobiledevice3 crash parse` | Parse latest crash |
| `pymobiledevice3 crash shell` | Interactive crash log shell |
| `pymobiledevice3 afc shell` | File system shell on device |
| `pymobiledevice3 afc pull <remote> <local>` | Pull file from device |
| `uxplay -d <name> -p <port>` | AirPlay receiver |
| `ideviceinfo -s` | Device summary |
| `idevicebackup2 backup --encryption <pw> <dir>` | Encrypted backup |
| `mvt-ios check-sysdiagnose -o <out> <tarball>` | IOC scan |
| `mvt-ios decrypt-backup -p <pw> -o <out> <dir>` | Decrypt backup |
| `mvt-ios check-backup -o <out> <dir>` | Backup IOC scan |

---

## 🧹 Cleanup Checklist
- [ ] Stop UX Play (`Ctrl+C`)
- [ ] Remove UFW AirPlay rules (5353/udp, 35000:35002/udp, 35000:35002/tcp)
- [ ] Stop Avahi daemon (`systemctl stop avahi-daemon.service`)
- [ ] Disable Bluetooth on iPhone
- [ ] Remove developer profiles from iPhone after use (auto-expire in 72h)
- [ ] Delete sensitive PCAPs, backups, sysdiagnose tarballs when analysis complete

---

## 🔗 Resources
- **pymobiledevice3:** `github.com/doronzo/pymobiledevice3`
- **MVT:** `github.com/mvt-project/mvt`
- **UX Play:** `github.com/uxplay/uxplay`
- **Apple Developer:** `developer.apple.com`

---

*Made with ❤️ by Kool Kat Moe D 🐾🏴‍☠️*