#!/bin/bash
#
# MacBook Air 6,2 (2013/2014) — Arch Linux Complete Setup
#
# Configures a fresh Arch Linux install on a MacBookAir6,2:
#   - Broadcom BCM4360 Wi-Fi via DKMS
#   - FaceTime HD camera with calibration
#   - Silent kernel boot with a custom splash image (BMP preferred)
#   - Custom boot menu label
#   - Boot sound at greeter stage (direct ALSA)
#   - KDE Plasma custom backgrounds (desktop, lock, logout, greeter)
#   - Account lockout after 5 failed password attempts
#   - MP4 archive for future use
#
# Splash logic:
#   1. Download pre-made 1440x900 24-bit BMP from GitHub.
#   2. If invalid or unavailable, fall back to PNG + ffmpeg conversion.
#
# Usage:
#   chmod +x macbook-air-setup.sh
#   ./macbook-air-setup.sh
#
# Run as a normal user. Safe to re-run. Backs up originals on first run.
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
BMP_URL="https://raw.githubusercontent.com/killiandaisreauxgoffman/projects/refs/heads/main/216-killian.bmp"
PNG_URL="https://github.com/killiandaisreauxgoffman/projects/blob/main/boot-background.png?raw=true"

SOUND_DIR="/usr/share/sounds/custom/stereo"
SOUND_FILE="${SOUND_DIR}/desktop-login.ogg"

BG_DIR="/usr/share/backgrounds/custom"
BG_FILE="${BG_DIR}/boot-background.png"
BG_BMP="/usr/share/systemd/bootctl/splash-arch.bmp"

MEDIA_DIR="/usr/local/share/media"
MP4_FILE="${MEDIA_DIR}/failboot-movie.mp4"
MP4_SOURCE="${HOME}/Downloads/Telegram/failboot-movie.mp4"

CMD_LINE_FILE="/etc/kernel/cmdline"
PRESET_FILE="/etc/mkinitcpio.d/linux.preset"
UKI_PATH="/boot/EFI/Linux/arch-linux.efi"
LOADER_CONF="/boot/loader/loader.conf"
OS_RELEASE="/usr/lib/os-release"

DISPLAY_W=1440
DISPLAY_H=900
QUIET_PARAMS="quiet loglevel=3 systemd.show_status=no rd.udev.log_level=0 vt.global_cursor_default=0"
LOADER_TIMEOUT=15

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
    log_err "Aborting. System has NOT been rebooted."
    exit 1
}

require_user() {
    [ "$EUID" -eq 0 ] && { log_err "Do not run as root."; exit 1; }
}

require_arch() {
    command -v pacman &>/dev/null || { log_err "Not an Arch system."; exit 1; }
}

pkg_install() { sudo pacman -S --needed --noconfirm "$@"; }
aur_install() { paru -S --needed --noconfirm "$@"; }

is_valid_bmp() {
    local f="$1"
    [ -f "$f" ] || return 1
    file "$f" | grep -qi 'PC bitmap' || return 1
    file "$f" | grep -q "${DISPLAY_W} x ${DISPLAY_H} x 24" || return 1
    return 0
}

# ============================================================================
# PREFLIGHT
# ============================================================================

require_user
require_arch

CURRENT_CMDLINE=$(cat /proc/cmdline 2>/dev/null || true)
[ -z "$CURRENT_CMDLINE" ] && fail "Cannot read /proc/cmdline."

ROOT_PARAM=$(echo "$CURRENT_CMDLINE" | tr ' ' '\n' | grep -E '^root=' | head -1 || true)
[ -z "$ROOT_PARAM" ] && fail "Cannot detect root= from /proc/cmdline."

ROOTFLAGS_PARAM=$(echo "$CURRENT_CMDLINE" | tr ' ' '\n' | grep -E '^rootflags=' | head -1 || true)
ROOTFSTYPE_PARAM=$(echo "$CURRENT_CMDLINE" | tr ' ' '\n' | grep -E '^rootfstype=' | head -1 || true)
ZSWAP_PARAM=$(echo "$CURRENT_CMDLINE" | tr ' ' '\n' | grep -E '^zswap\.' | head -1 || true)

