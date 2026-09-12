# Devbox keyboard shortcuts helper

This module installs Quickshell and a small searchable popup for the global
shortcuts configured by KDE Plasma. It reads `~/.config/kglobalshortcutsrc`
each time it opens, so shortcut changes appear without keeping a second list in
the repository. Desktop-entry names are used to label the host's app shortcuts.

Press **Meta+Shift+K** to open the viewer. Press **Escape** or click **Close**
to dismiss it.

The data adapter is intentionally limited to Plasma global shortcuts. It does
not enumerate shortcuts internal to individual applications.
