#!/usr/bin/env bash
# Start one eval run, wait for it to end, then grade it and report its spend.
#
#   start_run.sh RUN_NAME [TICKET_NUMBER ...]
#
# RUN_NAME is a run that setup_scratch.sh built with --github. Ticket numbers are the
# scratch repository's own (1, 2, 3, ...) and limit a v1.9 run to those tickets, for a
# trial. A v1.8 run always works every ticket it finds eligible.
#
# Two versions are built in. v1.8 is a swarm: its start script opens a Lead session in a
# tmux session, and the Lead starts worker sessions. Any other version runs as one headless
# main session that starts its own helpers, given the /process-batch command.
#
# Run this from your own terminal with no other agent work on the machine. An agent
# session cannot start it: the session's sandbox cannot renew the Claude sign-in.
#
# The run ends when the version's main session ends, when no ticket is in progress and
# none can start, or at the time cap (24 hours; NALA_EVAL_CAP_SECONDS overrides it).
#
# It also starts the stand-in for a person (standin.py), which gives the fixed answer to a
# question and grants the approval label. A v1.9 main session that exited on blocked
# tickets continues in the same session after the stand-in answers.
set -euo pipefail

run_name=${1:?usage: start_run.sh RUN_NAME [TICKET_NUMBER ...] | start_run.sh RUN_NAME --resume}
shift
# --resume continues a v1.9 run whose launcher died, for example because the machine slept.
# The time between the last log line and the resume is recorded as a pause and left out
# of the run's wall time.
resume=""
if [ "${1:-}" = "--resume" ]; then resume=1; shift; fi
tickets=("$@")

here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/eval/config.sh"
scratch_root=$NALA_SCRATCH_ROOT
setup="$scratch_root/$run_name.setup.json"
[ -f "$setup" ] || { echo "no setup record at $setup; run setup_scratch.sh first" >&2; exit 1; }
field() { jq -r ".$1" "$setup"; }
repo=$(field scratch_repository)
version=$(field nala_version)
github=$(field github_repository)
[ "$github" != null ] || { echo "$run_name was built without --github" >&2; exit 1; }
results="$here/results/$run_name"
if [ -z "$resume" ]; then
  [ ! -e "$results/run.json" ] || { echo "$results/run.json exists; this run already started" >&2; exit 1; }
else
  [ -e "$results/run.json" ] || { echo "$run_name never started; start it without --resume" >&2; exit 1; }
  case "$version" in v1.8*) echo "--resume is for a v1.9 run only" >&2; exit 1 ;; esac
fi
cap=${NALA_EVAL_CAP_SECONDS:-86400}
tmux_session="nala-eval"

# 1. The sign-in the attempt uses must reach the scratch repository and nothing else.
export GH_CONFIG_DIR
GH_CONFIG_DIR=$(field github_sign_in_folder)
gh api "repos/$github" --jq .full_name >/dev/null \
  || { echo "the eval sign-in in $GH_CONFIG_DIR cannot reach $github" >&2; exit 1; }
for closed in ${NALA_SOURCE_NAME:?set NALA_SOURCE_NAME in eval/config.env} ${NALA_HARNESS_NAME:?set NALA_HARNESS_NAME in eval/config.env}; do
  if gh api "repos/$closed" --jq .full_name >/dev/null 2>&1; then
    echo "the eval sign-in can reach $closed; narrow the token to the scratch repository" >&2
    exit 1
  fi
done
# Git in the scratch repository asks the same sign-in, not the machine's keychain.
git -C "$repo" config --replace-all credential.helper ""
git -C "$repo" config --add credential.helper "!gh auth git-credential"

# The product's tests start their database in a Docker container. A hung engine accepts a
# connection and never answers, so the check has its own time limit.
docker info --format '{{.ServerVersion}}' >/dev/null 2>&1 &
docker_check=$!
for _ in $(seq 1 20); do kill -0 "$docker_check" 2>/dev/null || break; sleep 1; done
if kill -0 "$docker_check" 2>/dev/null; then
  kill "$docker_check" 2>/dev/null || true
  echo "the Docker engine does not answer; restart Docker Desktop first" >&2; exit 1
