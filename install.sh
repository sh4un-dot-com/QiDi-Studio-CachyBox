#!/bin/bash

# --- Configuration & Colors ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "QIDI Studio Installer (Universal Bash)"
echo -e "${BLUE}--------------------------------------------------------${NC}"

# --- CLI options & Logging ---
LOG_DIR="$HOME/.cache/qidi-installer"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"
LAST_STEP_FILE="$LOG_DIR/last_failed_step"

NON_INTERACTIVE=false
DRY_RUN=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --non-interactive|--yes|-y)
            NON_INTERACTIVE=true; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --log-file)
            LOG_FILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--non-interactive] [--dry-run] [--log-file FILE]"; exit 0 ;;
        *) shift ;;
    esac
done

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

trap 'rc=$?; if [ $rc -ne 0 ]; then log "ERROR" "Installer exited with code $rc (last step: $LAST_STEP)"; fi' EXIT

# Helpers: download with retries and run commands (logs + dry-run)
download_with_retries(){
    local url="$1" dest="$2"
    local tries=0 max=5
    while [ $tries -lt $max ]; do
        tries=$((tries+1))
        if [ "$DRY_RUN" = true ]; then
            log "INFO" "DRY RUN: would download $url to $dest (attempt $tries)"
            return 0
        fi
        log "INFO" "Downloading $url (attempt $tries/$max)"
        curl --fail -L --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 300 --progress-bar "$url" -o "$dest" 2>&1 | tee -a "$LOG_FILE"
        if [ ${PIPESTATUS[0]:-0} -eq 0 ]; then
            return 0
        fi
        sleep $((tries * 2))
    done
    return 1
}

run_in_container(){
    # run command in distrobox container and stream output to log
    local cmd="$*"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run in container: $cmd"
        return 0
    fi
    distrobox enter qidi-studio -- bash -lc "$cmd" 2>&1 | tee -a "$LOG_FILE"
    return ${PIPESTATUS[0]:-0}
}


# --- Download URL for the latest AppImage release ---
QIDI_URL="https://github.com/QIDITECH/QIDIStudio/releases/download/v2.04.01.11/QIDIStudio_v02.04.01.11_Ubuntu24.AppImage"

# --- GPU Selection ---
# detect hardware and ask the user to choose a driver stack

echo -e "\n${YELLOW}--- GPU Selection ---${NC}"
detected_gpu="none"
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    detected_gpu="nvidia"
elif lspci | grep -Ei "VGA|3D" | grep -iq "AMD"; then
    detected_gpu="amd"
elif lspci | grep -Ei "VGA|3D" | grep -iq "Intel"; then
    detected_gpu="intel"
fi

echo -e "Detected Hardware: ${GREEN}$detected_gpu${NC}"

gpu_default="4"
case $detected_gpu in
    "nvidia") gpu_default="1" ;;
    "amd")    gpu_default="2" ;;
    "intel")  gpu_default="3" ;;
esac

echo "1) Nvidia (uses --nvidia flag)"
echo "2) AMD (uses DRI pass-through)"
echo "3) Intel (uses DRI pass-through)"
echo "4) Generic / None / Software Rendering"
if [ "$NON_INTERACTIVE" = true ]; then
    gpu_choice=$gpu_default
    log "INFO" "Non-interactive: selecting GPU stack $gpu_choice"
else
    read -p "Select Driver Stack [$gpu_default]: " gpu_choice
    gpu_choice=${gpu_choice:-$gpu_default}
fi

GPU_FLAG=""
ADD_FLAGS=""
GPU_TYPE="generic"
CONTAINERFILE="containerfile.amd"

# continue with chosen values

# (containerfile default set earlier)
echo -e "\n${YELLOW}--- Step 2: GPU Selection ---${NC}"
detected_gpu="none"
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    detected_gpu="nvidia"
elif lspci | grep -Ei "VGA|3D" | grep -iq "AMD"; then
    detected_gpu="amd"
elif lspci | grep -Ei "VGA|3D" | grep -iq "Intel"; then
    detected_gpu="intel"
fi

