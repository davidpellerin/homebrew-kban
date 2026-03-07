---
title: Add a kban create CLI command
priority: high
depends_on: []
blocked: false
---

## Goal

The web UI can create tickets via `/api/create`, but the CLI cannot. SKILL.md explicitly says "There is no `kban create` command" and tells users to hand-write files. This is the most basic CRUD operation missing from the primary interface.

## Tasks

- [ ] Implement `kban create <id> --title "..." --priority high|medium|low` command in bin/kban
- [ ] Default lane should be backlog, with optional `--lane` flag
- [ ] Support `--depends-on` flag accepting comma-separated ticket IDs
- [ ] Generate the ticket Markdown file with proper YAML frontmatter and a skeleton body
- [ ] Validate the ticket ID doesn't already exist
- [ ] Update SKILL.md to document the new command
- [ ] Update README.md command reference
- [ ] Add tests for the new command (see TASK-001)
