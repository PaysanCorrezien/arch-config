#!/usr/bin/env python3
"""Prepare Hermes specialist profiles for the cron ownership cutover.

Reads Discord credentials only from an operator-supplied env bundle.  It never
prints or stores credentials in the dcli repository.
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import stat
import sys
import tempfile
from pathlib import Path

import yaml

HOME = Path.home()
HERMES_HOME = HOME / ".hermes"
DEFAULT_SCRIPTS = HERMES_HOME / "scripts"
DEFAULT_TOKEN_BUNDLE = HOME / "Téléchargements" / "discord-bot-tokens.env"
MANIFEST = Path(__file__).resolve().parents[1] / "profile-cron-split.yaml"

PROFILE_SCRIPTS = {
    "correzianlabs-manager": ["host-state-manager.py"],
    "repository-orchestrator": [
        "hermes_loop_state.py",
        "chirac-classifier.py",
        "chirac-pr-queue.py",
        "github-pr-queue.py",
        "maria-pr-queue.py",
        "sentry-error-autofix.py",
        "brassens-electron-log-autofix.py",
        "brassens-pr-queue-detector.py",
    ],
    "marketing": [
        "hermes_loop_state.py",
        "competitor-analysis.py",
    ],
    "life": [
        "hermes_loop_state.py",
        "nightly-issue-report.py",
        "nightly-issue-reconcile.py",
        "nightly-issue-approval-intake.py",
        "nightly-issue-launcher.py",
        "nightly-issue-codex-worker.py",
        "artificial-analysis-stt-monitor.py",
    ],
}


def parse_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value.strip().strip('"')
    return values


def replace_env_value(path: Path, key: str, value: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    replacement = f"{key}={value}"
    found = False
    output: list[str] = []
    for line in lines:
        if line.startswith(f"{key}="):
            output.append(replacement)
            found = True
        else:
            output.append(line)
    if not found:
        output.append(replacement)
    fd, temporary = tempfile.mkstemp(prefix=".env.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write("\n".join(output) + "\n")
        os.chmod(temporary, stat.S_IRUSR | stat.S_IWUSR)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def remove_env_value(path: Path, key: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    output = [line for line in lines if not line.startswith(f"{key}=")]
    fd, temporary = tempfile.mkstemp(prefix=".env.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write("\n".join(output) + "\n")
        os.chmod(temporary, stat.S_IRUSR | stat.S_IWUSR)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def reconcile_profile_model(profile: str, model: str) -> None:
    """Apply the manifest's model selection without rewriting unrelated config."""
    path = HERMES_HOME / "profiles" / profile / "config.yaml"
    if not path.is_file():
        raise SystemExit(f"missing profile configuration: {path}")
    source = path.read_text(encoding="utf-8")
    replacement = (
        "model:\n"
        "  base_url: ''\n"
        f"  default: {model}\n"
        "  openai_runtime: auto\n"
        "  provider: openai-codex\n"
    )
    updated, count = re.subn(
        r"\\Amodel:\\n.*?(?=^providers:)",
        replacement,
        source,
        count=1,
        flags=re.DOTALL | re.MULTILINE,
    )
    if count != 1:
        raise SystemExit(f"cannot locate model configuration in {path}")
    updated, no_thread_count = re.subn(
        r"^  no_thread_channels:.*$", "  no_thread_channels: ''", updated, count=1, flags=re.MULTILINE
    )
    if no_thread_count != 1:
        raise SystemExit(f"cannot locate Discord no_thread_channels in {path}")
    if updated != source:
        path.write_text(updated, encoding="utf-8")