log_info "Root:       $ROOT_PARAM"
log_info "rootflags:  ${ROOTFLAGS_PARAM:-none}"
log_info "rootfstype: ${ROOTFSTYPE_PARAM:-none}"
log_info "zswap:      ${ZSWAP_PARAM:-none}"

# ============================================================================
# [1/11] AUR helper
# ============================================================================

echo ""
log_info "=== [1/11] AUR helper (paru) ==="
pkg_install base-devel git

if ! command -v paru &>/dev/null; then
    TMPDIR=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$TMPDIR/paru"
    ( cd "$TMPDIR/paru" && makepkg -si --noconfirm )
    rm -rf "$TMPDIR"
else
    log_info "paru already installed."
fi

# ============================================================================
# [2/11] Broadcom BCM4360 Wi-Fi
# ============================================================================

echo ""
log_info "=== [2/11] Broadcom BCM4360 Wi-Fi driver ==="
pkg_install broadcom-wl-dkms linux-headers

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
log_info "=== [3/11] FaceTime HD camera drivers ==="
aur_install facetimehd-dkms-git facetimehd-firmware facetimehd-data

lsmod | grep -q '^facetimehd ' || sudo modprobe facetimehd || true

# ============================================================================
# [4/11] NetworkManager and Wi-Fi profile
# ============================================================================

echo ""
log_info "=== [4/11] NetworkManager and Wi-Fi profile ==="
sudo systemctl enable --now NetworkManager

if nmcli -t -f NAME connection show | grep -Fxq "$WIFI_CON_NAME"; then
    log_info "Updating existing profile."
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
    log_info "Creating new profile."
    sudo nmcli connection add type wifi ifname "*" \
        con-name "$WIFI_CON_NAME" ssid "$WIFI_SSID"
    sudo nmcli connection modify "$WIFI_CON_NAME" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$WIFI_PASSWORD" \
        connection.autoconnect yes
fi

sudo nmcli connection up "$WIFI_CON_NAME" || log_warn "Could not connect immediately."

# ============================================================================
# [5/11] Boot sound service
# ============================================================================

echo ""
log_info "=== [5/11] Boot sound (greeter stage, direct ALSA) ==="
pkg_install alsa-utils mpv

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
    log_info "CS4208 detected on card ${CS4208_CARD}."
else
    AUDIO_DEVICE="alsa/hw:1,0"
    log_warn "CS4208 not detected; defaulting to ${AUDIO_DEVICE}."
fi

sudo tee /etc/systemd/system/boot-sound.service > /dev/null << EOF
[Unit]
Description=Play Boot Audio Sound (MacBookAir6,2 CS4208)
After=sound.target
Before=display-manager.service plasmalogin.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'exec >/dev/null 2>&1; for i in \$(seq 1 40); do aplay -l 2>/dev/null | grep -q CS4208 && break; sleep 0.25; done; exec /usr/bin/mpv --really-quiet --no-video --ao=alsa --audio-device=${AUDIO_DEVICE} ${SOUND_FILE}'
User=root
StandardOutput=null
StandardError=null
TTYPath=/dev/null
Restart=no

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable boot-sound.service

# ============================================================================
# [6/11] KDE login sound
# ============================================================================

echo ""
log_info "=== [6/11] KDE login sound ==="

kwriteconfig6 --file kdeglobals --group General --key Theme "custom"
kwriteconfig6 --file plasmanotifyrc \
    --group Notifications --group PlasmaWorkspace --key Login "true"
kwriteconfig6 --file plasmanotifyrc \
    --group Notifications --group PlasmaWorkspace --key LoginSoundFile "$SOUND_FILE"

