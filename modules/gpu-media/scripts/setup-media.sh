#!/usr/bin/env bash
# gpu-media: mount the 8TB "media8" disk and serve it with SFTPGo over Tailscale.
#
#   1. fstab entry (nofail) so the box still boots when the disk is absent.
#   2. docker.service drop-in ordering Docker after the mount.
#   3. SFTPGo container on 127.0.0.1 (restart: unless-stopped).
#   4. `tailscale serve` exposes anonymous WebDAV on tailnet :2022, SFTP on
#      :2023, and the authenticated SFTPGo web interface on :8080 —
#      no dependency on the tailnet IP existing when Docker starts, and nothing
#      reachable from the LAN. The serve config persists in tailscaled.
#
# SFTPGo remains available for authenticated SFTP and its web UI. A separate
# anonymous WebDAV service exposes the whole media disk to trusted tailnet
# devices without per-client credentials.
#
# Idempotent: safe to re-run (`dcli hooks run gpu-media`).
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISK_UUID="f3ed501d-415e-4269-b24d-4afde3730c0a"
MOUNT_POINT="/mnt/media8"
API="http://127.0.0.1:8080"
COMPOSE=(sudo docker compose -p sftpgo -f "${MODULE_DIR}/compose.yaml")

echo "=== gpu-media setup ==="

echo "[1/4] Mounting media8 at ${MOUNT_POINT}..."
sudo install -d "$MOUNT_POINT"
if ! grep -q "UUID=${DISK_UUID}" /etc/fstab; then
  printf '\n# 8TB media disk (arch-config gpu-media)\nUUID=%s %s ext4 defaults,noatime,nofail,x-systemd.device-timeout=30s 0 2\n' \
    "$DISK_UUID" "$MOUNT_POINT" | sudo tee -a /etc/fstab >/dev/null
  echo "  + fstab entry added"
fi
sudo systemctl daemon-reload
findmnt "$MOUNT_POINT" >/dev/null || sudo mount "$MOUNT_POINT"
echo "  ✓ $(findmnt -no SOURCE "$MOUNT_POINT") mounted at ${MOUNT_POINT}"

echo "[2/4] Ordering Docker after the mount..."
sudo install -Dm0644 "${MODULE_DIR}/systemd/docker.service.d/20-media8.conf" \
  /etc/systemd/system/docker.service.d/20-media8.conf
sudo systemctl daemon-reload
echo "  ✓ docker.service.d/20-media8.conf"

echo "[3/4] Starting SFTPGo..."
"${COMPOSE[@]}" up -d
for _ in $(seq 1 30); do
  if curl -fsS "${API}/healthz" >/dev/null 2>&1 &&\
    curl -fsS -X PROPFIND -H 'Depth: 0' http://127.0.0.1:8091/ >/dev/null 2>&1; then break; fi
  sleep 2
done
if ! curl -fsS "${API}/healthz" >/dev/null 2>&1; then
  echo "  ✗ SFTPGo did not become healthy"
  "${COMPOSE[@]}" logs --tail 30
  exit 1
fi
if ! curl -fsS -X PROPFIND -H 'Depth: 0' http://127.0.0.1:8091/ >/dev/null 2>&1; then
  echo "  ✗ Anonymous WebDAV did not become healthy"
  "${COMPOSE[@]}" logs --tail 30 webdav
  exit 1
fi
echo "  ✓ SFTPGo healthy on 127.0.0.1:2022 (SFTP) and 127.0.0.1:8080 (web)"
echo "  ✓ Anonymous WebDAV healthy on 127.0.0.1:8091"

echo "[4/4] Exposing SFTPGo on the tailnet..."
if ! tailscale ip -4 >/dev/null 2>&1; then
  echo "  ⚠ Tailscale is not authenticated yet; run 'tailscale up' and re-run this hook."
  exit 0
fi
# Port 2022 is intentionally HTTPS WebDAV rather than SFTP. The tailnet policy
# used by Homebot already permits this port, while standard HTTPS port 443 is
# not currently reachable from that device.
sudo tailscale serve --tcp 2022 off >/dev/null 2>&1 || true
sudo tailscale serve --bg --https 2022 http://127.0.0.1:8091 >/dev/null
# Keep :2022 for the existing WebDAV share. SFTP is raw SSH and therefore
# needs its own TCP port instead of an HTTPS serve listener.
sudo tailscale serve --bg --tcp 2023 tcp://127.0.0.1:2022 >/dev/null
sudo tailscale serve --bg --tcp 8080 tcp://127.0.0.1:8080 >/dev/null
# HTTPS with the tailnet's own certificate: WebDAV on 443 (maps as a network
# drive in Explorer/Finder/file apps, which want TLS for basic auth) and the
# web UI on 8443.
sudo tailscale serve --bg --https 443 http://127.0.0.1:8091 >/dev/null
sudo tailscale serve --bg --https 8443 http://127.0.0.1:8080 >/dev/null
# serve listens on the tailnet IP as normal kernel sockets, so the ssh module's
# default-deny ufw would drop remote peers. Open these ports on tailscale0 only.
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow in on tailscale0 to any port 443,2022,2023,8080,8443 proto tcp comment 'SFTPGo over Tailscale' >/dev/null
fi
ts_name="$(tailscale status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
echo "  ✓ WebDAV: https://${ts_name}:2022/  (anonymous read/write media drive)"
echo "  ✓ WebDAV: https://${ts_name}/  (also available where tailnet policy permits 443)"
echo "  ✓ SFTP:   sftp -P 2023 <user>@${ts_name}"
echo "  ✓ Web:    https://${ts_name}:8443/web/client"

# The setup page only answers 200 while no admin exists.
if [[ "$(curl -s -o /dev/null -w '%{http_code}' "${API}/web/admin/setup")" == "200" ]]; then
  echo ""
  echo "  → First run: create the admin at http://${ts_name}:8080/web/admin/setup"
  echo "    then add a user with home directory /srv/media8 and permission '*' on '/'."
fi

echo "=== gpu-media done ==="
