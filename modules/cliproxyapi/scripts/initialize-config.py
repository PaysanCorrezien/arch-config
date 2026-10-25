import json
import os
from pathlib import Path
import secrets
import sys


def initialize(directory, tailnet_ip):
    credentials_path = directory / "credentials.json"
    config_path = directory / "config.yaml"
    if config_path.exists() and not credentials_path.exists():
        raise SystemExit("Existing config has no credentials.json; reconcile its client and management keys manually.")
    if not credentials_path.exists():
        credentials = {name: secrets.token_hex(32) for name in ("management", "client")}
        with credentials_path.open("x") as output:
            json.dump(credentials, output, indent=2)
    if not config_path.exists():
        credentials = json.loads(credentials_path.read_text())
        config_path.write_text(
            "config-version: 8\n"
            f"server:\n  host: {json.dumps(tailnet_ip)}\n  port: 8317\n"
            "management:\n  allow-remote: true\n"
            f"  secret-key: {json.dumps(credentials['management'])}\n"
            "access:\n  api-keys:\n"
            f"    - {json.dumps(credentials['client'])}\n"
            f"oauth:\n  auth-dir: {json.dumps(str(directory / 'auth'))}\n"
            "routing:\n  strategy: fill-first\n  session-affinity: true\n"
            "observability:\n  usage:\n    usage-statistics-enabled: true\n"
        )
    for private_file in (credentials_path, config_path):
        private_file.chmod(0o600)


if __name__ == "__main__":
    os.umask(0o077)
    initialize(Path(sys.argv[1]), sys.argv[2])
