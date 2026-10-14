# Eval tools

The design is in `docs/eval-design.md`.
Each tool does one step of a run.
Every tool reads its settings from `eval/config.env`; copy `config.example.env` to start.

| Step | Tool | What it does |
|---|---|---|
| Before a run | `setup_scratch.sh VERSION RUN_NAME [--github OWNER/NAME]` | Builds the scratch repository at the start state with one version in place, and writes a setup record. With `--github` it also creates the private repository and copies the tickets in. |
| Before a run | `probe_isolation.sh RUN_NAME` | Starts one small session in the scratch repository and has it try each closed place. |
| Before a run | `probe_gate.sh RUN_NAME STEPS_FILE` | Starts one small session that runs the merge check's own tools, so a sandbox fault shows before a scored run. |
| Before a run | `reisolate.sh RUN_NAME` | Applies changed isolation rules to a scratch repository that already exists. |
| The run | `start_run.sh RUN_NAME [TICKET ...]` | Writes the run record, starts the version, waits for the end, then grades, reports spend, and audits. |
| During the run | `standin.py RUN_NAME` | Stands in for the person: the fixed answer to a question, and the `approved` label on request. `start_run.sh` starts it. |
| After a run | `grade.py REPO REF OUT_DIR` | Lays the hidden tests over the run's main branch, runs them, and writes `grade.json`. The deciding score is the share of tickets whose kept tests all pass. |
| After a run | `spend.py RUN_RECORD.json` | Reports dollars, tokens by model, and wall time for the whole run. |
| After a run | `audit_transcripts.py TRANSCRIPTS_DIR` | Lists every tool call that named a closed place. |

`hidden-tests/` holds the method and file formats of the grading tests.
`tickets/` holds the names section added to each copied ticket, one `names_TICKET.md` per source ticket.
`versions/` at the repository root holds one folder per frozen version under test, and `versions/FILES.txt` lists the agent-system paths a version replaces.
None of `hidden-tests/files/`, `tickets/`, or `versions/` is in this public copy.

## What you supply

- A source project on GitHub with a batch of tickets that already merged, and a local clone of it.
- The hidden tests for that batch, made by the method in `hidden-tests/README.md`.
- The frozen versions under test in `versions/`.
- A machine with Claude Code, `gh`, `jq`, `uv`, `tmux`, `sqlite3`, and Docker. The launcher uses `pmset` and `sed -i ''`, so it runs on macOS as written.

## Order of one run

1. `setup_scratch.sh VERSION RUN_NAME --github OWNER/NAME`, run by an agent session or by hand.
   It builds the repository under `$NALA_SCRATCH_ROOT` and closes it off with `isolate.py`.
2. The founder adds the new repository to the eval token (see below).
3. `probe_isolation.sh RUN_NAME`, from the founder's terminal.
   Every "must fail" step must show a refusal.
4. `start_run.sh RUN_NAME`, from the founder's terminal.
   It writes the run record, starts the version's entry point, waits for the end, copies the transcripts, and runs `grade.py`, `spend.py`, and `audit_transcripts.py`.
   It also starts `standin.py`, the stand-in for a person.
   A v1.9 main session that exited on blocked tickets continues in the same session after the stand-in answers.
   `results/RUN_NAME/launcher.log` gets a line at each check, so a dead launcher shows.
   A gap of more than ten minutes between log lines marks the run void, because the machine slept or stalled.
   `start_run.sh RUN_NAME --resume` continues a v1.9 run whose launcher died, and records the pause.
   Results land in `results/RUN_NAME/`.

An agent session cannot do steps 3 and 4, because its sandbox cannot renew the Claude sign-in.

## The eval sign-in

An attempt uses a GitHub token that reaches the scratch repositories only.
It is a fine-grained personal access token with "Only select repositories", and read and write access to Contents, Issues, and Pull requests.
It lives in its own GitHub command line folder, `$NALA_EVAL_GH_CONFIG`, stored in a file there and not in the keychain, so the machine's own sign-in is untouched.
The scratch repository's settings point every session at that folder, and `start_run.sh` refuses to start when the token can reach the source project or the private harness repository.

## Isolation

`isolate.py` edits the scratch repository's tracked session settings.
It denies every connector tool, every outside-service address and command line tool, and reads of the source project, this harness, the closed folders, their Claude Code notes, and earlier runs.
It is a guard against an attempt that looks around the disk, not a security boundary.
`audit_transcripts.py` lists every tool call that named a closed place.
A listed call is not proof of a leak; read each one.

## Not tested in this form

This public copy generalizes the private harness: settings moved to `config.env`, and source-project names and paths left out.
The generalized scripts pass a syntax check and small local tests, but no full run has used them.
