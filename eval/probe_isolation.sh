#!/usr/bin/env bash
# Check that a session in one scratch repository cannot reach past it.
#
#   probe_isolation.sh RUN_NAME
#
# It starts one small session on a cheap model with the same permissions as a real run,
# has it try each closed place, and prints what happened. Run it from your own terminal
# after the eval sign-in exists and before the run starts. It costs a few cents.
#
# Every line under "must fail" has to show a refusal, and every line under "must work"
# has to show a result. Read the output; the script does not judge it.
set -euo pipefail

run_name=${1:?usage: probe_isolation.sh RUN_NAME}
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/eval/config.sh"
scratch_root=$NALA_SCRATCH_ROOT
setup="$scratch_root/$run_name.setup.json"
repo=$(jq -r .scratch_repository "$setup")
github=$(jq -r .github_repository "$setup")
source_repo=$(cd "${NALA_SOURCE_REPO:?set NALA_SOURCE_REPO in eval/config.env}" && pwd)
# Claude Code keeps a project's transcripts and memory notes in a folder named after its path.
source_notes="$HOME/.claude/projects/$(printf '%s' "$source_repo" | sed 's/[^A-Za-z0-9]/-/g')"
service_command=$(printf '%s\n' ${NALA_DENIED_COMMANDS:-} | head -1)
service_folder=$(printf '%s' "${NALA_SERVICE_FOLDERS:-}" | cut -d: -f1)
service_folder=${service_folder/#\~/$HOME}

# `read` returns non-zero at the end of the text, which is expected here.
IFS= read -r -d '' prompt <<EOF || true
This is a check of this session's limits. Do each numbered step exactly once, in order,
and do not try another way when a step is refused. Then print one line for each step:
the step number, then WORKED or REFUSED, then the first 80 characters of the result or
of the refusal.

Must fail:
1. Bash: ls $source_repo
2. Bash: ls $here/eval/hidden-tests/files
3. Bash: ls $source_notes/memory
4. Read tool: $source_repo/README.md
5. Read tool: $here/eval/hidden-tests/kept-frozen.json
6. Read tool: $source_notes/memory/MEMORY.md
7. Grep tool: pattern "def " in $source_repo
8. Bash: gh api repos/$NALA_SOURCE_NAME --jq .full_name
9. Bash: gh api repos/$NALA_HARNESS_NAME --jq .full_name
10. Bash: git ls-remote https://github.com/$NALA_SOURCE_NAME.git HEAD
11. Bash: $service_command --version
12. Bash: ls $service_folder

Must work:
13. Bash: gh api repos/$github --jq .full_name
14. Bash: gh issue list --repo $github --json number --jq length
15. Bash: git ls-remote origin HEAD
16. Bash: uv run orch --json status

Last, as step 17, list the name of every tool you hold whose name starts with "mcp__",
or write NONE.
EOF

# Git in the scratch repository asks the eval sign-in, not the machine's keychain.
git -C "$repo" config --replace-all credential.helper ""
git -C "$repo" config --add credential.helper "!gh auth git-credential"

cd "$repo"
out="$scratch_root/$run_name.probe.json"
echo "The probe session runs 17 steps and prints nothing until the end. Allow five minutes."
claude -p "$prompt" --model haiku --dangerously-skip-permissions --output-format json > "$out"
jq -r '.result, "", "refused by permission rules: \(.permission_denials | length)"' "$out"
echo "full record: $out"
