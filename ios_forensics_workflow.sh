#!/usr/bin/env bash
# iOS Forensics on Linux — Operational Workflow
# Made with ❤️ by Kool Kat Moe D 🐾🏴‍☠️

set -euo pipefail

# ─── Colors ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Helpers ───
log()   { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[-]${NC} $*" >&2; }
info()  { echo -e "${BLUE}[i]${NC} $*"; }
step()  { echo -e "\n${CYAN}==== $* ====${NC}\n"; }

# ─── Prerequisites Check ───
check_prereqs() {
    step "Checking Prerequisites"
    local missing=()

    command -v pymobiledevice3 >/dev/null || missing+=("pymobiledevice3 (pipx install pymobiledevice3)")
    command -v uxplay >/dev/null || missing+=("uxplay (sudo apt install uxplay)")
    command -v wireshark >/dev/null || missing+=("wireshark (sudo apt install wireshark)")
    command -v capinfos >/dev/null || missing+=("capinfos (sudo apt install wireshark-common)")
    command -v exiftool >/dev/null || missing+=("exiftool (sudo apt install libimage-exiftool-perl)")
    command -v ideviceinfo >/dev/null || missing+=("libimobiledevice (sudo apt install libimobiledevice-utils)")
    command -v idevicebackup2 >/dev/null || missing+=("idevicebackup2 (sudo apt install libimobiledevice-utils)")

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing tools:"
        for m in "${missing[@]}"; do echo "  - $m"; done
        read -rp "Install missing via apt/pipx now? [y/N] " ans
        [[ $ans =~ ^[Yy]$ ]] && install_missing "${missing[@]}"
    else
        log "All core tools present."
    fi
}

install_missing() {
    for tool in "$@"; do
        case $tool in
            *pymobiledevice3*) pipx install pymobiledevice3 && pipx ensurepath ;;
            *uxplay*) sudo apt update && sudo apt install -y uxplay ;;
            *wireshark*) sudo apt update && sudo apt install -y wireshark ;;
            *capinfos*) sudo apt update && sudo apt install -y wireshark-common ;;
            *exiftool*) sudo apt update && sudo apt install -y libimage-exiftool-perl ;;
            *libimobiledevice*) sudo apt update && sudo apt install -y libimobiledevice-utils ;;
        esac
    done
}

# ─── Phase 1: Setup ───
phase_setup() {
    step "Phase 1: Environment Setup"
    log "Installing/upgrading pymobiledevice3 via pipx..."
    pipx install pymobiledevice3 2>/dev/null || pipx upgrade pymobiledevice3
    pipx ensurepath

    log "Verifying device connection..."
    pymobiledevice3 doctor
    echo
    ideviceinfo -s 2>/dev/null || warn "ideviceinfo failed (device may not be paired)"
}

# ─── Phase 2: Mirroring ───
phase_mirror() {
    step "Phase 2: Screen Mirroring (AirPlay via UX Play)"

    # Firewall
    log "Configuring UFW for AirPlay/mDNS..."
    sudo ufw allow 5353/udp
    sudo ufw allow 35000:35002/udp
    sudo ufw allow 35000:35002/tcp
    sudo ufw status verbose

    # Avahi
    log "Starting Avahi daemon..."
    sudo systemctl start avahi-daemon.service
    sleep 1
    sudo systemctl status avahi-daemon.service --no-pager

    # Launch UX Play
    log "Launching UX Play (name: Linux, port: 35000)..."
    info "On iPhone: Control Center → Screen Mirroring → Select 'Linux'"
    info "Press Ctrl+C here to stop mirroring and proceed to cleanup."
    uxplay -d Linux -p 35000

    # Cleanup (runs after Ctrl+C)
    log "Cleaning up firewall rules..."
    sudo ufw delete allow 5353/udp
    sudo ufw delete allow 35000:35002/udp
    sudo ufw delete allow 35000:35002/tcp
    sudo ufw status verbose

    log "Stopping Avahi daemon..."
    sudo systemctl stop avahi-daemon.service
}

