---
title: Declare Python 3 dependency in Homebrew Formula
priority: medium
depends_on: []
blocked: false
---

## Goal

`kban serve` requires Python 3 to run web/serve.py, but Formula/kban.rb doesn't declare this dependency. Installation succeeds but `kban serve` fails on systems without Python 3.

## Tasks

- [ ] Add `depends_on "python@3"` (or appropriate version) to Formula/kban.rb
- [ ] Test the formula installation on a clean system to verify the dependency is pulled in
- [ ] Update the sha256 and version tag if a new release is needed
