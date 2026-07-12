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
#          --no-deps        skip the base packages/repos step
#          --no-bin         skip the helper-scripts & launcher step
#          --verbose        show live output during install (default: show on failure only)
#          --help           show usage
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

# --- DESKTOPS REGISTRY (extend here) -----------------------------------------
DE_IDS=(    "xfce4"                              "i3"                              "openbox"                              "fluxbox"                             )
DE_NAMES=(  "XFCE4 - full desktop (recommended)" "i3 - tiling window manager"      "Openbox - lightweight floating WM"    "Fluxbox - lightweight stacking WM"   )
DE_PKGS=(   "xfce4 xfce4-goodies xfce4-whiskermenu-plugin xfce4-battery-plugin xfce4-cpugraph-plugin xfce4-docklike-plugin xfce4-pulseaudio-plugin xfce4-screenshooter xfce4-taskmanager mousepad" "i3 i3status dmenu xfce4-terminal" "openbox tint2 obconf xfce4-terminal" "fluxbox xfce4-terminal" )
DE_LAUNCH=( "xfce4-session"                      "i3"                              "openbox-session"                      "fluxbox"                             )

# --- APPS REGISTRY (extend here) ---------------------------------------------
APP_IDS=(   "firefox"   "chromium"  "vlc"   "mpv"   "code-oss"      "geany" )
APP_NAMES=( "Firefox"   "Chromium"   "VLC"   "MPV"   "VS Code (code-oss)" "Geany" )
APP_PKGS=(  "firefox"   "chromium"   "vlc-qt" "mpv"  "code-oss"      "geany" )

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
PROOT_WARN=(   ""                                     ""                                           "Keyring trust issues (#424); stale images (#480). Consider Arch instead." "dnf segfaults (#545); sudo broken (#533); filesystem upgrade fails (#525)." "musl libc; some pre-built binaries fail; no systemd." )
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
    local pid=$1 msg=$2 log_file=$3 spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 c=0 ctx=""
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 )); c=$((c+1))
        [ $((c % 50)) -eq 0 ] && [ -n "$log_file" ] && [ -s "$log_file" ] \
            && ctx=$(tail -1 "$log_file" 2>/dev/null | head -c 60)
        printf "\r\033[K ${Y}⏳${N} ${msg} ${C}${spin:$i:1}${N}"
        [ -n "$ctx" ] && printf " ${GR}${ctx//$'\n'/}${N}"
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

# ============================ STEP FUNCTIONS =================================
step_system() {
    apt-get update -y
    apt-get upgrade -y $APT_OPTS
    # naprawia przejściowe braki bibliotek po upgrade (libpcre2.so, etc.)
    apt-get --fix-broken install -y $APT_OPTS
    apt-get install -y $APT_OPTS x11-repo tur-repo
    apt-get update -y
    apt-get install -y $APT_OPTS termux-x11-nightly termux-api pulseaudio proot-distro curl
    termux-wake-lock
    [ "$DO_MIRROR" = 1 ] && {
        cat > "$PREFIX/etc/apt/sources.list" <<-EOF
deb https://packages.termux.dev/apt/termux-main stable main
deb https://grimler.se/termux stable main
deb https://termux.netmirror.org stable main
EOF
        apt-get update -y
    }
}

step_hwa() {
    apt install -y $APT_OPTS "$MESA_ZINK_DEB" "$MESA_ZINK_DEV_DEB"
    apt --fix-broken install -y $APT_OPTS
    apt install -y $APT_OPTS $HWA_LIBS
    apt install -y $APT_OPTS "$VULKAN_WRAPPER_DEB"
    apt --fix-broken install -y $APT_OPTS
    apt-get install -y $APT_OPTS glmark2 vkmark
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
}

