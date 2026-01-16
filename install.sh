#!/bin/bash

# Arch + Hyprland + Noctalia Installer
# Run after fresh archinstall with Minimal profile

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check we're not root
if [ "$EUID" -eq 0 ]; then
    error "Don't run this script as root. Run as your normal user."
fi

# Check internet
info "Checking internet connection..."
ping -c 1 archlinux.org &>/dev/null || error "No internet connection. Connect with nmtui first."

echo ""
echo "========================================="
echo "  Arch + Hyprland + Noctalia Installer"
echo "========================================="
echo ""

# -----------------------------------------------------------------------------
# Step 1: Install yay (AUR Helper)
# -----------------------------------------------------------------------------
if command -v yay &>/dev/null; then
    info "yay already installed, skipping..."
else
    info "Installing yay..."
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd ~
fi

# -----------------------------------------------------------------------------
# Step 2: Enable multilib
# -----------------------------------------------------------------------------
if grep -q "^\[multilib\]" /etc/pacman.conf; then
    info "Multilib already enabled, skipping..."
else
    info "Enabling multilib repository..."
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
fi

# Update package database
sudo pacman -Syu --noconfirm

# -----------------------------------------------------------------------------
# Step 3: Graphics drivers
# -----------------------------------------------------------------------------
echo ""
echo "Select your GPU:"
echo "  1) NVIDIA"
echo "  2) AMD"
echo "  3) Intel"
echo "  4) Skip (already installed)"
echo ""
read -p "Choice [1-4]: " gpu_choice

case $gpu_choice in
    1)
        info "Installing NVIDIA drivers (with VA-API for hardware acceleration)..."
        sudo pacman -S --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
            nvidia-settings libva-nvidia-driver

        # Create modprobe config
        info "Configuring NVIDIA for Wayland..."
        sudo tee /etc/modprobe.d/nvidia.conf > /dev/null <<EOF
options nvidia-drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

        # Add modules to initramfs
        if ! grep -q "nvidia nvidia_modeset" /etc/mkinitcpio.conf; then
            sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
            sudo mkinitcpio -P
        fi

        # Enable services
        sudo systemctl enable nvidia-suspend nvidia-hibernate nvidia-resume

        NVIDIA_ENV=true
        ;;
    2)
        info "Installing AMD drivers..."
        sudo pacman -S --noconfirm mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
        ;;
    3)
        info "Installing Intel drivers..."
        sudo pacman -S --noconfirm mesa lib32-mesa vulkan-intel lib32-vulkan-intel
        ;;
    4)
        info "Skipping GPU drivers..."
        ;;
    *)
        warn "Invalid choice, skipping GPU drivers..."
        ;;
esac

# -----------------------------------------------------------------------------
# Step 4: Hyprland + Native Ecosystem (Official Repos)
# -----------------------------------------------------------------------------
info "Installing Hyprland and native tools from official repos..."
sudo pacman -S --noconfirm \
    hyprland \
    xdg-desktop-portal-hyprland \
    hypridle \
    hyprlock \
    hyprsunset \
    hyprpolkitagent \
    qt5-wayland qt6-wayland

# -----------------------------------------------------------------------------
# Step 5: Noctalia Shell (AUR)
# -----------------------------------------------------------------------------
info "Installing Noctalia Shell from AUR..."
warn "This may take 10-20 minutes (compiles quickshell/qt6 components)..."
yay -S --noconfirm noctalia-shell

# -----------------------------------------------------------------------------
# Step 6: Voice-to-Text (optional)
# -----------------------------------------------------------------------------
echo ""
read -p "Install hyprwhspr (voice-to-text with on-screen visualizer)? [y/N]: " voice_choice

if [[ "$voice_choice" =~ ^[Yy]$ ]]; then
    info "Installing hyprwhspr from AUR..."
    yay -S --noconfirm hyprwhspr-git
    HYPRWHSPR_INSTALLED=true
fi

# -----------------------------------------------------------------------------
# Step 7: Essential packages
# -----------------------------------------------------------------------------
info "Installing essentials..."
sudo pacman -S --noconfirm \
    kitty \
    thunar \
    firefox \
    ttf-jetbrains-mono-nerd \
    noto-fonts \
    noto-fonts-emoji \
    cliphist \
    wl-clipboard

# -----------------------------------------------------------------------------
# Step 8: Optional extras
# -----------------------------------------------------------------------------
echo ""
read -p "Install Bluetooth support? [y/N]: " bluetooth_choice

if [[ "$bluetooth_choice" =~ ^[Yy]$ ]]; then
    info "Installing Bluetooth..."
    sudo pacman -S --noconfirm bluez bluez-utils
    sudo systemctl enable bluetooth
fi

# -----------------------------------------------------------------------------
# Step 9: Environment variables
# -----------------------------------------------------------------------------
info "Setting environment variables..."
sudo tee /etc/environment > /dev/null <<EOF
XDG_CURRENT_DESKTOP=Hyprland
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=Hyprland
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
MOZ_ENABLE_WAYLAND=1
EOF

