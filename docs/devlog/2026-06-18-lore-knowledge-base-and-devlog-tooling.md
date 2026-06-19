---
lore_type: devlog
created: 2026-06-18
title: "Lore knowledge base + global devlog tooling"
date: 2026-06-18
day: 1
phase: Tooling
---

**Stood up a lore knowledge base in the repo and made devlog-writing consistent across every repo via global Claude Code tooling.**

## What got done

- Ran `lore init` → `docs/.lore/types/` with the standard four schemas (task, devlog, decision, idea) + generated `index.md` files.
- Added repo `CLAUDE.md` — build/verify notes (XcodeGen, simulator UDID pinning), the `docs/` structure, and auto-logging conventions.
- Created a **global** `/devlog` command (`~/.claude/commands/devlog.md`): portable, resolves `lore` on PATH (fallback `node ~/.local/bin/lore`), works in any lore-enabled repo.
- Added a **global SessionEnd nudge hook** to `~/.claude/settings.json`, guarded to fire only in repos with `docs/devlog/`. Merged alongside the existing `Stop` hook (backup at `~/.claude/settings.json.bak`).
- Added a "lore" auto-logging convention to `~/.claude/CLAUDE.md`.
- Committed the lore setup and pushed `main` to `origin`.

## Decisions

- **Devlog tooling lives at global `~/.claude/`, not per-repo.** `.claude/` is ignored by `~/.gitignore_global`, and the goal is consistency across all repos (cliphy, dev-dash, backyamon). Global sidesteps the ignore and covers every lore repo at once.
- **Hook guarded by `docs/devlog/` existence** so it's silent in non-lore repos; uses only `git` + `$CLAUDE_PROJECT_DIR` so it's portable across machines.
- **`/devlog` writes the file directly** rather than via `lore add` — multiline bodies are fragile over the CLI; direct write + `reindex`/`validate` is robust.
- Left the lore-setup commit on `main` (per request) instead of branching.

## Issues

- `.claude/` is ignored globally, so a repo-level command/hook can't be committed — this drove the move to global config.
- `lore` wasn't on PATH in non-interactive harness shells at first; the `~/.local/bin/lore` symlink now resolves, and the command/hook fall back to `node ~/.local/bin/lore`.
- Removed the redundant repo-level `.claude/` afterward so the SessionEnd hook doesn't double-fire (global + project).

## What to remember

- Run `lore init` once per repo to get the type schemas; markdown is the source of truth, `index.md` is regenerable.
- The global SessionEnd hook may need a `/hooks` reload or a restart to arm in the current session.
- lore invocation: `lore` on PATH, else `node ~/.local/bin/lore`.

---

## Commits

- `17c253d` docs: set up lore knowledge base (task/devlog/decision/idea) + CLAUDE.md conventions