echo -e "Detected Hardware: ${GREEN}$detected_gpu${NC}"

gpu_default="4"
case $detected_gpu in
    "nvidia") gpu_default="1" ;;
    "amd")    gpu_default="2" ;;
    "intel")  gpu_default="3" ;;
esac

echo "1) Nvidia (uses --nvidia flag)"
echo "2) AMD (uses DRI pass-through)"
echo "3) Intel (uses DRI pass-through)"
echo "4) Generic / None / Software Rendering"
if [ "$NON_INTERACTIVE" = true ]; then
    gpu_choice=$gpu_default
    log "INFO" "Non-interactive: selecting GPU stack $gpu_choice"
else
    read -p "Select Driver Stack [$gpu_default]: " gpu_choice
    gpu_choice=${gpu_choice:-$gpu_default}
fi

GPU_FLAG=""
ADD_FLAGS=""
GPU_TYPE="generic"
CONTAINERFILE="containerfile.amd"

case $gpu_choice in
    1) GPU_FLAG="--nvidia"; GPU_TYPE="nvidia"; CONTAINERFILE="containerfile.nvidia" ;;
    2) ADD_FLAGS="--device /dev/dri:/dev/dri"; GPU_TYPE="amd"; CONTAINERFILE="containerfile.amd" ;;
    3) ADD_FLAGS="--device /dev/dri:/dev/dri"; GPU_TYPE="intel"; CONTAINERFILE="containerfile.intel" ;;
    *) GPU_TYPE="generic"; CONTAINERFILE="containerfile.amd" ;;
esac

# --- Step 3: Image Source ---
echo -e "\n${YELLOW}--- Step 3: Image Source ---${NC}"
echo "1) Standard Ubuntu 24.04 from DockerHub (Default)"
echo "2) Custom Local Containerfile (Build locally)"
if [ "$NON_INTERACTIVE" = true ]; then
    img_choice=1
    log "INFO" "Non-interactive: selecting image source $img_choice"
else
    read -p "Selection [1]: " img_choice
    img_choice=${img_choice:-1}
fi

# Inform user what's next and where logs will go
LAST_STEP="start"
log "INFO" "Starting installation loop. Output will stream to console and $LOG_FILE"
echo -e "\nStarting installation — streaming output to console and log: $LOG_FILE\n"

# --- Step 4: Installation Loop with DNS Retry ---
SUCCESS=false
USE_DNS=false

