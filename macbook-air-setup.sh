#!/bin/bash
#
# MacBook Air 6,2 (2013/2014) Arch Linux Post-Install Setup
# Handles: Broadcom BCM4360 Wi-Fi, FaceTime HD Camera, and Wi-Fi Profile
#

set -e

# --- Configuration ---
WIFI_SSID="216-KILLIAN"
WIFI_PASSWORD="rytgah-tyVcyw-hutxy6"

echo "=== [1/4] Preparing the system (installing AUR helper: paru) ==="
# Check if we are in a graphical session
if ! command -v pacman &> /dev/null; then
    echo "This script must be run on an Arch Linux system."
    exit 1
fi

# Install base-devel and git if not present
sudo pacman -S --needed --noconfirm base-devel git

# Install paru (AUR Helper) if not already present
if ! command -v paru &> /dev/null; then
    echo "Installing paru (AUR Helper)..."
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    cd /tmp/paru
    makepkg -si --noconfirm
    cd ~
    rm -rf /tmp/paru
else
    echo "paru is already installed."
fi

echo "=== [2/4] Installing Broadcom BCM4360 Wi-Fi Driver ==="
# The DKMS package builds the wl kernel module automatically
sudo pacman -S --needed --noconfirm broadcom-wl-dkms linux-headers

echo "=== [3/4] Installing FaceTime HD Camera Drivers ==="
# Install the DKMS driver, firmware, and calibration data from the AUR
paru -S --needed --noconfirm facetimehd-dkms-git facetimehd-firmware facetimehd-data

echo "=== [4/4] Configuring Wi-Fi Profile and NetworkManager ==="
# Ensure NetworkManager is enabled
sudo systemctl enable --now NetworkManager

# Create the persistent Wi-Fi connection profile
echo "Creating Wi-Fi profile for: $WIFI_SSID"
sudo nmcli connection add type wifi ifname "*" con-name "$WIFI_SSID" ssid "$WIFI_SSID"
sudo nmcli connection modify "$WIFI_SSID" wifi-sec.key-mgmt wpa-psk
sudo nmcli connection modify "$WIFI_SSID" wifi-sec.psk "$WIFI_PASSWORD"
sudo nmcli connection modify "$WIFI_SSID" connection.autoconnect yes
# Attempt to connect immediately
sudo nmcli connection up "$WIFI_SSID" || echo "Please verify your Wi-Fi password."

echo "=== Setup Complete! ==="
echo "A reboot is recommended to ensure the camera driver loads correctly."
echo "After reboot, your system should be fully functional."