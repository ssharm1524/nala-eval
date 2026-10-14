#!/usr/bin/env python3
"""Close one scratch repository off from the rest of this machine.

    isolate.py REPO GH_CONFIG_DIR [OTHER_RUN_REPO ...]

An eval attempt must not see the real fixes, the hidden tests, an earlier run, or any
signed-in outside service. This script edits the tracked `.claude/settings.json` of the
scratch repository, so every session there gets the same limits: the main session, each
ticket's working copy, and each helper.

It is a guard against an attempt that looks around the disk for context, not a security
boundary. `audit_transcripts.py` checks after the run that nothing reached past it.
The closed places come from eval/config.env (see config.example.env).
"""

from __future__ import annotations

import json
import os
import sys

import nala_config

HOME = os.path.expanduser("~")
SOURCE_REPO = nala_config.path("NALA_SOURCE_REPO")
# This harness's own folder holds the hidden tests and the earlier results.
HARNESS = os.path.dirname(nala_config.HERE)

# Folders that hold the real fixes, the hidden tests, or notes written while making them.
CLOSED_FOLDERS = [folder for folder in (SOURCE_REPO, HARNESS) if folder] + nala_config.folders(
    "NALA_CLOSED_FOLDERS"
)
# Sign-in folders of the outside services.
SERVICE_FOLDERS = nala_config.folders("NALA_SERVICE_FOLDERS")
# The command line tools of the outside services. The address list below does not hold
# when a session runs without permission prompts, so these deny rules are the real stop.
DENIED_COMMANDS = nala_config.words("NALA_DENIED_COMMANDS")
# Outside services the product uses. Docker serves image layers from a
# cloudflare.docker.com address, so a mark must not match that one.
SERVICE_DOMAIN_MARKS = tuple(nala_config.words("NALA_SERVICE_DOMAIN_MARKS"))
# Commands that run outside the sandbox. An attempt needs these three only.
KEPT_UNSANDBOXED = {"gh", "docker", "kill *"}


def home_form(path: str) -> str:
    path = os.path.abspath(os.path.expanduser(path))
    return "~" + path[len(HOME) :] if path.startswith(HOME + os.sep) else path


def read_rule(path: str) -> str:
    """Permission rules take `~/` for home and `//` for an absolute path."""
    return f"Read({path if path.startswith('~') else '/' + path}/**)"


def slug(folder: str) -> str:
    """Claude Code keeps transcripts and memory notes in a folder named after the project
    path, with every character that is not a letter or a digit replaced by "-"."""
    return "".join(char if char.isalnum() else "-" for char in os.path.abspath(os.path.expanduser(folder)))


def project_notes(repo: str) -> list[str]:
    """The notes folders of a repository and of its working copies, which live in hidden
    folders inside it (".worktrees/x" becomes "--worktrees-x"). An exact name, not a
    prefix, so a neighbour such as "repo-runs" stays open."""
    return [f"~/.claude/projects/{slug(repo)}", f"~/.claude/projects/{slug(repo)}--*"]


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    if not SOURCE_REPO:
        print("NALA_SOURCE_REPO is not set; see eval/config.example.env", file=sys.stderr)
        return 2
    repo, gh_config, others = sys.argv[1], sys.argv[2], sys.argv[3:]
    path = os.path.join(repo, ".claude", "settings.json")
    with open(path) as handle:
        settings = json.load(handle)

    denied = [home_form(folder) for folder in CLOSED_FOLDERS + SERVICE_FOLDERS]
    denied += [notes for folder in CLOSED_FOLDERS for notes in project_notes(folder)]
    for other in others:
        denied += [home_form(other), *project_notes(other)]

    permissions = settings.setdefault("permissions", {})
    deny = permissions.setdefault("deny", [])
    command_rules = [f"Bash({tool}{rest})" for tool in DENIED_COMMANDS for rest in ("", " *")]
    command_rules += [f"Bash(npx {tool} *)" for tool in DENIED_COMMANDS]
    for rule in ["mcp__*", *command_rules, *(read_rule(entry) for entry in denied)]:
        if rule not in deny:
            deny.append(rule)

    sandbox = settings.setdefault("sandbox", {})
    files = sandbox.setdefault("filesystem", {})
    deny_read = files.setdefault("denyRead", [])
    for entry in denied:
        if entry not in deny_read:
            deny_read.append(entry)
    # The version's settings come from the source project, so they may grant writes into
    # it or into a service sign-in folder. Those grants go.
    source_marks = (home_form(SOURCE_REPO), slug(SOURCE_REPO))
    service_forms = {home_form(folder) for folder in SERVICE_FOLDERS}
    files["allowWrite"] = [
        entry
        for entry in files.get("allowWrite", [])
        if not any(mark in entry for mark in source_marks) and entry not in service_forms
    ]
    # A ticket's working copy writes the run record and its notes in the main checkout.
    wanted = [home_form(os.path.join(repo, "state")), f"~/.claude/projects/{slug(repo)}/memory"]
    # A session that starts in a working copy cannot create the next working copy without
    # the main checkout's Git folder and working-copy folder, and the package cache.
    wanted += [home_form(os.path.join(repo, ".git")), home_form(os.path.join(repo, ".worktrees")), "~/.npm"]
    # The merge check runs on this machine, because the scratch repository has no hosted
    # checks. Tools it runs may keep state or install themselves in these folders.
    wanted += [home_form(folder) for folder in nala_config.folders("NALA_EXTRA_WRITABLE")]
    files["allowWrite"] += [entry for entry in wanted if entry not in files["allowWrite"]]
    network = sandbox.setdefault("network", {})
    # A file watcher used by a JavaScript test runner talks over this socket.
    sockets = network.setdefault("allowUnixSockets", [])
    watcher = f"~/.local/state/watchman/{os.path.basename(HOME)}-state/sock"
    if watcher not in sockets:
        sockets.append(watcher)
    network["allowedDomains"] = [
        domain
        for domain in network.get("allowedDomains", [])
        if not any(mark in domain for mark in SERVICE_DOMAIN_MARKS)
    ]
    sandbox["excludedCommands"] = [
        command for command in sandbox.get("excludedCommands", []) if command in KEPT_UNSANDBOXED
    ]

    settings["disableClaudeAiConnectors"] = True
    env = settings.setdefault("env", {})
    env["ENABLE_CLAUDEAI_MCP_SERVERS"] = "false"
    env["GH_CONFIG_DIR"] = os.path.abspath(os.path.expanduser(gh_config))
    # The Expo command line keeps its settings, and the account sign-in, in ~/.expo. That
    # folder stays closed; the tool gets an empty settings folder inside the run record
    # folder instead. Harmless when the source project does not use Expo.
    env["__UNSAFE_EXPO_HOME_DIRECTORY"] = os.path.join(os.path.abspath(repo), "state", "expo-home")
    env["EXPO_NO_TELEMETRY"] = "1"

    with open(path, "w") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
