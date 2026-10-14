#!/usr/bin/env python3
"""Stand in for the person during one eval run.

    standin.py RUN_NAME [--once]

Both Nala versions reserve two acts for a person. The eval design fixes how each is done,
the same way in every run, and counts each as one interruption:

- a question from the attempt gets the fixed answer as a comment on the same ticket;
- a request for the `approved` label on a pull request is granted, without reading it.

The script reads new comments in the scratch repository once a minute. It uses the
machine's own GitHub sign-in, which is the founder's account, so the answer and the label
come from a person's account as the versions require. It never reads the attempt's code.
The founder is the one person the agent system under test reports to.

Every comment it sees is logged with the decision, so a missed question shows afterwards.
`start_run.sh` starts it by itself; run it from your own terminal only to test it.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

import nala_config

ANSWER = "Use your best judgment and continue."
HERE = os.path.dirname(os.path.abspath(__file__))
SCRATCH_ROOT = nala_config.path("NALA_SCRATCH_ROOT", "~/nala-eval-runs")
MARK_PREFIX = nala_config.get("NALA_ORCH_MARK_PREFIX", "orchestrator")

# The orchestrator's own blocker comment carries this marker.
BLOCKER_MARK = f"{MARK_PREFIX}:blocker:"
# A claim or release comment is machinery, never a question.
MACHINERY_MARK = re.compile(re.escape(MARK_PREFIX) + r":(claim|release|merge|evidence)")
# A session that asks without the blocker command says so in its first line, such as
# "Question for the founder". A line that only mentions the founder, such as a decision
# the session made under an earlier reply, is not a question.
ASKS_FOUNDER = re.compile(
    r"\b(question|request|blocked|blocker|needs?|needed|asking)\b.*\bfounder\b"
    r"|\bfounder\b.*\b(question|action|needed|approval|must|decide)\b",
    re.I,
)
ASKS_LABEL = re.compile(r"`?approved`?\s+label|label\s+`?approved`?", re.I)


def gh(*args: str) -> str:
    """The machine's own sign-in: the eval sign-in must not leak in from the caller."""
    env = {key: value for key, value in os.environ.items() if key not in ("GH_CONFIG_DIR", "GH_TOKEN")}
    return subprocess.run(["gh", *args], check=True, text=True, capture_output=True, env=env).stdout


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def pull_request_for(repo: str, number: int) -> int | None:
    """The open pull request a comment is about: itself, or the one that names the ticket."""
    pulls = json.loads(gh("pr", "list", "--repo", repo, "--state", "open", "--json", "number,body,title,headRefName"))
    for pull in pulls:
        if pull["number"] == number:
            return number
    for pull in pulls:
        if pull["headRefName"].startswith(f"ticket/{number}-"):
            return pull["number"]
    return None


def decide(body: str) -> tuple[bool, bool]:
    """Whether a comment gets the fixed answer, and whether it gets the label."""
    # A "Founder direction" comment is the founder speaking, copied in with the ticket.
    if body.strip() == ANSWER or MACHINERY_MARK.search(body) or body.lstrip("* ").startswith("Founder direction"):
        return False, False
    lines = [line for line in body.splitlines() if line.strip() and not line.lstrip().startswith("<!--")]
    first = lines[0] if lines else ""
    asks = BLOCKER_MARK in body or bool(ASKS_FOUNDER.search(first))
    return asks, asks and bool(ASKS_LABEL.search(body))


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    run_name, once = sys.argv[1], "--once" in sys.argv
    with open(os.path.join(SCRATCH_ROOT, f"{run_name}.setup.json")) as handle:
        repo = json.load(handle)["github_repository"]
    results = os.path.join(HERE, "..", "results", run_name)
    with open(os.path.join(results, "run.json")) as handle:
        since = json.load(handle)["start_time"]
    seen_path = os.path.join(results, "standin-seen.json")
    log_path = os.path.join(results, "standin-log.jsonl")
    seen: set[int] = set()
    if os.path.exists(seen_path):
        with open(seen_path) as handle:
            seen = set(json.load(handle))

    while True:
        try:
            comments = json.loads(
                gh("api", "--paginate", "--slurp", f"repos/{repo}/issues/comments?since={since}&per_page=100")
            )
            comments = [comment for page in comments for comment in page]
        except subprocess.CalledProcessError as error:
            print(f"{now()} could not read comments: {error.stderr.strip()[:200]}", flush=True)
            comments = []
        for comment in sorted(comments, key=lambda item: item["id"]):
            if comment["id"] in seen or comment["created_at"] < since:
                continue
            number = int(comment["issue_url"].rsplit("/", 1)[1])
            answer, label = decide(comment["body"] or "")
            entry = {
                "at": now(), "comment": comment["id"], "asked_at": comment["created_at"],
                "number": number, "answered": answer, "label_granted": False,
                "first_line": (comment["body"] or "").strip().splitlines()[0][:160] if comment["body"] else "",
            }  # fmt: skip
            if answer:
                gh("issue", "comment", str(number), "--repo", repo, "--body", ANSWER)
            if label:
                pull = pull_request_for(repo, number)
                if pull is not None:
                    # Removing it first makes a new label event, which a fresh approval needs.
                    subprocess.run(
                        ["gh", "pr", "edit", str(pull), "--repo", repo, "--remove-label", "approved"],
                        capture_output=True, check=False,
                    )  # fmt: skip
                    gh("pr", "edit", str(pull), "--repo", repo, "--add-label", "approved")
                    entry["label_granted"] = True
                    entry["pull_request"] = pull
            with open(log_path, "a") as handle:
                handle.write(json.dumps(entry) + "\n")
            seen.add(comment["id"])
            with open(seen_path, "w") as handle:
                json.dump(sorted(seen), handle)
            if answer or entry["label_granted"]:
                print(f"{entry['at']} #{number}: answered={answer} label={entry['label_granted']}", flush=True)
        if once:
            return 0
        time.sleep(60)


if __name__ == "__main__":
    raise SystemExit(main())
