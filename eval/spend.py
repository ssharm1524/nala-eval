#!/usr/bin/env python3
"""Report what one eval run spent, from its run record and the Claude Code transcripts.

    spend.py RUN_RECORD.json [--transcripts DIR] [--prices PRICES.json] [--json]

The run record lists the session ids of the run. For each session the script finds the
root transcript and its helper transcripts, and reports tokens by model and dollars.

Dollars come from Claude Code's own cost record when the transcript has one, because it
includes billed calls that the transcript never logs. Without one, dollars are priced
from the logged requests with PRICES.json and marked "estimated"; that figure runs about
11% low. With neither, the script reports tokens only.

The batch total is the score. A per-session line is information only.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from collections import defaultdict
from datetime import datetime

TOKEN_KINDS = ("input", "output", "cache_read", "cache_write")


def read_lines(path: str):
    with open(path, errors="ignore") as handle:
        for line in handle:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def find_root(session_id: str, roots: list[str]) -> str | None:
    for root in roots:
        hits = glob.glob(os.path.join(root, "**", f"{session_id}.jsonl"), recursive=True)
        hits = [hit for hit in hits if f"{os.sep}subagents{os.sep}" not in hit]
        if hits:
            return hits[0]
    return None


def logged_usage(paths: list[str]) -> dict[str, dict[str, int]]:
    """Tokens by model. Claude Code logs one line per content block of a response, all with
    one request id and a growing output count, so only the highest line per request counts."""
    best: dict[str, tuple[str, dict]] = {}
    for path in paths:
        for record in read_lines(path):
            message = record.get("message") or {}
            usage = message.get("usage")
            model = message.get("model")
            if record.get("type") != "assistant" or not usage or model in (None, "<synthetic>"):
                continue
            key = record.get("requestId") or message.get("id") or record.get("uuid")
            held = best.get(key)
            if held is None or usage.get("output_tokens", 0) >= held[1].get("output_tokens", 0):
                best[key] = (model, usage)
    totals: dict[str, dict[str, int]] = defaultdict(lambda: dict.fromkeys(TOKEN_KINDS, 0))
    for model, usage in best.values():
        row = totals[model]
        row["input"] += usage.get("input_tokens", 0)
        row["output"] += usage.get("output_tokens", 0)
        row["cache_read"] += usage.get("cache_read_input_tokens", 0)
        row["cache_write"] += usage.get("cache_creation_input_tokens", 0)
    return dict(totals)


def cost_record(root: str) -> dict | None:
    last = None
    for record in read_lines(root):
        if record.get("type") == "cost-state":
            last = record
    return last


def priced(usage: dict[str, dict[str, int]], prices: dict) -> float | None:
    """Dollars at list price, or None when a model has no price."""
    total = 0.0
    for model, row in usage.items():
        rate = prices.get(model)
        if rate is None:
            return None
        total += sum(row[kind] * rate[kind] for kind in TOKEN_KINDS) / 1_000_000
    return total


def session_report(session_id: str, roots: list[str], prices: dict) -> dict:
    root = find_root(session_id, roots)
    if root is None:
        return {"session": session_id, "found": False}
    helpers = sorted(glob.glob(os.path.join(root[: -len(".jsonl")], "subagents", "*.jsonl")))
    usage = logged_usage([root, *helpers])
    record = cost_record(root)
    report = {
        "session": session_id,
        "found": True,
        "helpers": len(helpers),
        "logged_tokens": usage,
    }
    if record is not None:
        report["dollars"] = record.get("totalCostUSD")
        report["dollars_source"] = "cost record"
        report["dollars_by_model"] = {
            model: row.get("costUSD") for model, row in (record.get("modelUsage") or {}).items()
        }
    else:
        estimate = priced(usage, prices)
        report["dollars"] = estimate
        report["dollars_source"] = "estimated" if estimate is not None else "unknown"
    return report


def hours_between(start: str | None, end: str | None) -> float | None:
    if not start or not end:
        return None
    parse = lambda text: datetime.fromisoformat(text.replace("Z", "+00:00"))  # noqa: E731
    return (parse(end) - parse(start)).total_seconds() / 3600


def wall_hours(run: dict) -> float | None:
    """Start to end, less each recorded pause, such as a machine that slept."""
    total = hours_between(run.get("start_time"), run.get("end_time"))
    if total is None:
        return None
    return total - sum(hours_between(p["from"], p["to"]) or 0 for p in run.get("pauses", []))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("run_record")
    parser.add_argument(
        "--transcripts",
        action="append",
        help="folder to search for transcripts; default is the run's results folder, "
        "then ~/.claude/projects",
    )
    parser.add_argument("--prices", help="JSON: model -> dollars per million tokens by kind")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    with open(args.run_record) as handle:
        run = json.load(handle)
    roots = args.transcripts or [
        os.path.join(os.path.dirname(os.path.abspath(args.run_record)), "transcripts"),
        os.path.expanduser("~/.claude/projects"),
    ]
    prices = {}
    if args.prices:
        with open(args.prices) as handle:
            prices = json.load(handle)

    sessions = [session_report(sid, roots, prices) for sid in run.get("session_ids", [])]
    known = [s["dollars"] for s in sessions if s.get("dollars") is not None]
    complete = len(known) == len(sessions) and all(s["found"] for s in sessions)
    tokens: dict[str, dict[str, int]] = defaultdict(lambda: dict.fromkeys(TOKEN_KINDS, 0))
    for session in sessions:
        for model, row in session.get("logged_tokens", {}).items():
            for kind in TOKEN_KINDS:
                tokens[model][kind] += row[kind]
    result = {
        "run_id": run.get("run_id"),
        "nala_version": run.get("nala_version"),
        "dollars": sum(known) if complete else None,
        "dollars_complete": complete,
        "dollars_sources": sorted({s.get("dollars_source", "missing") for s in sessions}),
        "wall_hours": wall_hours(run),
        "paused_hours": sum(hours_between(p["from"], p["to"]) or 0 for p in run.get("pauses", [])),
        "usage_limit_wait_hours": run.get("usage_limit_wait_hours"),
        "logged_tokens": dict(tokens),
        "sessions": sessions,
    }
    if args.json:
        json.dump(result, sys.stdout, indent=1)
        print()
        return 0
    print(f"run {result['run_id']}  Nala {result['nala_version']}")
    dollars = "unknown" if result["dollars"] is None else f"${result['dollars']:.2f}"
    print(f"dollars: {dollars}  ({', '.join(result['dollars_sources'])})")
    if result["wall_hours"] is not None:
        print(f"wall time: {result['wall_hours']:.2f} hours")
    for model, row in sorted(tokens.items()):
        print(f"  {model}: " + ", ".join(f"{kind} {row[kind]:,}" for kind in TOKEN_KINDS))
    for session in sessions:
        if not session["found"]:
            print(f"  session {session['session']}: transcript not found")
            continue
        amount = session.get("dollars")
        shown = "unknown" if amount is None else f"${amount:.2f}"
        print(
            f"  session {session['session']}: {shown} "
            f"({session['dollars_source']}), {session['helpers']} helpers"
        )
    return 0 if complete else 1


if __name__ == "__main__":
    raise SystemExit(main())
