# Termux Desktop — Lenovo IdeaPad Pro 12.7 (Dimensity 8300)

<p align="center">
  <img src="assets/transparent-image.png" alt="Lenovo IdeaPad Pro 12.7 with keyboard" width="380">
</p>

> Transparent product render (background removed). To swap it, replace
> `assets/lenovo-pad-pro-12.7-keyboard.png`.

A modular shell wizard that installs a **native** Linux desktop in Termux with
**Mali hardware acceleration** (Zink → Vulkan), and a generic launcher that
starts any installed desktop (XFCE4, i3, Openbox, Fluxbox).

- **SoC**: MediaTek Dimensity 8300 — GPU **Mali-G615 MC6** (Vulkan-capable)
- **HWA path**: `mesa-zink` + `vulkan-wrapper-android` (auto, no manual setup)
- **Display server**: Termux:X11 (native, not VNC)
- **Audio**: PulseAudio over TCP + SLES microphone
- Upstream HWA stack: [`avelith07/Termux-Desktop`](https://github.com/avelith07/Termux-Desktop) (MIT). That project is marked *unmaintained* but the build artifacts still work for Mali+Vulkan.

---

## Target Hardware (2025)

This script is **purpose-built and tested for the Lenovo IdeaPad Pro 12.7 (2025)**
tablet. Every choice below follows from the hardware — most importantly the GPU,
which decides the whole acceleration path.

| Component | Spec | Why it matters for this script |
|-----------|------|--------------------------------|
| **Device** | Lenovo IdeaPad Pro 12.7 (2025) | 12.7" tablet with keyboard — full DEs (XFCE4/LXQt) are practical, tiling WMs work well with the keyboard. |
| **SoC** | MediaTek Dimensity 8300 (MT6897) | ARMv9-A, octa-core. Powerful enough for any DE here without CPU rasterizer fallback. |
| **CPU** | 1× Cortex-A715 @ 3.35 GHz · 3× Cortex-A715 @ 3.20 GHz · 4× Cortex-A510 @ 2.20 GHz | 8 cores → comfortable multitasking under a full desktop. |
| **Process** | TSMC N4P (4 nm) | Cool/efficient — the desktop can run sustained without throttling. |
| **GPU** | **Mali-G615 MC6 @ 1400 MHz** (Valhall, ~2150 GFLOPS FP32) | The key fact: Mali + **Vulkan 1.3** support → the Zink (GL→Vulkan) + `vulkan-wrapper-android` path works, so HWA is automatic. No manual GPU setup needed. |
| **RAM** | LPDDR5X (8 / 12 GB) | Plenty for XFCE4 + a browser + IDE simultaneously. |
| **Storage** | UFS 3.1 (128 / 256 / 512 GB) | Fast I/O keeps `pkg install` and app launches snappy. |
| **Display** | 12.7" high-res, 144 Hz | If the UI looks too small/big, adjust Termux:X11 *Preferences* → scaled mode (see Troubleshooting). |

**What this means in practice:**

- The installer selects the **Mali + Vulkan** HWA branch automatically (no GPU menu
  to answer) — `mesa-zink` + `vulkan-wrapper-android` are installed for you.
- The launcher (`desktop.sh`) hard-codes the Mali/Zink/Vulkan environment variables
  that are correct for the Mali-G615. For a *different* GPU you would have to edit
  that env block — but for this tablet it is exactly right out of the box.
- On other hardware (Adreno, PowerVR, Mali-without-Vulkan) this script is **not**
  correct without changes — see the upstream HWA setup guide instead.

> Specs sourced from MediaTek's official Dimensity 8300 page and Wikipedia.

---

## 1. Prerequisites (do these on the tablet first)

> ⚠️ **Never** install Termux from Google Play — it is outdated and broken. Use GitHub only.

Install **all three** APKs from GitHub (turn off Play Protect temporarily if install fails):

| App | Source |
|-----|--------|
| Termux | https://github.com/termux/termux-app/releases |
| Termux:X11 | https://github.com/termux/termux-x11/actions/workflows/debug_build.yml (latest green build → scroll to Artifacts → `app-arm64-v8a-debug.apk`) |
| Termux:API | https://github.com/termux/termux-api/releases |

**Android tuning (stops Termux:X11 from being killed):**

- **Android 11 & below**: open Termux once, run `termux-wake-lock`, grant "Background activity" when prompted.
- **Android 12 / 13**: disable Phantom Processes — see https://github.com/EDLLT/TermuxDisablePhantomProcess
- **Android 14+**: Settings → Developer options → enable *Disable Child Process Killer*.
- Still being killed? Apply https://dontkillmyapp.com/ to **both** Termux and Termux:X11.

**Specs**: Android 9+, ~3 GB free RAM, ~5 GB free storage, ~1 GB of data.

---

## 2. Get the scripts

Open Termux and run:

```bash
pkg update -y && pkg install -y git
git clone https://github.com/<your-user>/termux-desktop-installer.git
cd termux-desktop-installer
```

*(No git? Use wget for both files:)*
```bash
pkg install -y wget
wget -O install.sh  <raw-url>/install.sh
wget -O desktop.sh  <raw-url>/desktop.sh
```

---

## 3. Run the installer

```bash
chmod +x install.sh
./install.sh
```

The wizard will:

1. Optionally pick the fastest package mirror.
2. Update the system and install base packages + repos (`x11-repo`, `tur-repo`, `termux-x11-nightly`, …).
3. Install the **Mali HWA stack** (mesa-zink debs + Vulkan wrapper + Zink libs + `glmark2`/`vkmark`).
4. Ask which **desktop(s)** to install — XFCE4, i3, Openbox, Fluxbox (pick one, several, or all).
5. Ask which **apps** to install — Firefox, Chromium, VLC, MPV, VS Code, Geany (skippable).
6. Optionally install a **Debian PRoot** container for broader package compatibility.
7. Drop helper scripts + the `desktop` launcher into `~/bin` and add it to `PATH`.

Each phase shows a spinner and a progress bar. Failures are reported but do not abort the whole run.

### Useful flags

```bash
./install.sh --selftest   # validate the DE/app registries, then exit
./install.sh --list       # list available desktops
./install.sh --help       # usage
```

---

## 4. Start the desktop

After the install completes, **restart Termux** (or `source ~/.bashrc`), then:

```bash
desktop              # if only one is installed it launches; otherwise shows a menu
desktop xfce4        # launch directly
desktop i3           # launch i3
desktop openbox      # launch Openbox
desktop fluxbox      # launch Fluxbox
```

The launcher (`~/bin/desktop`) sets the Mali/Zink/Vulkan environment, starts
PulseAudio + the SLES mic source, launches `termux-x11`, then runs the chosen
session via `dbus-launch --exit-with-session`. **Switch to the Termux:X11 app**
to see the desktop.

Other handy commands (from the upstream helper scripts):

```bash
desktop-help          # cheat-sheet of all commands
apphwa zink firefox   # run an app with the HWA driver forced on
native_cleaner        # clean caches
```

### Verify hardware acceleration

```bash
glmark2               # GL benchmark via Zink -> should be smooth, not 1 fps
vkmark                # Vulkan benchmark
```

If `glmark2` crawls, HWA isn't engaged — check that `desktop` (not the old
`termux-xfce4` script) was used to start the session.

