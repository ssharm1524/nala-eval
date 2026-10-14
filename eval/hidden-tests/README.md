# Hidden tests

The hidden tests grade an attempt.
They are the tests from the real merged fixes, filtered so that each one is fair to an independent attempt.
An attempt never sees them.

This public copy holds the method and the file formats only.
The real test files, the frozen list, the reader verdicts, and the ticket texts come from a private product and are not here.

## Files the grader needs

`grade.py` reads three things from this folder:

- `kept-frozen.json`: the frozen list. `order` lists the source ticket numbers in batch order, and `kept` maps each ticket to its kept test ids. See `kept-frozen.example.json`.
- `candidate-files.txt`: every candidate test file, one path per line, relative to the repository root.
- `files/`: the final test files, laid out as in the repository. The grader copies them over the attempt's result, so they replace whatever the attempt wrote at the same paths.

## Method

1. Clone the source project at the start commit.
2. Apply the batch's real fixes in their original merge order.
3. Take every test file those fixes added or changed. These are the candidates.
4. Run the candidates against the code with all the real fixes. Every candidate must pass.
5. Run the candidates against the start-state code. Keep only the tests that fail there.
6. Map each test function to the ticket whose fix added or changed it.
7. For each test that fails at the start state, a fresh reader decides KEEP or DROP against the ticket text.
   KEEP means a correct attempt that follows the ticket text would pass the test.
   DROP means the test needs a name or a choice that the real fix made and the ticket does not state.
   A test also drops when it patches a private name, or asserts a query shape, a call count, an exact log line, or an exact count in seed data.
8. Run all candidates against each intermediate state: the start state, then one more real fix at each step.
   Keep a test only when it fails at the start state and passes with all the fixes.
   Assign it to the ticket whose fix first makes it pass.
9. Record each hand override in `kept-frozen.json`, with its reason.
10. Freeze the list before the first scored run.

## Names sections

A first reader pass judged the tests against the ticket text alone.
Three of the six tickets then had no fair test, because their tests need names that the tickets never state, such as a route path or a column name.
The fix was a short "Names and decisions" section added to each copied ticket (`eval/tickets/names_TICKET.md`).
It states the names and choices the hidden tests depend on, and nothing about how to build the change.
A second reader pass then judged each test against the ticket body, the founder-direction comments, and the names section.

## Counts in the pilot

The pilot batch had six connected backend tickets.

| Step | Tests |
|---|---|
| Candidate tests from the real fixes (21 files) | 250 |
| Pass with all six real fixes | 250 |
| Fail at the start state | 126 |
| Already pass at the start state | 122 |
| Do not exist at the start state | 2 |
| Kept after the first reader pass (ticket text alone) | 45 |
| Kept in the frozen list (with names sections) | 87 |

Kept tests by ticket, in batch order:

| Ticket | Kept tests |
|---|---|
| 1 | 15 |
| 2 | 9 |
| 3 | 35 |
| 4 | 16 |
| 5 | 5 |
| 6 | 7 |

24 tests of one rule dropped at step 8: they already pass at the start state once an example data file exists.

## One change after the first scored run

The first scored run failed one test that did not check what it meant to check.
The test replaced a method with an empty stand-in that accepted exactly the three arguments the names section states.
A later ticket in the run added a fourth keyword argument to that method, so the test crashed before it checked anything.
The behaviour the test checks was intact.

Three empty stand-ins in that test file now accept extra keyword arguments.
What each test checks is unchanged.
The founder approved the change before any run of the other version was graded, and it applies to every run.

Proof after the change: 0 of 87 kept tests pass at the start state, and all 87 pass with the six real fixes.
The first scored run was regraded under the corrected list (see `RESULTS.md`).