# ─── Phase 3: Developer Profiles ───
phase_profiles() {
    step "Phase 3: Apple Developer Profiles (Manual Step Required)"
    cat <<'EOF'
⚠️  THIS STEP MUST BE DONE ON THE IPHONE (use mirrored screen or directly)

1. Open Safari → developer.apple.com → Sign in with Apple ID
2. Go to "Profiles and Logs" (upper right)
3. Search for and download ONE AT A TIME:
   - Wi-Fi Performance Diagnostics (iOS)
   - Bluetooth Logging (iOS)
   - Location (iOS)
   - Any other relevant profiles
4. After EACH download:
   Settings → General → VPN & Device Management → Tap profile → Install → Passcode → Install → Done

⏱️  PROFILES EXPIRE AFTER 72 HOURS. Re-download when needed.
EOF
    read -rp "Press Enter when profiles are installed..."
}

# ─── Phase 4: WiFi Capture ───
phase_wifi_capture() {
    step "Phase 4: WiFi Traffic Capture (PCAP)"
    local outfile="${1:-ios.pcap}"

    log "Starting WiFi capture (requires Wi-Fi profile active)..."
    info "Press Ctrl+C to stop capture."
    pymobiledevice3 pcap -d -o "$outfile"

    log "Capture saved to $outfile"
    ls -lh "$outfile"
    capinfos "$outfile"

    read -rp "Open in Wireshark now? [y/N] " ans
    [[ $ans =~ ^[Yy]$ ]] && wireshark "$outfile" &
}

# ─── Phase 5: Bluetooth Capture ───
phase_bt_capture() {
    step "Phase 5: Bluetooth HCI Capture (PCAPNG)"
    local outfile="${1:-ble.pcapng}"

    log "Starting Bluetooth capture (requires Bluetooth profile active)..."
    info "Enable Bluetooth on iPhone, connect devices, generate traffic."
    info "Press Ctrl+C to stop capture."
    pymobiledevice3 bluetooth logger -f pcapng -o "$outfile"

    log "Capture saved to $outfile"
    file "$outfile"
    capinfos "$outfile" | less

    read -rp "Open in Wireshark now? [y/N] " ans
    [[ $ans =~ ^[Yy]$ ]] && wireshark "$outfile" &
}

# ─── Phase 6: Sysdiagnose ───
phase_sysdiagnose() {
    step "Phase 6: Sysdiagnose (Full Device Diagnostic)"

    local outdir="crash"
    mkdir -p "$outdir"
    cd "$outdir"

    log "Triggering sysdiagnose..."
    info "On iPhone: Simultaneously press Power + Volume Up + Volume Down for ~0.25s"
    info "Phone will vibrate and show 'sysdiagnose in progress'"
    info "Wait 2-5 minutes for completion. Tarball auto-downloads here."
    pymobiledevice3 crash sysdiagnose -o .

    # Find the tarball
    local tarball=$(ls -t sysdiagnose_*.tar.gz 2>/dev/null | head -1)
    if [[ -n $tarball ]]; then
        log "Sysdiagnose downloaded: $tarball"

        read -rp "Analyze with MVT now? [y/N] " ans
        if [[ $ans =~ ^[Yy]$ ]]; then
            step "Running MVT check-sysdiagnose..."
            mkdir -p results
            mvt-ios check-sysdiagnose -o results "$tarball"
            log "Results in ./results/"
        fi
    else
        warn "No sysdiagnose tarball found. Did the process complete?"
    fi
    cd ..
}

# ─── Phase 7: Crash Logs ───
phase_crash_logs() {
    step "Phase 7: Crash Log Management"
    cat <<'EOF'
Available commands:
  1) pymobiledevice3 crash ls       — List all crash logs
  2) pymobiledevice3 crash parse    — Parse latest crash
  3) pymobiledevice3 crash shell    — Interactive shell in crash dir
  4) pymobiledevice3 crash clear    — Clear crash logs
  5) pymobiledevice3 crash flush    — Flush crash logs
EOF
    read -rp "Run which command? [1-5 or custom] " choice
    case $choice in
        1) pymobiledevice3 crash ls ;;
        2) pymobiledevice3 crash parse ;;
        3) pymobiledevice3 crash shell ;;
        4) pymobiledevice3 crash clear ;;
        5) pymobiledevice3 crash flush ;;
        *) pymobiledevice3 $choice ;;
    esac
}

