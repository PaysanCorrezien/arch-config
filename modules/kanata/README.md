# Kanata

This module installs kanata, provides two configs, and adds a user service.

- `~/.config/kanata/kanata.kbd` auto-detects keyboards.
- `~/.config/kanata/kanata-by-id.kbd` pins to `/dev/input/by-id` paths.

To use the by-id config, update the device path(s) and change the service
ExecStart to point at `kanata-by-id.kbd`.
