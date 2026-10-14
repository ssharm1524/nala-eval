#!/usr/bin/env bash
# Build the scratch repository for one eval run.
#
#   setup_scratch.sh VERSION RUN_NAME [--github OWNER/NAME]
#
# VERSION is a folder under versions/ that holds the frozen agent-system files of one
# version under test, such as v1.8 or v1.9-candidate. RUN_NAME names the run, such as
# pilot-1-A. The repository is built at $NALA_SCRATCH_ROOT/RUN_NAME and its setup record
# is written beside it. Settings come from eval/config.env (see config.example.env).
#
# Without --github the script builds the local repository only, which is enough to check
# the build. With --github it also creates the private GitHub repository, pushes main,
# and copies the batch's tickets in as issues with their blocking links.
#
# Every adjustment to the source project is listed in the setup record, because each one
# is a difference between this replay and the real work.
set -euo pipefail

version=${1:?usage: setup_scratch.sh VERSION RUN_NAME [--github OWNER/NAME]}
run_name=${2:?usage: setup_scratch.sh VERSION RUN_NAME [--github OWNER/NAME]}
github=""
if [ "${3:-}" = "--github" ]; then github=${4:?--github needs OWNER/NAME}; fi

here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/eval/config.sh"
source_repo=${NALA_SOURCE_REPO:?set NALA_SOURCE_REPO in eval/config.env}
source_name=${NALA_SOURCE_NAME:?set NALA_SOURCE_NAME in eval/config.env}
start_commit=${NALA_START_COMMIT:?set NALA_START_COMMIT in eval/config.env}
prestart_fix=${NALA_PRESTART_FIX:-}
read -r -a tickets <<< "${NALA_TICKETS:?set NALA_TICKETS in eval/config.env}"   # batch order
scratch_root=$NALA_SCRATCH_ROOT
gh_config=$NALA_EVAL_GH_CONFIG
repo="$scratch_root/$run_name"
record="$scratch_root/$run_name.setup.json"
adjustments=()

[ -d "$here/versions/$version" ] || { echo "no versions/$version" >&2; exit 1; }
[ ! -e "$repo" ] || { echo "$repo exists; pick a new RUN_NAME" >&2; exit 1; }
mkdir -p "$scratch_root"

git_s() { git -C "$repo" -c user.name="nala-eval" -c user.email="nala-eval@localhost" "$@"; }

# 1. History up to the start commit only. A fetch of one commit brings its ancestors and
#    nothing newer, so the attempt cannot read the real fixes from Git.
git init --quiet --initial-branch=main "$repo"
git_s fetch --quiet "$source_repo" "$start_commit"
git_s merge --quiet --ff-only FETCH_HEAD
# The orchestrator creates each ticket's working copy with per-worktree settings.
git_s config extensions.worktreeConfig true

# 2. A fix the batch depends on, applied as a patch so no later history comes with it.
if [ -n "$prestart_fix" ]; then
  git -C "$source_repo" diff --binary "$prestart_fix^" "$prestart_fix" | git_s apply --index
  git_s commit --quiet -m "Prestart fix from source commit $prestart_fix"
  adjustments+=("The change of source commit $prestart_fix is applied to the start commit, because a batch ticket depends on it and it is outside the batch.")
fi

# 3. The version under test replaces the agent-system files of the start commit.
#    versions/FILES.txt lists those paths, one per line.
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  git_s rm -r --quiet --ignore-unmatch -- "$line"
done < "$here/versions/FILES.txt"
tar -C "$here/versions/$version" --exclude MANIFEST.sha256 --exclude SOURCE -cf - . | tar -C "$repo" -xf -
# Claude Code finds a skill through a link under .claude/skills. The freeze does not carry
# those links, so they are rebuilt here: one for each of the version's own skills.
git_s rm -r --quiet --ignore-unmatch -- .claude/skills
mkdir -p "$repo/.claude/skills"
for skill in "$repo"/.agents/skills/*/; do
  [ -d "$skill" ] || continue
  name=$(basename "$skill")
  ln -s "../../.agents/skills/$name" "$repo/.claude/skills/$name"
done
adjustments+=("The skill links under .claude/skills are rebuilt from the version's own skills, because the freeze did not carry them.")

# 4. Adjustments, each recorded.
#    a. The version's files name the source repository; the run works in the scratch one.
#       Only the agent-system paths are changed, never the product code.
target_name=${github:-nala-eval/$run_name}
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  [ -e "$repo/$line" ] || continue
  grep -rlF "$source_name" "$repo/$line" 2>/dev/null | while IFS= read -r file; do
    sed -i '' "s|$source_name|$target_name|g" "$file"
  done
done < "$here/versions/FILES.txt"
adjustments+=("The source repository name is replaced by the scratch repository name in the version's files.")
#    b. No hosted workflow runs in the scratch repository, so no secret is needed there and
#       the merge safety path runs the product gate on this machine.
git_s rm -r --quiet --ignore-unmatch -- .github/workflows
adjustments+=("Hosted workflows are removed and Actions are off, so the product gate runs on this machine.")
#    c. The attempt reaches nothing outside its own repository: no connector, no outside
#       service, no folder that holds the real fixes or the hidden tests, no earlier run.
git_s rm --quiet --ignore-unmatch -- .mcp.json
other_runs=()
for other in "$scratch_root"/*/; do
  other=${other%/}
  [ -d "$other/.git" ] && [ "$other" != "$repo" ] && other_runs+=("$other")
