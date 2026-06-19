# Backyamon — project guide

A SwiftUI iOS backgammon game (dub/reggae beach theme). XcodeGen project — `project.yml` is the source of truth; the `.xcodeproj` and `Backyamon/Info.plist` are generated (`xcodegen generate`), so edit `project.yml` for project/Info settings, not the generated files.

## Build & verify

- Build: `xcodebuild -project Backyamon.xcodeproj -scheme Backyamon -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Always **build → verify it works → commit**. Never commit untested code.
- Multiple simulators share the name "iPhone 17"; pin to a UDID when installing/launching to avoid hitting a stale device.
- Device builds need a signing team (not set in `project.yml` yet) — simulator builds don't.

## Project context (docs/)

Project knowledge lives as plain markdown in `docs/`, managed by **lore** (a git-native PKM). Markdown is the source of truth; `index.md` files are regenerable views.

- **Devlog:** `docs/devlog/` — one dated file per session.
- **Decisions:** `docs/decisions/` — one ADR per architectural/tooling choice.
- **Tasks:** `docs/tasks/` — one file per task (status/owner frontmatter).
- **Ideas:** `docs/ideas/` — lightweight captures.
- Specs/plans from feature work live under `docs/superpowers/`.

**`lore` is not on PATH in non-interactive shells** — invoke the built binary directly:
`node /Users/suki/dev/lore/packages/cli/bin/lore.js <cmd>` (run from the repo root). Common: `list <type>`, `reindex <type>`, `validate <type>`, `tui <type>`.

## Auto-logging (write lore without being asked)

Keep the markdown current as work happens — don't reconstruct it later.

**Log a `devlog` entry (use the `/devlog` command) when a session ends**, and whenever a session included any of:
- a feature/task completed
- a bug hit and fixed
- a tool/dependency/approach switched

`/devlog` gathers commits + branch, writes the entry in the fixed structure (TL;DR → What got done → Decisions → Issues → What to remember → Commits), then runs `reindex` + `validate`. Don't hand-format devlogs — use the command so every entry is consistent.

**Log a `decision` (ADR)** when you make an architectural or tooling choice — capture the why, the options considered, and the tradeoffs, *as it happens*.

After editing any lore doc, run `… reindex <type>` so the index stays fresh; run `… validate <type>` and fix issues before committing.

## Style

- Concise: bullets over paragraphs. Explain the "why" behind choices, not just the "what".
- Commit after each logical chunk, not all at the end.
