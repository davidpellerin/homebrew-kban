.PHONY: test test-bash test-python lint work

test: lint test-bash test-python

lint:
	shellcheck bin/kban

test-bash:
	bats tests/kban.bats

test-python:
	pytest tests/test_serve.py -v -p no:langsmith --cov=web --cov-report=term-missing

work:
	@for id in $$(kban list ready | grep -oE '^[A-Z]+-[0-9]+'); do \
		echo "==> Working on $$id"; \
		kban start $$id || continue; \
		{ cat templates/agent-prompt.md; kban show $$id; } | claude --dangerously-skip-permissions --print; \
	done