---

## 5. Adding a new desktop or app (extensibility)

Everything is driven by registries at the top of `install.sh`:

```bash
# Add a desktop: append one entry to EACH of these arrays
DE_IDS=(    ... "sway"                 )
DE_NAMES=(  ... "Sway - Wayland tiler" )
DE_PKGS=(   ... "sway swaylock"        )
DE_LAUNCH=( ... "sway"                 )

# Add an app: append one entry to each of these arrays
APP_IDS=(   ... "gimp"        )
APP_NAMES=( ... "GIMP"        )
APP_PKGS=(  ... "gimp"        )
```

Then run `./install.sh --selftest` to confirm the arrays line up, and re-run
`./install.sh` (the package step is idempotent — already-installed packages are
skipped). The launcher needs no changes; it reads
`~/.config/termux-desktop/desktops.conf`, which `install.sh` rewrites from the
registry for every desktop you select.

> The launcher's Mali HWA env block is hardware-specific (correct for the
> Dimensity 8300 / Mali-G615). For a different GPU, edit that block in
> `desktop.sh`.

---

## 6. Troubleshooting

| Problem | Fix |
|---------|-----|
| Termux:X11 crashes / freezes / "signal" | See the Android tuning steps in §1; then force-stop **both** Termux and Termux:X11 and retry. |
| Resolution too big/small | Press the Android **back** key, or leave & re-enter Termux:X11. For UI scale: open Termux:X11 *Preferences* (only when no session is running) → scaled mode. |
| Cursor too fast/slow | Termux:X11 Preferences → enable *Capture external pointer devices* and adjust the speed factor. |
| No audio | Re-run `desktop` (it restarts PulseAudio). Grant Termux:API the microphone permission (`termux-microphone-record -d 4` once). |
| `glmark2` is ~1 fps (no HWA) | Start the session with `desktop`, **not** the old `termux-xfce4`. Confirm `VK_ICD_FILENAMES` points to `wrapper_icd.aarch64.json`. |
| `apt --fix-broken` loops | Run `pkg update && pkg upgrade -y`, then re-run `./install.sh`. |
| A `pkg install <x>` fails | The package name may have changed; check `pkg search <x>`, fix the registry, re-run. |
| Black screen after `desktop` (X starts, no DE) | The DE session crashed. Run the launch command manually to see the error: `export DISPLAY=:0; dbus-launch --exit-with-session xfce4-session` (swap for `i3`/`openbox`/`fluxbox`). Often a missing package or a bad `~/.xprofile`. |
| Keyboard / mouse not working in desktop | Termux:X11 needs input focus. Tap inside the Termux:X11 window once. For hardware keyboards/mice, enable *Capture external pointer devices* in Termux:X11 Preferences and re-plug the device. |
| `termux-wake-lock` keeps prompting / won't stick | Grant Termux the *Background activity* + *Ignore battery optimizations* permissions (App info → Battery). On MIUI/realme skins also disable *Auto-start* management for Termux. |
| `desktop` says "No desktop installed" but you installed one | `~/.config/termux-desktop/desktops.conf` is missing or empty. Re-run `./install.sh` (the desktop step rewrites it), or add a line manually: `xfce4\|XFCE4\|xfce4-session`. |
| `dpkg` / `apt` errors about held/broken packages after HWA debs | The mesa-zink debs can conflict with an existing `mesa`. Fix with `apt --fix-broken install -y` then `pkg upgrade -y`; if it loops, `pkg remove mesa` first, then re-run the HWA step. |
| Out of space / install dies halfway | The full HWA + XFCE4 + apps stack needs ~5 GB. Check with `df -h ~`. Clear `pkg clean` and `~/Temp`, or skip the IDE/apps in the wizard and add them later. |
| Wrong desktop starts / two DEs conflict | Only the desktops you selected are registered. Run `desktop` (no arg) to pick from a menu, or `cat ~/.config/termux-desktop/desktops.conf` to see what is registered. Re-running the installer overwrites this file. |
| Fonts look bad / missing glyphs (boxes/tofu) | Install fonts: `pkg install fontconfig fonts-dejavu fonts-noto-cjk`. Then `fc-cache -f`. Needed for CJK/emoji and a clean XFCE4 look. |
| Wi-Fi drops / download stalls mid-install | Termux can be killed mid-download. Run `termux-wake-lock` first, stay on Wi-Fi, and re-run `./install.sh` (steps are idempotent). For slow mirrors, answer **yes** to the mirror-optimization prompt. |

**To start completely fresh**: Termux app info → *Clear data* → redo from §1.

---

## 7. Files

| File | Purpose |
|------|---------|
| `install.sh` | The wizard. All config/registries live at its top. |
| `desktop.sh` | Copied to `~/bin/desktop`. Generic Mali launcher. |
| `README.md` | This file. |

## 8. What was corrected vs. a common draft

- `mesa-zink` / `mesa-zink-dev` are **not** Termux packages — they are `.deb`
  artifacts downloaded from the upstream releases (`v23.0.4-5`). `apt install
  mesa-zink` alone fails; this script downloads the debs first.
- The Vulkan wrapper URL (`v25.0.0-2`) is a real upstream release.
- `xterm` / `rxvt-unicode` are **not** in Termux, so standalone WMs (i3,
  Openbox, Fluxbox) ship with `xfce4-terminal` as the terminal.
- The launcher is generalized (any installed DE) instead of an XFCE4-only
  script, and reads an install-written config so adding a DE needs no launcher
  edit.
