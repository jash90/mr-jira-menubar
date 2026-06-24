# MR/Jira Menu Bar — Design

Date: 2026-06-24
Status: Approved

## Purpose

A personal macOS menu bar app that shows, at a glance, four live counters:

1. **My open MRs** — open merge requests I authored on `drm-gitlab.redlabs.pl`.
2. **My MRs ready to merge** — my open MRs with **≥2 approvals** (the team's merge threshold).
3. **Jira backlog** — issues assigned to me, unresolved, in status **To Do** or **Backlog**.
4. **Jira in progress** — issues assigned to me, unresolved, in status **In Progress**.

Single user (the machine owner). No multi-account support. No window — lives only in the menu bar.

## Platform & Stack

- macOS 13+ (Ventura) native app, Swift.
- **AppKit `NSStatusItem`** for the menu bar item (not SwiftUI `MenuBarExtra`).
  Rationale: `MenuBarExtra` cannot show a hover tooltip on the status button nor cleanly
  mix SF Symbol images with text in the title. `NSStatusItem.button` gives both via
  `attributedTitle` and `toolTip`.
- `URLSession` for HTTP. No third-party dependencies.
- App is an `LSUIElement` (agent app): no Dock icon, no main window.

## Data Sources

### GitLab — `drm-gitlab.redlabs.pl`
- Authenticated user: `bartlomiej.zimny` (id 988).
- REST API v4, header `PRIVATE-TOKEN: <token>`.
- My open MRs: `GET /api/v4/merge_requests?scope=created_by_me&state=opened&per_page=100`.
  Total comes from the `X-Total` response header (or the returned array length when paged).
- Ready-to-merge count: for each returned MR, `GET /api/v4/projects/{project_id}/merge_requests/{iid}/approvals`,
  count the MR if `approved_by.length >= 2`. These per-MR calls run concurrently.

### Jira — `jira.redge.com`
- Authenticated user: `bartlomiej.zimny` (key `JIRAUSER18124`).
- REST API v2, header `Authorization: Bearer <token>`.
- Counts via `GET /rest/api/2/search` with `maxResults=0` (returns only `total`, fast):
  - Backlog JQL: `assignee = currentUser() AND resolution = Unresolved AND status in ("To Do", "Backlog")`
  - In progress JQL: `assignee = currentUser() AND resolution = Unresolved AND status = "In Progress"`

## Credentials

Read from existing on-disk config — no re-entry, no Keychain in v1:

- GitLab token: parsed from `~/Library/Application Support/glab-cli/config.yml`,
  under `hosts:` → `drm-gitlab.redlabs.pl:` → `token:`.
- Jira token: read from `~/.claude/.secrets/jira-token` (trimmed).

If a token file/key is missing, the app surfaces a clear error naming the missing path
(see Error Handling). Tokens are held in memory only.

## Components

Each is independently testable, communicating through small interfaces.

- **`Credentials`** — locates and reads the two tokens. Pure file I/O + YAML/text parse.
  `gitlabToken() throws -> String`, `jiraToken() throws -> String`. Throws a typed error
  naming the missing path on failure.
- **`GitLabClient`** — `init(host:token:)`.
  - `fetchOpenMRCount() async throws -> Int`
  - `fetchReadyToMergeCount() async throws -> Int` (lists my open MRs, then counts those
    with `approved_by.count >= 2` via concurrent approvals calls).
- **`JiraClient`** — `init(host:token:)`.
  - `count(jql:) async throws -> Int` (single `search?maxResults=0`).
  - Convenience: `backlogCount()`, `inProgressCount()` with the JQL above.
- **`StatusStore`** — `ObservableObject`/`@MainActor` model holding the four counts plus
  per-source status (`loading` / `value` / `error`) and `lastRefresh: Date?`.
  - `refresh()` runs GitLab and Jira fetches concurrently; a failure in one source does not
    clear or block the other. Last known good values are retained on error.
  - Owns a repeating timer (default 5 min) and exposes `refreshNow()`.
- **`StatusItemController`** (AppKit) — owns the `NSStatusItem`.
  - Renders `button.attributedTitle`: SF Symbol image + number, repeated for the 4 metrics.
  - Sets `button.toolTip` to a one-line human summary on every update.
  - Builds the `NSMenu` (see UI) and wires actions.
- **`AppDelegate`** — wires `StatusStore` to `StatusItemController`, starts the timer.

### SF Symbols (initial choice, tweakable)
- My MRs: `arrow.triangle.merge`
- Ready to merge: `checkmark.seal`
- Jira backlog: `tray.full`
- Jira in progress: `bolt` (or `figure.run`)

## UI

### Menu bar title
Compact single row: `[merge] 8  [seal] 2   [tray] 4  [bolt] 3`
(SF Symbol images interleaved with counts via `NSAttributedString` + `NSTextAttachment`).

### Tooltip (hover)
One line, e.g.:
`Moje MR: 8 otwartych, 2 gotowe do mergu (≥2 approve) · Jira: 4 backlog, 3 w toku · odświeżono 12:34`
On error, the tooltip names what failed.

### Dropdown menu
```
GitLab — moje MR
  Otwarte:            8        → opens MR dashboard
  Gotowe do mergu:    2        → opens MR dashboard
─────────────────────────────
Jira
  Backlog (To Do):    4        → opens JQL filter
  W toku:             3        → opens JQL filter
─────────────────────────────
Ostatnie odświeżenie: 12:34
Odśwież teraz                 ⌘R
Zakończ                       ⌘Q
```
Link targets (open in default browser):
- MR: `https://drm-gitlab.redlabs.pl/dashboard/merge_requests?scope=created_by_me&state=opened`
- Jira backlog: `https://jira.redge.com/issues/?jql=` + url-encoded backlog JQL
- Jira in progress: `https://jira.redge.com/issues/?jql=` + url-encoded in-progress JQL

Refresh interval is a constant in v1 (5 min); a settings UI is out of scope (see Non-Goals).

## Error Handling

- Network error / HTTP 401 / decode failure on a source → that source's counts show `⚠`
  in the title (symbol-based, e.g. `exclamationmark.triangle`), and the menu shows a
  `Błąd: <message>` row. Last known good values for that source are retained, not zeroed.
- Missing token file/key → menu shows an instruction row naming the exact missing path.
- GitLab and Jira are evaluated independently; one failing never affects the other.
- A manual `Odśwież teraz` always re-attempts.

## Testing

- `Credentials`: parsing a sample glab `config.yml` returns the right token; missing
  host/key throws the typed error with the path.
- `GitLabClient`: with a stubbed `URLProtocol`, `fetchReadyToMergeCount` counts only MRs
  whose approvals payload has `>= 2` approvers; pagination handled.
- `JiraClient`: `count(jql:)` parses `total` from a stubbed search response; builds the
  expected query items.
- `StatusStore`: a failing GitLab fetch leaves Jira values intact and vice versa; last
  known values retained on error; timer triggers refresh.
- `StatusItemController`: title attributed string contains the four counts; tooltip string
  matches the current state (logic extracted into a pure formatter for testability).

## Non-Goals (v1)

- No settings window / configurable interval (constant 5 min).
- No Keychain storage or in-app token entry (reads existing files).
- No multi-account, no other GitLab/Jira hosts.
- No notifications/badges beyond the menu bar title.
- No persistence across launches (counts re-fetched on start).

## Open Risks

- `attributedTitle` with `NSTextAttachment` symbol sizing/baseline needs visual tuning so
  symbols align with the numbers in the menu bar.
- GitLab `approved_by` reflects current approvers; if the instance enforces approval rules
  differently, "≥2 approvals" may differ from GitLab's own "mergeable" state — acceptable
  per the chosen definition.