if [ "$NVIDIA_ENV" = true ]; then
    info "Adding NVIDIA environment variables..."
    sudo tee -a /etc/environment > /dev/null <<EOF
LIBVA_DRIVER_NAME=nvidia
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
NVD_BACKEND=direct
EOF
fi

# -----------------------------------------------------------------------------
# Step 10: Auto-login
# -----------------------------------------------------------------------------
echo ""
read -p "Configure auto-login for user '$USER'? [Y/n]: " autologin_choice

if [[ ! "$autologin_choice" =~ ^[Nn]$ ]]; then
    info "Configuring auto-login..."
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $USER %I \$TERM
EOF
fi

# -----------------------------------------------------------------------------
# Step 11: Auto-start Hyprland
# -----------------------------------------------------------------------------
info "Configuring Hyprland auto-start..."
if ! grep -q "exec Hyprland" ~/.bash_profile 2>/dev/null; then
    cat >> ~/.bash_profile <<'EOF'

# Auto-start Hyprland on tty1
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec Hyprland
fi
EOF
fi

# -----------------------------------------------------------------------------
# Step 12: Hyprland config
# -----------------------------------------------------------------------------
info "Creating Hyprland config..."
mkdir -p ~/.config/hypr

if [ -f ~/.config/hypr/hyprland.conf ]; then
    warn "Hyprland config exists, backing up to hyprland.conf.bak"
    cp ~/.config/hypr/hyprland.conf ~/.config/hypr/hyprland.conf.bak
fi

cat > ~/.config/hypr/hyprland.conf <<'HYPRCONF'
# Monitor
monitor=,preferred,auto,1

# =============================================================================
# STARTUP
# =============================================================================

# Noctalia Shell (bar, launcher, notifications, wallpaper)
exec-once = qs -c noctalia-shell

# Native Hypr ecosystem tools
exec-once = systemctl --user start hyprpolkitagent
exec-once = hypridle
exec-once = hyprsunset --temperature 4500

# Clipboard history
exec-once = wl-paste --watch cliphist store

# =============================================================================
# ENVIRONMENT
# =============================================================================

env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt6ct
HYPRCONF

# Add NVIDIA env vars to config if needed
if [ "$NVIDIA_ENV" = true ]; then
    cat >> ~/.config/hypr/hyprland.conf <<'HYPRCONF'

# NVIDIA
env = LIBVA_DRIVER_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
HYPRCONF
fi

# Continue with rest of config
cat >> ~/.config/hypr/hyprland.conf <<'HYPRCONF'

# =============================================================================
# LOOK & FEEL
# =============================================================================

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(b4befeee) rgba(cba6f7ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

decoration {
    rounding = 15
    blur {
        enabled = true
        size = 6
        passes = 3
        new_optimizations = true
    }
    shadow {
        enabled = true
        range = 4
        render_power = 3
        color = rgba(1a1a1aee)
    }
}

animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# =============================================================================
# INPUT
# =============================================================================

input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
}

# =============================================================================
# LAYOUT
# =============================================================================

dwindle {
    pseudotile = true
    preserve_split = true
}

# =============================================================================
# KEYBINDS
# =============================================================================

$mainMod = SUPER

# Apps
bind = $mainMod, Return, exec, kitty
bind = $mainMod, E, exec, thunar
bind = $mainMod, B, exec, firefox

# Window management
bind = $mainMod, Q, killactive
bind = $mainMod SHIFT, Q, exit
bind = $mainMod, F, fullscreen
bind = $mainMod, Space, togglefloating
bind = $mainMod, P, pseudo
bind = $mainMod, J, togglesplit

# Noctalia controls
bind = $mainMod, D, exec, qs -c noctalia-shell ipc call launcher toggle
bind = $mainMod, A, exec, qs -c noctalia-shell ipc call control toggle
bind = $mainMod, Escape, exec, qs -c noctalia-shell ipc call session toggle


# Move focus
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Move to workspace
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

# Scroll through workspaces
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Move/resize with mouse
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow
HYPRCONF

# Add hyprwhspr keybind if installed
if [ "$HYPRWHSPR_INSTALLED" = true ]; then
    cat >> ~/.config/hypr/hyprland.conf <<'HYPRCONF'

# Voice-to-text
bind = $mainMod ALT, D, exec, hyprwhspr
HYPRCONF
fi

# -----------------------------------------------------------------------------
# Step 13: Enable hyprpolkitagent service
# -----------------------------------------------------------------------------
info "Enabling hyprpolkitagent user service..."
systemctl --user enable hyprpolkitagent.service 2>/dev/null || true

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Reboot to start using Hyprland + Noctalia:"
echo ""
echo "  sudo reboot"
echo ""
echo "After reboot:"
echo "  Super + D       - Launcher"
echo "  Super + Return  - Terminal (kitty)"
echo "  Super + E       - File manager (thunar)"
echo "  Super + B       - Browser (firefox)"
echo "  Super + A       - Control center"
echo "  Super + Escape  - Power menu"
if [ "$HYPRWHSPR_INSTALLED" = true ]; then
echo "  Super + Alt + D - Voice-to-text"
fi
echo ""
