#!/usr/bin/env python3
"""Export active KDE global shortcuts for the Quickshell overlay."""

from __future__ import annotations

import configparser
import json
import os
from pathlib import Path


def desktop_name(desktop_id: str) -> str:
    search_roots = (
        Path.home() / ".local/share/applications",
        Path.home() / ".local/share/kglobalaccel",
        Path("/usr/local/share/applications"),
        Path("/usr/share/applications"),
    )
    for root in search_roots:
        path = root / desktop_id
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                if line.startswith("Name="):
                    return line.partition("=")[2].strip()
        except OSError:
            continue
    return desktop_id.removesuffix(".desktop").replace("-", " ").title()


def main() -> None:
    config_path = Path(os.environ.get("KGLOBALSHORTCUTS_FILE", Path.home() / ".config/kglobalshortcutsrc"))
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    parser.read(config_path, encoding="utf-8")

    entries: list[dict[str, str]] = []
    for section in parser.sections():
        friendly_name = parser.get(section, "_k_friendly_name", fallback="").strip()
        service_id = ""
        if section.startswith("services]["):
            service_id = section[len("services][") :]
            category = "Applications"
        else:
            category = friendly_name or section.strip("[]")

        for action_id, value in parser.items(section):
            if action_id == "_k_friendly_name":
                continue

            fields = value.split(",", 2)
            active_keys = fields[0].strip() if fields else ""
            if not active_keys or active_keys.casefold() in {"none", "disabled"}:
                continue

            description = fields[2].strip() if len(fields) > 2 else ""
            if service_id:
                label = desktop_name(service_id)
                if action_id != "_launch":
                    label = f"{label}: {description or action_id}"
                elif description:
                    label = description
            else:
                label = description or action_id.replace("_", " ").strip().capitalize()

            entries.append(
                {
                    "category": category,
                    "keys": "  /  ".join(
                        part.strip()
                        for part in active_keys.replace("\\t", "\t").split("\t")
                        if part.strip()
                    ),
                    "label": label,
                }
            )

    entries.sort(key=lambda item: (item["category"].casefold(), item["label"].casefold(), item["keys"].casefold()))
    print(json.dumps({"shortcuts": entries}, ensure_ascii=False))


if __name__ == "__main__":
    main()
