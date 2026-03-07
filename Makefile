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
		{ \
			printf 'You are an autonomous agent working on a kban ticket.\n'; \
			printf 'Your job is to implement everything described completely and to a high standard —\n'; \
			printf 'not to summarise or plan, but to actually do the work.\n\n'; \
			printf 'WORKING INSTRUCTIONS:\n'; \
			printf '- Read the ticket carefully, then execute all tasks described.\n'; \
			printf '- Leverage available agents and skills — spawn sub-agents for independent subtasks,\n'; \
			printf '  run things in parallel where possible, use specialised skills when they match.\n'; \
			printf '- Write clean, minimal, well-tested code. Avoid over-engineering.\n'; \
			printf '- When work is genuinely complete, output a concise summary of what you did.\n'; \
			printf '- Do NOT call kban done — the Makefile handles lane transitions.\n\n'; \
			printf 'TICKET:\n'; \
			kban show $$id; \
		} | claude --dangerously-skip-permissions --print; \
	done
