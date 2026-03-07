---
title: Fix broken CI pipeline
priority: high
depends_on: []
blocked: false
---

## Goal

The security.yml workflow has two problems: it references a `requirements.txt` that doesn't exist in the repo, and uses `|| true` which silently swallows all failures. The pip-audit job is effectively a no-op giving false confidence.

## Tasks

- [ ] Add an empty requirements.txt (with a comment explaining zero external dependencies) or remove the pip-audit step entirely
- [ ] Remove `|| true` from the pip-audit command so real failures are caught
- [ ] Add a shellcheck lint step for bin/kban to the CI workflow
- [ ] Add a step to run the test suite once TASK-001 is complete
- [ ] Verify the workflow passes on a test PR
