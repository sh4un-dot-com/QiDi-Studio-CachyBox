#!/bin/bash

# --- Configuration & Colors ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

LOG_DIR="$HOME/.cache/qidi-installer"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/uninstall.log"
LAST_STEP_FILE="$LOG_DIR/last_failed_step"

CONTAINER_NAME="qidi-studio"
NON_INTERACTIVE=false
DRY_RUN=false

# CLI parser
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --container-name)
            CONTAINER_NAME="$2"; shift 2 ;;
        --non-interactive|--yes|-y)
            NON_INTERACTIVE=true; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --log-file)
            LOG_FILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--container-name NAME] [--non-interactive] [--dry-run]"; exit 0 ;;
        *) shift ;;
    esac
done

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "QIDI Studio Uninstaller (Universal Bash)"
echo -e "${BLUE}--------------------------------------------------------${NC}"

log(){
    local level="$1"; shift
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo -e "[$ts] [$level] $*" | tee -a "$LOG_FILE"
}

fail(){
    local msg="$1"; shift
    echo
    log "ERROR" "$msg"
    echo "$LAST_STEP" > "$LAST_STEP_FILE" || true
    exit 1
}

trap 'rc=$?; if [ $rc -ne 0 ]; then log "ERROR" "Uninstaller exited with code $rc (last step: $LAST_STEP)"; fi' EXIT

# 1. Unexport the application (removes menu entries and binaries)
if distrobox list | grep -q "$CONTAINER_NAME"; then
    log INFO "--- Step 1: Removing Menu Entries & Binaries ---"
    distrobox enter "$CONTAINER_NAME" -- distrobox-export --app QIDIStudio --delete
else
    log INFO "No active container '$CONTAINER_NAME' found for unexporting."
fi

# 2. Remove the Distrobox container
if distrobox list | grep -q "$CONTAINER_NAME"; then
    log INFO "--- Step 2: Removing Distrobox Container ---"
    if [ "$DRY_RUN" = true ]; then
        log INFO "DRY RUN: would remove container $CONTAINER_NAME"
    else
        distrobox rm -f "$CONTAINER_NAME"
    fi
    log INFO "Container '$CONTAINER_NAME' removed."
else
    log INFO "Container '$CONTAINER_NAME' does not exist."
fi

# 3. Remove custom Podman images
echo -e "${YELLOW}--- Step 3: Removing Podman Images ---${NC}"
# Look for images created during custom installation
IMAGES=$(podman images | grep "qidi-custom" | awk '{print $3}')
if [ -n "$IMAGES" ]; then
    if [ "$DRY_RUN" = true ]; then
        log INFO "DRY RUN: would remove images: $IMAGES"
    else
        podman rmi -f "$IMAGES"
    fi
    log INFO "Custom QIDI images removed."
else
    log INFO "No custom QIDI images found."
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
echo -e "\n${RED}CAUTION: Configuration Cleanup${NC}"
echo -e "Your slicer profiles and settings are stored in ${BLUE}~/.config/QIDIStudio${NC}"
if [ "$NON_INTERACTIVE" = true ]; then
    cleanup_config=n
else
    read -p "Do you want to delete all your profiles and settings? (y/N): " cleanup_config
fi

if [[ "$cleanup_config" == "y" || "$cleanup_config" == "Y" ]]; then
    rm -rf ~/.config/QIDIStudio
    rm -rf ~/.config/qidi-studio
    echo -e "${GREEN}Configuration directories deleted.${NC}"
else
    echo -e "${BLUE}Configuration directories kept.${NC}"
fi

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "Uninstallation complete!"
echo -e "${BLUE}--------------------------------------------------------${NC}"
