#!/bin/bash
#
# MacBook Air 6,2 (2013/2014) — Arch Linux Post-Install Setup
#
# Handles:
#   - AUR helper (paru)
#   - Broadcom BCM4360 Wi-Fi driver + blacklist + profile (216-KILLIAN)
#   - FaceTime HD Camera drivers + firmware + calibration
#   - Kernel command line written to /etc/kernel/cmdline (authoritative)
#   - Quiet boot parameters (no logs)
#   - Custom boot splash embedded in the UKI
#   - Custom boot label via /etc/os-release override
#   - 15-second systemd-boot menu timeout
#   - Boot sound at greeter stage (direct ALSA on CS4208)
#   - KDE login sound via PipeWire notification
#   - Custom backgrounds (desktop, lock, logout, greeter)
#   - Account lockout after 5 failed password attempts
#   - Optional archived MP4 for future use
#
# Usage:
#   chmod +x macbook-air-setup.sh
#   ./macbook-air-setup.sh
#
# Requirements:
#   - A working Arch Linux install with a bootloader, kernel, and sudo
#   - Network access (Wi-Fi or Ethernet)
#   - Run as a normal user (not root); sudo is used internally
#
# Safe to re-run — each step checks the current state before making changes.
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WIFI_SSID="216-KILLIAN"
WIFI_PASSWORD="rytgah-tyVcyw-hutxy6"
WIFI_CON_NAME="216-KILLIAN"

OS_PRETTY_NAME="216-KILLIAN"
OS_HOME_URL="https://daisreaux.com/"

SOUND_URL="https://raw.githubusercontent.com/killiandaisreauxgoffman/projects/refs/heads/main/boot-sound.ogg"
BG_URL="https://github.com/killiandaisreauxgoffman/projects/blob/main/boot-background.png?raw=true"
MP4_LOCAL_PATH="${HOME}/Downloads/Telegram/failboot-movie.mp4"

SOUND_DIR="/usr/share/sounds/custom/stereo"
SOUND_FILE="${SOUND_DIR}/desktop-login.ogg"

BG_DIR="/usr/share/backgrounds/custom"
BG_FILE="${BG_DIR}/boot-background.png"
BG_BMP="/usr/share/systemd/bootctl/splash-arch.bmp"

MEDIA_DIR="/usr/local/share/media"
MP4_FILE="${MEDIA_DIR}/failboot-movie.mp4"

CMD_LINE_FILE="/etc/kernel/cmdline"
PRESET_FILE="/etc/mkinitcpio.d/linux.preset"
UKI_PATH="/boot/EFI/Linux/arch-linux.efi"
LOADER_CONF="/boot/loader/loader.conf"

DISPLAY_RES="1440x900"
QUIET_PARAMS="quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0"

# ============================================================================
# HELPERS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

fail() {
    log_err "$1"
    log_err "Aborting. The system has NOT been rebooted. Investigate before proceeding."
    exit 1
}

require_user() {
    if [ "$EUID" -eq 0 ]; then
        log_err "Do not run this script as root. Run it as your normal user."
        exit 1
    fi
}

require_arch() {
    if ! command -v pacman &>/dev/null; then
        log_err "This script must be run on an Arch Linux system."
        exit 1
    fi
}

# ============================================================================
# PREFLIGHT
# ============================================================================

require_user
require_arch

CURRENT_CMDLINE=$(cat /proc/cmdline 2>/dev/null || true)
[ -z "$CURRENT_CMDLINE" ] && fail "Could not read /proc/cmdline."
log_info "Current kernel command line: $CURRENT_CMDLINE"

ROOT_PARAM=$(echo "$CURRENT_CMDLINE" | tr ' ' '\n' | grep -E '^root=' | head -1 || true)
[ -z "$ROOT_PARAM" ] && fail "Could not detect root= from /proc/cmdline."
log_info "Detected: $ROOT_PARAM"

ROOTFLAGS_PARAM=$(echo "$CURRENT_CMDLINE" | tr ' ' '\n' | grep -E '^rootflags=' | head -1 || true)
ROOTFSTYPE_PARAM=$(echo "$CURRENT_CMDLINE" | tr ' ' '\n' | grep -E '^rootfstype=' | head -1 || true)
ZSWAP_PARAM=$(echo "$CURRENT_CMDLINE" | tr ' ' '\n' | grep -E '^zswap\.' | head -1 || true)

log_info "Preserved: ${ROOTFLAGS_PARAM:-none} ${ROOTFSTYPE_PARAM:-none} ${ZSWAP_PARAM:-none}"

