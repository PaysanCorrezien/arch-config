# CLIProxyAPI

Central gateway enabled only on gpu. Installs the official Linux release 8.0.42,
verifies its release checksum, and runs `cliproxyapi.service` as the desktop user.
The listener binds to the host's Tailscale IPv4 address on port 8317, with separate
client and management keys. Join Tailscale before running the hook.

Run `dcli sync` for host gpu, or `dcli module run-hook cliproxyapi`.
Existing configuration, credentials and provider sessions are preserved. Repeated
syncs do not restart an unchanged service. Enable lingering once if the hook reports
it is disabled: `sudo loginctl enable-linger <user>`.

## Authentication

Open `http://gpu.tail66a3d.ts.net:8317/management.html`. The management key is in
`~/.config/cliproxyapi/credentials.json`; sign into providers in the management UI.
Alternatively run:

```sh
cli-proxy-api -config ~/.config/cliproxyapi/config.yaml -codex-device-login -no-browser
cli-proxy-api -config ~/.config/cliproxyapi/config.yaml -claude-login -no-browser
```

Configuration and secrets are generated under `~/.config/cliproxyapi` with private
permissions, never linked into this repository. Preserve that directory in private
backups. Account login and mobile pairing remain one-time interactive operations.
Usage statistics are in memory, not durable billing records.

## Clients and T3

The hook installs `claude-proxy` and `codex-proxy` under `~/.local/bin`. Existing
plain CLI settings are unchanged. In T3 provider settings use their absolute paths
as the binary paths, then start new sessions. These launchers have been exercised
against the live gpu gateway during initial setup.

For a remote client, copy only the launchers and a private `credentials.json`
containing its client key; do not copy provider OAuth files or the management key.
`CLIPROXY_CONFIG_DIR` overrides the credential directory and `CLIPROXY_BASE_URL`
overrides the gateway URL (without `/v1`). Install the provider CLIs separately.

Tailscale policy is managed in PaysanCorrezien/tailscale-acl. Allow client sources
to reach the gateway on TCP 8317. `tag:t3` controls T3 ports, not this gateway port.
The module does not alter tailnet policy, device tags, firewalls, or T3 services.