fi
wait "$docker_check" || { echo "the Docker engine is not running; start Docker Desktop first" >&2; exit 1; }

# A closed lid or a flat battery puts the machine to sleep, and a sleeping machine kills
# the run. Keep it on power with the lid open.
# NALA_EVAL_ALLOW_BATTERY=1 starts anyway; a sleep then shows as a gap in the log.
if [ -z "${NALA_EVAL_ALLOW_BATTERY:-}" ] && ! pmset -g batt | head -1 | grep -q "AC Power"; then
  echo "the machine is on battery; connect power and keep the lid open, then start again" >&2; exit 1
fi

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
if [ -z "$resume" ]; then
# 2. The run record, written before the first session starts.
mkdir -p "$results/transcripts"
jq -n --arg run "$run_name" --arg version "$version" --arg repo "$repo" --arg github "$github" \
  --arg claude "$(claude --version)" --arg start_state "$(field start_state_commit)" \
  --arg source "$(field source_start_commit)" --arg start "$(now)" \
  --argjson tickets "$(printf '%s\n' ${tickets[@]+"${tickets[@]}"} | jq -R 'select(length > 0) | tonumber' | jq -s .)" \
  '{run_id: $run, nala_version: $version, harness: "claude-code", claude_code_version: $claude,
    main_model: "opus", main_effort: "max", scratch_tickets: $tickets,
    source_start_commit: $source, start_state_commit: $start_state,
    scratch_repository: $repo, github_repository: $github,
    start_time: $start, end_time: "", end_reason: "", session_ids: [],
    interruptions: 0, usage_limit_wait_hours: 0, machinery_failures: []}' > "$results/run.json"
fi
started=$(date +%s)
# Sessions that ran in the scratch repository before the run, such as the isolation probe,
# are not part of it.
before_run="$results/sessions-before-run.txt"
slug=$(printf '%s' "$repo" | sed 's/[^A-Za-z0-9]/-/g')
[ -n "$resume" ] || find "$HOME/.claude/projects" -maxdepth 2 -path "*/$slug*" -name '*.jsonl' -exec basename {} .jsonl \; 2>/dev/null | sort > "$before_run"
if [ -n "$resume" ]; then
  # The pause runs from the last line the dead launcher wrote to this moment.
  paused_from=$(tail -1 "$results/launcher.log" | awk '{print $1}')
  paused_to=$(now)
  jq --arg from "$paused_from" --arg to "$paused_to" '.pauses = ((.pauses // []) + [{from: $from, to: $to, cause: "the launcher died; resumed with --resume"}])' \
    "$results/run.json" > "$results/run.json.new" && mv "$results/run.json.new" "$results/run.json"
fi

# 3. The stand-in for a person answers questions and grants the approval label, the same
#    way in every run. The launcher itself survives a closed terminal window, and it
#    writes a line to launcher.log at each check, so a dead launcher shows.
trap '' HUP
log() { echo "$(now) $*" >> "$results/launcher.log"; }
python3 "$here/eval/standin.py" "$run_name" >> "$results/standin.out" 2>&1 &
standin=$!
trap 'kill "$standin" 2>/dev/null || true' EXIT
acts() {
  local count
  count=$(grep -c -E '"answered": true|"label_granted": true' "$results/standin-log.jsonl" 2>/dev/null) || count=0
  echo "${count:-0}"
}
over_cap() { [ $(( $(date +%s) - started )) -ge "$cap" ]; }
if [ -n "$resume" ]; then log "resumed after a pause from $paused_from"; else log "started $version in $repo"; fi

