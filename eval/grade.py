#!/usr/bin/env python3
"""Grade one eval run: lay the hidden tests over the run's result and run them.

    grade.py REPO REF OUT_DIR

REPO is a local clone of the run's scratch repository and REF is the commit to grade,
normally its main branch after the run ended. The script works in a fresh working copy
under OUT_DIR, so the run's own files are never changed.

A ticket passes when every one of its kept hidden tests passes. A ticket that is not
merged fails on its own, because its tests fail against a main branch without it.
The deciding score is the share of tickets that pass.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HIDDEN = os.path.join(HERE, "hidden-tests")


def run(*args: str, cwd: str | None = None, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=cwd, check=check, text=True, capture_output=True)


def test_results(xml_path: str, files: list[str]) -> tuple[dict[str, str], set[str]]:
    """Status by test id, and the files pytest could not load."""
    modules = {path[:-3].replace("/", "."): path for path in files}
    results: dict[str, str] = {}
    unloadable: set[str] = set()
    with open(xml_path) as handle:
        text = handle.read()
    for match in re.finditer(r"<testcase ([^>]*?)(/>|>(.*?)</testcase>)", text, re.S):
        attributes = dict(re.findall(r'(\w+)="([^"]*)"', match.group(1)))
        body = match.group(3) or ""
        if re.search(r"<(failure|error)\b", body):
            status = "fail"
        elif "<skipped" in body:
            status = "skip"
        else:
            status = "pass"
        classname, name = attributes.get("classname", ""), attributes.get("name", "")
        module = next(
            (
                key
                for key in sorted(modules, key=len, reverse=True)
                if classname == key or classname.startswith(key + ".")
            ),
            None,
        )
        if module is None:
            module = next((key for key in modules if name.replace("/", ".").startswith(key)), None)
            if module:
                unloadable.add(modules[module])
            continue
        owner = classname[len(module) :].lstrip(".").replace(".", "::")
        results[modules[module] + "::" + (owner + "::" if owner else "") + name] = status
    return results, unloadable


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    repo, ref, out = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3])
    with open(os.path.join(HIDDEN, "kept-frozen.json")) as handle:
        frozen = json.load(handle)
    with open(os.path.join(HIDDEN, "candidate-files.txt")) as handle:
        files = [line.strip() for line in handle if line.strip().endswith(".py")]

    os.makedirs(out, exist_ok=True)
    work = os.path.join(out, "graded-copy")
    if os.path.exists(work):
        print(f"{work} exists; give a fresh OUT_DIR", file=sys.stderr)
        return 2
    commit = run("git", "-C", repo, "rev-parse", "--verify", f"{ref}^{{commit}}").stdout.strip()
    run("git", "-C", repo, "worktree", "add", "--detach", work, commit)
    # The hidden files replace whatever the attempt wrote at the same paths.
    shutil.copytree(os.path.join(HIDDEN, "files"), work, dirs_exist_ok=True)

    run("uv", "sync", "--quiet", "--all-extras", "--directory", work, check=False)
    xml_path = os.path.join(out, "hidden-tests.xml")
    with open(os.path.join(out, "hidden-tests.log"), "w") as log:
        subprocess.run(
            [
                "uv", "run", "--directory", work, "pytest", *files,
                "-q", "-p", "no:cacheprovider", "--continue-on-collection-errors",
                f"--junitxml={xml_path}",
            ],
            stdout=log, stderr=subprocess.STDOUT, check=False,
        )  # fmt: skip
    if not os.path.exists(xml_path):
        print("pytest wrote no result file; see hidden-tests.log", file=sys.stderr)
        return 1
    results, unloadable = test_results(xml_path, files)

    tickets = {}
    for ticket in frozen["order"]:
        kept = frozen["kept"][str(ticket)]
        failed = [
            test
            for test in kept
            if test.split("::")[0] in unloadable or results.get(test) != "pass"
        ]
        tickets[str(ticket)] = {
            "kept": len(kept),
            "passed": len(kept) - len(failed),
            "ticket_passes": not failed,
            "failed_tests": failed,
        }
    passing = sum(1 for row in tickets.values() if row["ticket_passes"])
    report = {
        "graded_commit": commit,
        "tickets_passing": passing,
        "tickets_total": len(tickets),
        "share_passing": passing / len(tickets),
        "tickets": tickets,
        "unloadable_files": sorted(unloadable),
    }
    with open(os.path.join(out, "grade.json"), "w") as handle:
        json.dump(report, handle, indent=1)
    for ticket, row in tickets.items():
        mark = "pass" if row["ticket_passes"] else "FAIL"
        print(f"#{ticket}: {mark}  {row['passed']}/{row['kept']} kept tests")
    print(f"tickets passing: {passing} of {len(tickets)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