# ============================================================================
# [1/11] AUR helper — paru
# ============================================================================

echo ""
log_info "=== [1/11] Installing base-devel, git, and paru ==="
sudo pacman -S --needed --noconfirm base-devel git

if ! command -v paru &>/dev/null; then
    TMPDIR=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$TMPDIR/paru"
    cd "$TMPDIR/paru"
    makepkg -si --noconfirm
    cd "$HOME"
    rm -rf "$TMPDIR"
else
    log_info "paru is already installed."
fi

# ============================================================================
# [2/11] Broadcom BCM4360 Wi-Fi driver
# ============================================================================

echo ""
log_info "=== [2/11] Installing Broadcom BCM4360 Wi-Fi driver ==="
sudo pacman -S --needed --noconfirm broadcom-wl-dkms linux-headers

BLACKLIST_FILE="/etc/modprobe.d/broadcom-wl.conf"
if [ ! -f "$BLACKLIST_FILE" ]; then
    sudo tee "$BLACKLIST_FILE" > /dev/null << 'EOF'
blacklist b43
blacklist b43legacy
blacklist b44
blacklist bcma
blacklist brcm80211
blacklist brcmsmac
blacklist ssb
EOF
fi

lsmod | grep -q '^wl ' || sudo modprobe wl || true

# ============================================================================
# [3/11] FaceTime HD camera
# ============================================================================

echo ""
log_info "=== [3/11] Installing FaceTime HD camera drivers ==="
paru -S --needed --noconfirm \
    facetimehd-dkms-git \
    facetimehd-firmware \
    facetimehd-data

lsmod | grep -q '^facetimehd ' || sudo modprobe facetimehd || true

# ============================================================================
# [4/11] NetworkManager and Wi-Fi profile
# ============================================================================

echo ""
log_info "=== [4/11] Configuring NetworkManager and Wi-Fi profile ==="
sudo systemctl enable --now NetworkManager

if nmcli -t -f NAME connection show | grep -Fxq "$WIFI_CON_NAME"; then
    log_info "Updating existing '$WIFI_CON_NAME' profile."
    sudo nmcli connection modify "$WIFI_CON_NAME" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$WIFI_PASSWORD" \
        connection.autoconnect yes

    DUPLICATE_UUIDS=$(nmcli -t -f UUID,NAME connection show \
        | awk -F: -v name="$WIFI_CON_NAME" '$2 == name {print $1}' \
        | tail -n +2)
    for uuid in $DUPLICATE_UUIDS; do
        sudo nmcli connection delete "$uuid" || true
    done
else
    log_info "Creating '$WIFI_CON_NAME' profile."
    sudo nmcli connection add type wifi ifname "*" \
        con-name "$WIFI_CON_NAME" ssid "$WIFI_SSID"
    sudo nmcli connection modify "$WIFI_CON_NAME" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$WIFI_PASSWORD" \
        connection.autoconnect yes
fi

sudo nmcli connection up "$WIFI_CON_NAME" || log_warn "Could not bring up '$WIFI_CON_NAME'."

# ============================================================================
# [5/11] Boot sound at greeter stage (direct ALSA on CS4208)
# ============================================================================

echo ""
log_info "=== [5/11] Installing boot sound (greeter stage) ==="

sudo pacman -S --needed --noconfirm alsa-utils mpv

sudo mkdir -p "$SOUND_DIR"
sudo curl -sL "$SOUND_URL" -o "$SOUND_FILE"
sudo chmod 644 "$SOUND_FILE"
sudo ln -sf "$SOUND_FILE" "$SOUND_DIR/desktop-login-short.ogg"
sudo ln -sf "$SOUND_FILE" "$SOUND_DIR/desktop-login-long.ogg"

sudo mkdir -p /usr/share/sounds/custom
sudo tee /usr/share/sounds/custom/index.theme > /dev/null << 'EOF'
[Sound Theme]
Name=Custom
Comment=Custom sound theme
Directories=stereo

[stereo]
OutputProfile=stereo
EOF

CS4208_CARD=$(aplay -l 2>/dev/null | awk '/CS4208 Analog/ {gsub("card ","",$1); gsub(":","",$1); print $1; exit}' || true)
if [ -n "$CS4208_CARD" ]; then
    AUDIO_DEVICE="alsa/hw:${CS4208_CARD},0"
    log_info "Detected CS4208 on card $CS4208_CARD; using $AUDIO_DEVICE"
else
    AUDIO_DEVICE="alsa/hw:1,0"
    log_warn "Could not detect CS4208; defaulting to $AUDIO_DEVICE"
