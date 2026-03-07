---
title: Fix version mismatch between CLI and Formula
priority: high
depends_on: []
blocked: false
---

## Goal

`bin/kban` line 38 reports `KBAN_VERSION="1.5.0"` but `Formula/kban.rb` installs v1.7.0. Anyone running `kban version` after a Homebrew install sees the wrong number. Establish a single source of truth for the version.

## Tasks

- [ ] Update KBAN_VERSION in bin/kban to match the Formula version (1.7.0)
- [ ] Consider a VERSION file at the repo root that both bin/kban and Formula/kban.rb read from
- [ ] Alternatively, add a release checklist or script that bumps version in all locations
- [ ] Verify `kban version` output matches Formula after the fix
