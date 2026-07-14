# Sticky "Rejected" Counter — Design

Date: 2026-07-14
Status: Approved

## Problem

The current `testingRejected` counter only counts issues that are *currently* sitting in a
pre-testing status. Once a rejected issue is re-sent to testing (or accepted), it disappears
from the counter. It also relies on the "author of the last Code review transition" heuristic
to decide who developed the tested round, which misses issues and has no hard evidence that
the user actually wrote the code.

## Goal

The "Odrzucone" counter shows every issue the user **ever** had rejected, defined as:

1. The user transitioned the issue **to** `Internal testing` (they were the developer), and
2. the **next** status change after that transition was **to** `In Progress`, made by
   **someone else** (a tester bouncing it back), and
3. GitLab confirms the user coded it: a merge request **created by the user**, referencing the
   issue key, exists and was **created before** the bounce-back transition.

An issue counts once, regardless of how many rejection cycles it went through and regardless
of its current status. The count is permanent ("ever rejected") — later acceptance does not
remove it.

Deliberate simplification: the "assigned to me" wording from the original request is treated
as satisfied by the evidence pair "I clicked the transition to testing" + "my MR predates the
bounce". No assignee-history reconstruction.

## Design

### JiraClient changes

- New candidate JQL (also used for the menu link):

  ```
  status CHANGED TO "Internal testing" BY currentUser()
  AND status CHANGED FROM "Internal testing" TO "In Progress"
  ```

  JQL cannot express event ordering or exclude self-bounces; it only narrows the candidate
  set server-side. The precise filter runs on the changelog.

- `StatusTransition` gains a `date` (parsed from the changelog history `created` field,
  Jira server format `yyyy-MM-dd'T'HH:mm:ss.SSSZ`).

- `searchTransitions` returns the issue key alongside its transitions and **paginates**
  (`startAt` loop, 100 per page) instead of capping at 100 issues — the "ever rejected" set
  grows without bound.

- New pure function `rejectionCycle(transitions:me:)` — scans the transition list for the
  cycle from the Goal section and returns the bounce-back date (`nil` when no cycle exists).
  Unit-testable in isolation, like the existing `developerOfLastTestingRound`.

### GitLabClient changes

- New method `hasMyMergeRequest(referencing key: String, createdBefore: Date) async throws -> Bool`:

  ```
  GET /api/v4/merge_requests?scope=created_by_me&state=all&search=<key>&created_before=<ISO8601>&per_page=1
  ```

  Result read from the `X-Total` header (> 0 → true). `search` matches MR title and
  description; the team MR template always contains a `Closes SOFKRS-…` link, so referencing
  MRs are found.

### New `RejectedIssuesService`

Combines both sources so `JiraClient` and `GitLabClient` stay single-source:

1. Fetch candidates via the new JQL (with changelog).
2. Keep issues whose changelog contains a rejection cycle.
3. Verify each kept issue against GitLab (`hasMyMergeRequest`).
4. Return the count of verified issues.

GitLab verdicts (both positive and negative) are cached in memory per issue key — the
history the verdict depends on never changes, so subsequent 5-minute refreshes skip GitLab
entirely for already-decided issues. The cache lives for the app run (rebuilt when settings
change recreate the clients).

### Wiring

`StatusStore` stays unchanged. `ClientFactory` wraps the Jira client in a thin `JiraFetching`
adapter that delegates the four other counters to `JiraClient` and `testingRejectedCount()`
to the service.

### Error handling — fail-open on GitLab

- GitLab not configured in Settings → count from the changelog alone (no MR verification).
- Network/HTTP error while verifying a single issue → the issue **is counted** (the changelog
  is the primary evidence; only a confirmed 200 response with zero results excludes an
  issue). A GitLab hiccup neither breaks the Jira section nor deflates the counter. Errored
  verdicts are not cached, so a later refresh retries.
- Jira errors → unchanged (message in the menu).

### UI

The "Odrzucone" menu row links to the new candidate JQL — an approximation, since the final
filtering happens in-app and JQL cannot express event order.

## Testing

- `rejectionCycle`: classic cycle; bounce by the user themselves (not a rejection); bounce to
  a status other than `In Progress` (e.g. back to `Code review`); multiple cycles; no bounce;
  transition list from a different developer's round.
- Jira pagination across `startAt` pages; changelog date parsing.
- `hasMyMergeRequest` via `StubURLProtocol` (query shape, `X-Total` handling, error paths).
- `RejectedIssuesService` with stub clients: verified, excluded (0 MRs), GitLab error
  (fail-open, not cached), no GitLab configured, cache hit skips GitLab.
- JQL constants.
