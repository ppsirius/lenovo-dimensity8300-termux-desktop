#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  TERMUX DESKTOP INSTALLER
#  Target : Lenovo IdeaPad Pro 12.7  ·  MediaTek Dimensity 8300 (Mali-G615)
#  GPU    : Mali + Vulkan  ->  Zink + vulkan-wrapper-android (auto HWA)
#  License: MIT (upstream stack: avelith07/Termux-Desktop)
# =============================================================================
#
#  ADD A DESKTOP: append one entry to each DE_* array in the CONFIG block.
#  ADD AN APP    : append one entry to each APP_* array.
#  No other code needs to change.
#
#  Flags:  --selftest       validate registries & vendored files, then exit
#          --list           list available desktops & exit
#          --sync           refresh ./vendor from upstream (uses tag vars) & exit
#          -y, --yes        non-interactive (defaults: XFCE4, no apps/proot/mirror)
#          --proot-distro D also install a proot container (D = debian|arch|manjaro|fedora|alpine)
#          --vendored       use pinned ./vendor HWA debs (DEFAULT; only verified-accelerating path)
#          --repo           install mesa-zink from Termux/tur repos (stale 22.0.5; experimental)
#          --mesa26         install Mesa 26.x from the main repo (newest; experimental) + vendored Mali shim
#          --virgl          install virgl + ANGLE -> Vulkan stack (ar37-rs; for proot containers)
#          --no-deps        skip the base packages/repos step
#          --no-bin         skip the helper-scripts & launcher step
#          --verbose        show live output during install (default: show on failure only)
#          --help           show usage
# =============================================================================
#
#  GPU/HWA source: four paths. DEFAULT is --vendored (pinned ./vendor debs,
#  the only path verified to accelerate on Mali-G615). --repo installs the
#  stale mesa-zink (tur, 22.0.5) — experimental. --mesa26 installs Mesa 26.x
#  from the main repo (newest, includes Zink) + the vendored Mali shim — also
#  experimental. --virgl installs the virgl -> ANGLE -> Vulkan stack from
#  ar37-rs/virgl-angle (designed for proot containers; per-app GPU via `gpu`).
#  USE_LATEST=1 and --sync refresh the vendored debs from
#  avelith07/Termux-Desktop (only relevant with --vendored).

# ============================ CONFIG ==========================================
# Resolve the script's own directory (so vendored files are found wherever it runs)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Package source & versions
# ---------------------------------------------------------------------------
# GPU/HWA source: "vendor" (default) uses the pinned ./vendor debs — the only
# path verified to accelerate on Mali-G615. "repo" installs from the Termux
# repos; note tur-repo's mesa-zink is stale (22.0.5, OLDER than vendored
# 23.0.4-5), so "repo" is experimental and currently a downgrade. The newer
# Mesa 26.x lives in the main-repo `mesa` package (not `mesa-zink`) — that's a
# separate, untested path. See AGENTS.md.
GPU_SOURCE="vendor"

# Refresh the vendored fallback debs from upstream before using them
# (only relevant with --vendored). --sync does the same thing standalone.
USE_LATEST=0

# Default Termux mirror group, pre-selected before the first `apt-get update`
# so Termux doesn't scan every mirror worldwide ("no mirror group selected").
# Target user is in Europe; override e.g. MIRROR_GROUP="asia" elsewhere.
MIRROR_GROUP="europe"

UPSTREAM="avelith07/Termux-Desktop"
UPSTREAM_RAW="https://raw.githubusercontent.com/$UPSTREAM/refs/heads/main"
UPSTREAM_REL="https://github.com/$UPSTREAM/releases/download"

# Release tags. Bump these to pick up newer HWA builds, then set USE_LATEST=1
# (or run: ./install.sh --sync). Asset URLs are derived from these tags.
MESA_ZINK_TAG="v23.0.4-5"
VULKAN_WRAPPER_TAG="v25.0.0-2"

VENDOR_BIN="$SCRIPT_DIR/vendor/bin"
VENDOR_DEBS="$SCRIPT_DIR/vendor/debs"

# derive versioned file names from the tags (v23.0.4-5 -> 23.0.4-5)
MESA_VER="${MESA_ZINK_TAG#v}"
VULKAN_VER="${VULKAN_WRAPPER_TAG#v}"
MESA_ZINK_DEB="$VENDOR_DEBS/mesa-zink_${MESA_VER}_aarch64.deb"
MESA_ZINK_DEV_DEB="$VENDOR_DEBS/mesa-zink-dev_${MESA_VER}_all.deb"
VULKAN_WRAPPER_DEB="$VENDOR_DEBS/vulkan-wrapper-android_${VULKAN_VER}_aarch64.deb"

# helper scripts vendored from upstream bin/
BIN_SCRIPTS=(apphwa native_cleaner proot_program termux-fastest-repo desktop-help termux-multi-instance extract)

HWA_LIBS="virglrenderer-mesa-zink vulkan-loader-generic angle-android virglrenderer-android libandroid-shmem libc++ libdrm libx11 libxcb libxshmfence libwayland zlib zstd"

# mesa26 path: same as HWA_LIBS but WITHOUT the virgl renderers
# (virglrenderer-mesa-zink depends on mesa-zink, which mesa26 replaces with the
# main `mesa` package; virgl is the GL-over-virtio path, unused by Zink anyway).
HWA_LIBS_MESA26="vulkan-loader-generic angle-android libandroid-shmem libc++ libdrm libx11 libxcb libxshmfence libwayland zlib zstd"

