#!/bin/bash

# --- Configuration & Colors ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "🚀 Anycubic Slicer Next Installer (Universal Bash)"
echo -e "${BLUE}--------------------------------------------------------${NC}"

# --- Pre-Check: Resource Availability ---
echo -e "${BLUE}🔍 Checking resource availability...${NC}"
GLOBAL_URL="https://cdn-global-slicer.anycubic.com/install/AnycubicSlicerNextInstaller.sh"
UNIVERSE_URL="https://cdn-universe-slicer.anycubic.com/install/AnycubicSlicerNextInstaller.sh"

GLOBAL_AVAILABLE=false
if curl --head --silent --fail --connect-timeout 5 "$GLOBAL_URL" > /dev/null 2>&1; then
    GLOBAL_AVAILABLE=true
fi

# --- Step 1: Version Selection ---
echo -e "\n${YELLOW}--- Step 1: Region / Version Selection ---${NC}"
V_DEFAULT="2"
if [ "$GLOBAL_AVAILABLE" = true ]; then
    V_DEFAULT="1"
    echo -e "1) Global Version (International - ${GREEN}Available / Recommended Default${NC})"
    echo -e "2) Universe Version (Asia-Pacific)"
else
    V_DEFAULT="2"
    echo -e "1) Global Version (${RED}Not available / Offline${NC})"
    echo -e "2) Universe Version (Asia-Pacific - ${GREEN}Default${NC})"
fi

read -p "Selection [$V_DEFAULT]: " v_choice
v_choice=${v_choice:-$V_DEFAULT}

SELECTED_URL="$UNIVERSE_URL"
if [ "$v_choice" == "1" ]; then
    SELECTED_URL="$GLOBAL_URL"
    echo -e "Selection: ${BLUE}Global Version${NC}"
else
    echo -e "Selection: ${BLUE}Universe Version${NC}"
fi

# --- Step 2: Hardware Detection & GPU Override ---
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
read -p "Select Driver Stack [$gpu_default]: " gpu_choice
gpu_choice=${gpu_choice:-$gpu_default}

GPU_FLAG=""
ADD_FLAGS=""
GPU_TYPE="generic"
CONTAINERFILE="Containerfile.amd"

case $gpu_choice in
    1) GPU_FLAG="--nvidia"; GPU_TYPE="nvidia"; CONTAINERFILE="Containerfile.nvidia" ;;
    2) ADD_FLAGS="--device /dev/dri:/dev/dri"; GPU_TYPE="amd"; CONTAINERFILE="Containerfile.amd" ;;
    3) ADD_FLAGS="--device /dev/dri:/dev/dri"; GPU_TYPE="intel"; CONTAINERFILE="Containerfile.intel" ;;
    *) GPU_TYPE="generic"; CONTAINERFILE="Containerfile.amd" ;;
esac

# --- Step 3: Image Source ---
echo -e "\n${YELLOW}--- Step 3: Image Source ---${NC}"
echo "1) Standard Ubuntu 24.04 from DockerHub (Default)"
echo "2) Custom Local Containerfile (Build locally)"
read -p "Selection [1]: " img_choice
img_choice=${img_choice:-1}

# --- Step 4: Installation Loop with DNS Retry ---
SUCCESS=false
USE_DNS=false

while [ "$SUCCESS" = false ]; do
    # Cleanup old container if exists
    if distrobox list | grep -q "anycubic-slicer"; then
        distrobox rm -f anycubic-slicer
    fi

    CURRENT_ADD_FLAGS="$ADD_FLAGS"
    if [ "$USE_DNS" = true ]; then
        echo -e "${YELLOW}🔧 DNS/Network issues detected. Re-creating container with explicit DNS (1.1.1.1)...${NC}"
        CURRENT_ADD_FLAGS="$CURRENT_ADD_FLAGS --dns 1.1.1.1 --dns 8.8.8.8"
    fi

    # Host Dependencies
    if command -v pacman &> /dev/null; then sudo pacman -S --needed --noconfirm distrobox podman
    elif command -v apt &> /dev/null; then sudo apt update && sudo apt install -y distrobox podman
    elif command -v dnf &> /dev/null; then sudo dnf install -y distrobox podman; fi

    # Image Preparation
    IMAGE_NAME="ubuntu:24.04"
    if [ "$img_choice" == "2" ]; then
        if [ -f "$CONTAINERFILE" ]; then
            echo -e "${BLUE}🏗️ Building local image...${NC}"
            podman build -t "anycubic-custom-$GPU_TYPE" -f "$CONTAINERFILE" .
            IMAGE_NAME="anycubic-custom-$GPU_TYPE"
        else
            echo -e "${RED}Warning: $CONTAINERFILE not found, using standard image.${NC}"
        fi
    fi

    echo -e "${BLUE}📦 Creating Distrobox container...${NC}"
    eval "distrobox create --name anycubic-slicer --image $IMAGE_NAME $GPU_FLAG --additional-flags '$CURRENT_ADD_FLAGS' --yes"

    echo -e "\n${YELLOW}⏳ Installing basic packages. This might take a few minutes...${NC}"

    # Package list fixed for Ubuntu 24.04 (Noble)
    distrobox enter anycubic-slicer -- bash -c "
        sudo apt update && \
        sudo apt install -y curl ca-certificates lsb-release locales libfuse2* sudo libgl1 libglx-mesa0 libegl1 libgl1-mesa-dri && \
        sudo locale-gen en_US.UTF-8 && \
        echo 'Downloading and running Anycubic installer...' && \
        curl -fsSL $SELECTED_URL -o /tmp/installer.sh && \
        /bin/bash /tmp/installer.sh
    "

    # Check if binary exists
    if distrobox enter anycubic-slicer -- bash -c "command -v AnycubicSlicerNext" &> /dev/null; then
        SUCCESS=true
    else
        if [ "$USE_DNS" = false ]; then
            echo -e "${RED}⚠️ Installation failed. Retrying with DNS fix...${NC}"
            USE_DNS=true
        else
            echo -e "${RED}❌ Installation failed twice. Please check your internet connection.${NC}"
            exit 1
        fi
    fi
done

# --- Step 5: Export & Final Fixes ---
echo -e "\n${BLUE}🔗 Exporting application and applying fixes...${NC}"
distrobox enter anycubic-slicer -- distrobox-export --app AnycubicSlicerNext

D_FILE=$(find ~/.local/share/applications -name "*anycubic*.desktop" | head -n 1)

if [ -n "$D_FILE" ]; then
    # Fix Icon Path
    sed -i 's|/run/host||' "$D_FILE"

    # Apply Auto-Stop logic
    OLD_EXEC=$(grep "Exec=" "$D_FILE" | cut -d'=' -f2-)
    if ! grep -q "distrobox stop" "$D_FILE"; then
        sed -i "s|Exec=.*|Exec=sh -c \"$OLD_EXEC; distrobox stop anycubic-slicer --yes\"|" "$D_FILE"
    fi

    [ -x "$(command -v update-desktop-database)" ] && update-desktop-database ~/.local/share/applications
    echo -e "${GREEN}✅ Installation successful!${NC}"
    echo -e "You can now find 'Anycubic Slicer Next' in your app menu."
else
    echo -e "${RED}❌ Export failed. Desktop file not found.${NC}"
    exit 1
fi