mkdir -p ~/.config/autostart
cat > ~/.config/autostart/play-login-sound.desktop << EOF
[Desktop Entry]
Type=Application
Name=Play Login Sound
Exec=bash -c 'sleep 2; pw-play $SOUND_FILE'
OnlyShowIn=KDE;
EOF

# ============================================================================
# [7/11] Splash image — BMP preferred, PNG fallback
# ============================================================================

echo ""
log_info "=== [7/11] Splash image (BMP preferred, PNG fallback) ==="

sudo mkdir -p "$BG_DIR" /usr/share/systemd/bootctl

BMP_OK=0
log_info "Attempting direct BMP download..."
if sudo curl -fsSL "$BMP_URL" -o "$BG_BMP"; then
    sudo chmod 644 "$BG_BMP"
    if is_valid_bmp "$BG_BMP"; then
        log_info "BMP validated: $(file -b "$BG_BMP")"
        BMP_OK=1
    else
        log_warn "Downloaded file is not a valid ${DISPLAY_W}x${DISPLAY_H} 24-bit BMP."
        log_warn "Got: $(file -b "$BG_BMP")"
    fi
else
    log_warn "BMP download failed."
fi

if [ "$BMP_OK" -eq 0 ]; then
    log_info "Falling back to PNG download + ffmpeg conversion."

    if ! sudo curl -fsSL "$PNG_URL" -o "$BG_FILE"; then
        fail "PNG download failed."
    fi
    sudo chmod 644 "$BG_FILE"

    file "$BG_FILE" | grep -qi 'PNG image' \
        || fail "Downloaded fallback is not a valid PNG."

    log_info "PNG: $(file -b "$BG_FILE")"

    sudo ffmpeg -y -i "$BG_FILE" \
        -vf "scale=${DISPLAY_W}:${DISPLAY_H}:force_original_aspect_ratio=increase,crop=${DISPLAY_W}:${DISPLAY_H}" \
        -pix_fmt bgr24 \
        "$BG_BMP" > /dev/null 2>&1

    is_valid_bmp "$BG_BMP" \
        || fail "BMP conversion failed: $(file -b "$BG_BMP")"

    log_info "BMP created: $(file -b "$BG_BMP")"
fi

if [ ! -f "$BG_FILE" ] || ! file "$BG_FILE" | grep -qi 'PNG image'; then
    log_info "Downloading PNG for KDE wallpaper use..."
    sudo curl -fsSL "$PNG_URL" -o "$BG_FILE" || log_warn "PNG download failed."
    sudo chmod 644 "$BG_FILE" 2>/dev/null || true
fi

if [ -f "$BG_FILE" ] && file "$BG_FILE" | grep -qi 'PNG image'; then
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
fi

# ============================================================================
# [8/11] Kernel command line
# ============================================================================

echo ""
log_info "=== [8/11] Kernel command line ==="

if [ -f "$CMD_LINE_FILE" ] && [ ! -f "${CMD_LINE_FILE}.orig" ]; then
    sudo cp "$CMD_LINE_FILE" "${CMD_LINE_FILE}.orig"
    log_info "Backed up original cmdline."
fi

NEW_CMDLINE="$ROOT_PARAM"
[ -n "$ZSWAP_PARAM" ]      && NEW_CMDLINE="$NEW_CMDLINE $ZSWAP_PARAM"
[ -n "$ROOTFLAGS_PARAM" ]  && NEW_CMDLINE="$NEW_CMDLINE $ROOTFLAGS_PARAM"
[ -n "$ROOTFSTYPE_PARAM" ] && NEW_CMDLINE="$NEW_CMDLINE $ROOTFSTYPE_PARAM"

echo "$NEW_CMDLINE" | grep -qE '(^| )rw( |$)' || NEW_CMDLINE="$NEW_CMDLINE rw"

for p in $QUIET_PARAMS; do
    NEW_CMDLINE=$(echo "$NEW_CMDLINE" | sed "s| $p||g")
