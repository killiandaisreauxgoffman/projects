#!/bin/bash
#
# MacBook Air 6,2 (2013/2014) — Arch Linux Post-Install Setup
#
# Handles:
#   - AUR helper (paru)
#   - Broadcom BCM4360 Wi-Fi driver + blacklist + profile
#   - FaceTime HD Camera drivers + firmware + calibration
#   - Custom boot splash embedded in the UKI
#   - Custom boot label via /etc/os-release override
#   - 15-second systemd-boot menu timeout
#   - Boot sound at greeter stage (direct ALSA, hw:1,0 for CS4208)
#   - KDE login sound via PipeWire notification
#   - Custom background for desktop, lock, logout, greeter
#   - Account lockout after 5 failed password attempts
#   - Optional archived MP4 for future use
#
# Usage:
#   chmod +x macbook-air-setup.sh
#   ./macbook-air-setup.sh
#
# Must be run as a normal user (not root). The script uses sudo internally.
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WIFI_SSID="216-KILLIAN"
WIFI_PASSWORD="rytgah-tyVcyw-hutxy6"
WIFI_CON_NAME="216-KILLIAN"

HOSTNAME_CUSTOM="216-KILLIAN"
OS_PRETTY_NAME="216-KILLIAN"
OS_HOME_URL="https://daisreaux.com/"

SOUND_URL="https://raw.githubusercontent.com/killiandaisreauxgoffman/projects/refs/heads/main/boot-sound.ogg"
BG_URL="https://github.com/killiandaisreauxgoffman/projects/blob/main/boot-background.png?raw=true"
MP4_LOCAL_PATH="/home/killian/Downloads/Telegram/failboot-movie.mp4"

SOUND_DIR="/usr/share/sounds/custom/stereo"
SOUND_FILE="$SOUND_DIR/desktop-login.ogg"

BG_DIR="/usr/share/backgrounds/custom"
BG_FILE="$BG_DIR/boot-background.png"
BG_BMP="/usr/share/systemd/bootctl/splash-arch.bmp"

MEDIA_DIR="/usr/local/share/media"
MP4_FILE="$MEDIA_DIR/failboot-movie.mp4"

AUDIO_DEVICE="alsa/hw:1,0"

# Screen resolution for the MacBookAir6,2
DISPLAY_RES="1440x900"

# ============================================================================
# HELPERS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $1"; }

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

# Detect the root partition UUID for later use
ROOT_UUID=$(findmnt -no UUID -T / 2>/dev/null || true)
if [ -z "$ROOT_UUID" ]; then
    log_err "Could not determine root filesystem UUID. Aborting."
    exit 1
fi
log_info "Detected root UUID: $ROOT_UUID"

# ============================================================================
# [1/10] AUR helper — paru
# ============================================================================

echo ""
log_info "=== [1/10] Installing base-devel, git, and paru ==="
sudo pacman -S --needed --noconfirm base-devel git

if ! command -v paru &>/dev/null; then
    TMPDIR=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$TMPDIR/paru"
    cd "$TMPDIR/paru"
    makepkg -si --noconfirm
    cd ~
    rm -rf "$TMPDIR"
else
    log_info "paru is already installed."
fi

# ============================================================================
# [2/10] Broadcom BCM4360 Wi-Fi driver
# ============================================================================

echo ""
log_info "=== [2/10] Installing Broadcom BCM4360 Wi-Fi driver ==="
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

if ! lsmod | grep -q '^wl '; then
    sudo modprobe wl || true
fi

# ============================================================================
# [3/10] FaceTime HD camera
# ============================================================================

echo ""
log_info "=== [3/10] Installing FaceTime HD camera drivers ==="
paru -S --needed --noconfirm \
    facetimehd-dkms-git \
    facetimehd-firmware \
    facetimehd-data

if ! lsmod | grep -q '^facetimehd '; then
    sudo modprobe facetimehd || true
fi

# ============================================================================
# [4/10] NetworkManager and Wi-Fi profile
# ============================================================================

echo ""
log_info "=== [4/10] Configuring NetworkManager and Wi-Fi profile ==="
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

sudo nmcli connection up "$WIFI_CON_NAME" \
    || log_warn "Could not bring up '$WIFI_CON_NAME'."

# ============================================================================
# [5/10] Boot sound at greeter stage (direct ALSA)
# ============================================================================

echo ""
log_info "=== [5/10] Installing boot sound (greeter stage) ==="

sudo mkdir -p "$SOUND_DIR"
sudo curl -sL "$SOUND_URL" -o "$SOUND_FILE"
sudo chmod 644 "$SOUND_FILE"
sudo ln -sf "$SOUND_FILE" "$SOUND_DIR/desktop-login-short.ogg"
sudo ln -sf "$SOUND_FILE" "$SOUND_DIR/desktop-login-long.ogg"

# Create the KDE sound theme descriptor
sudo mkdir -p /usr/share/sounds/custom
sudo tee /usr/share/sounds/custom/index.theme > /dev/null << 'EOF'
[Sound Theme]
Name=Custom
Comment=Custom sound theme
Directories=stereo

[stereo]
OutputProfile=stereo
EOF

# Detect the correct ALSA hardware for the CS4208 codec
CS4208_CARD=$(aplay -l 2>/dev/null | awk '/CS4208 Analog/ {gsub("card ","",$1); gsub(":","",$1); print $1; exit}')
if [ -n "$CS4208_CARD" ]; then
    AUDIO_DEVICE="alsa/hw:${CS4208_CARD},0"
    log_info "Detected CS4208 on card $CS4208_CARD; using $AUDIO_DEVICE"
else
    log_warn "Could not detect CS4208; defaulting to $AUDIO_DEVICE"