# virgl path: virglrenderer + ANGLE -> Vulkan (ar37-rs/virgl-angle approach).
# Render chain: app -> virpipe -> virgl_test_server -> ANGLE -> Vulkan -> Mali.
# Designed for proot containers; desktop stays software, GPU is per-app (`gpu`).
VGL_URL="https://github.com/ar37-rs/virgl-angle/raw/refs/heads/main/vgl"
VIRGL_ICD_URL="https://github.com/ar37-rs/virgl-angle/releases/download/latest/mesa-vulkan-icd-wrapper_25.0.0-1_aarch64.deb"
HWA_LIBS_VIRGL="virglrenderer virglrenderer-android angle-android vulkan-loader-generic libandroid-shmem libc++ libdrm libx11 libxcb libxshmfence libwayland zlib zstd"

# --- DESKTOPS REGISTRY (extend here) -----------------------------------------
DE_IDS=(    "xfce4"                              "i3"                              "openbox"                              "fluxbox"                             )
DE_NAMES=(  "XFCE4 - full desktop (recommended)" "i3 - tiling window manager"      "Openbox - lightweight floating WM"    "Fluxbox - lightweight stacking WM"   )
DE_PKGS=(   "xfce4 xfce4-goodies xfce4-whiskermenu-plugin xfce4-battery-plugin xfce4-cpugraph-plugin xfce4-netload-plugin xfce4-docklike-plugin xfce4-pulseaudio-plugin xfce4-screenshooter xfce4-taskmanager mousepad pavucontrol" "i3 i3status dmenu xfce4-terminal" "openbox tint2 obconf xfce4-terminal" "fluxbox xfce4-terminal" )
DE_LAUNCH=( "xfce4-session"                      "i3"                              "openbox-session"                      "fluxbox"                             )

# --- APPS REGISTRY (extend here) ---------------------------------------------
APP_IDS=(   "opencode"  "firefox"   "chromium"  "vlc"   "mpv"   "code-oss"      "geany" )
APP_NAMES=( "OpenCode (AI coding agent)" "Firefox" "Chromium" "VLC"   "MPV"   "VS Code (code-oss)" "Geany" )
APP_PKGS=(  ""          "firefox"   "chromium"  "vlc-qt" "mpv"  "code-oss"      "geany" )

# --- PROOT DISTROS REGISTRY (extend here) ------------------------------------
# PD_ALIAS : proot-distro alias / image name for `proot-distro install`
# PD_NAME  : display name
# PD_PKGS  : packages to install inside the container (space-separated)
# PD_WARN  : known-issue warning (shown in wizard; empty = no warning)
# ponytail: registry not a class hierarchy — arrays, not objects
PROOT_IDS=(    "debian"                              "arch"                                       "manjaro"                               "fedora"                              "alpine"                          )
PROOT_NAMES=(  "Debian 12 (recommended, most stable)" "Arch Linux ARM (rolling, AUR access)"        "Manjaro ARM (Arch-based, friendlier)"    "Fedora 44 (cutting-edge, may break)" "Alpine 3.23 (tiny, 10MB rootfs)"  )
PROOT_IMAGES=( "debian:12"                            "danhunsaker/archlinuxarm:latest"            "manjarolinux/base:latest"              "fedora:44"                           "alpine:3.23"                     )
PROOT_PKGS=(   "sudo nano dbus-x11 pulseaudio build-essential git" "sudo nano dbus-x11 pulseaudio base-devel git" "sudo nano dbus-x11 pulseaudio base-devel git" "sudo nano dbus-x11 pulseaudio gcc git make" "sudo nano dbus-x11 pulseaudio build-base git" )
PROOT_WARN=(   "Audio (Firefox/Chrome) inside proot needs PULSE_SERVER=127.0.0.1 — set it in ~/.bashrc inside the container"                                     ""                                           "Keyring trust issues (#424); stale images (#480). Consider Arch instead." "dnf segfaults (#545); sudo broken (#533); filesystem upgrade fails (#525)." "musl libc; some pre-built binaries fail; no systemd." )
PROOT_PM=(     "apt"                                  "pacman"                                     "pacman"                                 "dnf"                                 "apk"                             )

CONF_DIR="$HOME/.config/termux-desktop"
DESKTOPS_CONF="$CONF_DIR/desktops.conf"
# ============================ /CONFIG =========================================

# --- Force non-interactive apt/dpkg (no config file prompts) -----------------
# Without this, dpkg may block on "What would you like to do about it?" for
# config file conflicts (e.g. openssl), killing the installer on stdin EOF.
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# ----------------------------- colors ----------------------------------------
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'
W='\033[1;37m'; GR='\033[0;90m'; B='\033[1m'; N='\033[0m'

# ----------------------------- spinner ---------------------------------------
VERBOSE=0
STEP_LOG=""

spinner() {
    local pid=$1 msg=$2 log_file=$3 i=0 c=0 ctx=""
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 )); c=$((c+1))
        [ $((c % 50)) -eq 0 ] && [ -n "$log_file" ] && [ -s "$log_file" ] \
            && ctx=$(tail -1 "$log_file" 2>/dev/null | head -c 60)
        printf "\r\033[K ${Y}⏳${N} ${msg} ${C}${spin[$i]}${N}"
        [ -n "$ctx" ] && printf " ${GR}%s${N}" "${ctx//$'\n'/}"
        read -t 0.1 2>/dev/null || true
    done
    wait "$pid"; local rc=$?
    printf "\r%$((${#msg}+30))s\r"
    if [ $rc -eq 0 ]; then
        printf "${G}✓${N} ${msg}          \n"
    else
        printf "${R}✗${N} ${msg} ${R}(failed)${N}  \n"
        if [ -n "$log_file" ] && [ -f "$log_file" ] && [ -s "$log_file" ]; then
            echo -e "${R}── full log of ${msg} ──${N}"
            cat "$log_file"
            echo -e "${R}── end (full: $log_file) ──${N}\n"
        fi
    fi
    return $rc
}

