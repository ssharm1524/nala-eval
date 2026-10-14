#!/usr/bin/env bash
# Apply the current isolation rules to a scratch repository that already exists.
#
#   reisolate.sh RUN_NAME [--finished]
#
# Use it when isolate.py changes after setup_scratch.sh built the repository and before
# the run starts. It commits the settings change on the scratch main branch and pushes it.
set -euo pipefail
run_name=${1:?usage: reisolate.sh RUN_NAME}
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/eval/config.sh"
scratch_root=$NALA_SCRATCH_ROOT
setup="$scratch_root/$run_name.setup.json"
repo=$(jq -r .scratch_repository "$setup")
# A finished trial repository may be updated for a probe: pass --finished to allow it.
if [ -e "$here/results/$run_name/run.json" ] && [ "${2:-}" != "--finished" ]; then
  echo "$run_name already started" >&2; exit 1
fi
other_runs=()
for other in "$scratch_root"/*/; do
  other=${other%/}
  [ -d "$other/.git" ] && [ "$other" != "$repo" ] && other_runs+=("$other")
done
python3 "$here/eval/isolate.py" "$repo" "$(jq -r .github_sign_in_folder "$setup")" ${other_runs[@]+"${other_runs[@]}"}
git_s() { git -C "$repo" -c user.name="nala-eval" -c user.email="nala-eval@localhost" "$@"; }
if git_s diff --quiet; then echo "no change"; exit 0; fi
git_s commit --quiet -am "Nala $(jq -r .nala_version "$setup"): current isolation rules"
git_s push --quiet origin main
start_state=$(git_s rev-parse HEAD)
jq --arg commit "$start_state" '.start_state_commit = $commit' "$setup" > "$setup.new" && mv "$setup.new" "$setup"
echo "$repo at $start_state"
