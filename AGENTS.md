# Termux Desktop Installer

Self-contained installer for a native Linux desktop in Termux with Mali GPU
hardware acceleration (Zink + vulkan-wrapper). Targets Lenovo IdeaPad Pro 12.7
(Dimensity 8300, Mali-G615). Supports XFCE4, i3, Openbox, Fluxbox, optional
proot containers, and vendored HWA debs — no runtime dependency on upstream.

# Conventions

- Desktop-specific config (panel layout, wallpaper, etc.) goes in `configs/<desktop>/`.
  The installer copies these files rather than embedding large heredocs.
- Vendored debs and helper scripts stay in `vendor/`, never modified by the
  installer.
- Keep the shell script POSIX-friendly; avoid bashisms where `dash` would break.
- One function = one step; phases are listed in `steps_label`/`steps_fn` arrays.
