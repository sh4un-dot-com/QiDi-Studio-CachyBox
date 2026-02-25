#!/usr/bin/fish

set blue (set_color blue); set green (set_color green); set red (set_color red); set yellow (set_color yellow); set normal (set_color normal)

echo -e "$blue--------------------------------------------------------"
echo -e "🚀 Anycubic Slicer Next Installer for CachyOS"
echo -e "--------------------------------------------------------$normal"

# --- Pre-Check: Resource Availability ---
echo -e "$blue🔍 Checking resource availability...$normal"
set global_url "https://cdn-global-slicer.anycubic.com/install/AnycubicSlicerNextInstaller.sh"
set universe_url "https://cdn-universe-slicer.anycubic.com/install/AnycubicSlicerNextInstaller.sh"

set global_available false
if curl --head --silent --fail "$global_url" > /dev/null 2>&1
    set global_available true
end

# --- Step 1: Version Selection ---
echo -e "\n$yellow--- Step 1: Version Selection ---$normal"
set v_default "2"
set global_note ""

if test "$global_available" = true
    set v_default "1"
    echo -e "1) Global Version (International - $greenAvailable / Default$normal)"
    echo -e "2) Universe Version (Asia-Pacific)"
else
    set v_default "2"
    set global_note " ($red Not available / Offline $normal)"
    echo -e "1) Global Version$global_note"
    echo -e "2) Universe Version (Asia-Pacific - $green Default $normal)"
end

read -P "Selection [$v_default]: " v_choice
if test -z "$v_choice"; set v_choice "$v_default"; end

set installer_url "$universe_url"
if test "$v_choice" = "1"
    set installer_url "$global_url"
    echo "Selected: Global Version"
else
    echo "Selected: Universe Version"
end

# --- Step 2: GPU Detection & Override ---
set detected_gpu "none"
if type -q nvidia-smi; if nvidia-smi > /dev/null 2>&1; set detected_gpu "nvidia"; end; end
if test "$detected_gpu" = "none"
    if lspci | grep -Ei "VGA|3D" | grep -iq "AMD"; set detected_gpu "amd"
    else if lspci | grep -Ei "VGA|3D" | grep -iq "Intel"; set detected_gpu "intel"; end
end

echo -e "\n$yellow--- Step 2: GPU Selection ---$normal"
echo "Detected Hardware: $green$detected_gpu$normal"
set g_def "4"; switch $detected_gpu; case "nvidia"; set g_def "1"; case "amd"; set g_def "2"; case "intel"; set g_def "3"; end
echo "1) Nvidia  2) AMD  3) Intel  4) Generic"
read -P "Select Driver Stack [$g_def]: " g_choice; if test -z "$g_choice"; set g_choice "$g_def"; end

set gpu_flags ""; set add_flags ""; set g_type "generic"; set c_file "Containerfile.amd"
switch $g_choice
    case 1; set gpu_flags "--nvidia"; set g_type "nvidia"; set c_file "Containerfile.nvidia"
    case 2; set add_flags "--device /dev/dri:/dev/dri"; set g_type "amd"; set c_file "Containerfile.amd"
    case 3; set add_flags "--device /dev/dri:/dev/dri"; set g_type "intel"; set c_file "Containerfile.intel"
end

# --- Step 3: Installation Loop with DNS Retry ---
set use_custom_dns false; set install_success false
while test "$install_success" = false
    if distrobox list | grep -q "anycubic-slicer"; distrobox rm -f anycubic-slicer; end
    set current_add_flags "$add_flags"
    if test "$use_custom_dns" = true
        echo -e "$yellow🔧 DNS issues detected. Retrying with explicit DNS...$normal"
        set current_add_flags "$current_add_flags --dns 1.1.1.1 --dns 8.8.8.8"
    end

    distrobox create --name anycubic-slicer --image ubuntu:24.04 $gpu_flags --additional-flags "$current_add_flags" --yes
    echo -e "\n$yellow⏳ Installing basic packages. This might take a few minutes...$normal"

    distrobox enter anycubic-slicer -- bash -c "
        sudo apt update && \
        sudo apt install -y curl ca-certificates lsb-release locales libfuse2* sudo libgl1 libglx-mesa0 libegl1 libgl1-mesa-dri && \
        sudo locale-gen en_US.UTF-8 && \
        curl -fsSL $installer_url -o /tmp/installer.sh && /bin/bash /tmp/installer.sh
    "
    if test $status -eq 0; set install_success true
    else
        if test "$use_custom_dns" = false; set use_custom_dns true
        else; echo -e "$red❌ Installation failed.$normal"; exit 1; end
    end
end

# --- Step 4: Export & Auto-Stop ---
distrobox enter anycubic-slicer -- distrobox-export --app AnycubicSlicerNext
set d_file (find ~/.local/share/applications -name "*anycubic*.desktop" | head -n 1)
if test -n "$d_file"
    sed -i 's|/run/host||' $d_file
    set exec_cmd (grep "Exec=" $d_file | cut -d'=' -f2-)
    sed -i "s|Exec=.*|Exec=sh -c \"$exec_cmd; distrobox stop anycubic-slicer --yes\"|" $d_file
    update-desktop-database ~/.local/share/applications
    echo -e "$green✅ Done! Container stops automatically on exit.$normal"
end
