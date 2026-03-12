---
name: kban
description: Manage a filesystem-based kanban board using the kban CLI. Use when the user wants to view their kanban board, create or move tickets, check what's next to work on, track task dependencies, or manage work in lanes (backlog, ready, doing, done). Triggers on requests like "show the board", "what's next?", "move ticket to done", "start a ticket", or any kanban/ticket management task.
---

# kban

`kban` is a filesystem-based kanban board. Tickets are Markdown files stored in `.kban/work/<lane>/`. The board has four active lanes: `backlog` → `ready` → `doing` → `done`, plus an `archive` lane for completed work hidden from the board.

## Commands

```bash
kban version               # Show kban version
kban init                  # Create .kban/ structure in current directory
kban board                 # Show board overview (all lanes and ticket counts)
kban create <id>           # Create a new ticket (default lane: backlog)
kban list [lane]           # List tickets in a lane, or all lanes
kban show <id>             # Show full ticket details (frontmatter + body)
kban next                  # Print the id of the next actionable ready ticket
kban start <id>            # Move ticket to doing
kban done <id>             # Move ticket to done
kban promote               # Move eligible backlog tickets to ready (deps met + not blocked)
kban move <id> <lane>      # Move ticket to any lane (including archive)
kban block <id>            # Mark ticket as blocked
kban unblock <id>          # Clear blocked status from ticket
kban archive <id>          # Move ticket to archive (hidden from board)
kban unarchive <id>        # Restore ticket from archive to done
kban tickets [lane]        # Flat list of all tickets with lane/priority/deps
kban delete <id>           # Delete a ticket permanently
kban serve                 # Start the web UI (default: http://localhost:8080)
kban install skill user    # Install this skill for your user account (all projects)
kban install skill project # Install this skill for this project only
```

## Ticket Format

Tickets are Markdown files with YAML frontmatter:

```markdown
---
title: Short description of the work
priority: high|medium|low
depends_on: [TICKET-001, TICKET-002]
blocked: false
refined: false
---

## Goal

What needs to be accomplished.

## Tasks

- [ ] Step one
- [ ] Step two
```

Ticket IDs come from the filename (e.g., `FEAT-001.md` → ID is `FEAT-001`).

**Canonical ID format:** `[A-Z]+-[0-9]+` — one or more uppercase letters, a hyphen, then one or more digits (e.g., `TASK-001`, `FEAT-042`, `BUG-7`). IDs that don't match this format will be rejected by the web UI and will produce a warning from the CLI. Always use this format when creating ticket files.


## Dependency and Blocked Rules

- `depends_on: []` means no dependencies — ticket can go straight to `ready`.
- `blocked: true` prevents a ticket from being promoted to `ready` via `kban promote`.
- `kban promote` moves all backlog tickets whose deps are all in `done` and are not blocked into `ready`. Run this manually after completing work to surface newly eligible tickets.
- `kban next` returns the first `ready` ticket whose dependencies are all met.


## Typical Workflow

```bash
kban board          # Check current state
kban next           # Get next actionable ticket id
kban show <id>      # Read the ticket
kban start <id>     # Move to doing
# ... do the work ...
kban done <id>      # Mark done
kban promote        # Promote any newly eligible backlog tickets to ready
```


## Creating Tickets

Use `kban create` to create a ticket from the CLI:

```bash
kban create FEAT-009 --title "Add dark mode toggle" --priority medium
kban create BUG-003 --title "Fix login redirect" --priority high --lane ready
kban create FEAT-010 --title "Export to CSV" --depends-on "FEAT-009,TASK-001"
```

Options:
- `--title "..."` — ticket title (required)
- `--priority high|medium|low` — priority (default: `medium`)
- `--lane backlog|ready|doing|done` — lane to create in (default: `backlog`)
- `--depends-on ID1,ID2` — comma-separated dependency IDs

Verify creation with `kban show <ID>` after creating.


## Git Worktrees

The `.kban/` directory lives in the main repository root. When working in a git worktree (e.g., `.claude/worktrees/TASK-001`), `kban` commands will fail because there is no `.kban/` in the worktree directory.

**Detection:** Check if you're in a worktree by comparing `git rev-parse --git-common-dir` with `git rev-parse --git-dir`. If they differ, you're in a worktree.

**Solution:** Find the main repo root and `cd` there before running any `kban` command:

```bash
# Get the main repo root (parent of the shared .git dir)
MAIN_REPO="$(git rev-parse --path-format=absolute --git-common-dir | sed 's/\/\.git$//')"
cd "$MAIN_REPO" && kban <command>
```

Always `cd` back or use a subshell so subsequent work stays in the worktree:

```bash
(cd "$MAIN_REPO" && kban show TASK-001)
(cd "$MAIN_REPO" && kban start TASK-001)
# ... do the work in the worktree ...
(cd "$MAIN_REPO" && kban done TASK-001)
```


## Environment Variables (for `kban serve`)

- `KBAN_HOST` — host to bind (default: `localhost`)
- `KBAN_PORT` — port to bind (default: `8080`)