done
NEW_CMDLINE="$NEW_CMDLINE $QUIET_PARAMS"

log_info "New cmdline: $NEW_CMDLINE"

sudo tee "$CMD_LINE_FILE" > /dev/null << EOF
$NEW_CMDLINE
EOF

# ============================================================================
# [9/11] UKI preset and rebuild
# ============================================================================

echo ""
log_info "=== [9/11] UKI preset and rebuild ==="

if [ ! -f "${PRESET_FILE}.orig" ]; then
    sudo cp "$PRESET_FILE" "${PRESET_FILE}.orig"
    log_info "Backed up original preset."
fi

sudo tee "$PRESET_FILE" > /dev/null << EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default')

default_uki="$UKI_PATH"
default_options="--splash $BG_BMP"
EOF

sudo mkinitcpio -P

CMDLINE_SECTION=$(sudo objdump -h "$UKI_PATH" 2>/dev/null | awk '$2 == ".cmdline" {print $3}' || true)
[ -z "$CMDLINE_SECTION" ] && fail "UKI missing .cmdline section. DO NOT REBOOT."

SPLASH_SECTION=$(sudo objdump -h "$UKI_PATH" 2>/dev/null | awk '$2 == ".splash" {print $3}' || true)
if [ -z "$SPLASH_SECTION" ]; then
    log_warn "UKI missing .splash section. Boot image will not appear."
else
    log_info "UKI .cmdline: ${CMDLINE_SECTION} bytes, .splash: ${SPLASH_SECTION} bytes"
fi

sudo objdump -s -j .cmdline "$UKI_PATH" > /tmp/uki-cmdline.txt 2>/dev/null || true
grep -q 'quiet' /tmp/uki-cmdline.txt || fail "UKI .cmdline missing 'quiet'. DO NOT REBOOT."

# ============================================================================
# [10/11] Boot label
# ============================================================================

echo ""
log_info "=== [10/11] Boot menu label ==="

sudo tee "$OS_RELEASE" > /dev/null << EOF
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
[ -z "$CMDLINE_SECTION" ] && fail "UKI lost .cmdline after label update. DO NOT REBOOT."

# ============================================================================
# [11/11] Final: timeout, faillock, MP4 archive
# ============================================================================

echo ""
log_info "=== [11/11] Finalizing system ==="

if [ -f "$LOADER_CONF" ]; then
    if grep -q '^timeout' "$LOADER_CONF"; then
        sudo sed -i "s/^timeout.*/timeout $LOADER_TIMEOUT/" "$LOADER_CONF"
    else
        echo "timeout $LOADER_TIMEOUT" | sudo tee -a "$LOADER_CONF" > /dev/null
    fi
fi

sudo tee /etc/security/faillock.conf > /dev/null << 'EOF'
deny = 5
unlock_time = 900
fail_interval = 900
EOF

sudo faillock --user "$(whoami)" --reset || true

if [ -f "$MP4_SOURCE" ] && [ ! -f "$MP4_FILE" ]; then
    sudo mkdir -p "$MEDIA_DIR"
    sudo cp "$MP4_SOURCE" "$MP4_FILE"
    sudo chown root:root "$MP4_FILE"
    sudo chmod 644 "$MP4_FILE"
    log_info "MP4 archived to $MP4_FILE."
else
    log_info "MP4 already archived or source absent."
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
# SUMMARY
# ============================================================================

echo ""
log_info "=== Setup Complete ==="
echo ""
echo "UKI sections:"
sudo objdump -h "$UKI_PATH" | grep -E 'cmdline|splash|osrel' || true
echo ""
echo "Image formats:"
[ -f "$BG_BMP" ] && echo "  BMP: $(file -b "$BG_BMP")" || echo "  BMP: not present"
[ -f "$BG_FILE" ] && echo "  PNG: $(file -b "$BG_FILE")" || echo "  PNG: not present"
echo ""
log_info "Reboot to apply: sudo reboot"
