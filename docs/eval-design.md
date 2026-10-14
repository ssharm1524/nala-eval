# Eval design

Settled with the founder on 2026-10-08, with rulings added as the pilot ran.
The eval started as internal testing to decide which Nala version to keep.
This public copy removes the private product's name, paths, commit ids, and ticket numbers.
Tickets are numbered 1 to 6 in batch order, as in each scratch repository.

## Question

Which Nala version turns a batch of tickets into correct merged code, and at what cost in tokens and wall time?
The eval compares Nala versions inside Claude Code only.

Nala is the agent system under test: the instruction files, roles, skills, and orchestrator that drive Claude Code sessions through a ticket.

## Versions in the pilot

- Version A is v1.8, the full swarm: a Lead session, worker sessions in terminal windows, and messages between sessions.
- Version B is the v1.9 candidate: one session that works through the tickets and uses only Claude Code's own helper agents.

Both versions are frozen before the first run.
Both are built from the same instruction text, at one source commit (2026-10-09).
That commit follows a prompt audit of the instruction files and a retro over two weeks of sessions.
The only intended difference between them is the coordination layer.

The main session in both versions runs Opus at maximum effort (founder ruling, 2026-10-09).
The run record stores the exact model id, because the name "Opus" follows the newest Opus model and can change during the study.
Helpers keep the models each version assigns to them.
Lower worker effort is a later experiment, not part of the pilot.

### Version B design (approved 2026-10-09)

- One main session works the tickets.
- For each ticket it starts one background helper in its own working copy.
- That helper follows the same ticket contract as v1.8 and starts its own test author and reviewer.
- Removed: the Lead session, the terminal windows, the message script, the watcher, worker replacement, and the merge queue.
- The main session merges one ticket at a time.
- Unchanged: the ticket contract, the seven roles, the run record, the fresh review of every final commit, the product gate, the migration approval, and the single merge path.

### Version B as built (2026-10-09)

The candidate is made from the v1.8 freeze.

- New: the `ticket-worker` role and the `process-batch` skill.
- Removed: the Lead skill and the three scripts that start the Lead, wake sessions, and carry messages.
- Rewritten: the orchestrator guide (446 lines to 387), with small edits to the project instruction file, the ticket contract, and six other files.
- The main session claims each ticket with the existing single-session claim, so both versions use one run record and one merge path.
- A ticket-worker waits for the product gate with `gh pr checks --watch`, because it holds no wait tool.

Known gaps, accepted for the pilot:

- The orchestrator's Python package and the safety hook are unchanged. The admit, replace, and worker-start code is unused, and two messages still name the Lead.
- With two claimed runs in one session, the safety hook confines file-tool writes to the two working copies but does not confine shell writes.
- A ticket-worker holds no browser or connector tools, so the main session does any outside-service step itself. The pilot's six tickets have none.

Claude Code facts the design depends on, checked against its documentation on 2026-10-09:

- A helper can start helpers when its definition lists the `Agent` tool, up to three layers below the main conversation.
- At most 20 helpers run at once by default.
- A helper shares the main session's id.

## Method: replay

A run replays tickets that already merged in the source project.
Nothing is merged into the source project.

- The batch is six connected backend tickets.
- Every run starts from one source commit (2026-09-27), when all six were open.
- The start state adds the real fix for one ticket outside the batch, because ticket 3 is blocked by it.
- Each copied ticket carries its body, its founder-direction comments, and a "Names and decisions" section, so the hidden tests are fair to an independent attempt (founder ruling, 2026-10-09).
- Blocking links: ticket 4 needs tickets 1 and 3. Tickets 5 and 6 need ticket 4.
- Each run gets a private scratch GitHub repository with history only up to the start commit, and the six tickets copied in as issues.
- Merges happen in the scratch repository.
- The version under test is copied over the product code before the run starts.

## Isolation rules

- The scratch repository contains no history after the start commit.
- The attempt signs in to the scratch repository only.
- The attempt gets no sign-in to staging, production, hosting, database, or payment services.
- Backend tests use a local database in Docker only.
- The saved memory notes of the source project are not loaded.
- No person is present. A question from the attempt is answered "use your best judgment and continue" and counts as one interruption.

## Pilot shape

- Four batch runs, in the order A, B, B, A.
- One run at a time, with no other agent work on the machine.
- At most two tickets in progress at once.
- A run ends when every ticket is merged or durably blocked, or after 24 hours.

## The stand-in for a person (rule set 2026-10-12, during the first scored run)

No person is present, and both Nala versions reserve two acts for a person.
A stand-in does both the same way in every run, and each act counts as one interruption.

- A question from the attempt gets one fixed answer as a comment on the ticket: "Use your best judgment and continue."
  The stand-in does not read the options and does not choose one.
- A request for the `approved` label on a pull request that changes a gated path, such as a database migration, is granted.
  The stand-in does not read the change.

The founder approved the label rule on 2026-10-12, before any run had asked for the label.
The first scored run got its first answer by hand, a few minutes after the question.
From the second scored run on, a script gives both acts, so the wait does not depend on a person's reply time.
Each run's results list each act with its times.

