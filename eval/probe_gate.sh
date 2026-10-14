#!/usr/bin/env bash
# Check that a session in one scratch repository can run the merge check's own tools.
#
#   probe_gate.sh RUN_NAME STEPS_FILE
#
# The merge check runs on this machine, because a scratch repository has no hosted checks.
# The session sandbox can stop a tool the check needs, for example a test runner that
# keeps state in a home folder, or a scanner that installs itself. This probe has one
# small session run each such tool, so a sandbox fault shows before a scored run, not in it.
#
# STEPS_FILE holds one shell command per line; REPO in a command is replaced by the scratch
# repository's path. gate-probe-steps.example.txt shows the form. Each step should exit 0.
# A last step that reads a closed folder should be refused.
#
# Run it from your own terminal before the run starts. Allow 20 minutes.
set -euo pipefail

run_name=${1:?usage: probe_gate.sh RUN_NAME STEPS_FILE}
steps_file=${2:?usage: probe_gate.sh RUN_NAME STEPS_FILE}
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/eval/config.sh"
scratch_root=$NALA_SCRATCH_ROOT
repo=$(jq -r .scratch_repository "$scratch_root/$run_name.setup.json")

steps=""
number=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  number=$((number + 1))
  steps+="$number. Bash: $line"$'\n'
done < "$steps_file"

IFS= read -r -d '' prompt <<PROMPT || true
This is a check of this session's tools. Do each numbered step exactly once, in order,
as written. Give each Bash call a timeout of 600000 milliseconds. Do not
try another way when a step fails. Then print one line for each step: the step number,
the exit status, and the last 150 characters of the output.

$steps
PROMPT
# A Bash call keeps the folder of the call before it, so each step names its own.
prompt=${prompt//REPO/$repo}

cd "$repo"
out="$scratch_root/$run_name.gate-probe.json"
echo "The probe runs $number steps and prints nothing until the end. Allow 20 minutes."
claude -p "$prompt" --model haiku --dangerously-skip-permissions --output-format json > "$out"
jq -r .result "$out"
echo "full record: $out"
