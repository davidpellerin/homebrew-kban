.PHONY: test test-bash test-python lint work

test: lint test-bash test-python

lint:
	shellcheck bin/kban

test-bash:
	bats tests/kban.bats

test-python:
	pytest tests/test_serve.py -v -p no:langsmith --cov=web --cov-report=term-missing

work:
	@for id in $$(kban list ready | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '^[A-Z]+-[0-9]+'); do \
		echo "==> Working on $$id"; \
		kban start $$id; \
		kban show $$id | claude --dangerously-skip-permissions --print \
			"Work on ticket $$id until complete. Use available agents and skills to do a great job. When done, output a brief summary of what you did."; \
	done
