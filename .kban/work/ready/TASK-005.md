---
title: Fix fabricated references in README
priority: medium
depends_on: []
blocked: false
---

## Goal

The "Ralph Wiggum Loop" section in README.md (around line 153-179) references things that don't exist: `claude plugin marketplace`, `anthropics/claude-plugins-official`, and `ralph-loop@claude-plugins-official`. Users who follow these instructions will hit a dead end.

## Tasks

- [ ] Remove or rewrite the Ralph Wiggum Loop section
- [ ] If keeping the concept, replace with a real automation example (e.g., a shell loop calling `kban next` / `kban start` / `kban done`)
- [ ] Verify all other README references point to real commands and packages
