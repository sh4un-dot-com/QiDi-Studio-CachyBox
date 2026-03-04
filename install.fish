#!/usr/bin/fish

set blue (set_color blue); set green (set_color green); set red (set_color red); set yellow (set_color yellow); set normal (set_color normal)

echo -e "$blue--------------------------------------------------------"
echo -e "QIDI Studio Installer for CachyOS"
echo -e "--------------------------------------------------------$normal"

# --- CLI options & logging ---
set LOG_DIR "$HOME/.cache/qidi-installer"
mkdir -p $LOG_DIR
set LOG_FILE "$LOG_DIR/install.log"
set NON_INTERACTIVE false
set DRY_RUN false

# Prevent running as root: distrobox commands do not behave correctly under sudo
if test (id -u) -eq 0
    echo "ERROR: Do not run this installer with sudo or as root."
    echo "Please run as your regular user (no sudo): ./install.fish"
    echo "If you intentionally need root distrobox operations, re-run without this script or use distrobox --root commands as documented."
    exit 1
end

set PRECHECK false
set UNINSTALL false
set QIDI_URL "https://github.com/QIDITECH/QIDIStudio/releases/download/v2.04.01.11/QIDIStudio_v02.04.01.11_Ubuntu24.AppImage"
set CONTAINER_NAME "qidi-studio"
set gpu_choice ""
set img_choice ""
set i 1
while test $i -le (count $argv)
    switch $argv[$i]
        case --non-interactive --yes -y
            set NON_INTERACTIVE true
        case --dry-run
            set DRY_RUN true
        case --check
            set PRECHECK true
        case --uninstall
            set UNINSTALL true
        case --url
            set i (math $i + 1)
            set QIDI_URL $argv[$i]
        case --container-name
            set i (math $i + 1)
            set CONTAINER_NAME $argv[$i]
        case --log-file
            set i (math $i + 1)
            set LOG_FILE $argv[$i]
        case --gpu
            set i (math $i + 1)
            set gpu_choice $argv[$i]
        case --image-source
            set i (math $i + 1)
            set img_choice $argv[$i]
        case --help -h
            echo "Usage: $_ [--non-interactive] [--dry-run] [--check] [--uninstall] [--url URL] [--container-name NAME] [--gpu 1-4] [--image-source 1-2]"
            exit 0
    end
    set i (math $i + 1)
end

if test "$UNINSTALL" = "true"
    log INFO "Switching to uninstaller mode"
    set extra_args
    if test "$NON_INTERACTIVE" = "true"
        set extra_args $extra_args --yes
    end
    if test "$DRY_RUN" = "true"
        set extra_args $extra_args --dry-run
    end
    set script_dir (dirname (status filename))
    exec fish "$script_dir/uninstall.fish" --container-name $CONTAINER_NAME $extra_args
end

function log
    set level $argv[1]; set -e argv[1]
    set ts (date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$ts] [$level] $argv" | tee -a $LOG_FILE
end

function spinner
    # simple spinner for a pid (compatible with older fish)
    set pid $argv[1]
    set chars "|/-\\"
    set len (echo $chars | wc -c)
    set i 1
    while ps -p $pid > /dev/null
        # extract the i-th character
        set char (echo $chars | cut -c$i)
        printf " [%s]  " $char
        set i (math "($i % $len) + 1")
        sleep 0.1
        printf "\b\b\b\b\b\b"
    end
end

function preflight
    log INFO "Running preflight checks"
    for cmd in distrobox podman curl lspci
        if not type -q $cmd
            log WARN "Command $cmd not found"
        end
    end
    if not ping -c1 github.com >/dev/null 2>&1
        log WARN "Network appears unreachable"
        echo "WARNING: network check failed"
    end
    set avail (df --output=avail -k . | tail -n1)
    if test $avail -lt 1048576
        log WARN "Less than 1GB free disk space"
    end
    echo "preflight complete"
end



# --- Download URL for the latest AppImage release ---
# (already in QIDI_URL, copied earlier)

# if preflight requested, run and exit
if test "$PRECHECK" = "true"
    preflight
    exit 0
end

# --- GPU Selection ---

echo -e "\n$yellow--- GPU Selection ---$normal"

if test -n "$gpu_choice"
    log INFO "Using GPU selection from CLI: $gpu_choice"
else
    set gpu_choice ""
end
set detected_gpu "none"
if type -q nvidia-smi; if nvidia-smi > /dev/null 2>&1; set detected_gpu "nvidia"; end; end
if test "$detected_gpu" = "none"
    if lspci | grep -Ei "VGA|3D" | grep -iq "AMD"; set detected_gpu "amd"
    else if lspci | grep -Ei "VGA|3D" | grep -iq "Intel"; set detected_gpu "intel"; end
end

echo -e "Detected Hardware: $green$detected_gpu$normal"
set g_def "4"; switch $detected_gpu; case "nvidia"; set g_def "1"; case "amd"; set g_def "2"; case "intel"; set g_def "3"; end

echo "1) Nvidia  2) AMD  3) Intel  4) Generic"
if test -n "$gpu_choice"
    set g_choice $gpu_choice
    log INFO "Using GPU from CLI: $g_choice"
else if test "$NON_INTERACTIVE" = "true"
    set g_choice $g_def
    log INFO "Non-interactive: selecting GPU stack $g_choice"
