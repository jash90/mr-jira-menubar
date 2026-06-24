# MR/Jira Menu Bar

A small macOS menu bar app showing four live counters at a glance:

- **My open MRs** on `drm-gitlab.redlabs.pl`
- **My MRs ready to merge** — open MRs with ≥2 approvals
- **Jira backlog** — issues assigned to me, unresolved, status `To Do` / `Backlog`
- **Jira in progress** — issues assigned to me, unresolved, status `In Progress`

Hover the menu bar item for a one-line summary; click it for a breakdown with links
that open the GitLab MR dashboard and the matching Jira filters in your browser.

## Requirements

- macOS 13+
- Swift 5.9+ toolchain (Xcode)
- Credentials read from existing files (no re-entry, in-memory only):
  - GitLab token: `~/Library/Application Support/glab-cli/config.yml` (host `drm-gitlab.redlabs.pl`)
  - Jira token: `~/.claude/.secrets/jira-token`

## Build & run

```sh
swift build -c release
./.build/release/MRJiraMenuBar
```

Or for development:

```sh
swift run MRJiraMenuBar
```

The app is an agent app (no Dock icon). Quit via the menu's **Zakończ** (⌘Q).
It refreshes every 5 minutes; **Odśwież teraz** (⌘R) forces a refresh.

## Test

```sh
swift test
```

## Layout

- `Sources/MenuBarCore/` — Foundation-only, fully unit-tested logic
  (`Credentials`, `GitLabClient`, `JiraClient`, `StatusStore`, `StatusFormatter`).
- `Sources/MRJiraMenuBar/` — AppKit executable (`NSStatusItem` UI wiring).
- `docs/superpowers/` — design spec and implementation plan.

## Notes

- Under the default Swift 5 language mode the build is warning-free. Opting into
  `-strict-concurrency=complete` surfaces a few MainActor-isolation warnings inside the
  AppKit executable target only; these are not errors and do not affect v1.