def write_json(path: Path, payload: dict) -> None:
    fd, temporary = tempfile.mkstemp(prefix=".jobs.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def route_profile_cron_to_home(profile: str, home_channel_id: str) -> int:
    """Bind cron delivery to the owning Bot's channel, never an old shared thread."""
    path = HERMES_HOME / "profiles" / profile / "cron" / "jobs.json"
    if not path.is_file():
        return 0
    payload = json.loads(path.read_text(encoding="utf-8"))
    count = 0
    for job in payload.get("jobs", []):
        target = f"discord:{home_channel_id}"
        if job.get("deliver") != target:
            job["deliver"] = target
            job["last_delivery_error"] = None
            count += 1
    if count:
        payload["updated_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        write_json(path, payload)
    return count


def stage_cron(manifest: dict) -> None:
    """Move the validated default definitions into exactly one target registry.

    Cron's public CLI cannot round-trip per-job toolsets and metadata, so this
    migration retains the complete validated definitions in an atomic registry
    rewrite.  Every original registry is backed up first; target jobs remain
    disabled until their profile gateway is installed and ready.
    """
    source_path = HERMES_HOME / "cron" / "jobs.json"
    source_payload = json.loads(source_path.read_text(encoding="utf-8"))
    source_jobs = {job["name"]: job for job in source_payload.get("jobs", [])}
    expected = [job for spec in manifest["profiles"].values() for job in spec["jobs"]]
    if len(expected) != len(set(expected)) or set(expected) != set(source_jobs):
        raise SystemExit("manifest jobs must match the live default registry exactly")

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S")
    shutil.copy2(source_path, source_path.with_name(f"jobs.json.bak-profile-cutover-{stamp}"))
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    for profile, spec in manifest["profiles"].items():
        profile_path = HERMES_HOME / "profiles" / profile / "cron" / "jobs.json"
        profile_path.parent.mkdir(mode=0o700, exist_ok=True)
        if profile_path.exists():
            shutil.copy2(profile_path, profile_path.with_name(f"jobs.json.bak-profile-cutover-{stamp}"))
        jobs = []
        for name in spec["jobs"]:
            job = copy.deepcopy(source_jobs[name])
            job["enabled"] = False
            job["state"] = "paused"
            job["paused_at"] = now
            job["paused_reason"] = "profile-cutover staging"
            metadata = job.get("metadata") if isinstance(job.get("metadata"), dict) else {}
            metadata["logical_profile_owner"] = profile
            job["metadata"] = metadata
            jobs.append(job)
        write_json(profile_path, {"jobs": jobs, "updated_at": now})
    write_json(source_path, {"jobs": [], "updated_at": now})
    print(f"staged {len(expected)} jobs across {len(manifest['profiles'])} profiles; default registry is empty")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--token-bundle", type=Path, default=DEFAULT_TOKEN_BUNDLE)
    parser.add_argument("--apply", action="store_true", help="write profile .env files and copy required scripts")
    parser.add_argument("--stage-cron", action="store_true", help="stage the one-owner cron registry cutover")
    args = parser.parse_args()

    manifest = yaml.safe_load(MANIFEST.read_text(encoding="utf-8"))
    tokens = parse_env(args.token_bundle)
    selected: dict[str, str] = {}
    for profile, spec in manifest["profiles"].items():
        variable = spec["bot"]["discord_token_variable"]
        token = tokens.get(variable, "")
        if not token:
            raise SystemExit(f"missing non-empty {variable} for {profile}")
        selected[profile] = token
    if len(set(selected.values())) != len(selected):
        raise SystemExit("Discord tokens must be distinct across specialist profiles")

    for profile, token in selected.items():
        spec = manifest["profiles"][profile]
        profile_root = HERMES_HOME / "profiles" / profile
        env_file = profile_root / ".env"
        if not env_file.is_file():
            raise SystemExit(f"missing profile environment: {env_file}")
        missing = [script for script in PROFILE_SCRIPTS.get(profile, []) if not (DEFAULT_SCRIPTS / script).is_file()]
        if missing:
            raise SystemExit(f"missing source scripts for {profile}: {', '.join(missing)}")
        if args.apply:
            reconcile_profile_model(profile, spec["bot"]["model"])
            scripts_dir = profile_root / "scripts"
            scripts_dir.mkdir(mode=0o700, exist_ok=True)
            for script in PROFILE_SCRIPTS.get(profile, []):
                shutil.copy2(DEFAULT_SCRIPTS / script, scripts_dir / script)
            replace_env_value(env_file, "DISCORD_BOT_TOKEN", token)
            replace_env_value(env_file, "DISCORD_HOME_CHANNEL", spec["bot"]["home_channel_id"])
            # Dedicated Bot channels do not inherit a legacy shared thread.
            replace_env_value(env_file, "DISCORD_HOME_CHANNEL_THREAD_ID", "")
            home_channel = spec["bot"]["home_channel_id"]
            # A Bot speaks freely in its own channel, creating a task thread
            # there. It then follows only the threads it has joined below its
            # own channel or the shared agent-work forum. Other Bot threads
            # remain mention-only because they are not in this profile's
            # remembered-thread set.
            remove_env_value(env_file, "DISCORD_ALLOWED_CHANNELS")
            replace_env_value(env_file, "DISCORD_FREE_RESPONSE_CHANNELS", home_channel)
            replace_env_value(env_file, "DISCORD_REQUIRE_MENTION", "true")
            replace_env_value(env_file, "DISCORD_THREAD_REQUIRE_MENTION", "false")
            replace_env_value(
                env_file,
                "DISCORD_AUTO_REPLY_THREAD_PARENTS",
                ",".join((home_channel, manifest["discord_routing"]["global_intake_channel_id"])),
            )
            replace_env_value(env_file, "DISCORD_AUTO_THREAD", "true")
            replace_env_value(env_file, "DISCORD_AUTO_THREAD_FREE_RESPONSE_CHANNELS", home_channel)
            remove_env_value(env_file, "DISCORD_NO_THREAD_CHANNELS")
            rerouted = route_profile_cron_to_home(profile, home_channel)
            if rerouted:
                print(f"rerouted {rerouted} cron jobs for {profile} to its Discord home")
        fingerprint = hashlib.sha256(token.encode()).hexdigest()[:12]
        print(f"prepared {profile}: token={fingerprint}, scripts={len(PROFILE_SCRIPTS.get(profile, []))}")
    if args.stage_cron:
        if not args.apply:
            raise SystemExit("--stage-cron requires --apply")
        stage_cron(manifest)
    print("no credential values were written to the repository or stdout")
    return 0


if __name__ == "__main__":
    sys.exit(main())