else
    read -P "Select Driver Stack [$g_def]: " g_choice; if test -z "$g_choice"; set g_choice "$g_def"; end
end

set gpu_flags ""; set add_flags ""; set g_type "generic"; set c_file "containerfile.amd"
switch $g_choice
    case 1; set gpu_flags "--nvidia"; set g_type "nvidia"; set c_file "containerfile.nvidia"
    case 2; set add_flags "--device /dev/dri:/dev/dri"; set g_type "amd"; set c_file "containerfile.amd"
    case 3; set add_flags "--device /dev/dri:/dev/dri"; set g_type "intel"; set c_file "containerfile.intel"
end

# --- Step 2: Image Source ---
echo -e "\n$yellow--- Step 2: Image Source ---$normal"
echo "1) Standard Ubuntu 24.04 from DockerHub (Default)"
echo "2) Custom Local Containerfile (Build locally)"
if test "$NON_INTERACTIVE" = "true"
    set img_choice 1
    log INFO "Non-interactive: selecting image source $img_choice"
else
    read -P "Selection [1]: " img_choice
    if test -z "$img_choice"; set img_choice "1"; end
end

# --- Image Preparation ---
set image_name "ubuntu:24.04"
if test "$img_choice" = "2"
    if test -f "$c_file"
        log INFO "Building local image from $c_file"
        if test "$DRY_RUN" = "true"
            log INFO "DRY RUN: would run podman build -t qidi-custom-$g_type -f $c_file ."
        else
            podman build -t "qidi-custom-$g_type" -f "$c_file" . 2>&1 | tee -a $LOG_FILE &
            spinner $last_pid
            wait $last_pid
        end
        set image_name "qidi-custom-$g_type"
    else
        echo -e "{$red}Warning: $c_file not found, using standard image.$normal"
    end
end

# Inform user what's next and where logs will go
log INFO "Starting installation loop. Output will stream to console and $LOG_FILE"
echo "\nStarting installation — streaming output to console and log: $LOG_FILE\n"

# --- Step 3: Installation Loop with DNS Retry ---
set use_custom_dns false; set install_success false
while test "$install_success" = false
    if distrobox list | grep -q "$CONTAINER_NAME"; distrobox rm -f "$CONTAINER_NAME"; end
    set current_add_flags "$add_flags"
    if test "$use_custom_dns" = true
        echo -e "$yellowDNS issues detected. Retrying with explicit DNS...$normal"
        set current_add_flags "$current_add_flags --dns 1.1.1.1 --dns 8.8.8.8"
    end

    if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: would create distrobox container: distrobox create --name $CONTAINER_NAME --image $image_name $gpu_flags --additional-flags \"$current_add_flags\" --yes"
    else
        distrobox create --name "$CONTAINER_NAME" --image $image_name $gpu_flags --additional-flags "$current_add_flags" --yes 2>&1 | tee -a $LOG_FILE &
        spinner $last_pid
    end
    echo -e "\n$yellowInstalling basic packages. This might take a few minutes...$normal"

    if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: would enter container and run apt update/install and download QIDI AppImage"
    else
        distrobox enter $CONTAINER_NAME -- bash -lc "set -euo pipefail; echo 'Running: apt update'; sudo apt update; echo 'Running: apt install'; sudo apt install -y curl ca-certificates lsb-release locales libfuse2* sudo libgl1 libglx-mesa0 libegl1 libgl1-mesa-dri; sudo locale-gen en_US.UTF-8; echo 'Downloading QIDI Studio AppImage'; curl --fail -L --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 300 --progress-bar $QIDI_URL -o /usr/local/bin/QIDIStudio; chmod +x /usr/local/bin/QIDIStudio" 2>&1 | tee -a $LOG_FILE &
        spinner $last_pid
    end
    if test "$DRY_RUN" = "true"
        set install_success true
    else
        distrobox enter "$CONTAINER_NAME" -- bash -lc "command -v QIDIStudio >/dev/null 2>&1"
        if test $status -eq 0
            set install_success true
        else
            if test "$use_custom_dns" = false
                set use_custom_dns true
            else
                log ERROR "Installation failed. See $LOG_FILE for details"
                exit 1
            end
        end
    end
end

# --- Step 4: Export & Auto-Stop ---
if test "$DRY_RUN" = "true"
    log INFO "DRY RUN: would run distrobox-export --app QIDIStudio"
else
    distrobox enter "$CONTAINER_NAME" -- distrobox-export --app QIDIStudio 2>&1 | tee -a $LOG_FILE
end
set d_file (find ~/.local/share/applications -name "*qidi*.desktop" | head -n 1)
if test -n "$d_file"
    sed -i 's|/run/host||' $d_file
    set exec_cmd (grep "Exec=" $d_file | cut -d'=' -f2-)
    sed -i "s|Exec=.*|Exec=sh -c \"$exec_cmd; distrobox stop $CONTAINER_NAME --yes\"|" $d_file
    if type -q update-desktop-database
        update-desktop-database ~/.local/share/applications
    end
    echo -e "$greenDone! Container stops automatically on exit.$normal"
else
    if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: desktop file would be created at ~/.local/share/applications/*qidi*.desktop"
        exit 0
    end
    echo -e "{$red}Export failed. Desktop file not found.$normal"
    echo "See $LOG_FILE for details"
    exit 1
end

