# QiDi‑Studio‑CachyBox 🚀
### QiDi Studio: CachyOS Container Edition

This repository contains installer scripts and container configuration that make it simple to run **QiDi Studio** inside a lightweight Ubuntu 24.04 LTS container using **Distrobox** and **Podman**. The container approach protects you from library incompatibilities on rolling‑release distros such as CachyOS while still providing native GPU acceleration.

---

## ✨ Features

* **Automatic Release Fetching:** Downloads the latest QiDi Studio AppImage directly from the official GitHub releases.
* **Hardware-Aware Detection:** Automatically identifies Nvidia, AMD, or Intel GPUs and sets up the correct driver stack.
* **Manual Hardware Override:** Allows users to force a specific driver stack (Nvidia, AMD, Intel, or Generic) during setup.
* **Image Source Selection:** Choose between pulling a standard image from DockerHub or building a locally optimized image via specific `Containerfiles`.
* **Automatic Resource Management (Auto‑Stop):** The container shuts down (`distrobox stop`) as soon as the QiDi Studio window is closed.
* **Desktop Integration:** Clean integration into your application menu with corrected icon paths and categories.
* **Robust Network Handling:** Retries the installation with a DNS workaround if network resolution fails.

---

## 🛠 Prerequisites

Ensure your host system has the following installed:

* **Podman** (Container Engine)
* **Distrobox** (Container Integration Tool)
* **curl** (for downloading releases)
* **Nvidia-utils** (Only if you are using an Nvidia GPU)

---

## 🚀 Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/Slashdacoda/AnySlicer-Next-CachyBox.git
   cd AnySlicer-Next-CachyBox
   ```


2. **Run the installer script:**

   Choose the script that matches your shell environment and make it executable:
   ```bash
   # Bash (universal)
   chmod +x install.sh
   ./install.sh
   # or, if you use Fish:
   chmod +x install.fish
   ./install.fish
   ```

3. **Answer the interactive prompts.**

   The installer will:
   * detect your GPU and let you override the driver stack (Nvidia/AMD/Intel/Generic),
   * optionally build a custom container image or pull a prebuilt one,
   * download the latest QiDi Studio AppImage and register it with Distrobox.

   Once complete the application will appear in your desktop menu; closing the window automatically stops the container.

---

## 📂 File Structure

| File | Purpose |
| :--- | :--- |
| `install.fish` | Interactive installer for CachyOS / Fish shell. |
| `install.sh` | Universal Bash installer for any Linux distro. |
| `uninstall.fish` / `uninstall.sh` | Clean up containers, images, and desktop entries. |
| `Containerfile.[gpu]` | Blueprints to build a local container image (AMD, Nvidia, Intel). |
| `docker-compose.yml` | Configuration for running QiDi Studio via `podman-compose`. |

---

## ⚙️ Functionality Summary

1. **GPU override:** Detects your GPU (e.g. AMD 7900XTX) but lets you pick a different stack if needed.
2. **Image source options:** Use a prebuilt image or build one locally for maximum compatibility.
3. **Auto‑stop launcher:** Exported desktop entry wraps the command so the container exits when the app closes.
4. **Icon fixup:** Removes `/run/host` prefixes from exported `.desktop` files to avoid broken icons.

---

## 🐳 Advanced Usage: Podman‑Compose

You can bypass the installer and run the container manually.

1. Export the desired image variable:
   * Fish: `set -x QIDI_IMAGE qidi-custom-amd`
   * Bash: `export QIDI_IMAGE=qidi-custom-amd`

2. Launch:
   ```bash
   podman-compose up
   ```

---

## 🔍 Troubleshooting

* **DNS errors:** Installer retries with `--dns 1.1.1.1` if it cannot resolve hosts.
* **GUI/graphics issues:** Ensure `nvidia-container-toolkit` is installed for Nvidia cards.
* **FUSE errors:** The container installs `libfuse2*`; make sure you have FUSE permissions.
* **Broken icons:** Run `update-desktop-database ~/.local/share/applications` after install.

---

## ❓ FAQ

### Why use Distrobox?

QiDi Studio depends on specific library versions that can conflict on rolling‑release distros. Distrobox provides a stable Ubuntu environment while still presenting the app as native.

### Is there a performance penalty?

No. The GPU is passed through directly via Mesa/DRI or the Nvidia stack, giving native performance in the 3D preview.

### Where are my settings stored?

Configurations persist in `~/.config/QIDIStudio/` on the host. They remain intact if you reinstall or recreate the container.

---

## 🗑 Uninstallation

Run `./uninstall.fish` or `./uninstall.sh` to remove the container, images, and desktop entries.

---

## 🤝 Credits

Adapted specifically for QiDi Studio with help from an AI assistant for the CachyOS community.