while [ "$SUCCESS" = false ]; do
    # Cleanup old container if exists
    if distrobox list | grep -q "qidi-studio"; then
        distrobox rm -f qidi-studio
    fi

    CURRENT_ADD_FLAGS="$ADD_FLAGS"
    if [ "$USE_DNS" = true ]; then
        echo -e "${YELLOW}DNS/Network issues detected. Re-creating container with explicit DNS (1.1.1.1)...${NC}"
        CURRENT_ADD_FLAGS="$CURRENT_ADD_FLAGS --dns 1.1.1.1 --dns 8.8.8.8"
    fi

    # Host Dependencies
    LAST_STEP="host:deps"
    log "INFO" "Ensuring host dependencies: distrobox, podman"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would install distrobox and podman via system package manager"
    else
        if command -v pacman &> /dev/null; then
            sudo pacman -S --needed --noconfirm distrobox podman 2>&1 | tee -a "$LOG_FILE"
        elif command -v apt &> /dev/null; then
            sudo apt update 2>&1 | tee -a "$LOG_FILE"
            sudo apt install -y distrobox podman 2>&1 | tee -a "$LOG_FILE"
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y distrobox podman 2>&1 | tee -a "$LOG_FILE"
        else
            log "WARN" "Unknown package manager; please ensure distrobox and podman are installed"
        fi
    fi

    # Image Preparation
    IMAGE_NAME="ubuntu:24.04"
    if [ "$img_choice" == "2" ]; then
        if [ -f "$CONTAINERFILE" ]; then
            log "INFO" "Building local image from $CONTAINERFILE"
            if [ "$DRY_RUN" = true ]; then
                log "INFO" "DRY RUN: would run podman build -t qidi-custom-$GPU_TYPE -f $CONTAINERFILE ."
            else
                podman build -t "qidi-custom-$GPU_TYPE" -f "$CONTAINERFILE" . 2>&1 | tee -a "$LOG_FILE"
            fi
            IMAGE_NAME="qidi-custom-$GPU_TYPE"
        else
            echo -e "${RED}Warning: $CONTAINERFILE not found, using standard image.${NC}"
        fi
    fi

    echo -e "${BLUE}Creating Distrobox container...${NC}"
    LAST_STEP="container:create"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run: distrobox create --name qidi-studio --image $IMAGE_NAME $GPU_FLAG --additional-flags '$CURRENT_ADD_FLAGS' --yes"
    else
        distrobox create --name qidi-studio --image $IMAGE_NAME $GPU_FLAG --additional-flags "$CURRENT_ADD_FLAGS" --yes 2>&1 | tee -a "$LOG_FILE"
    fi

    echo -e "\n${YELLOW}Installing basic packages. This might take a few minutes...${NC}"

    # Package list fixed for Ubuntu 24.04 (Noble)
    LAST_STEP="install:packages"
    log "INFO" "Installing packages and downloading application inside container"
    install_cmds=$(cat <<'EOC'
    set -euo pipefail
    echo 'Running: apt update'
    sudo apt update
    echo 'Running: apt install (this will stream progress)'
    sudo apt install -y curl ca-certificates lsb-release locales libfuse2* sudo libgl1 libglx-mesa0 libegl1 libgl1-mesa-dri
    echo 'Generating locales'
    sudo locale-gen en_US.UTF-8
    echo 'Downloading QIDI Studio AppImage (with retries)'
    echo 'Downloading with curl (retries)'
    curl --fail -L --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 300 --progress-bar "$QIDI_URL" -o /usr/local/bin/QIDIStudio
    chmod +x /usr/local/bin/QIDIStudio
    EOC
)

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run install commands inside container"
    else
        # run and capture exit code
        distrobox enter qidi-studio -- bash -lc "$install_cmds" 2>&1 | tee -a "$LOG_FILE"
        install_rc=${PIPESTATUS[0]:-0}
        if [ $install_rc -eq 0 ]; then
            SUCCESS=true
        else
            if [ "$USE_DNS" = false ]; then
                log "WARN" "Installation inside container failed (rc=$install_rc). Retrying with DNS fix..."
                USE_DNS=true
            else
                fail "Installation failed twice. See $LOG_FILE for details."
            fi
        fi
    fi
done

# --- Step 5: Export & Final Fixes ---
echo -e "\n${BLUE}🔗 Exporting application and applying fixes...${NC}"
LAST_STEP="export:app"
log "INFO" "Exporting application"
if [ "$DRY_RUN" = true ]; then
    log "INFO" "DRY RUN: would run distrobox-export for QIDIStudio"
else
    distrobox enter qidi-studio -- distrobox-export --app QIDIStudio 2>&1 | tee -a "$LOG_FILE"
fi

D_FILE=$(find ~/.local/share/applications -name "*qidi*.desktop" | head -n 1)

if [ -n "$D_FILE" ]; then
    # Fix Icon Path
    sed -i 's|/run/host||' "$D_FILE"

    # Apply Auto-Stop logic
    OLD_EXEC=$(grep "Exec=" "$D_FILE" | cut -d'=' -f2-)
    if ! grep -q "distrobox stop" "$D_FILE"; then
        sed -i "s|Exec=.*|Exec=sh -c \"$OLD_EXEC; distrobox stop qidi-studio --yes\"|" "$D_FILE"
    fi

    [ -x "$(command -v update-desktop-database)" ] && update-desktop-database ~/.local/share/applications
    echo -e "${GREEN}Installation successful!${NC}"
    echo -e "You can now find 'QIDI Studio' in your app menu."
else
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: desktop file would be created at ~/.local/share/applications/*qidi*.desktop"
        exit 0
    fi
    echo -e "${RED}Export failed. Desktop file not found.${NC}"
    echo "See $LOG_FILE for details"
    exit 1
fi