fi

sudo tee /etc/systemd/system/boot-sound.service > /dev/null << EOF
[Unit]
Description=Play Boot Audio Sound (MacBookAir6,2 CS4208)
After=sound.target
Before=display-manager.service plasmalogin.service

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/usr/bin/mpv --no-video --ao=alsa --audio-device=$AUDIO_DEVICE $SOUND_FILE
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable boot-sound.service

# ============================================================================
# [6/11] KDE login sound and autostart
# ============================================================================

echo ""
log_info "=== [6/11] Configuring KDE login sound ==="

kwriteconfig6 --file kdeglobals --group General --key Theme "custom"
kwriteconfig6 --file plasmanotifyrc \
    --group Notifications --group PlasmaWorkspace \
    --key Login "true"
kwriteconfig6 --file plasmanotifyrc \
    --group Notifications --group PlasmaWorkspace \
    --key LoginSoundFile "$SOUND_FILE"

mkdir -p ~/.config/autostart
cat > ~/.config/autostart/play-login-sound.desktop << EOF
[Desktop Entry]
Type=Application
Name=Play Login Sound
Exec=bash -c 'sleep 2; pw-play $SOUND_FILE'
OnlyShowIn=KDE;
EOF

# ============================================================================
# [7/11] Background image and KDE surfaces
# ============================================================================

echo ""
log_info "=== [7/11] Installing background image ==="

sudo mkdir -p "$BG_DIR"
sudo curl -sL "$BG_URL" -o "$BG_FILE"
sudo chmod 644 "$BG_FILE"

sudo ffmpeg -y -i "$BG_FILE" \
    -vf "scale=${DISPLAY_RES}:force_original_aspect_ratio=decrease,pad=${DISPLAY_RES}:(ow-iw)/2:(oh-ih)/2" \
    -pix_fmt bgr24 "$BG_BMP"

command -v plasma-apply-wallpaperimage &>/dev/null && \
    plasma-apply-wallpaperimage "$BG_FILE" || true

kwriteconfig6 --file kscreenlockerrc \
    --group Greeter --group Wallpaper --group org.kde.image --group General \
    --key Image "file://$BG_FILE"

kwriteconfig6 --file ksmserverrc \
    --group General --key logoutBackground "$BG_FILE"

sudo mkdir -p /etc/plasmalogin
sudo tee /etc/plasmalogin/plasmalogin.conf > /dev/null << EOF
[Greeter]
WallpaperPluginId=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=file://$BG_FILE
EOF

if id plasmalogin &>/dev/null; then
    sudo -u plasmalogin mkdir -p /var/lib/plasmalogin/wallpapers
    sudo cp "$BG_FILE" /var/lib/plasmalogin/wallpapers/
    sudo chown -R plasmalogin:plasmalogin /var/lib/plasmalogin/wallpapers
    sudo chmod 644 /var/lib/plasmalogin/wallpapers/boot-background.png
fi

# ============================================================================
# [8/11] Kernel command line — authoritative source
# ============================================================================

echo ""
log_info "=== [8/11] Writing kernel command line to $CMD_LINE_FILE ==="

if [ -f "$CMD_LINE_FILE" ] && [ ! -f "${CMD_LINE_FILE}.orig" ]; then
    sudo cp "$CMD_LINE_FILE" "${CMD_LINE_FILE}.orig"
    log_info "Backed up original cmdline to ${CMD_LINE_FILE}.orig"
fi

NEW_CMDLINE="$ROOT_PARAM"
[ -n "$ZSWAP_PARAM" ]      && NEW_CMDLINE="$NEW_CMDLINE $ZSWAP_PARAM"
[ -n "$ROOTFLAGS_PARAM" ]  && NEW_CMDLINE="$NEW_CMDLINE $ROOTFLAGS_PARAM"
[ -n "$ROOTFSTYPE_PARAM" ] && NEW_CMDLINE="$NEW_CMDLINE $ROOTFSTYPE_PARAM"

if ! echo "$NEW_CMDLINE" | grep -qE '(^| )rw( |$)'; then
    NEW_CMDLINE="$NEW_CMDLINE rw"
fi

# Strip any previous quiet params before appending, so re-runs don't duplicate
for p in $QUIET_PARAMS; do
    NEW_CMDLINE=$(echo "$NEW_CMDLINE" | sed "s| $p||g")
done

NEW_CMDLINE="$NEW_CMDLINE $QUIET_PARAMS"
log_info "New cmdline: $NEW_CMDLINE"

sudo tee "$CMD_LINE_FILE" > /dev/null << EOF
$NEW_CMDLINE
EOF

