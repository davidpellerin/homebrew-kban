---
title: Fix ticket ID format mismatch between CLI and web server
priority: medium
depends_on: []
blocked: false
---

## Goal

The web server (serve.py line 31) only accepts `TASK-\d+` format IDs, but the CLI allows any format (e.g., `001-Setup-API`, `FEAT-001`). Tickets created via CLI can't be edited in the web UI. The two interfaces need consistent validation.

## Tasks

- [ ] Decide on a canonical ticket ID format (recommend: alphanumeric prefix + hyphen + digits, e.g., `FEAT-001`, `BUG-042`, `TASK-007`)
- [ ] Update the web server regex in serve.py to accept the chosen format
- [ ] Add ticket ID validation to the CLI (at minimum in the create command, ideally in move/start/done too)
- [ ] Document the accepted ID format in SKILL.md and README.md
- [ ] Add tests for ID validation edge cases
