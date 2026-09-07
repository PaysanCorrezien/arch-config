#!/usr/bin/env python3
"""Reconcile Hermes profile cron ownership and fail closed on broken jobs.

The root ~/.hermes/scripts directory remains the preserved runtime source for
the custom detectors. This guard installs a complete copy into each owning
profile, repairs the daily auditor's ledger scope, and validates every enabled
job before gateways are restarted.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import tempfile
from pathlib import Path

HOME = Path.home()
HERMES = HOME / ".hermes"
ROOT_SCRIPTS = HERMES / "scripts"
PROFILES = ("correzianlabs-manager", "repository-orchestrator", "marketing", "life")
PROFILE_SCRIPTS = {
    "correzianlabs-manager": ("host-state-manager.py",),
    "repository-orchestrator": (
        "hermes_loop_state.py",
        "chirac-classifier.py",
        "chirac-pr-queue.py",
        "github-pr-queue.py",
        "maria-pr-queue.py",
        "sentry-error-autofix.py",
        "brassens-electron-log-autofix.py",
        "brassens-pr-queue-detector.py",
    ),
    "marketing": ("hermes_loop_state.py", "competitor-analysis.py"),
    "life": (
        "hermes_loop_state.py",
        "nightly-issue-report.py",
        "nightly-issue-reconcile.py",
        "nightly-issue-approval-intake.py",
        "nightly-issue-launcher.py",
        "nightly-issue-codex-worker.py",
        "artificial-analysis-stt-monitor.py",
    ),
}

AUDIT_OLD = (
    "Inspect loop ledger state under `~/.hermes/loop-memory/<loop_id>/state.json` when relevant. "
    "Flag stale active claims, completed work that did not actually move/merge a PR, and mismatch "
    "between owning profile ledger and repository-orchestrator profile ledger."
)
AUDIT_NEW = (
    "Inspect ledger state only under the owning profile's "
    "`~/.hermes/profiles/<profile>/loop-memory/<loop_id>/state.json`. Root-level "
    "`~/.hermes/loop-memory` entries are legacy/default-profile state and must not be used to "
    "diagnose a specialist-owned job. Flag stale active claims in the owning ledger, completed "
    "work that did not actually advance/merge a PR or rerun failed infrastructure CI, and any "
    "runtime HERMES_HOME that disagrees with the job's logical profile owner."
)

STT_OLD = '''    playwright_cmd = shutil.which("npx") or shutil.which("npx.cmd") or shutil.which("npx.exe")
    if not playwright_cmd:
        raise RuntimeError("npx is required for Playwright page screenshots but was not found on PATH")
'''
STT_NEW = '''    configured = os.getenv("HERMES_PLAYWRIGHT_BIN")
    candidates = [
        Path(configured).expanduser() if configured else None,
        Path.home() / ".hermes" / "hermes-agent" / "node_modules" / ".bin" / "playwright",
    ]
    playwright_cmd = next((str(path) for path in candidates if path and path.is_file() and os.access(path, os.X_OK)), None)
    if not playwright_cmd:
        raise RuntimeError("pinned Hermes Playwright CLI is missing; run the Hermes module installer")
'''
STT_NPX_ARG = '''            playwright_cmd,
            "playwright",
            "screenshot",'''
STT_PINNED_ARG = '''            playwright_cmd,
            "screenshot",'''


def atomic_text(path: Path, content: str) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def patch_stt(*, apply: bool) -> bool:
    path = ROOT_SCRIPTS / "artificial-analysis-stt-monitor.py"
    source = path.read_text(encoding="utf-8")
    if STT_NEW in source and STT_PINNED_ARG in source:
        return False
    if STT_OLD not in source or STT_NPX_ARG not in source:
        raise SystemExit(f"cannot safely patch changed STT monitor: {path}")
    updated = source.replace(STT_OLD, STT_NEW, 1).replace(STT_NPX_ARG, STT_PINNED_ARG, 1)
    if apply:
        atomic_text(path, updated)
    return True


def copy_profile_scripts(*, apply: bool) -> int:
    copied = 0
    for profile, names in PROFILE_SCRIPTS.items():
        destination = HERMES / "profiles" / profile / "scripts"
        if apply:
            destination.mkdir(mode=0o700, parents=True, exist_ok=True)
        for name in names:
            source = ROOT_SCRIPTS / name
            if not source.is_file():
                raise SystemExit(f"missing required Hermes source script: {source}")
            target = destination / name
            changed = not target.exists() or source.read_bytes() != target.read_bytes()
            if changed:
                copied += 1
                if apply:
                    shutil.copy2(source, target)
    return copied


def repair_audit(*, apply: bool) -> bool:
    path = HERMES / "profiles" / "correzianlabs-manager" / "cron" / "jobs.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    changed = False
    for job in payload.get("jobs", []):
        if job.get("name") != "daily-agent-cron-behavior-audit":
            continue
        prompt = str(job.get("prompt") or "")
        if AUDIT_NEW in prompt:
            continue
        if AUDIT_OLD not in prompt:
            raise SystemExit("daily audit prompt changed; refusing an unsafe blind rewrite")
        job["prompt"] = prompt.replace(AUDIT_OLD, AUDIT_NEW, 1)
        changed = True
    if changed and apply:
        atomic_text(path, json.dumps(payload, indent=2) + "\n")
    return changed


def validate() -> list[str]:
    errors: list[str] = []
    enabled_names: dict[str, str] = {}
    registries = [("default", HERMES / "cron" / "jobs.json")]
    registries.extend((profile, HERMES / "profiles" / profile / "cron" / "jobs.json") for profile in PROFILES)
    for owner, path in registries:
        if not path.is_file():
            errors.append(f"missing registry: {path}")
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        for job in payload.get("jobs", []):
            if not job.get("enabled"):
                continue
            name = str(job.get("name") or job.get("id") or "unnamed")
            previous = enabled_names.get(name)
            if previous:
                errors.append(f"enabled job {name!r} has duplicate owners: {previous}, {owner}")
            enabled_names[name] = owner
            workdir = Path(str(job.get("workdir") or HERMES)).expanduser()
            if not workdir.is_dir():
                errors.append(f"{owner}/{name}: missing workdir {workdir}")
            script = str(job.get("script") or "")
            if script:
                script_path = Path(script).expanduser() if Path(script).is_absolute() else HERMES / ("scripts" if owner == "default" else f"profiles/{owner}/scripts") / script
                if not script_path.is_file():
                    errors.append(f"{owner}/{name}: missing script {script_path}")
            metadata = job.get("metadata") if isinstance(job.get("metadata"), dict) else {}
            logical_owner = metadata.get("logical_profile_owner")
            if owner != "default" and logical_owner != owner:
                errors.append(f"{owner}/{name}: logical owner is {logical_owner!r}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    stt_changed = patch_stt(apply=args.apply)
    copied = copy_profile_scripts(apply=args.apply)
    audit_changed = repair_audit(apply=args.apply)
    if args.apply:
        # Validate the resulting live tree, not the pre-change view.
        errors = validate()
    else:
        errors = []
    if errors:
        raise SystemExit("Hermes cron reliability validation failed:\n- " + "\n- ".join(errors))
    verb = "reconciled" if args.apply else "would reconcile"
    print(f"{verb} Hermes cron reliability: scripts={copied}, stt_patch={stt_changed}, audit_prompt={audit_changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
