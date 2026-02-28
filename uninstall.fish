#!/usr/bin/fish

set blue (set_color blue)
set red (set_color red)
set yellow (set_color yellow)
set normal (set_color normal)

echo -e "$blue--------------------------------------------------------"
echo -e "🗑️  QIDI Studio Uninstaller"
echo -e "--------------------------------------------------------$normal"

# 1. Remove the app export (menu entries and binaries)
if distrobox list | grep -q "qidi-studio"
    echo -e "$yellow--- Step 1: Unexporting Application ---$normal"
    distrobox enter qidi-studio -- distrobox-export --app QIDIStudio --delete
end

# 2. Remove the Distrobox container
if distrobox list | grep -q "qidi-studio"
    echo -e "$yellow--- Step 2: Removing Distrobox Container ---$normal"
    distrobox rm -f qidi-studio
else
    echo -e "$blue Info: No container 'qidi-studio' found.$normal"
end

# 3. Remove Podman Images related to QIDI
echo -e "$yellow--- Step 3: Removing Podman Images ---$normal"
set images (podman images | grep "qidi" | awk '{print $3}')
if test -n "$images"
    for img in $images
        podman rmi -f $img
    end
    echo "Images removed."
else
    echo "No QIDI-related images found."
end

# 4. Manual cleanup of desktop files and icons (just in case)
echo -e "$yellow--- Step 4: Final Cleanup ---$normal"
rm -f ~/.local/share/applications/*qidi*.desktop
rm -f ~/.local/bin/qidi-studio*
update-desktop-database ~/.local/share/applications

# 5. Optional: Config files
echo -e "$red"
read -P "Do you want to delete all configuration and slicer settings in ~/.config? (y/N): " cleanup_config
echo -e "$normal"

if test "$cleanup_config" = "y"
    rm -rf ~/.config/QIDIStudio
    rm -rf ~/.config/qidi-studio
    echo "Configuration files deleted."
end

echo -e "$blue--------------------------------------------------------"
echo -e "✅ Deinstallation complete!"
echo -e "--------------------------------------------------------$normal"
