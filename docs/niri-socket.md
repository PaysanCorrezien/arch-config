# Niri socket usage

If `niri msg` fails with "error connecting to the niri socket", set `NIRI_SOCKET` to the active socket under `/run/user/$UID`.

Example:

```sh
ls -1 /run/user/$UID/niri*.sock
NIRI_SOCKET=/run/user/$UID/niri.wayland-1.XXXXXXXX.sock niri msg windows
```

Tip: when running from scripts or other shells, export `NIRI_SOCKET` so all `niri msg` commands work without repeating it.