# ─── Phase 8: AFC Shell ───
phase_afc() {
    step "Phase 8: AFC Shell (File System Access)"
    cat <<'EOF'
This drops you into a shell ON THE IPHONE.
Navigate to files (e.g., DCIM/100APPLE), then exit and pull.
EOF
    read -rp "Enter AFC shell now? [y/N] " ans
    [[ $ans =~ ^[Yy]$ ]] && pymobiledevice3 afc shell

    read -rp "Pull a file? Enter remote path (or blank to skip): " rpath
    [[ -n $rpath ]] && pymobiledevice3 afc pull "$rpath" .
}

# ─── Phase 9: GPS Metadata ───
phase_gps() {
    step "Phase 9: Extract GPS Metadata from Photo"
    read -rp "Path to image file: " img
    [[ -f $img ]] || { err "File not found: $img"; return; }

    log "Extracting GPS coordinates..."
    exiftool -GPSLatitude -GPSLongitude "$img"

    # Try to generate Google Maps URL
    local lat=$(exiftool -GPSLatitude -s3 "$img" 2>/dev/null)
    local lon=$(exiftool -GPSLongitude -s3 "$img" 2>/dev/null)
    if [[ -n $lat && -n $lon ]]; then
        local url="https://www.google.com/maps/search/?api=1&query=${lat},${lon}"
        log "Google Maps URL: $url"
        read -rp "Open in browser? [y/N] " ans
        [[ $ans =~ ^[Yy]$ ]] && xdg-open "$url" 2>/dev/null || sensible-browser "$url" 2>/dev/null
    fi
}

# ─── Phase 10: Encrypted Backup ───
phase_backup() {
    step "Phase 10: Encrypted iTunes Backup (Optional)"
    read -rp "Backup directory path: " bdir
    read -rsp "Backup encryption password: " pass; echo

    log "Creating encrypted backup..."
    idevicebackup2 backup --encryption "$pass" "$bdir"

    read -rp "Decrypt and analyze with MVT? [y/N] " ans
    if [[ $ans =~ ^[Yy]$ ]]; then
        local ddir="${bdir}_decrypted"
        local rdir="${bdir}_results"
        mkdir -p "$ddir" "$rdir"
        mvt-ios decrypt-backup -p "$pass" -o "$ddir" "$bdir"
        mvt-ios check-backup -o "$rdir" "$ddir"
        log "Decrypted backup: $ddir"
        log "MVT results: $rdir"
    fi
}

# ─── Main Menu ───
main_menu() {
    while true; do
        echo
        step "iOS Forensics Workflow — Main Menu"
        cat <<'EOF'
  1) Setup & Device Verify
  2) Screen Mirroring (AirPlay)
  3) Install Developer Profiles (manual)
  4) WiFi Traffic Capture
  5) Bluetooth Traffic Capture
  6) Sysdiagnose + MVT Analysis
  7) Crash Log Management
  8) AFC Shell & File Pull
  9) Extract GPS from Photo
 10) Encrypted Backup + MVT
 11) Full Guided Run (1→6)
  0) Exit
EOF
        read -rp "Select phase [0-11]: " choice
        case $choice in
            1) phase_setup ;;
            2) phase_mirror ;;
            3) phase_profiles ;;
            4) phase_wifi_capture ;;
            5) phase_bt_capture ;;
            6) phase_sysdiagnose ;;
            7) phase_crash_logs ;;
            8) phase_afc ;;
            9) phase_gps ;;
            10) phase_backup ;;
            11)
                phase_setup
                phase_mirror
                phase_profiles
                phase_wifi_capture
                phase_bt_capture
                phase_sysdiagnose
                ;;
            0) log "Goodbye! Stay fresh. 🐾🏴‍☠️"; exit 0 ;;
            *) warn "Invalid option" ;;
        esac
    done
}

# ─── Entry Point ───
main() {
    cat <<'EOF'

╔══════════════════════════════════════════════════════════════╗
║  iOS Forensics on Linux — Operational Workflow                ║
║  ⚠️  FOR AUTHORIZED TESTING ONLY — OWN DEVICES ONLY ⚠️         ║
╚══════════════════════════════════════════════════════════════╝

EOF
    check_prereqs
    main_menu
}

main "$@"