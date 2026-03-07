---
title: Add a comprehensive test suite
priority: high
depends_on: []
blocked: false
---

## Goal

The project has zero automated tests. Add test coverage for both the Bash CLI and the Python web server to catch regressions and validate core logic.

## Tasks

- [ ] Add bats-core tests for bin/kban (init, board, list, show, next, start, done, promote, move, block, unblock)
- [ ] Test YAML frontmatter parsing edge cases (missing fields, extra fields, quoted values)
- [ ] Test dependency resolution logic (depends_on, blocked status, promote behavior)
- [ ] Add pytest tests for web/serve.py (all API endpoints, input validation, error handling)
- [ ] Test ticket CRUD lifecycle end-to-end (create file, move through lanes, verify state)
- [ ] Add a GitHub Actions CI workflow to run both test suites on every PR
- [ ] Update the Homebrew formula test block to exercise more than just --help