# ============================================================================
# [9/11] UKI preset (no default_options; cmdline file wins)
# ============================================================================

echo ""
log_info "=== [9/11] Rewriting UKI preset ==="

if [ ! -f "${PRESET_FILE}.orig" ]; then
    sudo cp "$PRESET_FILE" "${PRESET_FILE}.orig"
    log_info "Backed up original preset to ${PRESET_FILE}.orig"
fi

sudo tee "$PRESET_FILE" > /dev/null << EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
ALL_default_splash="$BG_BMP"

PRESETS=('default')

default_uki="$UKI_PATH"
EOF

sudo mkinitcpio -P

# --- Verify UKI ---
echo ""
log_info "=== Verifying UKI .cmdline section ==="

CMDLINE_SECTION=$(sudo objdump -h "$UKI_PATH" 2>/dev/null | awk '$2 == ".cmdline" {print $3}' || true)
[ -z "$CMDLINE_SECTION" ] && fail "UKI does not contain a .cmdline section. DO NOT REBOOT."
log_info "UKI .cmdline section size: $CMDLINE_SECTION bytes"

sudo objdump -s -j .cmdline "$UKI_PATH" > /tmp/uki-cmdline.txt 2>/dev/null || true
grep -q 'quiet' /tmp/uki-cmdline.txt || fail "UKI .cmdline does not contain 'quiet'. DO NOT REBOOT."

log_info "UKI verified. Safe to proceed."

# ============================================================================
# [10/11] Boot label
# ============================================================================

echo ""
log_info "=== [10/11] Setting boot menu label ==="

sudo tee /etc/os-release > /dev/null << EOF
NAME="$OS_PRETTY_NAME"
PRETTY_NAME="$OS_PRETTY_NAME"
ID=arch
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="$OS_HOME_URL"
DOCUMENTATION_URL="$OS_HOME_URL"
SUPPORT_URL="$OS_HOME_URL"
BUG_REPORT_URL="$OS_HOME_URL"
LOGO=archlinux-logo
EOF

sudo mkinitcpio -P

CMDLINE_SECTION=$(sudo objdump -h "$UKI_PATH" 2>/dev/null | awk '$2 == ".cmdline" {print $3}' || true)
[ -z "$CMDLINE_SECTION" ] && fail "UKI lost its .cmdline section after the second rebuild. DO NOT REBOOT."
log_info "UKI verified after label update."

# ============================================================================
# [11/11] Boot timeout, faillock, MP4 archive
# ============================================================================

echo ""
log_info "=== [11/11] Finalizing system configuration ==="

if [ -f "$LOADER_CONF" ]; then
    if grep -q '^timeout' "$LOADER_CONF"; then
        sudo sed -i 's/^timeout.*/timeout 15/' "$LOADER_CONF"
    else
        echo "timeout 15" | sudo tee -a "$LOADER_CONF" > /dev/null
    fi
fi

sudo tee /etc/security/faillock.conf > /dev/null << 'EOF'
deny = 5
unlock_time = 900
fail_interval = 900
EOF

sudo faillock --user "$(whoami)" --reset || true

if [ -f "$MP4_LOCAL_PATH" ] && [ ! -f "$MP4_FILE" ]; then
    sudo mkdir -p "$MEDIA_DIR"
    sudo cp "$MP4_LOCAL_PATH" "$MP4_FILE"
    sudo chown root:root "$MP4_FILE"
    sudo chmod 644 "$MP4_FILE"
    log_info "Archived MP4 to $MP4_FILE"
else
    log_info "MP4 already archived or source not present; skipping."
fi

mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/failboot-movie.desktop << EOF
[Desktop Entry]
Type=Application
Name=Failboot Movie
Comment=Play the archived failboot video
Exec=mpv --fullscreen $MP4_FILE
Icon=mpv
Terminal=false
Categories=AudioVideo;Player;
EOF

# ============================================================================
# DONE
# ============================================================================

echo ""
log_info "=== Setup Complete ==="
echo ""
log_info "Final UKI verification:"
sudo objdump -h "$UKI_PATH" | grep -E 'cmdline|splash|osrel' || true
echo ""
log_info "If everything above looks correct, reboot:"
log_info "  sudo reboot"
log_info ""
log_info "If anything is wrong and you need to roll back:"
log_info "  sudo cp ${PRESET_FILE}.orig ${PRESET_FILE}"
log_info "  sudo cp ${CMD_LINE_FILE}.orig ${CMD_LINE_FILE}"
log_info "  sudo mkinitcpio -P"