# 4. Start the version's own entry point.
end_reason=""
case "$version" in
  v1.8*)
    [ ${#tickets[@]} -eq 0 ] || { echo "a v1.8 run takes no ticket list" >&2; exit 1; }
    # The version's start script opens the Lead in the tmux session NALA_TMUX_SESSION names.
    # It ends by attaching to that session, a step that fails here by design;
    # `tmux attach -t nala-eval` shows the run at any time.
    NALA_TMUX_SESSION=$tmux_session bash "$repo/${NALA_SWARM_START:-scripts/lead_start.sh}" </dev/null >> "$results/launcher.log" 2>&1 || true
    tmux has-session -t "=$tmux_session" 2>/dev/null || { echo "the Lead did not start" >&2; exit 1; }
    echo "the Lead runs in the tmux session $tmux_session; progress is in $results/launcher.log"
    idle=0
    while :; do
      sleep 120
      if ! tmux has-session -t "=$tmux_session" 2>/dev/null; then end_reason="main session ended"; break; fi
      if over_cap; then end_reason="time cap"; break; fi
      in_progress=$(cd "$repo" && uv run --quiet orch --json status 2>/dev/null \
        | jq '[.result.runs[] | select(.lifecycle_state | IN("merged","completed","cancelled","blocked") | not)] | length' 2>/dev/null || echo 1)
      can_start=$(cd "$repo" && uv run --quiet orch --json frontier 2>/dev/null | jq '.result.eligible | length' 2>/dev/null || echo 1)
      if [ "$in_progress" = 0 ] && [ "$can_start" = 0 ]; then idle=$((idle + 1)); else idle=0; fi
      log "in progress $in_progress, can start $can_start, idle checks $idle, stand-in acts $(acts)"
      if [ "$idle" -ge 3 ]; then end_reason="no ticket in progress and none can start"; break; fi
    done
    tmux capture-pane -p -S -3000 -t "$tmux_session:0" > "$results/lead-final-screen.txt" 2>/dev/null || true
    tmux kill-session -t "=$tmux_session" 2>/dev/null || true
    ;;
  *)
    # The main session runs headless and exits when every ticket is merged or blocked.
    # When the stand-in then answers, the same session continues, as it would for a
    # person who replied in it.
    session=$(uuidgen | tr '[:upper:]' '[:lower:]')
    if [ -n "$resume" ]; then
      # The run's main session is the one root transcript that was not there before it.
      session=""
      for transcript in "$HOME/.claude/projects/$slug"/*.jsonl; do
        candidate=$(basename "$transcript" .jsonl)
        grep -qx "$candidate" "$before_run" || session=$candidate
      done
      [ -n "$session" ] || { echo "no main session found to resume" >&2; exit 1; }
    fi
    # With no numbers, /process-batch takes only the tickets that are ready at its start,
    # so a ticket that waits on another would never join. The eval's task is every ticket.
    if [ ${#tickets[@]} -eq 0 ]; then
      tickets=($(jq -r '.ticket_numbers[]' "$setup" | sort -n))
    fi
    echo "main session $session started; progress is in $results/launcher.log"
    leg=1
    prompt="/process-batch ${tickets[*]-}"
    if [ -n "$resume" ]; then
      leg=$(( $(ls "$results"/main-session-leg-*.json 2>/dev/null | wc -l) + 1 ))
      prompt="The machine running this batch slept, and every background helper stopped without a report. Read the run record and the process-batch skill again, then continue the batch: each ticket in progress gets a fresh ticket-worker on its same run."
    fi
    while :; do
      acts_before=$(acts)
      if [ "$leg" -eq 1 ] && [ -z "$resume" ]; then which=(--session-id "$session"); else which=(--resume "$session"); fi
      log "leg $leg starts"
      ( cd "$repo" && CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 claude -p "$prompt" "${which[@]}" \
          --model opus --effort max --dangerously-skip-permissions \
          --output-format json > "$results/main-session-leg-$leg.json" 2>> "$results/main-session.err" ) &
      pid=$!
      while kill -0 "$pid" 2>/dev/null; do
        sleep 60
        log "leg $leg runs, stand-in acts $(acts)"
        if over_cap; then
          end_reason="time cap"
          pkill -TERM -P "$pid" 2>/dev/null || true
          kill "$pid" 2>/dev/null || true
        fi
      done
      [ -z "$end_reason" ] || break
      # Two stand-in checks, so an answer to the last question has time to land.
      sleep 150
      if [ "$(acts)" -le "$acts_before" ]; then end_reason="main session ended"; break; fi
      # A block that no answer can clear would otherwise repeat for the whole time cap.
      if [ "$leg" -ge 8 ]; then end_reason="eight legs"; break; fi
      leg=$((leg + 1))
      prompt="A person replied on the tickets of this batch. Read the new comments and labels on each blocked ticket and its pull request, then continue the batch by the process-batch skill."
    done
    ;;
esac
kill "$standin" 2>/dev/null || true
launcher_ended=$(now)
# The run's end is the last event in the run record, the same for both versions: a v1.8
# run is noticed as finished only some minutes after its last merge.
ended=$(sqlite3 -readonly "$repo/state/orchestrator.sqlite3" "select strftime('%Y-%m-%dT%H:%M:%SZ', max(at)) from events" 2>/dev/null || true)
[ -n "$ended" ] || ended=$launcher_ended
log "ended: $end_reason"
# A gap of more than ten minutes between log lines means the machine slept or the
# launcher stalled, and the run's times no longer measure the version.
gap=$(cat "$results/launcher.log" | python3 -c '
import sys
from datetime import datetime
rows = [line.split(" ", 1) for line in sys.stdin if line.strip()]
times = [(datetime.fromisoformat(stamp.replace("Z", "+00:00")), text) for stamp, text in rows]
# A gap that ends at a resume line is a recorded pause, not a fault.
print(max([0] + [round((b - a).total_seconds() / 60) for (a, _), (b, text) in zip(times, times[1:]) if not text.startswith("resumed")]))')
if [ "$gap" -gt 10 ]; then
  end_reason="$end_reason; VOID: the launcher log has a gap of $gap minutes"
  echo "this run is void: the launcher log has a gap of $gap minutes, so the machine slept or stalled" >&2
fi

# 5. Every session of the run: Claude Code files transcripts by folder, and each of the
#    run's sessions worked in the scratch repository or in one of its working copies.
for folder in "$HOME/.claude/projects/$slug"*; do
  [ -d "$folder" ] && cp -R "$folder" "$results/transcripts/"
done
while IFS= read -r earlier; do
  find "$results/transcripts" -maxdepth 2 -name "$earlier*" -exec rm -r {} +
done < "$before_run"
sessions=$(find "$results/transcripts" -name '*.jsonl' -not -path '*/subagents/*' -exec basename {} .jsonl \; | sort | jq -R . | jq -s .)
jq --arg end "$ended" --arg launcher_end "$launcher_ended" --arg reason "$end_reason" \
  --argjson sessions "$sessions" --argjson acts "$(acts)" \
  '.end_time = $end | .launcher_end_time = $launcher_end | .end_reason = $reason
   | .session_ids = $sessions | .interruptions = $acts' "$results/run.json" > "$results/run.json.new"
mv "$results/run.json.new" "$results/run.json"

# 6. Grade the scratch repository's main branch, report spend, and check the isolation held.
git -C "$repo" fetch --quiet origin main
python3 "$here/eval/grade.py" "$repo" origin/main "$results/grade" || true
python3 "$here/eval/spend.py" "$results/run.json" --transcripts "$results/transcripts" | tee "$results/spend.txt" || true
python3 "$here/eval/audit_transcripts.py" "$results/transcripts" --allow "$github" | tee "$results/audit.txt" || true
echo "run $run_name ended: $end_reason. Results are in $results"
