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
#  Flags:  --selftest   validate registries & vendored files, then exit
#          --list       list available desktops & exit
#          --sync       refresh ./vendor from upstream (uses tag vars) & exit
#          -y, --yes    non-interactive (defaults: XFCE4, no apps/proot/mirror)
#          --no-deps    skip the base packages/repos step
#          --no-bin     skip the helper-scripts & launcher step
#          --help       show usage
# =============================================================================
#
#  Package source: by default uses files vendored in ./vendor (pinned, offline).
#  Set USE_LATEST=1 (or edit the tag vars + run --sync) to pull newer versions
#  from avelith07/Termux-Desktop at install time.

# ============================ CONFIG ==========================================
# Resolve the script's own directory (so vendored files are found wherever it runs)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Package source & versions
# ---------------------------------------------------------------------------
# By default the installer uses the files vendored in ./vendor (pinned, offline,
# reproducible). Set USE_LATEST=1 to refresh them from upstream at install time.
USE_LATEST=0

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
BASE_PKGS="x11-repo termux-x11-nightly tur-repo termux-api pulseaudio proot-distro curl"

# --- DESKTOPS REGISTRY (extend here) -----------------------------------------
DE_IDS=(    "xfce4"                              "i3"                              "openbox"                              "fluxbox"                             )
DE_NAMES=(  "XFCE4 - full desktop (recommended)" "i3 - tiling window manager"      "Openbox - lightweight floating WM"    "Fluxbox - lightweight stacking WM"   )
DE_PKGS=(   "xfce4 xfce4-goodies xfce4-whiskermenu-plugin xfce4-battery-plugin xfce4-cpugraph-plugin xfce4-docklike-plugin xfce4-pulseaudio-plugin xfce4-screenshooter xfce4-taskmanager mousepad" "i3 i3status dmenu xfce4-terminal" "openbox tint2 obconf xfce4-terminal" "fluxbox xfce4-terminal" )
DE_LAUNCH=( "xfce4-session"                      "i3"                              "openbox-session"                      "fluxbox"                             )

# --- APPS REGISTRY (extend here) ---------------------------------------------
APP_IDS=(   "firefox"   "chromium"  "vlc"   "mpv"   "code-oss"      "geany" )
APP_NAMES=( "Firefox"   "Chromium"   "VLC"   "MPV"   "VS Code (code-oss)" "Geany" )
APP_PKGS=(  "firefox"   "chromium"   "vlc-qt" "mpv"  "code-oss"      "geany" )

CONF_DIR="$HOME/.config/termux-desktop"
DESKTOPS_CONF="$CONF_DIR/desktops.conf"
# ============================ /CONFIG =========================================

# ----------------------------- colors ----------------------------------------
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'
W='\033[1;37m'; GR='\033[0;90m'; B='\033[1m'; N='\033[0m'

# ----------------------------- spinner ---------------------------------------
spinner() {
    local pid=$1 msg=$2 spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r ${Y}⏳${N} ${msg} ${C}${spin:$i:1}${N} "
        sleep 0.1
    done
    wait "$pid"; local rc=$?
    if [ $rc -eq 0 ]; then printf "\r ${G}✓${N} ${msg}          \n"
    else                 printf "\r ${R}✗${N} ${msg} ${R}(failed)${N}  \n"; fi
    return $rc
}

run_step() { local msg="$1"; shift; ( "$@" ) >/dev/null 2>&1 & spinner $! "$msg"; }

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

# ============================ STEP FUNCTIONS =================================
step_system() {
    pkg update -y && pkg upgrade -y
    pkg install -y $BASE_PKGS
    termux-wake-lock
    [ "$DO_MIRROR" = 1 ] && {
        cp "$VENDOR_BIN/termux-fastest-repo" ~/termux-fastest-repo
        chmod +x ~/termux-fastest-repo; ~/termux-fastest-repo; rm -f ~/termux-fastest-repo
    }
}

step_hwa() {
    apt install -y "$MESA_ZINK_DEB" "$MESA_ZINK_DEV_DEB"
    apt --fix-broken install -y
    apt install -y $HWA_LIBS
    apt install -y "$VULKAN_WRAPPER_DEB"
    apt --fix-broken install -y
    pkg install -y glmark2 vkmark
}

step_install_desktops() {
    local id i
    mkdir -p "$CONF_DIR"; : > "$DESKTOPS_CONF"
    for id in "${SEL_DE[@]}"; do
        for i in "${!DE_IDS[@]}"; do
            if [[ "${DE_IDS[$i]}" == "$id" ]]; then
                pkg install -y ${DE_PKGS[$i]}
                echo "${DE_IDS[$i]}|${DE_NAMES[$i]}|${DE_LAUNCH[$i]}" >> "$DESKTOPS_CONF"
            fi
        done
    done
}

step_install_apps() {
    local id i
    for id in "${SEL_APP[@]}"; do
        for i in "${!APP_IDS[@]}"; do
            [[ "${APP_IDS[$i]}" == "$id" ]] && pkg install -y ${APP_PKGS[$i]}
        done
    done
}