One more difference follows from the isolation rules: no session holds a browser tool, because every connector tool is denied.
A ticket that changes what a user sees in the web app therefore cannot get the real browser look that Nala's rules ask for.
The attempt must ask, and it gets the fixed answer.
This is the same in all four runs.

## Void runs (rule set 2026-10-12, before the first scored run)

A scored run is void only for a fault in the scratch setup or in the machine.
Examples are a Docker engine that does not answer, a missing label in the scratch repository, and an isolation rule that stops a tool the merge check needs.
A void run is recorded with its cause, kept in the results, and repeated on a fresh scratch repository.
A run is never void for a fault in the Nala version under test.
That fault is the result.
The cause is judged from the run record and the transcripts, and it is written down before the repeat run starts.

Two unscored trial runs came before this rule.
Both ran the v1.9 candidate and both stopped on setup or machine faults: a hung Docker engine, then phone-app checks the session sandbox could not run.

Void runs so far:

- `pilot-2-B`, attempt 1 (v1.9): the launcher started `/process-batch` with no ticket numbers, so the batch held only the two tickets ready at the start. Repeated as `pilot-2-B2`.

Paused runs:

- `pilot-2-B2` (v1.9): the machine slept with its lid closed 22 minutes in, and the launcher and main session died.
  The founder chose to resume it on 2026-10-14 instead of repeating it.
  The main session continues under its same id, and the v1.9 rule for a dead helper applies: each ticket in progress gets a fresh helper on its same run.
  The pause, from the launcher's last log line to the resume, is recorded in the run record and left out of the wall time.
  The run differs from a clean one in one way: its helpers restart once, mid-ticket.

## Replay differences found by the unscored runs

- The merge check runs on the machine, because a scratch repository has no hosted checks.
  In the source project the hosted checks do this work, and the local path is a fallback.
  A change to the API contract file makes the local path run the phone-app checks too.
- The session settings therefore let a session write the file watcher's state folder and the scanner's install folder, and give the Expo command line an empty settings folder inside the run record folder.
- The readiness check inside both Nala versions reports ready without checking Docker.
  The launcher checks Docker before a run starts; the versions are left as they are.

## Scores

Roles are fixed before the first run.

| Role | Score |
|---|---|
| Decides the winner | Share of tickets whose kept hidden tests pass. |
| Second rank | Dollars at list price per passing ticket, and wall time per passing ticket. Reported separately, never blended. |
| Reported only | Product gate result, blind review verdict, interruptions, machinery failures. |

- A version wins the second rank only if it is better on one measure and not worse on the other. Otherwise the result is a trade-off.
- A ticket that is not merged when the run ends fails.
- A wait on a usage limit counts in wall time and is also recorded as its own number.
- Spend is scored as the batch total. A per-ticket split is informational, with shared coordination cost on its own line.

## Grading

- Grading runs once, after the run ends, against the scratch repository's main branch.
- Hidden tests are the tests from the real merged fix. The attempt never sees them.
- Before any run, the hidden tests are filtered to those that test what the ticket text specifies, such as a route or a table. Tests of internal names are dropped.
- The kept tests must fail at the start commit and pass once the real fixes are applied in order.
- The kept list is frozen: 87 tests, with the method in `eval/hidden-tests/README.md`.
- Ticket 3 is graded on its backend tests only.
- Phone and website tickets are out of the pilot.

## Run record

The eval code writes one record file per run, before the run starts.
Fields: Nala version, harness, model, effort level, Claude Code version, tickets, attempt number, start commit, session ids, start time, end time.

Each run stores under `results/`: the record file, the spend report, the grading output, and a copy of every session transcript.

## Spend measurement notes

Learned from the first spend script, which was lost because it was never committed.

- Claude Code logs one transcript line per content block of a response, all with one request id. Keep the line with the highest output token count.
- Claude Code's own cost record in a transcript is about 11% higher than pricing the logged requests, because some billed calls are never logged. Use the cost record when a session has one.
- A root session's helpers are in a `subagents` folder beside its transcript. Count them with the root.
- Local transcripts can disappear. Copy them into `results/` when a run ends.

## Claims

The pilot measures the spread between two attempts of the same version.
It names no winner unless the gap between versions is far larger than that spread.
The spread sets the size of any larger study.

## Setup problems found when v1.8 was frozen (2026-10-08)

The scratch-repository setup had to solve each one before v1.8 could run on the start commit.

1. Glossary file name. The v1.8 files point at one glossary file name. The product code at the start commit still used an older name.
2. Repository name. Nine v1.8 files name the source repository directly. A scratch repository has another name, so these need a substitution step.
3. The project instruction file mixes product guidance with Nala instructions and is copied whole. It describes the product on the freeze date, not the product at the start commit.
4. The safety hook resolves its script from the Git root of the shell's current directory. Every scratch repository needs the hook script present.
5. The Python project files are shared with the product and are not in the freeze. The orchestrator's command is declared there.

Problems 1, 3, and 5 share one cause: v1.8 is eleven days newer than the start commit.
Each mismatch needs an explicit, recorded adjustment.
