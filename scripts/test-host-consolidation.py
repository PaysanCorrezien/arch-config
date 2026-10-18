#!/usr/bin/env python3
"""Exercise recovered startup and maintenance scripts without touching services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class HostConsolidation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.root), STATE=str(self.root),
                        PATH=f"{self.bin}:{os.environ['PATH']}")

    def fake(self, name, source):
        p = self.bin / name
        p.write_text(source)
        p.chmod(0o755)

    def run_script(self, relative, *args, **env):
        return subprocess.run(["bash", str(REPO / relative), *args],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def test_launcher_reuses_persistent_sessions_and_existing_terminals(self):
        for repo in ["brassens-monorepo", "chirac"]:
            (self.root / "code" / repo).mkdir(parents=True)
        self.fake("tmux", """#!/usr/bin/env python3
import os,sys,json
from pathlib import Path
r=Path(os.environ['STATE']);a=sys.argv[1:]
with (r/'calls').open('a') as f:f.write(json.dumps(a)+'\\n')
if a[0]=='has-session':sys.exit(0 if (r/a[2].lstrip('=')).exists() else 1)
if a[0]=='new-session':(r/a[a.index('-s')+1]).touch()
if a[0]=='list-clients' and os.environ.get('ATTACHED'):print('123')
""")
        self.fake("systemctl", "#!/bin/sh\nexit 1\n")
        self.fake("systemd-run", "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$STATE/units\"\n")
        self.fake("pgrep", "#!/bin/sh\n[ -n \"$CHATGPT_RUNNING\" ]\n")
        self.fake("chatgpt", "#!/bin/sh\nexit 99\n")
        launcher = "modules/devbox-agent-workspaces/dotfiles/bin/devbox-agent-workspaces"
        first = self.run_script(launcher)
        self.assertEqual(first.returncode, 0, first.stderr)
        calls = [json.loads(x) for x in (self.root / "calls").read_text().splitlines()]
        created = [x for x in calls if x[0] == "new-session"]
        self.assertEqual(len(created), 2)
        self.assertIn("--continue --remote-control", created[0][-1])
        units = (self.root / "units").read_text()
        self.assertIn("attach-session", units)
        self.assertIn("Restart=on-failure", units)
        self.assertIn(str(self.bin / "chatgpt"), units)
        second = self.run_script(launcher, ATTACHED="1", CHATGPT_RUNNING="1")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual((self.root / "units").read_text(), units)
        calls = [json.loads(x) for x in (self.root / "calls").read_text().splitlines()]
        self.assertEqual(sum(x[0] == "new-session" for x in calls), 2)

    def test_rotation_only_removes_old_matching_directories(self):
        names = ["20261010-120000", "20261011-120000", "20261012-120000"]
        for name in names + ["important-unrelated-folder"]:
            (self.root / name).mkdir()
        (self.root / "20261009-120000").write_text("matching file must survive")
        script = "modules/auth-local-services/bin/deploy-backup-rotate"
        dry = self.run_script(script, DIR=str(self.root), KEEP="1")
        self.assertEqual(dry.returncode, 0, dry.stderr)
        self.assertTrue((self.root / names[0]).exists())
        applied = self.run_script(script, "--apply", DIR=str(self.root), KEEP="1")
        self.assertEqual(applied.returncode, 0, applied.stderr)
        self.assertFalse((self.root / names[0]).exists())
        self.assertTrue((self.root / names[-1]).exists())
        self.assertTrue((self.root / "important-unrelated-folder").exists())
        self.assertTrue((self.root / "20261009-120000").is_file())
        invalid = self.run_script(script, "--apply", DIR=str(self.root), KEEP="-1")
        self.assertNotEqual(invalid.returncode, 0)
        self.assertTrue((self.root / names[-1]).exists())

    def test_allocation_guard_stops_if_inspection_fails(self):
        self.fake("btrfs", """#!/bin/sh
case "$*" in
  'filesystem usage -b /') exit 1 ;;
  *) echo unexpected > "$STATE/unexpected"; exit 1 ;;
esac
""")
        result = self.run_script("modules/auth-local-services/bin/btrfs-alloc-guard")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no balance attempted", result.stdout)
        self.assertFalse((self.root / "unexpected").exists())

    def test_homebot_existing_mount_never_formats(self):
        self.fake("mountpoint", "#!/bin/sh\nexit 0\n")
        self.fake("findmnt", "#!/bin/sh\necho '/dev/sda2[/@data] btrfs'\n")
        self.fake("sudo", "#!/bin/sh\necho unexpected > \"$STATE/unexpected\"; exit 1\n")
        result = self.run_script("modules/homebot-data-disk/scripts/setup-data-disk.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "unexpected").exists())


if __name__ == "__main__":
    unittest.main()