step_helpers() {
    mkdir -p ~/bin
    cp "$VENDOR_BIN"/* ~/bin/
    chmod +x ~/bin/*

    # the generic desktop launcher (lives next to install.sh)
    cp "$SCRIPT_DIR/desktop.sh" ~/bin/desktop
    chmod +x ~/bin/desktop

    # make sure ~/bin is on PATH
    grep -q 'export PATH="$HOME/bin:$PATH"' ~/.bashrc 2>/dev/null \
        || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc

    mkdir -p ~/Desktop ~/Downloads ~/Pictures ~/Temp
}

step_proot() {
    proot-distro install debian
    proot-distro login debian --shared-tmp -- /bin/bash <<'EOF'
apt update -y; apt upgrade -y
apt install -y sudo nano dbus-x11 adduser pulseaudio
mkdir -p "$HOME/bin"
EOF
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
    # vendored files must be present when not fetching latest
    if [ "$USE_LATEST" = 0 ]; then
        for f in "$MESA_ZINK_DEB" "$MESA_ZINK_DEV_DEB" "$VULKAN_WRAPPER_DEB"; do
            [ -f "$f" ] || { echo "missing vendor deb: $f"; err=1; }
        done
        for s in "${BIN_SCRIPTS[@]}"; do
            [ -f "$VENDOR_BIN/$s" ] || { echo "missing vendor script: $s"; err=1; }
        done
    fi
    [ $err -eq 0 ] && echo -e "${G}selftest OK${N} - $n desktops, $na apps registered, vendor OK"
    return $err
}

list_desktops() {
    echo -e "${C}${B}Available desktops:${N}"
    for i in "${!DE_IDS[@]}"; do
        printf "  ${G}%-10s${N} %s\n" "${DE_IDS[$i]}" "${DE_NAMES[$i]}"
    done
}

usage() {
    sed -n '2,20p' "$0"
}

# ============================ MAIN ===========================================
ASSUME_YES=0; SKIP_DEPS=0; SKIP_BIN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --selftest) selftest; exit $?;;
        --list)     list_desktops; exit 0;;
        --sync)     echo -e "${Y}Refreshing vendored files from upstream...${N}"
                    sync_vendor; echo -e "${G}Done.${N}"; exit 0;;
        --help|-h)  usage; exit 0;;
        -y|--yes)   ASSUME_YES=1; shift;;
        --no-deps)  SKIP_DEPS=1; shift;;
        --no-bin)   SKIP_BIN=1; shift;;
        *) echo -e "${R}Unknown flag: $1${N}"; usage; exit 1;;
    esac
done

banner

echo -e "${W}This wizard installs a native Linux desktop in Termux with Mali HWA.${N}"
echo -e "${GR}HWA stack: $UPSTREAM (MIT). Upstream is unmaintained but functional.${N}"
[ "$USE_LATEST" = 1 ] && echo -e "${Y}USE_LATEST=1 -> refreshing vendored files from upstream.${N}\n" \
                       || echo -e "${GR}Using pinned vendored files (USE_LATEST=0).${N}\n"

# refresh vendored files now if requested
[ "$USE_LATEST" = 1 ] && sync_vendor

if [ "$ASSUME_YES" = 1 ]; then
    echo -e "${Y}Non-interactive mode (-y): defaults = XFCE4, no apps, no PRoot, no mirror.${N}\n"
    SEL_DE=("xfce4"); SEL_APP=(); DO_MIRROR=0; DO_PROOT=0
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

    # --- proot (optional) ---
    DO_PROOT=0; yesno "Install Debian PRoot container (for broader app compat)?" && DO_PROOT=1
fi

# --- build the step list (accurate progress) ---
steps_label=(); steps_fn=()
[ "$SKIP_DEPS" = 0 ] && { steps_label+=("System update, repos & base packages"); steps_fn+=(step_system); }
steps_label+=("Hardware acceleration (Mali/Zink/Vulkan)"); steps_fn+=(step_hwa)
steps_label+=("Desktop environment(s)");               steps_fn+=(step_install_desktops)
[ ${#SEL_APP[@]} -gt 0 ] && { steps_label+=("Applications"); steps_fn+=(step_install_apps); }
[ "$SKIP_BIN" = 0 ]  && { steps_label+=("Helper scripts & launcher"); steps_fn+=(step_helpers); }
[ "$DO_PROOT" = 1 ]  && { steps_label+=("Debian PRoot container"); steps_fn+=(step_proot); }

TOTAL=${#steps_fn[@]}
echo -e "${C}Running ${TOTAL} phases. Sit back.${N}\n"

for i in "${!steps_fn[@]}"; do
    show_progress $((i+1)) "$TOTAL" "${steps_label[$i]}"
    run_step "${steps_label[$i]}" "${steps_fn[$i]}" || echo -e "${Y}  (continued despite warning)${N}"
done

# --- done ---
echo
echo -e "${G}╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${G}║ ✅  INSTALLATION COMPLETE                                ║${N}"
echo -e "${G}╚══════════════════════════════════════════════════════════╝${N}\n"
echo -e "${W}Restart Termux (or run:${C} source ~/.bashrc${W}), then start the desktop:${N}"
echo -e "   ${C}desktop${N}              ${GR}# pick from installed${N}"
echo -e "   ${C}desktop xfce4${N}        ${GR}# launch directly${N}"
echo -e "   ${C}desktop i3${N}           ${GR}# launch i3${N}"
echo -e "\n${GR}Tip: run 'desktop-help' for the upstream command cheat-sheet.${N}"
exit 0
