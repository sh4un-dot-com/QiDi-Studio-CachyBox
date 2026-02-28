#!/bin/bash

# --- Configuration & Colors ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "🗑️  QIDI Studio Uninstaller (Universal Bash)"
echo -e "${BLUE}--------------------------------------------------------${NC}"

# 1. Unexport the application (removes menu entries and binaries)
if distrobox list | grep -q "qidi-studio"; then
    echo -e "${YELLOW}--- Step 1: Removing Menu Entries & Binaries ---${NC}"
    # We try to use the internal unexport first for a clean removal
    distrobox enter qidi-studio -- distrobox-export --app QIDIStudio --delete
else
    echo -e "${BLUE}Info: No active container 'qidi-studio' found for unexporting.${NC}"
fi

# 2. Remove the Distrobox container
if distrobox list | grep -q "qidi-studio"; then
    echo -e "${YELLOW}--- Step 2: Removing Distrobox Container ---${NC}"
    distrobox rm -f qidi-studio
    echo -e "${GREEN}Container 'qidi-studio' removed.${NC}"
else
    echo -e "${BLUE}Info: Container 'qidi-studio' does not exist.${NC}"
fi

# 3. Remove custom Podman images
echo -e "${YELLOW}--- Step 3: Removing Podman Images ---${NC}"
# Look for images created during custom installation
IMAGES=$(podman images | grep "qidi-custom" | awk '{print $3}')
if [ -n "$IMAGES" ]; then
    podman rmi -f $IMAGES
    echo -e "${GREEN}Custom QIDI images removed.${NC}"
else
    echo -e "${BLUE}No custom QIDI images found.${NC}"
fi

# 4. Manual Cleanup (Safety Net)
echo -e "${YELLOW}--- Step 4: Final Cleanup of Local Files ---${NC}"
# Remove leftover desktop files and binaries just in case
rm -f ~/.local/share/applications/*qidi*.desktop
rm -f ~/.local/share/applications/*QIDIStudio*.desktop
rm -f ~/.local/bin/QIDIStudio

# Update host desktop database
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database ~/.local/share/applications
fi
echo -e "${GREEN}Desktop database updated.${NC}"

# 5. Optional: Config files cleanup
echo -e "\n${RED}⚠️  CAUTION: Configuration Cleanup${NC}"
echo -e "Your slicer profiles and settings are stored in ${BLUE}~/.config/QIDIStudio${NC}"
read -p "Do you want to delete all your profiles and settings? (y/N): " cleanup_config

if [[ "$cleanup_config" == "y" || "$cleanup_config" == "Y" ]]; then
    rm -rf ~/.config/QIDIStudio
    rm -rf ~/.config/qidi-studio
    echo -e "${GREEN}Configuration directories deleted.${NC}"
else
    echo -e "${BLUE}Configuration directories kept.${NC}"
fi

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "✅ Uninstallation complete!"
echo -e "${BLUE}--------------------------------------------------------${NC}"
