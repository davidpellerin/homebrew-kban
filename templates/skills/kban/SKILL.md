---
name: kban
description: Manage a filesystem-based kanban board using the kban CLI. Use when the user wants to view their kanban board, create or move tickets, check what's next to work on, track task dependencies, or manage work in lanes (backlog, ready, doing, done). Triggers on requests like "show the board", "what's next?", "move ticket to done", "start a ticket", or any kanban/ticket management task.
---

# kban

`kban` is a filesystem-based kanban board. Tickets are Markdown files stored in `.kban/work/<lane>/`. The board has four lanes: `backlog` → `ready` → `doing` → `done`.

## Commands

```bash
kban init                  # Create .kban/ structure in current directory
kban board                 # Show board overview (all lanes and ticket counts)
kban list [lane]           # List tickets in a lane, or all lanes
kban show <id>             # Show full ticket details (frontmatter + body)
kban next                  # Print the id of the next actionable ready ticket
kban start <id>            # Move ticket to doing
kban done <id>             # Move ticket to done (auto-promotes backlog tickets)
kban move <id> <lane>      # Move ticket to any lane
kban serve                 # Start the web UI (default: http://localhost:8080)
kban install skill claude  # Install this skill into a project
```

## Ticket Format

Tickets are Markdown files with YAML frontmatter:

```markdown
---
title: Short description of the work
priority: high|medium|low
depends_on: [TICKET-001, TICKET-002]
---

## Goal

What needs to be accomplished.

## Tasks

- [ ] Step one
- [ ] Step two
```

Ticket IDs come from the filename (e.g., `FEAT-001.md` → ID is `FEAT-001`).

## Dependency Rules

- `depends_on: []` means no dependencies — ticket can go straight to `ready`.
- When `kban done <id>` is run, any backlog tickets whose `depends_on` are all in `done` are automatically promoted to `ready`.
- `kban next` returns the first `ready` ticket whose dependencies are all met.

## Typical Workflow

```bash
kban board          # Check current state
kban next           # Get next actionable ticket id
kban show <id>      # Read the ticket
kban start <id>     # Move to doing
# ... do the work ...
kban done <id>      # Mark done, auto-promotes unblocked backlog tickets
```

## Creating Tickets Manually

To add a new ticket, write a `.md` file directly into the appropriate lane directory:

```bash
# Example: create a ready ticket
cat > .kban/work/ready/FEAT-002.md <<'EOF'
---
title: Add dark mode toggle
priority: medium
depends_on: []
---

## Goal

Add a dark/light mode toggle to the settings page.

## Tasks

- [ ] Add toggle component
- [ ] Persist preference to localStorage
EOF
```

## Environment Variables (for `kban serve`)

- `KBAN_HOST` — host to bind (default: `localhost`)
- `KBAN_PORT` — port to bind (default: `8080`)