run_step() {
    local msg="$1"; shift
    STEP_LOG=$(mktemp "${TMPDIR:-/tmp}/termux-install-XXXXXX.log")
    if [ "$VERBOSE" = 1 ]; then
        ( "$@" ) 2>&1 | tee "$STEP_LOG" &
    else
        ( "$@" ) >"$STEP_LOG" 2>&1 &
    fi
    spinner $! "$msg" "$STEP_LOG"
}

show_progress() {
    local cur=$1 total=$2 label=$3
    local pct=$((cur*100/total)) filled=$((pct/5)) empty=$((20-filled))
    local bar sp; printf -v bar '%*s' "$filled" ''; bar="${bar// /█}"
    printf -v sp  '%*s' "$empty"  ''; sp="${sp// /░}"
    echo -e "\n${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${C} Phase ${cur}/${total}${N} ${G}${bar}${GR}${sp}${N} ${W}${pct}%${N}  ${GR}${label}${N}"
    echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
}

banner() {
    clear
    echo -e "${C}${B}"
    cat <<'EOF'
  ╔══════════════════════════════════════════════════════════════╗
  ║   TERMUX DESKTOP NATIVE INSTALLER                            ║
  ║   Device : Lenovo IdeaPad Pro 12.7                           ║
  ║   SoC    : MediaTek Dimensity 8300  ·  Mali-G615 MC6         ║
  ║   HWA    : Mali + Vulkan  ->  Zink + vulkan-wrapper-android  ║
  ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${N}"
}

