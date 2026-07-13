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
- **`--vendored` is the only GPU path verified to accelerate on Mali-G615.**
  Do NOT break it: leave `step_hwa_vendor`, the vendored debs in `vendor/debs/`,
  `desktop.sh`'s HWA env vars, and the `wrapper_icd.aarch64.json` ICD path alone.
  The repo path (`step_hwa_repo`) is experimental — when in doubt, favour the
  vendored fallback. Any change that risks the vendored path is not allowed.

# Validation (run after EVERY shell edit)

After any change to `install.sh`, `desktop.sh`, or anything in `vendor/bin/`,
verify before finishing — no exceptions:

```sh
bash -n install.sh desktop.sh && bash install.sh --selftest
```

- `bash -n` — syntax check (catches the `printf`-format / quoting / heredoc
  class of errors that only fire at runtime). Run it on every file you touched.
- `bash install.sh --selftest` — validates the registries (`DE_*`/`APP_*`/
  `PROOT_*` array lengths match) and that required vendored files exist.

If `shellcheck` is installed, also run `shellcheck install.sh desktop.sh` for
deeper static analysis (unused vars, unquoted expansions, SC2086). Treat
`printf "...$var..."` (variable in format string) as a bug — pass via `%s`.

Do not report a shell change as done until both checks pass.
