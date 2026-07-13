# Termux Desktop — Lenovo IdeaPad Pro 12.7 (Mediatek Dimensity 8300)

<p align="center">
  <img src="assets/transparent-image.png" alt="Lenovo IdeaPad Pro 12.7 with keyboard" width="380">
</p>

A modular shell wizard that installs a **native** Linux desktop in Termux with
**Mali hardware acceleration** (Zink → Vulkan), and a generic launcher that
starts any installed desktop (XFCE4, i3, Openbox, Fluxbox).

Based on [`avelith07/Termux-Desktop`](https://github.com/avelith07/Termux-Desktop) (MIT) — unmaintained upstream whose HWA build artifacts work for Mali+Vulkan and are vendored in `vendor/`.

---

## Target Hardware (2025)

Purpose-built for the **Lenovo IdeaPad Pro 12.7** tablet.

| Component | Spec |
|-----------|------|
| **SoC** | MediaTek Dimensity 8300 (MT6897) — TSMC N4P |
| **CPU** | 1× Cortex-A715 @ 3.35 GHz · 3× A715 @ 3.20 GHz · 4× A510 @ 2.20 GHz |
| **GPU** | Mali-G615 MC6 @ 1400 MHz (Valhall, Vulkan 1.3, ~2150 GFLOPS) |
| **RAM** | LPDDR5X 8 / 12 GB |
| **Storage** | UFS 3.1 128 / 256 / 512 GB |
| **Display** | 12.7" 144 Hz |

The installer selects the Mali+Vulkan HWA path automatically. The launcher
hard-codes the correct env vars for Mali-G615 — for other GPUs edit `desktop.sh`.

[sources](https://www.mediatek.com/products/dimensity-8300)

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

- **Android 9–11**: no phantom-process killer exists — just run `termux-wake-lock` once and grant "Background activity" when prompted.
- **Android 12 / 13**: disable Phantom Processes — see https://github.com/EDLLT/TermuxDisablePhantomProcess
- **Android 14+ (incl. 15 & 16)**: Settings → Developer options → enable *Disable child process restrictions* (then reboot). This is the cleanest path on current Android; the adb one-liners are less reliable from 15 onward.
- Still being killed? Apply https://dontkillmyapp.com/ to **both** Termux and Termux:X11.

**Specs**: Android 9+, ~3 GB free RAM, ~5 GB free storage, ~1 GB of data.
**Tested on**: Android 16 (Lenovo IdeaPad Pro 12.7, Dimensity 8300).

---

## 2. Get the scripts

This repo is **self-contained** — the helper scripts and a known-working HWA
`.deb` set are vendored in `vendor/`. By default the installer pulls the latest
Mesa/Zink/Vulkan stack from the Termux repos (`pkg`); pass `--vendored` to use
the offline vendored set instead. Clone the whole repo (or download a release ZIP):

```bash
pkg update -y && pkg install -y git
git clone https://github.com/ppsirius/lenovo-dimensity8300-termux-desktop.git
cd lenovo-dimensity8300-termux-desktop
```

> Clone or download the ZIP — don't grab individual files, or `vendor/` (the HWA
> debs) will be missing and `./install.sh --selftest` will report them absent.

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
6. Optionally install a **PRoot container** (Debian, Arch, Manjaro, Fedora, or Alpine) for broader package compatibility.
7. Drop helper scripts + the `desktop` launcher into `~/bin` and add it to `PATH`.

Each phase shows a spinner and a progress bar. Failures are reported but do not abort the whole run.

### Non-interactive / automated install

Skip all prompts and install with defaults (XFCE4, no apps, no PRoot):

```bash
./install.sh -y
```

Include a PRoot container in non-interactive mode:

```bash
./install.sh -y --proot-distro debian     # or arch, manjaro, fedora, alpine
```

Combine with step-skips to run only what you need (e.g. re-install just the desktop
onto an already-set-up system):

```bash
./install.sh -y --no-deps --no-bin   # skip base packages & helper scripts, just HWA + desktop
```

### Useful flags

```bash
./install.sh --selftest           # validate registries AND that vendor/ files are present
./install.sh --list               # list available desktops AND proot distros
./install.sh --sync               # refresh ./vendor from upstream (uses the tag vars), then exit
./install.sh -y|--yes             # non-interactive (defaults: XFCE4, no apps/proot/mirror)
./install.sh --proot-distro D     # install a proot container (D = debian|arch|manjaro|fedora|alpine)
./install.sh --vendored           # use pinned ./vendor HWA debs (fallback) instead of latest from repos
./install.sh --no-deps            # skip the base packages/repos step
./install.sh --no-bin             # skip the helper-scripts & launcher step
./install.sh --verbose            # show live output (default: full log shown on failure)
./install.sh --help               # usage
```

If a phase fails, the installer dumps the **full log** (e.g.
`/tmp/termux-install-XXXXXX.log`). Re-run with `--verbose` to see
live output as it happens.

### HWA packages: latest from repos vs. pinned vendored

By default the installer pulls the **latest coherent Mesa/Zink/Vulkan stack
from the Termux repos** (`pkg`) in one transaction — the resolver picks
mutually-compatible versions, so you get newer Zink/Mesa without manually
matching version numbers across libraries. `mesa-demos` is included for
`glxinfo` / `glxgears`.

If a repo update ever regresses, pass **`--vendored`** to fall back to the
**pinned, known-working** `.deb` set shipped in `vendor/debs/` (offline,
reproducible).

To refresh those vendored debs from upstream (only relevant with `--vendored`):

1. Edit the tag variables at the top of `install.sh`:
   ```bash
   MESA_ZINK_TAG="v23.0.4-5"        # bump to a newer mesa-zink release tag
   VULKAN_WRAPPER_TAG="v25.0.0-2"   # bump to a newer vulkan-wrapper release tag
   ```
2. Either set `USE_LATEST=1` (refreshes at install time) **or** run `./install.sh --sync`
   once to update `vendor/`, then run `./install.sh --vendored` normally.

Asset URLs are derived from the tags automatically (e.g. `v23.0.4-5` →
`mesa-zink_23.0.4-5_aarch64.deb`), so bumping the tag is all you need. Check
[upstream releases](https://github.com/avelith07/Termux-Desktop/releases) for new tags.

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
PulseAudio (AAudio output sink, SLES mic), launches `termux-x11`, then runs
the chosen session via `dbus-launch --exit-with-session`. **Switch to the
Termux:X11 app** to see the desktop.

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

## 6. PRoot distros

The installer supports five PRoot containers. The interactive wizard shows
all options with warnings for problematic distros.

| Alias | Image | Package manager | Status | Notes |
|-------|-------|-----------------|--------|-------|
| `debian` | `debian:12` | apt | **Recommended** | Most stable under proot; huge aarch64 repo; no symlink/cpio issues. |
| `arch` | `danhunsaker/archlinuxarm:latest` | pacman | Good | Rolling release; AUR access; `base-devel` included. |
| `manjaro` | `manjarolinux/base:latest` | pacman | ⚠ Unstable | Keyring trust issues ([#424](https://github.com/termux/proot-distro/issues/424)); stale images ([#480](https://github.com/termux/proot-distro/issues/480)). Consider Arch instead. |
| `fedora` | `fedora:44` | dnf | ⚠ Unstable | dnf segfaults ([#545](https://github.com/termux/proot-distro/issues/545)); sudo broken after updates ([#533](https://github.com/termux/proot-distro/issues/533)); filesystem package upgrade fails ([#525](https://github.com/termux/proot-distro/issues/525)). |
| `alpine` | `alpine:3.23` | apk | ⚠ Caveats | Tiny (10 MB rootfs, 50 MB installed). Uses musl libc — some pre-built binaries (Node.js, VS Code, JetBrains) will not run. No systemd. |

**CLI usage:**

```bash
./install.sh -y --proot-distro arch      # non-interactive: install Arch container
./install.sh -y --proot-distro fedora    # non-interactive: install Fedora container
```

**Interactive wizard:** When answering "yes" to the PRoot prompt, you get a
numbered list (1-5) to pick the distro. Warnings are shown inline.

### Manjaro under proot — known issues

- **Keyring trust**: The Manjaro ARM rootfs ships with a stale `manjaro-arm-keyring`.
  After first login, run `pacman-key --init && pacman-key --populate manjaro-arm`
  and then `pacman -Syu` to fix.
- **Stale images**: Docker Hub `manjarolinux/base` may lag behind current Arch ARM
  packages. Pin to a specific tag (e.g. `manjarolinux/base:20260322`) to avoid
  surprises.
- **No advantage over Arch**: In a proot context, Manjaro ARM offers no benefit over
  Arch Linux ARM (`danhunsaker/archlinuxarm`). Arch has more reliable keyring
  maintenance and the same package ecosystem. **Use Arch instead.**

### Fedora under proot — known issues

- **dnf segfaults**: proot's ptrace-based syscall interception breaks RPM/dnf
  operations. Upgrade proot to the latest version (`pkg upgrade proot`) and try
  again. If segfaults persist, this is an upstream proot bug.
- **sudo broken**: Fedora 42+ `sudo` fails with "no new privileges" flag — proot
  sets `PR_SET_NO_NEW_PRIVS` which conflicts. Workaround: run as root inside
  the container (proot-distro logs in as root by default).
- **filesystem package**: The `filesystem` package upgrade fails with "symlink
  failed — Directory not empty" due to `/bin → /usr/bin` and proot's symlink
  handling. Use a pinned Docker Hub tag with a recent build (e.g. `fedora:44`).

### Alpine under proot — known issues

- **musl libc**: Alpine uses musl instead of glibc. Pre-built binaries from most
  Linux repos (Node.js, VS Code, JetBrains, Python wheels) will not work.
  You'll need to build from source or use Alpine's own packages.
- **No systemd**: Same as all proot distros — systemd requires PID 1 and cgroups,
  neither of which work under proot.

---

## 7. Troubleshooting

| Problem | Fix |
|---------|-----|
| Phase failed / install stopped | The installer dumps the full failing phase log (`/tmp/termux-install-*.log`). Re-run with `--verbose` for live output. |
| Termux:X11 crashes / freezes / "signal" | See the Android tuning steps in §1; then force-stop **both** Termux and Termux:X11 and retry. |
| Resolution too big/small | Press the Android **back** key, or leave & re-enter Termux:X11. For UI scale: open Termux:X11 *Preferences* (only when no session is running) → scaled mode. |
| Cursor too fast/slow | Termux:X11 Preferences → enable *Capture external pointer devices* and adjust the speed factor. |
| No audio / mic | See the **Audio / no sound** subsection below. |
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

### Audio / no sound

The launcher starts PulseAudio and tries `module-aaudio-sink` first (Android's
modern audio API, reliable from Android 12+), falling back to
`module-sles-sink` (OpenSL ES — works on older Android, but deprecated from
Android 14+) if that fails. It then unmutes at 100%. If you hear nothing, work
through these in order:

**1. Diagnose** (run in Termux while the desktop is up):

```bash
pulseaudio --check && echo "PA running" || echo "PA NOT running"
pactl list short sinks            # at least one sink needed
pactl list short sink-inputs      # is an app actually playing?
```

- No sink → the AAudio/SLES backends both failed (go to step 3).
- `PA NOT running` → `pulseaudio --kill; pulseaudio --start`, then re-launch `desktop`.

**2. Volume & permissions (the most common cause):**

```bash
pactl set-sink-mute   @DEFAULT_SINK@ false
pactl set-sink-volume @DEFAULT_SINK@ 100%
```

Turn up **Android media volume**. Also grant mic permission once:
`termux-microphone-record -d 4`.

**3. PipeWire fallback** (if PulseAudio sinks all fail):

```bash
pkg install pipewire pipewire-pulse pulseaudio-utils
pulseaudio --kill
pipewire        &
pipewire-pulse  &
pactl list short sinks
```

`pipewire-pulse` provides a PulseAudio-compatible socket — desktop apps keep
working with `PULSE_SERVER=127.0.0.1`. To make permanent, edit `desktop.sh`
and replace the PulseAudio block with the two PipeWire daemons.

**Quick test tone:** `speaker-test -c2 -l1` or
`paplay /system/media/audio/ui/camera_click.ogg`.

---

## 7b. General Termux Performance Tips

These are commonly recommended practices from the Termux community.

### Use F-Droid Termux, not Play Store
The Play Store build is deprecated and breaks on current Android versions.
Always install from [F-Droid](https://f-droid.org/en/packages/com.termux/) or
[GitHub releases](https://github.com/termux/termux-app/releases).

### Phantom Process Killer (signal 9)
If Termux dies with `[Process completed (signal 9) - press Enter]` mid-session,
Android's phantom process killer is the cause, not a Termux bug. Fix per version:

| Android | Fix |
|---------|-----|
| **15 / 16** | Developer Options → **Disable child process restrictions** → reboot. (The adb `device_config` / `settings` one-liners are increasingly locked down from 15 onward; the GUI toggle is the reliable path.) |
| **14** | Developer Options → **Disable child process restrictions** → reboot |
| **12L / 13** | `adb shell "settings put global settings_enable_monitor_phantom_procs false"` → reboot |
| **12** | `adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"` → reboot |
| **9–11** | Nothing to do — no phantom-process killer exists. Just `termux-wake-lock` + battery optimization. |
| **Rooted** (any) | `su -c "settings put global settings_enable_monitor_phantom_procs false"` → reboot |

> ⚠️ A system update may reset these — reapply if signal 9 returns. Long-running
> AI agent sessions are the workload most likely to trigger it even after the fix.

### Battery Optimization
- Android Settings → Apps → Termux → Battery → **Unrestricted**
- Disable any power-saving mode while running the desktop.

### WakeLock
Pull down notifications → tap Termux entry → **Acquire WakeLock**. Or run:
`termux-wake-lock`. This prevents the CPU from freezing when the screen is off.

### Termux:X11 Settings
- **Display scale**: 170–200% for a phone-sized screen (Settings → Display → Scale).
- **Scancode mode**: enable "Prefer scancodes when possible" if WASD keys
  don't register in games.

### Storage Access
Run `termux-setup-storage` once to mount `/sdcard` under `~/storage`.

### Audio Microphone
Android Settings → Apps → Termux → Permissions → **Microphone**. Without this,
`pactl load-module module-sles-source` in `desktop.sh` will fail.

---

## 8. Files

| Path | Purpose |
|------|---------|
| `install.sh` | The wizard. All config, registries and version tags live at its top. |
| `desktop.sh` | Copied to `~/bin/desktop`. Generic Mali launcher (any installed DE). |
| `vendor/bin/` | 7 helper scripts (`apphwa`, `desktop-help`, …) vendored from upstream. |
| `vendor/debs/` | 3 HWA `.deb` packages (mesa-zink, vulkan-wrapper) — pinned fallback used by `--vendored`. |
| `assets/` | The device photo used in this README. |
| `README.md` | This file. |

By default the HWA stack comes from the Termux repos; the vendored set is the
offline fallback (`--vendored`).