# ----------------------------- multi-select menu -----------------------------
# Reads globals MENU_IDS / MENU_NAMES, fills global SELECTED with chosen ids.
pick_multi() {
    local prompt="$1" c n
    echo -e "${C}${B}${prompt}${N}"
    for i in "${!MENU_IDS[@]}"; do
        printf "  ${C}%d${N}) %s\n" "$((i+1))" "${MENU_NAMES[$i]}"
    done
    echo -e "  ${GR}(space-separated numbers · 'a' = all · 's' = skip)${N}"
    read -rp "$(echo -e "${Y}>>${N} ")" choices
    SELECTED=()
    for c in $choices; do
        case "$c" in
            a) SELECTED=("${MENU_IDS[@]}"); return;;
            s) return;;
        esac
        if [[ "$c" =~ ^[0-9]+$ ]] && (( c>=1 && c<=${#MENU_IDS[@]} )); then
            SELECTED+=("${MENU_IDS[$((c-1))]}")
        fi
    done
}

yesno() {
    local p="$1" d="${2:-n}" r
    read -rp "$(echo -e "${Y}${p} [y/N]${N} ")" r
    r="${r:-$d}"; [[ "$r" =~ ^[Yy] ]]
}

# Pre-select a Termux mirror group so apt never prints "no mirror group
# selected" and speed-tests every mirror worldwide. Called before any step
# (so it also covers --no-deps runs). Respects an existing selection.
setup_mirrors() {
    local mdir="$PREFIX/etc/termux/mirrors" chosen="$PREFIX/etc/termux/chosen_mirrors"
    [ -e "$chosen" ] && return 0
    if [ -d "$mdir/$MIRROR_GROUP" ]; then
        ln -s "$mdir/$MIRROR_GROUP" "$chosen"
    elif [ -f "$mdir/default" ]; then
        ln -s "$mdir/default" "$chosen"
    else
        echo -e "${Y}Could not pre-select a mirror group; run 'termux-change-repo' if apt is slow.${N}"
    fi
}

# ============================ STEP FUNCTIONS =================================
step_system() {
    apt-get update -y
    apt-get upgrade -y $APT_OPTS
    # repair transient missing libs after upgrade (libpcre2.so, etc.)
    apt-get --fix-broken install -y $APT_OPTS
    apt-get install -y $APT_OPTS x11-repo tur-repo
    apt-get update -y
    apt-get install -y $APT_OPTS termux-x11-nightly termux-api pulseaudio proot-distro curl
    # PulseAudio: dopasuj do natywnego 48kHz Androida, bez resamplingu
    cat > "$PREFIX/etc/pulse/daemon.conf" <<-EOF
default-sample-rate = 48000
alternate-sample-rate = 44100
default-sample-format = s16le
resample-method = speex-float-1
default-fragments = 4
default-fragment-size-msec = 25
EOF
    termux-wake-lock
    [ "$DO_MIRROR" = 1 ] && {
        cat > "$PREFIX/etc/apt/sources.list" <<-EOF
deb https://packages.termux.dev/apt/termux-main stable main
deb https://grimler.se/termux stable main
deb https://ftp.fau.de/termux stable main
deb https://termux.netmirror.org stable main
EOF
        apt-get update -y
    }
}

# Latest coherent Mesa/Zink/Vulkan stack straight from the Termux repos.
# NOTE: vulkan-wrapper-android is the upstream custom name and is NOT in the
# repos — detect the standard Termux Vulkan loader instead.
# Newest mesa-zink from repo PAIRED with the vendored Mali ICD shim.
# The repo's generic Vulkan loaders cannot see the proprietary Mali driver, so
# they yield "failed to load driver: zink" -> llvmpipe. The vendored
# vulkan-wrapper-android is the ICD manifest that redirects the loader to Mali;
# it is decoupled from Mesa's version (pure manifest), so repo mesa-zink +
# vendored 25.0.0-2 wrapper is a valid pairing and is what makes this path
# accelerate. step_hwa_vendor (--vendored) remains the untouched fallback.
step_hwa_repo() {
    # mesa-zink + dev: latest from repo (newest fixes/features).
    apt-mark unhold mesa-zink mesa-zink-dev 2>/dev/null || true
    apt install -y $APT_OPTS mesa-zink mesa-zink-dev
    # vulkan-wrapper-android: vendored Mali ICD shim, held so future upgrades
    # can't swap in a generic loader that loses Mali.
    if [ -f "$VULKAN_WRAPPER_DEB" ]; then
        apt-mark unhold vulkan-wrapper-android 2>/dev/null || true
        dpkg -i "$VULKAN_WRAPPER_DEB"
        apt-mark hold vulkan-wrapper-android 2>/dev/null || true
    else
        echo -e "${Y}WARN: $VULKAN_WRAPPER_DEB missing — Mali ICD shim not installed," >&2
        echo -e "       acceleration will likely fail. Run: ./install.sh --sync${N}" >&2
    fi
    apt-get --fix-broken install -y $APT_OPTS
    # HWA_LIBS includes vulkan-loader-generic (libvulkan.so) + the rest of the
    # rendering deps; all latest from repo.
    apt install -y $APT_OPTS mesa-demos $HWA_LIBS glmark2 vkmark
}

# Known-working fallback: pinned vendored debs (offline, reproducible).
# dpkg -i (not apt install) so the pinned versions win even if step_system's
# upgrade pulled a newer repo mesa-zink — dpkg allows version replacement
# where apt would refuse a downgrade.
step_hwa_vendor() {
    dpkg -i "$MESA_ZINK_DEB" "$MESA_ZINK_DEV_DEB"
    apt-get --fix-broken install -y $APT_OPTS
    apt install -y $APT_OPTS $HWA_LIBS
    dpkg -i "$VULKAN_WRAPPER_DEB"
    apt-get --fix-broken install -y $APT_OPTS
    apt-get install -y $APT_OPTS mesa-demos glmark2 vkmark
}

# Experimental: newest Mesa from the main repo (targets 26.1.4 when available;
# repo may lag — the step logs the installed version). Includes Zink
# (-Dgallium-drivers=…,zink), paired with the vendored Mali ICD shim.
# mesa-zink is obsolete (main mesa ships zink_dri.so).
# This path does NOT touch step_hwa_vendor — the verified fallback stays intact.
step_hwa_mesa26() {
    apt install -y $APT_OPTS mesa
    # Log installed version — helps confirm we got 26.1.x (not stale 26.0.x).
    local _mver
    _mver=$(dpkg -l mesa 2>/dev/null | awk '/^ii/{print $3}') || true
    echo -e "${C}  Mesa installed: ${_mver:-unknown}${N}"
    if [ -n "$_mver" ] && printf '%s\n' "$_mver" | grep -q '^26\.0\.'; then
        echo -e "${Y}  NOTE: repo still has 26.0.x; Zink bugs may persist. --vendored is the safe fallback.${N}"
    fi
    # Vendored Mali ICD shim (decoupled from Mesa version — pure manifest).
    if [ -f "$VULKAN_WRAPPER_DEB" ]; then
        dpkg -i "$VULKAN_WRAPPER_DEB"
        apt-mark hold vulkan-wrapper-android 2>/dev/null || true
    else
        echo -e "${Y}WARN: $VULKAN_WRAPPER_DEB missing — Mali ICD shim not installed," >&2
        echo -e "       acceleration will likely fail. Run: ./install.sh --sync${N}" >&2
    fi
    apt-get --fix-broken install -y $APT_OPTS
    apt install -y $APT_OPTS mesa-demos $HWA_LIBS_MESA26 glmark2 vkmark
    # --- Zink driver diagnostics (catches Zink load failures early) ---
    local _zink="$PREFIX/lib/dri/zink_dri.so"
    local _icd="$PREFIX/share/vulkan/icd.d/vulkan_wrapper_android.json"
    local _diag="/tmp/termux-install-mesa26-diag.log"
    : > "$_diag"
    {
        echo "=== mesa26 Zink diagnostics ==="
        echo "Mesa version: ${_mver:-unknown}"
        # Zink driver presence
        if [ -f "$_zink" ]; then
            echo "zink_dri.so: present ($(stat -c%s "$_zink" 2>/dev/null || echo '?') bytes)"
        else
            echo "zink_dri.so: MISSING at $_zink"
        fi
        # ICD manifest
        if [ -f "$_icd" ]; then
            echo "Mali ICD: present"
            cat "$_icd"
        else
            echo "Mali ICD: MISSING at $_icd"
        fi
        # Quick glxinfo probe (verbose — shows driver selection + errors)
        if command -v glxinfo >/dev/null 2>&1; then
            echo "--- glxinfo (first 30 lines) ---"
            LIBGL_DEBUG=verbose glxinfo 2>&1 | head -30
            echo "--- renderer ---"
            glxinfo 2>/dev/null | grep -i 'opengl renderer' || true
        else
            echo "glxinfo not available"
        fi
        echo "=== end diagnostics ==="
    } >> "$_diag" 2>&1
    echo -e "${C}  Diagnostics: $_diag${N}"
    # Surface the renderer line + any Zink errors to the user
    local _renderer _err
    _renderer=$(grep -i 'opengl renderer' "$_diag" 2>/dev/null | head -1) || true
    _err=$(grep -iE 'error|failed|zink.*not|llvmpipe' "$_diag" 2>/dev/null | head -5) || true
    if [ -n "$_renderer" ]; then
        echo -e "${C}  $_renderer${N}"
    fi
    if [ -n "$_err" ]; then
        echo -e "${Y}  Potential issues (see $_diag for full output):${N}"
        echo "$_err" | sed 's/^/    /'
    fi
}

# virgl -> ANGLE -> Vulkan path (ar37-rs/virgl-angle approach, Theguilherm3 repo).
# Render chain: app -> virpipe -> virgl_test_server -> ANGLE -> Vulkan -> Mali.
# Desktop shell stays software (llvmpipe); GPU is applied per-app via `gpu` alias.
# The Mali Vulkan ICD wrapper from ar37-rs is required — without it ANGLE falls
# back to Mali's broken OpenGL path (texImage2D 0x0502 / EGL_BAD_ACCESS).
# This path does NOT touch step_hwa_vendor — the verified fallback stays intact.
step_hwa_virgl() {
    # virgl + ANGLE + Vulkan loader from Termux repos
    apt install -y $APT_OPTS $HWA_LIBS_VIRGL
    # Remove swrast ICD — it shadows the Mali Vulkan ICD wrapper.
    apt remove -y '*icd-swrast' 2>/dev/null || true
    # Mali Vulkan ICD wrapper (ar37-rs) — redirects ANGLE to Mali's Vulkan driver.
    local _icd_deb="/tmp/mesa-vulkan-icd-wrapper_25.0.0-1_aarch64.deb"
    command -v wget >/dev/null 2>&1 || pkg install -y wget >/dev/null 2>&1
    wget -q -O "$_icd_deb" "$VIRGL_ICD_URL"
    dpkg -i "$_icd_deb"
    rm -f "$_icd_deb"
    apt-get --fix-broken install -y $APT_OPTS
    # vgl launcher script (virgl server manager: start/stop/target_app)
    local _vgl="$HOME/vgl"
    curl -fsSL -o "$_vgl" "$VGL_URL" \
        || wget -q -O "$_vgl" "$VGL_URL"
    chmod +x "$_vgl"
    apt install -y $APT_OPTS mesa-demos glmark2 vkmark
    # --- Diagnostics ---
    local _diag="/tmp/termux-install-virgl-diag.log"
    : > "$_diag"
    {
        echo "=== virgl diagnostics ==="
        echo "vgl script: $([ -x "$_vgl" ] && echo present || echo MISSING)"
        echo "--- virgl packages ---"
        dpkg -l virglrenderer virglrenderer-android angle-android vulkan-loader-generic 2>/dev/null | grep ^ii || true
        echo "--- Mali ICD ---"
        local _icd="$PREFIX/share/vulkan/icd.d/mesa-vulkan-icd-wrapper.json"
        [ -f "$_icd" ] && cat "$_icd" || echo "ICD MISSING at $_icd"
        echo "--- ANGLE libs ---"
        ls "$PREFIX/opt/angle-android/"*/libEGL*.so 2>/dev/null || echo "ANGLE libs not found"
        echo "=== end diagnostics ==="
    } >> "$_diag" 2>&1
    echo -e "${C}  Diagnostics: $_diag${N}"
    echo -e "${Y}  NOTE: before starting the desktop, run: ~/vgl angle=vulkan${N}"
    echo -e "${Y}  Per-app GPU: prefix apps with 'gpu' inside proot (see README).${N}"
}

step_install_desktops() {
    local id i
    mkdir -p "$CONF_DIR"; : > "$DESKTOPS_CONF"
    for id in "${SEL_DE[@]}"; do
        for i in "${!DE_IDS[@]}"; do
            if [[ "${DE_IDS[$i]}" == "$id" ]]; then
                pkg install -y $APT_OPTS ${DE_PKGS[$i]}
                echo "${DE_IDS[$i]}|${DE_NAMES[$i]}|${DE_LAUNCH[$i]}" >> "$DESKTOPS_CONF"
            fi
        done
    done

    # XFCE4: pre-configure panel with monitoring + wallpaper
    if [[ " ${SEL_DE[*]} " == *" xfce4 "* ]]; then
        local xfconf="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
        mkdir -p "$xfconf"
        cp "$SCRIPT_DIR/configs/xfce4/xfce4-panel.xml" "$xfconf/xfce4-panel.xml"
        local wal="" bg_dir="$PREFIX/share/backgrounds/xfce"
        [ -d "$bg_dir" ] && wal=$(find "$bg_dir" -maxdepth 1 \( -name '*.jpg' -o -name '*.png' -o -name '*.svg' \) 2>/dev/null | head -1)
        if [ -n "$wal" ]; then
            sed "s|WALLPAPER_PATH|$wal|g" "$SCRIPT_DIR/configs/xfce4/xfce4-desktop.xml" > "$xfconf/xfce4-desktop.xml"
        fi
    fi
}

step_install_apps() {
    local id i
    for id in "${SEL_APP[@]}"; do
        for i in "${!APP_IDS[@]}"; do
            if [[ "${APP_IDS[$i]}" == "$id" ]]; then
                if [ -z "${APP_PKGS[$i]}" ]; then
                    curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh | bash
                else
                    pkg install -y $APT_OPTS ${APP_PKGS[$i]}
                fi
            fi
        done
    done
}

step_helpers() {
    mkdir -p ~/bin
    cp "$VENDOR_BIN"/* ~/bin/
    chmod +x ~/bin/*

    # wrapper for pavucontrol (XFCE4 panel plugin traci PULSE_SERVER bez shella)
    cat > ~/bin/pavucontrol << 'PULSE_WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
export PULSE_SERVER=127.0.0.1
exec /data/data/com.termux/files/usr/bin/pavucontrol "$@"
PULSE_WRAPPER
    chmod +x ~/bin/pavucontrol

    # the generic desktop launcher (lives next to install.sh)
    cp "$SCRIPT_DIR/desktop.sh" ~/bin/desktop
    chmod +x ~/bin/desktop

    # make sure ~/bin is on PATH (for this session + future shells)
    grep -q 'export PATH="$HOME/bin:$PATH"' ~/.bashrc 2>/dev/null \
        || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/bin:$PATH"

    mkdir -p ~/Desktop ~/Downloads ~/Pictures ~/Temp
}

step_proot() {
    local idx=-1 i
    for i in "${!PROOT_IDS[@]}"; do
        [ "${PROOT_IDS[$i]}" = "$SEL_PROOT" ] && idx=$i && break
    done
    [ $idx -ge 0 ] || { echo -e "${R}Unknown proot distro: $SEL_PROOT${N}"; return 1; }

    local img="${PROOT_IMAGES[$idx]}" pm="${PROOT_PM[$idx]}" pkgs="${PROOT_PKGS[$idx]}"
    local alias="${PROOT_IDS[$idx]}"
    # proot-distro v5 uses OCI images; --name gives it a local alias
    proot-distro install --name "$alias" "$img"

    # ponytail: firefox audio inside proot needs --shared-tmp and pulseaudio TCP forwarded
    #           on ubuntu/debian try: pactl load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1
    # run first-boot setup inside the container (package-manager-specific)
    case "$pm" in
        apt)
            proot-distro login "$alias" --shared-tmp -- /bin/bash -c "
                apt update -y; apt upgrade -y
                apt install -y $pkgs
                echo 'export PULSE_SERVER=127.0.0.1' >> /root/.bashrc
                mkdir -p /root/bin
            " ;;
        pacman)
            proot-distro login "$alias" --shared-tmp -- /bin/bash -c "
                pacman-key --init; pacman-key --populate archlinuxarm 2>/dev/null || true
                pacman -Syu --noconfirm
                pacman -S --noconfirm --needed $pkgs
                echo 'export PULSE_SERVER=127.0.0.1' >> /root/.bashrc
                mkdir -p /root/bin
            " ;;
        dnf)
            proot-distro login "$alias" --shared-tmp -- /bin/bash -c "
                dnf upgrade -y || true
                dnf install -y $pkgs || true
                echo 'export PULSE_SERVER=127.0.0.1' >> /root/.bashrc
                mkdir -p /root/bin
            " ;;
        apk)
            proot-distro login "$alias" --shared-tmp -- /bin/sh -c "
                apk update; apk upgrade
                apk add $pkgs
                echo 'export PULSE_SERVER=127.0.0.1' >> /root/.bashrc
                mkdir -p /root/bin
            " ;;
    esac
}

# ============================ SYNC VENDOR =====================================
# Refresh vendored files from upstream (used when USE_LATEST=1 or --sync).
# Bin scripts come from the main branch (truly latest); debs come from the
# release tags defined above (asset URLs are derived from the tags).
sync_vendor() {
    command -v curl >/dev/null 2>&1 || pkg install -y curl >/dev/null 2>&1
    mkdir -p "$VENDOR_BIN" "$VENDOR_DEBS"
    local s
    for s in "${BIN_SCRIPTS[@]}"; do
        curl -fsSL -o "$VENDOR_BIN/$s" "$UPSTREAM_RAW/bin/$s" \
            || echo -e "${R}failed to fetch $s${N}"
    done
    chmod +x "$VENDOR_BIN"/* 2>/dev/null
    curl -fsSL -o "$MESA_ZINK_DEB"      "$UPSTREAM_REL/$MESA_ZINK_TAG/mesa-zink_${MESA_VER}_aarch64.deb"      || echo -e "${R}failed to fetch mesa-zink deb${N}"
    curl -fsSL -o "$MESA_ZINK_DEV_DEB"  "$UPSTREAM_REL/$MESA_ZINK_TAG/mesa-zink-dev_${MESA_VER}_all.deb"      || echo -e "${R}failed to fetch mesa-zink-dev deb${N}"
    curl -fsSL -o "$VULKAN_WRAPPER_DEB" "$UPSTREAM_REL/$VULKAN_WRAPPER_TAG/vulkan-wrapper-android_${VULKAN_VER}_aarch64.deb" || echo -e "${R}failed to fetch vulkan-wrapper deb${N}"
}

# ============================ SELF-TEST ======================================
selftest() {
    local err=0 n=${#DE_IDS[@]}
    [ ${#DE_NAMES[@]}  -eq $n ] || { echo "DE_NAMES length != DE_IDS";  err=1; }
    [ ${#DE_PKGS[@]}   -eq $n ] || { echo "DE_PKGS length != DE_IDS";   err=1; }
    [ ${#DE_LAUNCH[@]} -eq $n ] || { echo "DE_LAUNCH length != DE_IDS"; err=1; }
    local i
    for ((i=0;i<n;i++)); do
        [ -n "${DE_LAUNCH[$i]}" ] || { echo "DE_LAUNCH[$i] empty"; err=1; }
        [ -n "${DE_PKGS[$i]}"   ] || { echo "DE_PKGS[$i] empty";   err=1; }
    done
    local na=${#APP_IDS[@]}
    [ ${#APP_NAMES[@]} -eq $na ] || { echo "APP_NAMES length != APP_IDS"; err=1; }
    [ ${#APP_PKGS[@]}  -eq $na ] || { echo "APP_PKGS length != APP_IDS";  err=1; }
    # proot distro registry
    local np=${#PROOT_IDS[@]}
    [ ${#PROOT_NAMES[@]} -eq $np ] || { echo "PROOT_NAMES length != PROOT_IDS"; err=1; }
    [ ${#PROOT_IMAGES[@]} -eq $np ] || { echo "PROOT_IMAGES length != PROOT_IDS"; err=1; }
    [ ${#PROOT_PKGS[@]} -eq $np ]   || { echo "PROOT_PKGS length != PROOT_IDS"; err=1; }
    [ ${#PROOT_PM[@]} -eq $np ]     || { echo "PROOT_PM length != PROOT_IDS"; err=1; }
    [ ${#PROOT_WARN[@]} -eq $np ]   || { echo "PROOT_WARN length != PROOT_IDS"; err=1; }
    # vendored HWA debs: vendor path needs all three; mesa26 needs the Mali
    # shim (wrapper) only; repo and virgl need none (virgl downloads at runtime).
    if [ "$GPU_SOURCE" = vendor ] || [ "$GPU_SOURCE" = mesa26 ]; then
        [ -f "$VULKAN_WRAPPER_DEB" ] || { echo "missing vendor deb: $VULKAN_WRAPPER_DEB"; err=1; }
    fi
    if [ "$GPU_SOURCE" = vendor ]; then
        for f in "$MESA_ZINK_DEB" "$MESA_ZINK_DEV_DEB"; do
            [ -f "$f" ] || { echo "missing vendor deb: $f"; err=1; }
        done
    fi
    # bin scripts are always needed by step_helpers
    for s in "${BIN_SCRIPTS[@]}"; do
        [ -f "$VENDOR_BIN/$s" ] || { echo "missing vendor script: $s"; err=1; }
    done
    [ $err -eq 0 ] && echo -e "${G}selftest OK${N} - $n desktops, $na apps, $np proot distros, vendor OK"
    return $err
}

list_desktops() {
    echo -e "${C}${B}Available desktops:${N}"
    for i in "${!DE_IDS[@]}"; do
        printf "  ${G}%-10s${N} %s\n" "${DE_IDS[$i]}" "${DE_NAMES[$i]}"
    done
}

list_proot_distros() {
    echo -e "${C}${B}Available proot distros:${N}"
    for i in "${!PROOT_IDS[@]}"; do
        printf "  ${G}%-10s${N} %s" "${PROOT_IDS[$i]}" "${PROOT_NAMES[$i]}"
        [ -n "${PROOT_WARN[$i]}" ] && printf "  ${R}⚠ %s${N}" "${PROOT_WARN[$i]}"
        echo
    done
}

usage() {
    sed -n '2,20p' "$0"
}

# ============================ MAIN ===========================================
ASSUME_YES=0; SKIP_DEPS=0; SKIP_BIN=0
CLI_PROOT_DISTRO=""

while [ $# -gt 0 ]; do
    case "$1" in
        --selftest) selftest; exit $?;;
        --list)     list_desktops; list_proot_distros; exit 0;;
        --sync)     echo -e "${Y}Refreshing vendored files from upstream...${N}"
                    sync_vendor; echo -e "${G}Done.${N}"; exit 0;;
        --help|-h)  usage; exit 0;;
        -y|--yes)   ASSUME_YES=1; shift;;
        --proot-distro) CLI_PROOT_DISTRO="$2"; shift 2;;
        --no-deps)  SKIP_DEPS=1; shift;;
        --no-bin)   SKIP_BIN=1; shift;;
        --vendored) GPU_SOURCE=vendor; shift;;
        --repo)     GPU_SOURCE=repo; shift;;
        --mesa26)   GPU_SOURCE=mesa26; shift;;
        --virgl)    GPU_SOURCE=virgl; shift;;
        --verbose)  VERBOSE=1; shift;;
        *) echo -e "${R}Unknown flag: $1${N}"; usage; exit 1;;
    esac
done

# validate CLI proot distro flag, if given
SEL_PROOT=""
if [ -n "$CLI_PROOT_DISTRO" ]; then
    found=0
    for d in "${PROOT_IDS[@]}"; do [ "$d" = "$CLI_PROOT_DISTRO" ] && found=1 && break; done
    [ $found -eq 1 ] || { echo -e "${R}Unknown proot distro: $CLI_PROOT_DISTRO${N}"; list_proot_distros; exit 1; }
    SEL_PROOT="$CLI_PROOT_DISTRO"
fi

banner

echo -e "${W}This wizard installs a native Linux desktop in Termux with Mali HWA.${N}"
case "$GPU_SOURCE" in
    repo)   echo -e "${GR}HWA: mesa-zink from Termux/tur repos (stale 22.0.5, experimental).${N}\n" ;;
    mesa26) echo -e "${GR}HWA: Mesa 26.x from main repo + vendored Mali shim (experimental).${N}\n" ;;
    virgl)  echo -e "${GR}HWA: virgl -> ANGLE -> Vulkan (ar37-rs; per-app GPU for proot).${N}\n" ;;
    *)
        echo -e "${GR}HWA stack: $UPSTREAM (MIT). Upstream is unmaintained but functional.${N}"
        if [ "$USE_LATEST" = 1 ]; then
            echo -e "${Y}USE_LATEST=1 -> refreshing vendored files from upstream.${N}"
            sync_vendor
        fi
        echo
        ;;
esac

if [ "$ASSUME_YES" = 1 ]; then
    if [ -n "$SEL_PROOT" ]; then
        echo -e "${Y}Non-interactive mode (-y): defaults = XFCE4, no apps, PRoot=${SEL_PROOT}, no mirror.${N}\n"
    else
        echo -e "${Y}Non-interactive mode (-y): defaults = XFCE4, no apps, no PRoot, no mirror.${N}\n"
    fi
    SEL_DE=("xfce4"); SEL_APP=(); DO_MIRROR=0
else
    DO_MIRROR=0; yesno "Optimize package mirrors first (needs a keypress)?" && DO_MIRROR=1

    # --- desktop selection (mandatory) ---
    MENU_IDS=("${DE_IDS[@]}"); MENU_NAMES=("${DE_NAMES[@]}")
    while :; do
        pick_multi "Select desktop(s) to install:"
        [ ${#SELECTED[@]} -gt 0 ] && break
        echo -e "${R}Pick at least one.${N}"
    done
    SEL_DE=("${SELECTED[@]}")
    echo -e "${G}Desktops:${N} ${SEL_DE[*]}\n"

    # --- apps selection (optional) ---
    MENU_IDS=("${APP_IDS[@]}"); MENU_NAMES=("${APP_NAMES[@]}")
    pick_multi "Select apps to install (optional):"
    SEL_APP=("${SELECTED[@]}")
    [ ${#SEL_APP[@]} -gt 0 ] && echo -e "${G}Apps:${N} ${SEL_APP[*]}\n"

    # --- proot distro selection (optional, default skip for faster iteration) ---
    if [ -z "$SEL_PROOT" ] && yesno "Install a PRoot container? (broader app compat, LLM dev tools)"; then
        echo -e "${GR}Available distros:${N}"
        for i in "${!PROOT_IDS[@]}"; do
            printf "  ${C}%d${N}) ${G}%-10s${N} %s" "$((i+1))" "${PROOT_IDS[$i]}" "${PROOT_NAMES[$i]}"
            [ -n "${PROOT_WARN[$i]}" ] && printf " ${R}⚠${N}" || true
            echo
        done
        echo -e "  ${GR}(1-5 to pick · 's' = skip)${N}"
        read -rp "$(echo -e "${Y}>>${N} ")" pc
        case "$pc" in
            s|S|"") SEL_PROOT="" ;;
            *)
                if [[ "$pc" =~ ^[1-5]$ ]] && [ $pc -le ${#PROOT_IDS[@]} ]; then
                    SEL_PROOT="${PROOT_IDS[$((pc-1))]}"
                    [ -n "${PROOT_WARN[$((pc-1))]}" ] && \
                        echo -e "${R}⚠ ${PROOT_WARN[$((pc-1))]}${N}"
                    echo -e "${G}PRoot distro:${N} ${SEL_PROOT}\n"
                else
                    echo -e "${R}Invalid choice, skipping PRoot.${N}\n"
                    SEL_PROOT=""
                fi
                ;;
        esac
    else
        [ -n "$SEL_PROOT" ] && echo -e "${G}PRoot distro (from CLI):${N} ${SEL_PROOT}\n"
    fi
fi

# --- pre-select mirror group (always, so --no-deps runs are covered too) ---
setup_mirrors

# --- build the step list (accurate progress) ---
STEP_FAILED=0
steps_label=(); steps_fn=()
[ "$SKIP_DEPS" = 0 ] && { steps_label+=("System update, repos & base packages"); steps_fn+=(step_system); }
case "$GPU_SOURCE" in
    repo)   steps_label+=("Hardware acceleration (mesa-zink from repos — stale 22.0.5)"); steps_fn+=(step_hwa_repo) ;;
    mesa26) steps_label+=("Hardware acceleration (Mesa 26.x from main repo + Mali shim)"); steps_fn+=(step_hwa_mesa26) ;;
    virgl)  steps_label+=("Hardware acceleration (virgl -> ANGLE -> Vulkan)");              steps_fn+=(step_hwa_virgl) ;;
    *)      steps_label+=("Hardware acceleration (pinned vendored Mesa/Zink/Vulkan)");     steps_fn+=(step_hwa_vendor) ;;
esac
steps_label+=("Desktop environment(s)");               steps_fn+=(step_install_desktops)
[ ${#SEL_APP[@]} -gt 0 ] && { steps_label+=("Applications"); steps_fn+=(step_install_apps); }
[ "$SKIP_BIN" = 0 ]  && { steps_label+=("Helper scripts & launcher"); steps_fn+=(step_helpers); }
[ -n "$SEL_PROOT" ]  && { steps_label+=("${SEL_PROOT^} PRoot container"); steps_fn+=(step_proot); }

TOTAL=${#steps_fn[@]}
echo -e "${C}Running ${TOTAL} phases. Sit back.${N}\n"

for i in "${!steps_fn[@]}"; do
    show_progress $((i+1)) "$TOTAL" "${steps_label[$i]}"
    run_step "${steps_label[$i]}" "${steps_fn[$i]}" || { STEP_FAILED=1; echo -e "${Y}  (continued despite warning)${N}"; }
done

# --- cleanup log files on full success ---
[ "$STEP_FAILED" = 0 ] && rm -f /tmp/termux-install-*.log 2>/dev/null

# --- done ---
echo
echo -e "${G}╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${G}║ ✅  INSTALLATION COMPLETE                                ║${N}"
echo -e "${G}╚══════════════════════════════════════════════════════════╝${N}\n"
echo -e "${W}Start the desktop:${N}"
echo -e "   ${C}desktop${N}              ${GR}# pick from installed${N}"
echo -e "   ${C}desktop xfce4${N}        ${GR}# launch directly${N}"
echo -e "   ${C}desktop i3${N}           ${GR}# launch i3${N}"
echo -e "\n${GR}Tip: run 'desktop-help' for the upstream command cheat-sheet.${N}"
echo -e "\n${Y}⚠ Audio troubleshooting:${N}"
echo -e "   ${GR}1. Android Settings → Apps → Termux → Permissions → enable Microphone${N}"
echo -e "   ${GR}2. Android Settings → Apps → Termux → Battery → set Unrestricted${N}"
echo -e "   ${GR}3. If still no sound:${C} desktop${N} restarts PulseAudio; check: ${C}pactl info${N}"
exit 0