step_install_apps() {
    local id i
    for id in "${SEL_APP[@]}"; do
        for i in "${!APP_IDS[@]}"; do
            [[ "${APP_IDS[$i]}" == "$id" ]] && pkg install -y $APT_OPTS ${APP_PKGS[$i]}
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
    local idx=-1 i
    for i in "${!PROOT_IDS[@]}"; do
        [ "${PROOT_IDS[$i]}" = "$SEL_PROOT" ] && idx=$i && break
    done
    [ $idx -ge 0 ] || { echo -e "${R}Unknown proot distro: $SEL_PROOT${N}"; return 1; }

    local img="${PROOT_IMAGES[$idx]}" pm="${PROOT_PM[$idx]}" pkgs="${PROOT_PKGS[$idx]}"
    local alias="${PROOT_IDS[$idx]}"
    # proot-distro v5 uses OCI images; --name gives it a local alias
    proot-distro install --name "$alias" "$img"

    # run first-boot setup inside the container (package-manager-specific)
    case "$pm" in
        apt)
            proot-distro login "$alias" --shared-tmp -- /bin/bash -c "
                apt update -y; apt upgrade -y
                apt install -y $pkgs
                mkdir -p /root/bin
            " ;;
        pacman)
            proot-distro login "$alias" --shared-tmp -- /bin/bash -c "
                pacman-key --init; pacman-key --populate archlinuxarm 2>/dev/null || true
                pacman -Syu --noconfirm
                pacman -S --noconfirm --needed $pkgs
                mkdir -p /root/bin
            " ;;
        dnf)
            proot-distro login "$alias" --shared-tmp -- /bin/bash -c "
                dnf upgrade -y || true
                dnf install -y $pkgs || true
                mkdir -p /root/bin
            " ;;
        apk)
            proot-distro login "$alias" --shared-tmp -- /bin/sh -c "
                apk update; apk upgrade
                apk add $pkgs
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
    # vendored files must be present when not fetching latest
    if [ "$USE_LATEST" = 0 ]; then
        for f in "$MESA_ZINK_DEB" "$MESA_ZINK_DEV_DEB" "$VULKAN_WRAPPER_DEB"; do
            [ -f "$f" ] || { echo "missing vendor deb: $f"; err=1; }
        done
        for s in "${BIN_SCRIPTS[@]}"; do
            [ -f "$VENDOR_BIN/$s" ] || { echo "missing vendor script: $s"; err=1; }
        done
    fi
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
echo -e "${GR}HWA stack: $UPSTREAM (MIT). Upstream is unmaintained but functional.${N}"
[ "$USE_LATEST" = 1 ] && echo -e "${Y}USE_LATEST=1 -> refreshing vendored files from upstream.${N}\n" \
                       || echo -e "${GR}Using pinned vendored files (USE_LATEST=0).${N}\n"

# refresh vendored files now if requested
[ "$USE_LATEST" = 1 ] && sync_vendor

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

    # --- proot distro selection (optional) ---
    if [ -z "$SEL_PROOT" ]; then
        echo -e "${C}Install a PRoot container? (for broader app compat, LLM dev tools, etc.)${N}"
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
        echo -e "${G}PRoot distro (from CLI):${N} ${SEL_PROOT}\n"
    fi
fi

# --- build the step list (accurate progress) ---
STEP_FAILED=0
steps_label=(); steps_fn=()
[ "$SKIP_DEPS" = 0 ] && { steps_label+=("System update, repos & base packages"); steps_fn+=(step_system); }
steps_label+=("Hardware acceleration (Mali/Zink/Vulkan)"); steps_fn+=(step_hwa)
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
echo -e "${W}Restart Termux (or run:${C} source ~/.bashrc${W}), then start the desktop:${N}"
echo -e "   ${C}desktop${N}              ${GR}# pick from installed${N}"
echo -e "   ${C}desktop xfce4${N}        ${GR}# launch directly${N}"
echo -e "   ${C}desktop i3${N}           ${GR}# launch i3${N}"
echo -e "\n${GR}Tip: run 'desktop-help' for the upstream command cheat-sheet.${N}"
exit 0
