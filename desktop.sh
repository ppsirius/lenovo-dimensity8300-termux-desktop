#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  TERMUX DESKTOP LAUNCHER  -  Mali (Dimensity) hardware acceleration
#  Reads ~/.config/termux-desktop/desktops.conf written by install.sh.
#
#  Usage:
#     desktop              # pick from installed desktops (auto if only one)
#     desktop xfce4        # launch XFCE4 directly
#     desktop i3           # launch i3
#     desktop openbox      # launch Openbox
#     desktop fluxbox      # launch Fluxbox
# =============================================================================
CONF="$HOME/.config/termux-desktop/desktops.conf"

C='\033[0;36m'; G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; W='\033[1;37m'; N='\033[0m'

# --- load installed desktops -------------------------------------------------
if [ ! -f "$CONF" ]; then
    echo -e "${R}No desktop installed. Run the installer first.${N}"; exit 1
fi
IDS=(); NAMES=(); LAUNCH=()
while IFS='|' read -r id name cmd; do
    [ -z "$id" ] || [[ "$id" == \#* ]] && continue
    IDS+=("$id"); NAMES+=("$name"); LAUNCH+=("$cmd")
done < "$CONF"
if [ ${#IDS[@]} -eq 0 ]; then
    echo -e "${R}No desktop registered in $CONF${N}"; exit 1
fi

# --- resolve target ----------------------------------------------------------
target="$1"
if [ -z "$target" ]; then
    if [ ${#IDS[@]} -eq 1 ]; then
        target="${IDS[0]}"
    else
        echo -e "${W}Select desktop:${N}"
        for i in "${!IDS[@]}"; do
            printf "  ${C}%d${N}) %s\n" "$((i+1))" "${NAMES[$i]}"
        done
        read -rp "$(echo -e "${Y}>>${N} ")" n
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#IDS[@]} )); then
            target="${IDS[$((n-1))]}"
        else
            echo -e "${R}Invalid choice${N}"; exit 1
        fi
    fi
fi
cmd=""
for i in "${!IDS[@]}"; do [ "${IDS[$i]}" = "$target" ] && cmd="${LAUNCH[$i]}"; done
[ -z "$cmd" ] && { echo -e "${R}Unknown desktop: $target${N}"; echo -e "${GR}Installed: ${IDS[*]}${N}"; exit 1; }

echo -e "${Y}Starting ${W}$target${Y} with Mali HWA...${N}"

# --- stop any previous session ----------------------------------------------
am force-stop com.termux.x11 2>/dev/null
pkill -9 -f "termux.x11"    2>/dev/null
pkill -9 -f "Xwayland"      2>/dev/null
pkill -9 -f "pulseaudio"    2>/dev/null
sleep 1

# --- clean stale X sockets / locks / virgl socket ---------------------------
rm -f  "${TMPDIR}"/.X*-lock     2>/dev/null
rm -rf "${TMPDIR}"/.X11-unix    2>/dev/null
mkdir -p "${TMPDIR}"/.X11-unix
chmod 1777 "${TMPDIR}"/.X11-unix

# --- audio (network pulseaudio) ---------------------------------------------
# --disallow-exit --disable-shm: nie szukamy ALSA/OSS na Androidzie
pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1 \
    --disallow-exit --disable-shm

# mic source (sles)
pactl load-module module-sles-source 2>/dev/null || true

# output sink: AAudio first (Android 12+), fallback SLES
pactl load-module module-aaudio-sink 2>/dev/null \
    || pactl load-module module-sles-sink 2>/dev/null \
    || true

for _ in 1 2 3; do
    SINK="$(pactl list short sinks 2>/dev/null | head -n1 | awk '{print $2}')"
    [ -n "$SINK" ] && break
    sleep 0.3
done

if [ -n "$SINK" ]; then
    pactl set-default-sink "$SINK" 2>/dev/null
    pactl set-sink-mute   "$SINK" false 2>/dev/null
    pactl set-sink-volume "$SINK" 100%  2>/dev/null
else
    echo -e " ${Y}⚠ No audio sink — ensure Termux has microphone permission & battery optimization off${N}"
fi

export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
export XDG_RUNTIME_DIR=${TMPDIR}

# --- Mali / Zink / Vulkan HWA environment ------------------------------------
export MESA_NO_ERROR=1
export MESA_SHADER_CACHE_DISABLE=false
export MESA_NO_WAIT_FOR_VBLANK=1
export vblank_mode=0
export LIBGL_DRI3_ENABLE=1
export WRAPPER_LOG_LEVEL=none
export WRAPPER_CMD_LOG_LEVEL=none

GPU_MODE=""
[ -f "$HOME/.config/termux-desktop/gpu.conf" ] && GPU_MODE=$(cat "$HOME/.config/termux-desktop/gpu.conf")

if [ "$GPU_MODE" = "virgl" ]; then
    # virgl path: desktop shell stays software (llvmpipe); GPU is per-app via
    # `gpu` alias inside proot. The virgl server must be running for `gpu` apps.
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    # Start the virgl server (ANGLE -> Vulkan mode) if not already running.
    if ! pgrep -f 'virgl_test' >/dev/null 2>&1; then
        if [ -x "$HOME/vgl" ]; then
            rm -f "${TMPDIR}"/.virgl_test 2>/dev/null
            "$HOME/vgl" angle=vulkan
            sleep 2
        else
            echo -e "${Y}  WARN: ~/vgl not found — virgl server not started.${N}"
            echo -e "${Y}        Per-app GPU (`gpu`) will not work without it.${N}"
        fi
    fi
else
    # Zink path (vendored / mesa26 / repo): OpenGL -> Vulkan -> Mali
    export MESA_LOADER_DRIVER_OVERRIDE=zink
    export GALLIUM_DRIVER=zink
    export ZINK_DESCRIPTORS=lazy
    # Only pin the wrapper ICD when it exists (vendored vulkan-wrapper-android);
    # otherwise let the repo Vulkan loader auto-discover its ICD.
    export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json
    [ -f "$VK_ICD_FILENAMES" ] || unset VK_ICD_FILENAMES
fi

# --- start the X server ------------------------------------------------------
termux-x11 :0 >/dev/null 2>&1 &
sleep 4
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1
sleep 2

# --- launch the desktop session ---------------------------------------------
dbus-launch --exit-with-session $cmd &

# XFCE4: disable compositor vblank to avoid tearing with HWA
if [ "$target" = "xfce4" ]; then
    xfconf-query -c xfwm4 -p /general/vblank_mode -s "off" 2>/dev/null &
fi

echo -e "${G}Desktop started. Switch to the Termux:X11 app.${N}"
exit 0
