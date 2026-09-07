#!/usr/bin/env python3
"""Keep Hermes gateways on the documented model, routing, and session policy.

This deliberately changes only the root model block, the legacy Discord
no-thread exception, and non-secret Discord routing variables in ~/.hermes.
It preserves credentials, providers, sessions, and all unrelated settings.
"""

from __future__ import annotations

import json
import os
import re
import stat
import tempfile
from pathlib import Path

HERMES_HOME = Path.home() / ".hermes"
CONFIG = HERMES_HOME / "config.yaml"
ENV = HERMES_HOME / ".env"
PROFILE_CONFIGS = tuple(
    HERMES_HOME / "profiles" / profile / "config.yaml"
    for profile in ("correzianlabs-manager", "repository-orchestrator", "marketing", "life")
)
MARKETING_ENV = HERMES_HOME / "profiles" / "marketing" / ".env"
MARKETING_JOBS = HERMES_HOME / "profiles" / "marketing" / "cron" / "jobs.json"


def atomic_write(path: Path, content: str, mode: int | None = None) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        if mode is not None:
            os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def replace_env_value(path: Path, key: str, value: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    replacement = f"{key}={value}"
    found = False
    updated: list[str] = []
    for line in lines:
        if line.startswith(f"{key}="):
            updated.append(replacement)
            found = True
        else:
            updated.append(line)
    if not found:
        updated.append(replacement)
    content = "\n".join(updated) + "\n"
    if content != path.read_text(encoding="utf-8"):
        atomic_write(path, content, stat.S_IRUSR | stat.S_IWUSR)


def remove_env_value(path: Path, key: str) -> None:
    source = path.read_text(encoding="utf-8")
    content = "\n".join(line for line in source.splitlines() if not line.startswith(f"{key}=")) + "\n"
    if content != source:
        atomic_write(path, content, stat.S_IRUSR | stat.S_IWUSR)


def clear_legacy_no_thread_channels(path: Path) -> None:
    """Remove the legacy direct-reply exception from one gateway config."""
    source = path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r"^  no_thread_channels:.*$", "  no_thread_channels: ''", source, count=1, flags=re.MULTILINE
    )
    if count != 1:
        raise SystemExit(f"cannot locate Discord no_thread_channels in {path}")
    if updated != source:
        atomic_write(path, updated)


def disable_session_reset(path: Path) -> None:
    """Keep a Discord task thread's context until its normal compression policy."""
    source = path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r"(?ms)(^session_reset:\n.*?^  mode: )[^\n]+$", r"\1none", source, count=1
    )
    if count != 1:
        raise SystemExit(f"cannot locate session_reset mode in {path}")
    if updated != source:
        atomic_write(path, updated)


def reconcile_config() -> None:
    if not CONFIG.is_file():
        print(f"skipping default routing reconciliation: missing {CONFIG}")
        return
    source = CONFIG.read_text(encoding="utf-8")
    model = (
        "model:\n"
        "  base_url: ''\n"
        "  default: gpt-5.6-luna\n"
        "  openai_runtime: auto\n"
        "  provider: openai-codex\n"
    )
    updated, model_count = re.subn(
        r"\Amodel:\n.*?(?=^providers:)", model, source, count=1, flags=re.DOTALL | re.MULTILINE
    )
    if model_count != 1:
        raise SystemExit(f"cannot locate root model configuration in {CONFIG}")
    if updated != source:
        atomic_write(CONFIG, updated)
    clear_legacy_no_thread_channels(CONFIG)
    disable_session_reset(CONFIG)


def reconcile_profile_configs() -> None:
    for path in PROFILE_CONFIGS:
        if path.is_file():
            clear_legacy_no_thread_channels(path)
            disable_session_reset(path)


def reconcile_competitor_analysis() -> None:
    """Repair the Windows migration residue in Marketing's live loop contract."""
    if MARKETING_ENV.is_file():
        replace_env_value(MARKETING_ENV, "HERMES_COMPETITOR_DIR", str(HERMES_HOME / "competitor-analysis"))
    if not MARKETING_JOBS.is_file():
        return
    source = MARKETING_JOBS.read_text(encoding="utf-8")
    jobs = json.loads(source)
    for job in jobs.get("jobs", []):
        if job.get("name") != "competitor-analysis":
            continue
        prompt = str(job.get("prompt") or "")
        prompt = prompt.replace("/home/dylan/.hermes\\competitor-analysis", "/home/dylan/.hermes/competitor-analysis")
        prompt = prompt.replace("force-checks active watched pages with ,", "force-checks active watched pages with `node watcher.js changes --force`,")
        prompt = prompt.replace("Broad competitor baselines are generated with  and", "Broad competitor baselines are generated with `node watcher.js initial-analysis` and")
        job["prompt"] = prompt
        break
    updated = json.dumps(jobs, indent=2) + "\n"
    if updated != source:
        atomic_write(MARKETING_JOBS, updated, stat.S_IRUSR | stat.S_IWUSR)


def reconcile_env() -> None:
    if not ENV.is_file():
        print(f"skipping default Discord environment reconciliation: missing {ENV}")
        return
    home_channel = "1519636771401498649"
    values = {
        "DISCORD_FREE_RESPONSE_CHANNELS": home_channel,
        "DISCORD_REQUIRE_MENTION": "true",
        "DISCORD_THREAD_REQUIRE_MENTION": "false",
        "DISCORD_AUTO_THREAD": "true",
        "DISCORD_AUTO_THREAD_FREE_RESPONSE_CHANNELS": home_channel,
        "DISCORD_AUTO_REPLY_THREAD_PARENTS": f"{home_channel},1519977352388673687",
    }
    for key, value in values.items():
        replace_env_value(ENV, key, value)
    remove_env_value(ENV, "DISCORD_NO_THREAD_CHANNELS")


def main() -> int:
    reconcile_config()
    reconcile_profile_configs()
    reconcile_env()
    reconcile_competitor_analysis()
    print("reconciled Hermes model, Discord task-thread routing, and session retention")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