done
# Runs that are planned but not built yet are closed too: NALA_EVAL_PLANNED_RUNS names them.
for planned in ${NALA_EVAL_PLANNED_RUNS:-}; do
  [ "$scratch_root/$planned" != "$repo" ] && [ ! -d "$scratch_root/$planned/.git" ] && other_runs+=("$scratch_root/$planned")
done
python3 "$here/eval/isolate.py" "$repo" "$gh_config" ${other_runs[@]+"${other_runs[@]}"}
adjustments+=("The project connector file is removed, and the session settings deny every connector tool, every outside-service address, and reads of the source project, this harness, the closed folders, and earlier runs.")
adjustments+=("GitHub commands use a sign-in that reaches the scratch repository only.")
#    d. A fresh clone has no run record folder, and the status command fails without one.
mkdir -p "$repo/state"
adjustments+=("The run record folder is created empty, because the status command fails in a clone that has none.")
#    e. Adjustments specific to the source project.
if [ -n "${NALA_SETUP_HOOK:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && adjustments+=("$line")
  done < <(bash "$NALA_SETUP_HOOK" "$repo")
fi

git_s add -A
git_s commit --quiet -m "Nala $version"
start_state=$(git_s rev-parse HEAD)

ticket_map="{}"
if [ -n "$github" ]; then
  gh repo create "$github" --private --disable-wiki >/dev/null
  git_s remote add origin "https://github.com/$github.git"
  git_s push --quiet -u origin main
  gh api -X PUT "repos/$github/actions/permissions" -F enabled=false >/dev/null

  for label in $(for t in "${tickets[@]}"; do gh issue view "$t" --repo "$source_name" --json labels --jq '.labels[].name'; done | sort -u); do
    gh label create "$label" --repo "$github" --force >/dev/null
  done
  # The stand-in grants `approved`. The orchestrator puts the extra labels on tickets
  # itself, and a claim fails without them.
  for label in approved ${NALA_EXTRA_LABELS:-}; do
    gh label create "$label" --repo "$github" --force >/dev/null
  done

  # First pass: create the issues in batch order so a fresh repository numbers them 1, 2, 3, ...
  declare -a new_numbers=() new_ids=()
  for t in "${tickets[@]}"; do
    title=$(gh issue view "$t" --repo "$source_name" --json title --jq .title)
    labels=$(gh issue view "$t" --repo "$source_name" --json labels --jq '[.labels[].name] | map(select(. != "in-progress")) | join(",")')
    url=$(gh issue create --repo "$github" --title "$title" --label "$labels" --body "placeholder")
    number=${url##*/}
    new_numbers+=("$number")
    new_ids+=("$(gh api "repos/$github/issues/$number" --jq .id)")
  done

  # Rewrite references among the batch's tickets to the scratch numbers.
  rewrite() {
    local text; text=$(cat)
    for i in "${!tickets[@]}"; do text=${text//#${tickets[$i]}/#${new_numbers[$i]}}; done
    printf '%s\n' "$text"
  }

  # Second pass: body, names section, founder-direction comments, and blocking links.
  # eval/tickets/names_TICKET.md, when present, is added to the ticket body: it states the
  # names and decisions a hidden test needs and the ticket text does not.
  for i in "${!tickets[@]}"; do
    t=${tickets[$i]}; number=${new_numbers[$i]}
    { gh issue view "$t" --repo "$source_name" --json body --jq .body
      if [ -f "$here/eval/tickets/names_$t.md" ]; then
        printf '\n\n'
        cat "$here/eval/tickets/names_$t.md"
      fi
    } | rewrite | gh issue edit "$number" --repo "$github" --body-file - >/dev/null
    gh issue view "$t" --repo "$source_name" --json comments \
      --jq '.comments[] | select(.body | startswith("**Founder direction")) | .body | @base64' \
      | while IFS= read -r encoded; do
          printf '%s' "$encoded" | base64 --decode | rewrite | gh issue comment "$number" --repo "$github" --body-file - >/dev/null
        done
    for blocker in $(gh api "repos/$source_name/issues/$t/dependencies/blocked_by" --jq '.[].number'); do
      for j in "${!tickets[@]}"; do
        if [ "${tickets[$j]}" = "$blocker" ]; then
          gh api -X POST "repos/$github/issues/$number/dependencies/blocked_by" -F issue_id="${new_ids[$j]}" >/dev/null
        fi
      done
    done
  done
  ticket_map=$(for i in "${!tickets[@]}"; do printf '"%s": %s\n' "${tickets[$i]}" "${new_numbers[$i]}"; done | paste -sd, - | sed 's/^/{/;s/$/}/')
  adjustments+=("Each ticket is the source body, its founder-direction comments, and its names section; references among the batch's tickets use the scratch numbers.")
fi

jq -n --arg run "$run_name" --arg version "$version" --arg repo "$repo" --arg github "${github:-null}" \
  --arg sign_in "$gh_config" --arg source "$start_commit" --arg start_state "$start_state" \
  --argjson tickets "$ticket_map" \
  --argjson adjustments "$(printf '%s\n' "${adjustments[@]}" | jq -R . | jq -s .)" \
  '{run_name: $run, nala_version: $version, scratch_repository: $repo,
    github_repository: (if $github == "null" then null else $github end),
    github_sign_in_folder: $sign_in, source_start_commit: $source,
    start_state_commit: $start_state, ticket_numbers: $tickets, adjustments: $adjustments}' > "$record"
echo "$repo at $start_state"