fi

# Install alsa-utils for aplay
sudo pacman -S --needed --noconfirm alsa-utils mpv

# Create the systemd boot sound service
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
# [6/10] KDE login sound (via PipeWire) and session autostart
# ============================================================================

echo ""
log_info "=== [6/10] Configuring KDE login sound ==="

kwriteconfig6 --file kdeglobals --group General --key Theme "custom"
kwriteconfig6 --file plasmanotifyrc \
    --group Notifications --group PlasmaWorkspace \
    --key Login "true"
kwriteconfig6 --file plasmanotifyrc \
    --group Notifications --group PlasmaWorkspace \
    --key LoginSoundFile "$SOUND_FILE"

# Also add an autostart fallback that fires the sound 2 seconds after login
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/play-login-sound.desktop << EOF
[Desktop Entry]
Type=Application
Name=Play Login Sound
Exec=bash -c 'sleep 2; pw-play $SOUND_FILE'
OnlyShowIn=KDE;
EOF

# ============================================================================
# [7/10] Boot splash, background image, and greeter
# ============================================================================

echo ""
log_info "=== [7/10] Installing boot splash and backgrounds ==="

sudo mkdir -p "$BG_DIR"
sudo curl -sL "$BG_URL" -o "$BG_FILE"
sudo chmod 644 "$BG_FILE"

# Convert the PNG to a BMP scaled to the display resolution
sudo ffmpeg -y -i "$BG_FILE" \
    -vf "scale=${DISPLAY_RES}:force_original_aspect_ratio=decrease,pad=${DISPLAY_RES}:(ow-iw)/2:(oh-ih)/2" \
    -pix_fmt bgr24 "$BG_BMP"

# Apply as desktop wallpaper
if command -v plasma-apply-wallpaperimage &>/dev/null; then
    plasma-apply-wallpaperimage "$BG_FILE" || true
fi

# Lockscreen background
kwriteconfig6 --file kscreenlockerrc \
    --group Greeter --group Wallpaper --group org.kde.image --group General \
    --key Image "file://$BG_FILE"

# Logout background
kwriteconfig6 --file ksmserverrc \
    --group General --key logoutBackground "$BG_FILE"

# Greeter background
sudo mkdir -p /etc/plasmalogin
sudo tee /etc/plasmalogin/plasmalogin.conf > /dev/null << EOF
[Greeter]
WallpaperPluginId=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=file://$BG_FILE
EOF

# Greeter user wallpaper directory
if id plasmalogin &>/dev/null; then
    sudo -u plasmalogin mkdir -p /var/lib/plasmalogin/wallpapers
    sudo cp "$BG_FILE" /var/lib/plasmalogin/wallpapers/
    sudo chown -R plasmalogin:plasmalogin /var/lib/plasmalogin/wallpapers
    sudo chmod 644 /var/lib/plasmalogin/wallpapers/boot-background.png
fi

# ============================================================================
# [8/10] UKI preset — root UUID, quiet boot, splash
# ============================================================================

echo ""
log_info "=== [8/10] Updating UKI preset ==="

PRESET_FILE="/etc/mkinitcpio.d/linux.preset"

# Backup the preset once
if [ ! -f "${PRESET_FILE}.orig" ]; then
    sudo cp "$PRESET_FILE" "${PRESET_FILE}.orig"
fi

# Rewrite the preset cleanly, preserving the root UUID
sudo tee "$PRESET_FILE" > /dev/null << EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
ALL_default_splash="$BG_BMP"

PRESETS=('default')

default_uki="/boot/EFI/Linux/arch-linux.efi"
default_options="root=UUID=$ROOT_UUID rw quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0"
EOF

# Rebuild the UKI
sudo mkinitcpio -P

# ============================================================================
# [9/10] OS release override (boot menu label)
# ============================================================================

echo ""
log_info "=== [9/10] Setting boot menu label ==="

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

# Rebuild the UKI so the new label is embedded
sudo mkinitcpio -P

# ============================================================================
# [10/10] Boot timeout, account lockout, MP4 archive
# ============================================================================

echo ""
log_info "=== [10/10] Finalizing system configuration ==="

# Boot menu timeout
sudo sed -i 's/^timeout.*/timeout 15/' /boot/loader/loader.conf

# faillock policy
sudo tee /etc/security/faillock.conf > /dev/null << 'EOF'
deny = 5
unlock_time = 900
fail_interval = 900
EOF

# Reset any existing faillock state
sudo faillock --user "$(whoami)" --reset || true

# Archive the MP4 if it exists and is not already archived
if [ -f "$MP4_LOCAL_PATH" ] && [ ! -f "$MP4_FILE" ]; then
    sudo mkdir -p "$MEDIA_DIR"
    sudo cp "$MP4_LOCAL_PATH" "$MP4_FILE"
    sudo chown root:root "$MP4_FILE"
    sudo chmod 644 "$MP4_FILE"
    log_info "Archived MP4 to $MP4_FILE"
else
    log_info "MP4 already archived or source not present; skipping."
fi

# Create the desktop launcher for the MP4
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
echo "Verify:"
echo "  lsmod | grep wl                     # Wi-Fi driver"
echo "  lsmod | grep facetimehd             # Camera driver"
echo "  dkms status                         # DKMS modules"
echo "  nmcli device status                 # Wi-Fi connection"
echo "  systemctl status boot-sound.service # Boot sound"
echo "  objdump -h /boot/EFI/Linux/arch-linux.efi | grep splash"
echo "  cat /etc/os-release | grep PRETTY   # Boot menu label"
echo "  sudo cat /boot/loader/loader.conf   # Boot timeout"
echo ""
log_info "Reboot recommended to verify the complete boot experience."
