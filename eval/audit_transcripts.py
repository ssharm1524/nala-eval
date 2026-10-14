#!/usr/bin/env python3
"""After a run, list every tool call that named a place the attempt must not reach.

    audit_transcripts.py TRANSCRIPTS_DIR [--allow TEXT ...]

The session settings deny these places, and this check shows whether the denial held.
The places come from eval/config.env, as in isolate.py.
A listed call is not proof of a leak: a refused call is listed too. Read each one.
Exit status 1 means at least one call is listed.
"""

from __future__ import annotations

import glob
import json
import os
import sys

import nala_config


def needles() -> list[str]:
    """Text that names a closed place: the source project and this harness by path and by
    GitHub name, the closed folders, every connector tool, and the outside services."""
    folders = [nala_config.path("NALA_SOURCE_REPO"), os.path.dirname(nala_config.HERE)]
    folders += nala_config.folders("NALA_CLOSED_FOLDERS")
    found = [os.path.join(folder, "") for folder in folders if folder]
    # A transcript may name a home folder as ~ or in full.
    home = os.path.expanduser("~")
    found += ["~" + item[len(home) :] for item in found if item.startswith(home + os.sep)]
    found += [name for name in (nala_config.get("NALA_SOURCE_NAME"), nala_config.get("NALA_HARNESS_NAME")) if name]
    found.append("mcp__")
    # Short command names match ordinary words, so the service marks are their own list.
    found += nala_config.words("NALA_AUDIT_MARKS", "railway supabase.co vercel")
    return sorted(set(found))


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    root = sys.argv[1]
    allowed = [sys.argv[i + 1] for i, arg in enumerate(sys.argv) if arg == "--allow"]
    closed = needles()
    hits = 0
    for path in sorted(glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True)):
        with open(path, errors="ignore") as handle:
            for number, line in enumerate(handle, 1):
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                content = (record.get("message") or {}).get("content")
                if record.get("type") != "assistant" or not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict) or block.get("type") != "tool_use":
                        continue
                    text = block.get("name", "") + " " + json.dumps(block.get("input", {}))
                    for item in allowed:
                        text = text.replace(item, "")
                    found = [needle for needle in closed if needle in text]
                    if found:
                        hits += 1
                        print(f"{os.path.relpath(path, root)}:{number}  {found}  {text[:300]}")
    print(f"tool calls that named a closed place: {hits}")
    return 1 if hits else 0


if __name__ == "__main__":
    raise SystemExit(main())
