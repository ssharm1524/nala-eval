# nala-eval

A contamination-controlled replay eval for coding-agent designs.
The write-up of the method and the first pilot is at https://shivsharma.me/blog/nala-evals/.

It answers one question: given the same batch of real tickets, which agent design turns them into correct merged code, and at what cost in dollars and wall time?
It was built to compare two versions of Nala, an agent system that drives Claude Code sessions through tickets.
The harness itself does not depend on Nala's design: it needs a version folder, a start command, and a GitHub repository.

This is a sanitized public copy of a private harness.
The hidden tests, ticket texts, and run transcripts come from a private product and are not here.
The method, the tools, and a summary of the first scored run are.

## Contents

| Path | What it is |
|---|---|
| `RESULTS.md` | The first scored pilot run: one run, not a comparison. |
| `docs/eval-design.md` | The full design: question, versions, replay method, isolation, scores, grading, void rules. |
| `eval/README.md` | The tools, the order of one run, the eval sign-in. |
| `eval/hidden-tests/README.md` | How the hidden tests were chosen, with the counts. |
| `eval/*.py`, `eval/*.sh` | The harness. |
| `eval/config.example.env` | Every setting, with a comment. |

## How it works

1. **Replay.** Pick a batch of tickets that already merged in a source project.
   Every run starts from a source commit at which all of them were open.
2. **Scratch repository.** Each run gets a fresh private GitHub repository with history only up to that commit.
   A fetch of one commit brings its ancestors and nothing newer, so the real fixes are not in Git.
   The tickets are copied in as issues, with their blocking links and the scratch issue numbers.
3. **Version under test.** The frozen files of one agent design replace the agent-system files of the start commit.
4. **Run.** The launcher starts the version, logs a line every check, and ends the run when every ticket is merged or blocked, or at a time cap.
   A stand-in for the person gives a fixed answer to every question and grants the approval label on request, without reading the code.
5. **Grade.** Hidden tests from the real fixes are laid over the run's main branch and run.
   A ticket passes when all its kept tests pass.
   The deciding score is the share of tickets that pass.
6. **Spend.** Dollars and tokens come from the Claude Code transcripts of every session and helper in the run.

## Contamination control

An attempt must not see the real fix, the hidden tests, or an earlier attempt.
The harness closes each path an agent could use to find them:

| Path to the answer | Control |
|---|---|
| Later Git history | The scratch repository holds history up to the start commit only. |
| The source project on disk | Session settings deny reads of it, and the sandbox denies them again. |
| The hidden tests and earlier results | Same deny rules for this harness folder and every other scratch repository, built or planned. |
| Memory notes and transcripts of the source project | Same deny rules for Claude Code's project-notes folders. |
| The source repository on GitHub | The attempt's GitHub token reaches the scratch repositories only. The launcher refuses to start if it can reach the source project or the private harness. |
| Connectors and outside services | Every connector tool is denied, connectors are turned off, service command line tools and sign-in folders are denied, and service addresses leave the sandbox allow list. |
| A person giving hints | No person is present. The stand-in gives one fixed sentence and never reads the code. |

These controls are guards against an agent that looks around the disk for context.
They are not a security boundary against an adversarial agent.

Two checks show whether the controls held:

- **Before the run**, `probe_isolation.sh` starts one cheap session with the run's own permissions and has it try each closed place.
  Every "must fail" step must show a refusal.
- **After the run**, `audit_transcripts.py` lists every tool call in every transcript that named a closed place.
  A listed call is not proof of a leak, because a refused call is listed too, so a person reads each one.

## Fair hidden tests

Tests from a real fix often depend on names the ticket never stated.
An attempt that solves the ticket correctly would still fail them.
The harness keeps only tests that a correct attempt following the ticket text would pass, and that fail at the start state and pass with all the real fixes.
For the pilot, 250 candidate tests became 87 kept tests.
`eval/hidden-tests/README.md` gives the method step by step.

## Adapting it to another repository

1. Copy `eval/config.example.env` to `eval/config.env` and fill it in: the source project, its start commit, the ticket numbers in batch order, and the closed folders.
2. Build the hidden tests by the method in `eval/hidden-tests/README.md`.
   Put the test files in `eval/hidden-tests/files/`, their paths in `candidate-files.txt`, and the frozen list in `kept-frozen.json`.
   `grade.py` runs them with `uv` and `pytest`; change its two commands for another test runner.
3. Write `eval/tickets/names_TICKET.md` for any ticket whose kept tests need a name the ticket does not state.
4. Freeze each agent design under test in `versions/NAME/`, and list the paths it replaces in `versions/FILES.txt`.
5. Make a fine-grained GitHub token that reaches only the scratch repositories, in its own `gh` config folder (see `eval/README.md`).
6. Adjust the launcher's two start modes in `start_run.sh` to your designs' entry points.
   One starts a swarm in a tmux session; the other starts one headless `claude -p` session.
7. For each run: `setup_scratch.sh`, then `probe_isolation.sh`, then `start_run.sh`.

The `.gitignore` keeps `config.env`, the hidden tests, tickets, versions, and results out of Git.
Keep them out of any public copy.

## Limitations

- The pilot has one scored run. Its results describe that run only.
- Isolation is enforced by Claude Code session settings and its sandbox. It assumes a cooperative agent, not an adversarial one.
- The replay is not the real work: there are no hosted checks, no outside services, no browser, and no person to ask. `docs/eval-design.md` lists every known difference.
- The source project's tickets and tests are from one product, and the batch is six backend tickets.
- The launcher is written for macOS, Claude Code, `gh`, `tmux`, and Docker.
- This public copy generalizes the private scripts. They pass a syntax check and small local tests, but no full run has used them in this form.
- Claude Code's cost record runs about 11% above pricing the logged requests. Dollar figures from different methods do not compare directly.

## License

MIT. See `LICENSE`.
