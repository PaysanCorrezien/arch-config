# T3 Code on a host

This module installs the T3 Code desktop package and its CLI runtime, then
enables the official per-user systemd service. On Linux, T3's service setup
enables user lingering so the server can start at boot and keep running after
logout. The service binds to loopback; pairing through Tailscale Serve provides
the tailnet-only HTTPS endpoint.

To deploy on another configured host, add `t3code` to that host's
`enabled_modules` in `hosts/<host>.yaml`, then run the normal dcli install or
sync for that host. The host needs systemd, an authenticated Tailscale client,
and at least one installed and authenticated coding-agent provider.

After the service is running, mint a one-time pairing link on that host:

```sh
npx --yes t3@latest pair --tailscale --label "$(hostname)" --ttl 30m
```

The command configures the persistent Tailscale Serve route and prints the
pairing token and URL. Treat the token as a password and share it only with the
device being paired. T3 Code's current provider and Node.js requirements are
documented in the upstream [install guide](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md).
