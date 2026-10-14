# Results

This file reports one scored pilot run, `pilot-1-A`.
It is one run of one version.
It is not a conclusive comparison of agent designs, and it names no winner.
The pilot design needs two runs of each version before it compares them (see `docs/eval-design.md`, "Claims").

## The run

| Field | Value |
|---|---|
| Run | `pilot-1-A` |
| Version | Nala v1.8, the swarm: a Lead session, worker sessions in terminal windows, and messages between sessions |
| Harness | Claude Code 2.1.296 |
| Main session | Opus at maximum effort |
| Models used | `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-fable-5-1` |
| Batch | Six connected backend tickets, replayed from a private product |
| Start | 2026-10-12 22:48 UTC |
| End | 2026-10-13 04:29 UTC |
| End reason | All six tickets merged |

## Correctness

The swarm merged all six tickets.
The hidden tests graded the scratch repository's main branch after the run.

| Grade | Tickets passing | Kept tests passing |
|---|---|---|
| First grade | 4 of 6 | 84 of 87 |
| Corrected regrade | 5 of 6 | 85 of 87 |

By ticket, under the corrected regrade:

| Ticket | Kept tests | Passed | Ticket passes |
|---|---|---|---|
| 1 | 15 | 15 | yes |
| 2 | 9 | 9 | yes |
| 3 | 35 | 35 | yes |
| 4 | 16 | 16 | yes |
| 5 | 5 | 5 | yes |
| 6 | 7 | 5 | no |

Why there is a regrade:
the first grade failed ticket 1 on one test that crashed before it checked anything.
The test replaced a method with an empty stand-in that took exactly three arguments.
A later ticket in the run added a fourth keyword argument to that method, and the behaviour the test checks was intact.
The fix lets the stand-ins accept extra keyword arguments, and changes nothing the tests check.
The founder approved it before any run of the other version was graded, and it applies to every run.
After the fix, 0 of 87 kept tests pass at the start state, and all 87 pass with the real fixes.
`eval/hidden-tests/README.md` has the details.

The two failed tests on ticket 6 stay failed.
They check an ordering rule that the ticket text states, and the run's code chose a different order.

## Cost and time

| Measure | Value |
|---|---|
| Dollars, from Claude Code's cost record | $201.38 |
| Wall time | 5.69 hours |
| Dollars per passing ticket | $40.28 |
| Wall time per passing ticket | 1.14 hours |
| Sessions | 7 root sessions, 26 helpers |
| Wait on a usage limit | 0 hours |

Every session had a cost record, so no dollar figure is estimated.
Claude Code's cost record runs about 11% above pricing the logged requests at list price, because some billed calls never appear in the transcript.
`eval/spend.py` uses the cost record when a session has one, for that reason.

Logged tokens by model:

| Model | Input | Output | Cache read | Cache write |
|---|---|---|---|---|
| `claude-opus-5-5` | 2,378 | 1,540,764 | 385,781,818 | 3,414,737 |
| `claude-sonnet-5-5` | 552 | 302,611 | 15,834,206 | 1,376,290 |
| `claude-fable-5-1` | 4,277 | 377,890 | 13,028,271 | 1,508,857 |

## Interruptions

The run had five interruptions.
Each one is a time a person, or the stand-in for a person, acted on the run.

1. The Lead asked on ticket 3 how to check one line of web text with no browser tool. The founder posted the fixed answer by hand, about five minutes later.
2. The founder put the `approved` label on ticket 3's pull request, which has a database migration, by hand, before the Lead asked for it.
3. The Lead asked for the label on ticket 3 again, because the first label came before the migration file. The stand-in script answered and applied the label 16 seconds after the request.
4. The Lead blocked ticket 4 and asked for the `approved` label. The stand-in script answered and applied the label.
5. The Lead asked on ticket 6 which of two orders to use. The stand-in script gave the fixed answer.

The run record counts all five.
The hand-written list of interruptions kept during the run stopped after the third, so it undercounted.

One more act is not counted: the first version of the stand-in script took a Lead comment that only mentioned the founder for a question, and posted the fixed answer a second time.
The rule was tightened afterwards.

The run's launcher process died before the end for an unknown reason.
The six tickets were already merged, and the end steps (grade, spend, audit) were done by hand.

## Isolation audit

The transcript audit listed 6 tool calls that named a closed place.
None of them reached one:

- Two were searches for browser connector tools. The searches found no such tool.
- One was a helper prompt that named the browser tools in its text.
- Three were shell commands that searched the scratch repository's own files for a service name.

## Runs that do not count

The void rule is in `docs/eval-design.md`: a run is void only for a fault in the scratch setup or the machine, never for a fault in the version under test.

| Run | Version | What happened | Status |
|---|---|---|---|
| `trial-1` | v1.9 candidate | The Docker engine hung. | Unscored trial |
| `trial-2` | v1.9 candidate | The session sandbox stopped the phone-app checks that the local merge check runs. | Unscored trial |
| `pilot-2-B`, attempt 1 | v1.9 candidate | The launcher started the batch with no ticket numbers, so the batch held only the two tickets ready at the start. | Void, repeated as `pilot-2-B2` |
| `pilot-2-B2` | v1.9 candidate | The machine slept with its lid closed 22 minutes in, and the launcher and main session died. The founder chose to resume it, with the pause left out of the wall time. | In progress when this repository was published; not reported here |

Each fault led to a harness fix: a Docker check before the run, sandbox grants for the merge check's tools and a probe for them, a launcher that names every ticket, and a launcher that refuses battery power and flags sleep gaps.

## Limits of this result

- It is one run. The spread between two runs of the same version is unknown, so no gap between versions can be judged yet.
- The batch is six connected backend tickets from one product. It says nothing about other code bases or ticket kinds.
- The hidden tests went through a fairness filter, and one test still needed a correction after the first run.
- The main session's model name, "Opus", follows the newest Opus model. The run record stores the exact id.
- No transcripts, session ids, or product code are published, because they come from a private product.
