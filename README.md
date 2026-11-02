# Constructor (1997)
### Native Apple Silicon Container for iPadOS & macOS (`arm64`)

> *"You've got a lot of building to do..."*

[![Platform](https://img.shields.io/badge/Platform-iPadOS%2017%2B%20%7C%20macOS%2014%2B-blue.svg)](https://developer.apple.com)
[![Architecture](https://img.shields.io/badge/Architecture-ARM64%20(Apple%20Silicon)-orange.svg)](https://www.apple.com)
[![Graphics](https://img.shields.io/badge/Graphics-Metal%20Accelerated-green.svg)](https://developer.apple.com/metal/)
[![Audio](https://img.shields.io/badge/Audio-CoreAudio%20%2F%20AVAudioEngine-purple.svg)](https://developer.apple.com/av-foundation/)
[![License](https://img.shields.io/badge/License-MIT%20%26%20GPLv2-lightgrey.svg)](LICENSE)
[![Language: Español](https://img.shields.io/badge/Language-Español-yellow.svg)](README.es.md)

> 📖 *Leer en [Español](README.es.md)*

A high-performance, bare-metal container written in **Swift and Metal** that runs the classic city-building and real-time strategy game **Constructor (System 3, 1997)** natively on **Apple Silicon (`arm64`)** hardware for iPad and Mac.

The game runs as a modern, first-class iPadOS application: **no emulator frontends, no command prompts, and no on-screen virtual joysticks**. It features instantaneous boot, full-screen hardware-accelerated rendering, low-latency audio, and an intuitive **1:1 direct multi-touch control system** designed specifically for touchscreens and Apple Pencil.

---

## 🌟 Highlights & Features

- **🎮 Pure 1:1 Direct Touch Controls (No Clunky On-Screen D-Pads or Virtual Trackpads):**
  - **1-Finger Tap / Apple Pencil**: Instant Left-Click (select workers, lay down foundations, interact with menus).
  - **2-Finger Tap or Long Press**: Right-Click with tactile **haptic feedback** confirmation.
  - **2-Finger Pan / Drag**: Smooth map scrolling at **60 FPS with physics-based momentum and inertia**.
  - **Apple Pencil Support**: Native double-tap or squeeze gestures trigger a right-click.
  - **External Peripherals**: Full support for **Magic Keyboard**, external mice, and Bluetooth trackpads.
- **⚡ Metal Graphics Pipeline:**
  - GPU-accelerated MetalKit rendering with custom **Sharp-Bilinear filtering** (preserves crisp isometric pixel art on Liquid Retina and ProMotion displays without blurry bilinear softening).
  - Dynamic resolution switching (320×200 for intro cinematic/menus $\rightarrow$ 640×480 SVGA in-game).
  - Automatic 4:3 aspect ratio correction with integer pillarboxing.
- **🔊 Sound Blaster 16 Stereo Audio Engine:**
  - CoreAudio integration using a lock-free atomic **Ring Buffer** feeding an `AVAudioSourceNode` at 44,100 Hz stereo, eliminating audio buffer underruns, clicks, and pops.
- **💾 Save Game Management:**
  - Native integration with the iPadOS **Files app** (`UIFileSharingEnabled` enabled) so you can back up, restore, or export your save games at any time.
- **🚀 Zero-Friction One-Click Setup:**
  - Interactive zero-touch installer (`install.sh`) that verifies your developer environment, auto-extracts your GOG installer, compiles the ARM64 emulation core, signs the application, and deploys it directly to your connected iPad.

---

## 📋 Prerequisites

To build and install the port onto your iPad or Mac, you will need:

1. **Mac computer:** Running macOS Sonoma (14.0+) or Sequoia (15.0+) with Apple Silicon or Intel.
2. **Xcode 15+:** Installed from the Mac App Store or Apple Developer portal.
   - Command Line Tools configured: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
   - License accepted: `sudo xcodebuild -license accept`
3. **iPad:** Running iPadOS 17.0+ (iPad Pro, iPad Air, iPad mini, or standard iPad) with **Developer Mode** enabled (*Settings → Privacy & Security → Developer Mode*).
4. **Apple ID:** A free personal Apple ID works for sideloading onto your personal device (no paid $99/year developer membership required).
5. **Legitimate Copy of Constructor (1997):**
   - Available on [GOG.com](https://www.gog.com/game/constructor).
   - Download the Mac installer (`constructor_en_2.0.0.14.pkg`) or original MS-DOS game files.

---

## 🚀 Quick Start (Automated Setup)

Connect your iPad to your Mac via USB and run this single command in **Terminal**:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/MargeLenders/Constructor-ipad/main/install.sh)"
```

Or clone the repository and run the setup assistant locally:

```bash
git clone https://github.com/MargeLenders/Constructor-ipad.git
cd Constructor-ipad

./install.sh
```

### What `install.sh` does automatically:
1. **Repository Setup:** Clones or updates the `Constructor-ipad` repository into `~/Developer/Constructor-ipad`.
2. **Environment Verification:** Validates `xcode-select`, iOS SDKs (`iphoneos`), and required developer command-line tools.
3. **Game Asset Acquisition:** Detects your downloaded GOG installer (`.pkg`) in `~/Downloads` (or prompts you to drag and drop it into Terminal).
4. **Deterministic Payload Extraction:** Extracts the ISO CD image, sound files, MS-DOS hard drive structure, creates `AUTOBOOT.DBP`, and packages `Constructor.zip`.
5. **Core Compilation:** Compiles the optimized ARM64 DOSBox-Pure core (`dosbox_pure_libretro_ios.dylib`) in parallel.
6. **Code Signing Assistant:** Auto-detects your personal Apple Developer ID or Personal Team in Keychain for automatic signing.
7. **Direct Deployment:** Installs and launches Constructor directly on your connected iPad via `xcrun devicectl`.

---

## 🛠️ Compiling & Deploying via Xcode (Manual Setup)

If you prefer building and inspecting the project directly in the Xcode GUI, follow these steps:

### Step 1: Clone the Repository

```bash
git clone https://github.com/MargeLenders/Constructor-ipad.git
cd Constructor-ipad
```

---

### Step 2: Compile the DOSBox-Pure Core for iPadOS

Run the automated build script to compile the emulation core dynamic library for `arm64`:

```bash
./scripts/build_core.sh ios
```

*This compiles the core with iOS hardware optimizations and places `dosbox_pure_libretro_ios.dylib` directly into `ConstructorIOS/`.*

---

### Step 3: Prepare the Game Payload

Download your GOG installer (`constructor_en_2.0.0.14.pkg`) and run the payload extractor script:

```bash
./scripts/prepare_payload.sh ~/Downloads/constructor_en_2.0.0.14.pkg
```

*This unpacks the installer, extracts the CD ISO and DOS game directories, adds `AUTOBOOT.DBP`, and generates `ConstructorIOS/Constructor.zip`.*

---

### Step 4: Open the Project in Xcode

Double-click `Constructor.xcodeproj` or execute:

```bash
open Constructor.xcodeproj
```

---

### Step 5: Configure Personal Code Signing (Signing & Capabilities)

1. In Xcode's left-hand Project Navigator, select the blue root project icon **Constructor**.
2. Select the **Signing & Capabilities** tab in the center pane.
3. Ensure **Automatically manage signing** is checked.
4. Under the **Team** dropdown, select your name (*Personal Team*). If this is your first time, choose *Add Account...* and sign in with your Apple ID.
5. In **Bundle Identifier**, you can keep `com.margelenders.constructor` or replace it with your own unique identifier (e.g. `com.yourname.constructor`).

```
┌────────────────────────────────────────────────────────────────────────┐
│ Signing & Capabilities                                                │
├────────────────────────────────────────────────────────────────────────┤
│ [✓] Automatically manage signing                                      │
│                                                                        │
│ Team:              [ Your Name (Personal Team)               ▼ ]      │
│ Bundle Identifier: [ com.yourname.constructor                        ] │
└────────────────────────────────────────────────────────────────────────┘
```

---

### Step 6: Enable Developer Mode on Your iPad

Apple requires Developer Mode to be enabled on iPadOS 16/17+ before launching sideloaded apps:

1. On your iPad, open **Settings** $\rightarrow$ **Privacy & Security**.
2. Scroll to the bottom and tap **Developer Mode**.
3. Toggle the switch to **On** and tap **Restart**.
4. After your iPad reboots, unlock the screen and tap **Turn On** in the prompt, then enter your device passcode.

---

### Step 7: Connect Your iPad & Run the App

1. Connect your iPad to your Mac using a USB cable.
2. If prompted on the iPad to **Trust This Computer**, tap **Trust** and enter your passcode.
3. In the top toolbar of Xcode, click the run destination selector (next to the Play button) and **choose your connected iPad**.
4. Click the **Play (Run)** button or press `Cmd + R`.

*Xcode will compile the Swift source files, link Metal and the emulation core, embed `Constructor.zip`, and install the app on your iPad.*

---

### Step 8: Trust the Developer Certificate (First Time Only)

If you see an *"Untrusted Developer"* alert when tapping the Constructor icon on your iPad:

1. On your iPad, navigate to:
   **Settings → General → VPN & Device Management**
2. Under **Developer App**, tap your Apple ID email.
3. Tap **Trust "[Your Apple ID]"** and confirm.
4. Return to the Home Screen and launch **Constructor**!

---

## 🎮 iPad Touch Controls & Gestures

The container provides a responsive, direct-manipulation interface designed for touchscreens:

| Gesture / Input | Game Action | Description |
| :--- | :--- | :--- |
| **1-Finger Tap** | **Left Click** | Select workers, place buildings, interact with UI buttons. |
| **2-Finger Tap** | **Right Click** | Cancel actions, deselect units, open context menus. Confirmed with **tactile haptic feedback**. |
| **Long Press** | **Right Click** | Alternative right-click gesture for comfortable one-handed play. |
| **2-Finger Pan / Drag** | **Map Scrolling** | Pans the camera smoothly in any direction with **60 FPS physics-based inertia**. |
| **Apple Pencil (Tip)** | **Precise Cursor & Left Click** | Pixel-perfect precision for laying fences, selecting plots, and managing tenants. |
| **Apple Pencil (Double-Tap / Squeeze)** | **Right Click** | Hardware gesture on supported Apple Pencil models triggers secondary action. |
| **Magic Keyboard** | **Keyboard Shortcuts** | Full support for `F1`–`F12`, `Spacebar`, `Escape`, and arrow keys for map navigation. |
| **Bluetooth Mouse / Trackpad** | **Desktop Cursor** | Native iPadOS pointer behaves exactly like a traditional computer mouse. |

---

## 🏛️ System Architecture

```
┌────────────────────────────────────────────────────────┐
│               Host Layer (Swift & UIKit)               │
│   • UIKit / SwiftUI lifecycle                          │
│   • MetalKit rendering pipeline & MSL Shaders          │
│   • Multitouch gesture handling, Pencil & inertia      │
│   • CoreAudio sound engine (AVAudioEngine)             │
└──────────────────────────┬─────────────────────────────┘
                           │ C Bridge (@convention(c))
                           ▼
┌────────────────────────────────────────────────────────┐
│                C-API Bridge (libretro.h)               │
│   • Raw XRGB8888 video framebuffer delivery            │
│   • Interleaved 44.1 kHz 16-bit PCM stereo audio       │
│   • Normalized absolute touch pointer mapping          │
└──────────────────────────┬─────────────────────────────┘
                           │ Dynamic linking (dlopen / dlsym)
                           ▼
┌────────────────────────────────────────────────────────┐
│          Emulation Core (dosbox-pure ARM64)            │
│   • x86 virtual machine compiled for Apple Silicon     │
│   • In-memory mount of Constructor.zip payload         │
│   • Sound Blaster 16 and SVGA (S3 Trio64) emulation    │
└────────────────────────────────────────────────────────┘
```

---

## 🛠️ Advanced: Command Line Build & Install (CLI)

If you prefer building and installing without opening the Xcode GUI, use the provided helper scripts:

```bash
# 1. Compile the DOSBox-Pure core
./scripts/build_core.sh ios

# 2. Extract and prepare the game payload
./scripts/prepare_payload.sh ~/Downloads/constructor_en_2.0.0.14.pkg

# 3. Build the iPadOS application via CLI
./scripts/build_ipados.sh

# 4. Install and launch directly on the connected iPad
./scripts/install_to_ipad.sh
```

---

## 📂 Repository Structure

```
.
├── Constructor.xcodeproj      # Xcode project (targets for iPadOS and macOS)
├── ConstructorIOS/             # Native iPadOS layer (Swift, MetalKit, UIKit)
│   ├── ConstructorApp_iOS.swift # App entry point (@main)
│   ├── GameView_iOS.swift       # SwiftUI presentation view
│   ├── GameMTKView_iOS.swift    # MetalKit MTKView with multitouch & Apple Pencil
│   ├── InputManager_iOS.swift   # 1:1 input subsystem with 60 fps pan inertia & haptics
│   ├── MetalRenderer.swift      # Metal video pipeline with Sharp-Bilinear scaling
│   ├── AudioEngineManager.swift # CoreAudio audio backend (AVAudioEngine)
│   ├── AudioRingBuffer.swift    # Lock-free atomic ring buffer
│   ├── LibretroCore.swift       # Dynamic loader (dlopen/dlsym) for libretro core
│   ├── Shaders.metal            # Metal Shading Language (MSL) vertex & fragment shaders
│   └── Assets.xcassets          # Application icons (Light and Dark mode)
├── ConstructorHost/            # Native macOS layer (AppKit)
├── dosbox-pure-src/            # Optimized DOSBox-Pure emulation core for ARM64
├── scripts/
│   ├── install.sh              # All-in-one zero-touch automated installer
│   ├── build_core.sh           # Builds the emulation core dylib
│   ├── prepare_payload.sh      # Extracts & packages the GOG game payload
│   ├── build_ipados.sh         # Headless CLI builder for iPadOS
│   └── install_to_ipad.sh      # Headless CLI deployer via xcrun devicectl
├── Tests/                      # Unit tests for ring buffer, gestures, and coordinates
├── README.md                   # This English documentation
└── README.es.md                # Spanish documentation
```

---

## 🚦 Known Status & Roadmap

| Feature / Subsystem | Status | Notes |
|---|---|---|
| **Core Emulation (DOSBox-Pure ARM64)** | ✅ Fully Working | Native Apple Silicon execution with fast x86 dynamic recompiler. |
| **SVGA Graphics (MetalKit)** | ✅ Fully Working | 60 FPS hardware-accelerated rendering with Sharp-Bilinear 4:3 integer scaling. |
| **Stereo Audio (Sound Blaster 16)** | ✅ Fully Working | Lock-free atomic ring buffer feeding `AVAudioSourceNode` at 44.1 kHz. |
| **Touch Controls & Inertia** | ✅ Fully Working | 1:1 direct pointer mapping, 2-finger pan with 60 FPS physics momentum & haptics. |
| **Apple Pencil Support** | ✅ Fully Working | Pixel-perfect hover/tap, double-tap and squeeze gesture right-click. |
| **Save Game Management** | ✅ Fully Working | Direct integration with iPadOS Files app (`Documents/SAVEGAME/`). |
| **Hardware Peripherals** | ✅ Fully Working | Magic Keyboard shortcuts (`F1`–`F12`, Space, Esc) and Bluetooth mouse/trackpad. |
| **Network Multiplayer** | ⏳ In Progress | IPX network emulation for local WiFi multiplayer. |

---

## ❓ Frequently Asked Questions (FAQ)

#### Does this require a paid Apple Developer account?
No. Free Apple IDs (Personal Teams) are fully supported. Note that apps signed with free accounts are valid for 7 days, after which re-running the project from Xcode refreshes the profile without losing your save files. Paid Apple Developer accounts provide 365-day certificates.

#### Where are save games stored and how can I export them?
Save files are stored inside the application's `Documents/SAVEGAME/` sandbox. You can access and copy them anytime by opening the **Files** app on your iPad $\rightarrow$ **On My iPad** $\rightarrow$ **Constructor**.

#### Are game assets included in the repository?
No. To respect System 3's intellectual property, proprietary game data (`const.iso`, cinematics, and sound assets) is never tracked in git. The setup assistant extracts the official files from your own legally purchased GOG installer.

#### Xcode displays the error *"Failed to register bundle identifier"*.
The default Bundle Identifier (`com.margelenders.constructor`) may already be registered on Apple's servers. In Xcode, navigate to **Signing & Capabilities** and change the Bundle Identifier to your own (e.g. `com.yourname.constructor`).

#### The game displays a black screen or fails to launch.
Ensure you ran `./scripts/prepare_payload.sh` and verify that `ConstructorIOS/Constructor.zip` exists and is roughly 400–425 MB in size.

---

## ☕ Support the Project

If you appreciate the effort put into bringing Constructor (1997) natively to iPadOS and enjoy playing it on Apple Silicon, consider buying me a coffee to support future updates and maintenance!

<p align="center">
  <a href="https://www.buymeacoffee.com/margelenders" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="50" width="210">
  </a>
</p>

---

## ⚖️ Legal Disclaimer & Licenses

* **Constructor**: © 1997 System 3 Software Ltd. All rights reserved. Neither this repository nor its authors distribute copyrighted game assets, ROMs, graphics, proprietary executables, or game audio.
* **DOSBox-Pure**: Created by Bernardo Schelling under the **GNU General Public License v2 (GPLv2)**. See `dosbox-pure-src/LICENSE`.
* **Native Swift & Metal Wrapper**: Released under the open-source **MIT License**. See [LICENSE](LICENSE) for details.
